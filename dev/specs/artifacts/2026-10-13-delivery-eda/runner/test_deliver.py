"""Tests for the delivery runner.

Unit tests run anywhere. The end-to-end test needs Quarto, R and the R arrow
package, and is skipped when any is missing.

    pytest runner/test_deliver.py
"""
import importlib.util
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pandas as pd
import pytest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
import deliver  # noqa: E402


# ---- Unit -------------------------------------------------------------------

def test_bound_names_ignores_casts_and_quoted_text():
    sql = "SELECT x::date, ':notabind' FROM t WHERE d BETWEEN :start AND :end AND y = :start"
    assert deliver.bound_names(sql) == {"start", "end"}


def test_unexplained_needs_notes_for_warnings_and_errors_only():
    flags = [
        {"table": "patients", "variable": "bmi", "check": "OUT-RANGE", "severity": "warning"},
        {"table": "patients", "variable": "iv_dead", "check": "FU-NEG", "severity": "error"},
        {"table": "patients", "variable": "nyha", "check": "MISS-UNK", "severity": "info"},
    ]
    notes = {"patients": {"bmi": {"OUT-RANGE": "Unit error in source."},
                          "iv_dead": {"FU-NEG": "   "}}}
    todo = deliver.unexplained(flags, notes)
    assert [f["check"] for f in todo] == ["FU-NEG"]   # blank note does not count


def test_notes_template_lists_missing_flags():
    todo = [{"table": "echo", "variable": "_table", "check": "LONG-ORPHAN", "severity": "error"}]
    assert "LONG-ORPHAN: ''" in deliver.notes_template(todo)


def test_reshape_wide_to_long():
    wide = pd.DataFrame({"pt_id": ["A", "B"],
                         "echo_date_1": ["2010-01-01", "2011-01-01"], "lvef_1": [55, 60],
                         "echo_date_2": ["2012-01-01", None], "lvef_2": [50, None]})
    spec = {"id": "pt_id", "time": "echo_date", "wide": {"stems": ["echo_date", "lvef"]}}
    long = deliver.reshape_wide(wide, spec)
    assert len(long) == 3
    assert set(long.columns) >= {"pt_id", "echo_date", "lvef"}


def test_request_validation(tmp_path):
    bad = tmp_path / "request.yml"
    bad.write_text("request_id: 'a b'\nsource: {}\ntables: []\n")
    with pytest.raises(deliver.DeliveryError, match="request_id"):
        deliver.load_request(bad)


# ---- End to end -------------------------------------------------------------

def _have_toolchain() -> bool:
    if not shutil.which("quarto") or not shutil.which("Rscript"):
        return False
    r = subprocess.run(["Rscript", "-e", "quit(status = !requireNamespace('arrow', quietly = TRUE))"])
    return r.returncode == 0


@pytest.fixture(scope="module")
def example(tmp_path_factory):
    if not _have_toolchain():
        pytest.skip("needs quarto, R and the R arrow package")
    d = tmp_path_factory.mktemp("example")
    src = ROOT / "example"
    for name in ("make_example.py", "request.yml", "ranges.yml", "notes.example.yml"):
        shutil.copy(src / name, d / name)
    shutil.copytree(src / "queries", d / "queries")
    shutil.copy(src / "queries" / "echo_cohort.sql", d / "queries" / "echo.sql")
    spec = importlib.util.spec_from_file_location("make_example", d / "make_example.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.HERE = d
    mod.main()
    return d


def run(step, d, monkeypatch, capsys):
    monkeypatch.setenv("EXAMPLE_DB_URL", f"sqlite:///{d / 'source.sqlite'}")
    code = deliver.main([step, str(d / "request.yml")])
    return code, capsys.readouterr()


def test_end_to_end(example, monkeypatch, capsys):
    d = example
    code, out = run("prepare", d, monkeypatch, capsys)
    assert code == 0, out.err
    flags = json.loads((d / "work" / "DR-EXAMPLE-0001" / "flags.json").read_text())
    planted = {(f["table"], f["variable"], f["check"]) for f in flags}
    for expected in [("patients", "bmi", "OUT-RANGE"), ("patients", "iv_dead", "FU-NEG"),
                     ("patients", "iv_dead", "FU-PAST-CLOSE"), ("patients", "iv_reop", "FU-AFTER-TERMINAL"),
                     ("patients", "lvef_preop", "MISS-ERA"), ("echo", "lvef", "LONG-SHIFT"),
                     ("echo", "lvef", "LONG-DUP"), ("echo", "echo_date", "LONG-PREINDEX"),
                     ("echo", "echo_date", "LONG-POSTCLOSE")]:
        assert expected in planted, expected
    assert not any(f["check"] == "LONG-ORPHAN" for f in flags)  # cohort-joined query

    # Gate: no notes, no bundle.
    code, out = run("bundle", d, monkeypatch, capsys)
    assert code == 2 and "have no note" in out.err

    # With notes, the bundle builds.
    shutil.copy(d / "notes.example.yml", d / "notes.yml")
    code, out = run("bundle", d, monkeypatch, capsys)
    assert code == 0, out.err
    b = d / "bundle" / "DR-EXAMPLE-0001"
    for rel in ("data/patients.parquet", "data/echo.parquet", "query/patients.sql",
                "query/echo.sql", "report/eda.html", "params.yml", "notes.yml", "manifest.json"):
        assert (b / rel).is_file(), rel

    # The delivered query is the executed file, byte for byte.
    assert (b / "query" / "echo.sql").read_bytes() == (d / "queries" / "echo.sql").read_bytes()

    # No record IDs in the delivery report; the internal report has them.
    assert "SYN0" not in (b / "report" / "eda.html").read_text()
    internal = d / "work" / "DR-EXAMPLE-0001" / "internal" / "eda-internal.html"
    assert "SYN00401" in internal.read_text()

    manifest = json.loads((b / "manifest.json").read_text())
    assert all(f["note"] for f in manifest["flags"] if f["severity"] != "info")
    assert "ids" not in manifest["flags"][0]

    # Editing a query after prepare blocks the bundle.
    q = d / "queries" / "patients.sql"
    q.write_text(q.read_text() + "\n-- edited\n")
    code, out = run("bundle", d, monkeypatch, capsys)
    assert code == 2 and "edited after prepare" in out.err


def test_guard_stops_render_on_missing_variable(example, monkeypatch, capsys, tmp_path):
    d = example
    req = (d / "request.yml").read_text().replace("date_var: surgery_date", "date_var: op_date")
    bad = d / "request_bad.yml"
    bad.write_text(req.replace('request_id: "DR-EXAMPLE-0001"', 'request_id: "DR-BAD"'))
    monkeypatch.setenv("EXAMPLE_DB_URL", f"sqlite:///{d / 'source.sqlite'}")
    code = deliver.main(["prepare", str(bad)])
    err = capsys.readouterr().err
    assert code == 2 and "IN-VAR" in err and "op_date" in err
