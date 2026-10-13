"""Data delivery runner: execute queries, render the EDA report, gate on notes, bundle.

Two steps, run by the data manager filling the request:

    python deliver.py prepare path/to/request.yml
        Executes each table's .sql file with bound parameters, writes parquet,
        renders the INTERNAL report and flags.json, and lists flags needing notes.

    python deliver.py bundle path/to/request.yml
        Confirms data and queries are unchanged since prepare, refuses while any
        warning or error flag lacks a note, renders the DELIVERY report, and
        assembles the bundle with a manifest.

The query files in the bundle are the files that were executed, copied byte for
byte. Connection URLs come from an environment variable named in the request,
never from the request file itself.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import pandas as pd
import yaml
from sqlalchemy import create_engine, text

__version__ = "0.1.0"

REPORT_DIR = Path(__file__).resolve().parent.parent / "report"
TEMPLATE_FILES = ["eda.qmd", "R/checks.R", "R/plots.R"]


class DeliveryError(RuntimeError):
    """A condition that must stop the delivery, with a message for the data manager."""


# ---- Small helpers ----------------------------------------------------------

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def template_sha256() -> str:
    h = hashlib.sha256()
    for rel in TEMPLATE_FILES:
        h.update(rel.encode())
        h.update((REPORT_DIR / rel).read_bytes())
    return h.hexdigest()


def load_request(path: Path) -> dict:
    req = yaml.safe_load(path.read_text())
    for key in ("request_id", "source", "tables"):
        if key not in req:
            raise DeliveryError(f"request.yml is missing `{key}`.")
    if not re.fullmatch(r"[A-Za-z0-9._-]+", str(req["request_id"])):
        raise DeliveryError("request_id may contain only letters, digits, '.', '_' and '-'.")
    roles = [t.get("role") for t in req["tables"]]
    if roles.count("patient") != 1:
        raise DeliveryError("Exactly one table must have role: patient.")
    names = [t["name"] for t in req["tables"]]
    if len(set(names)) != len(names):
        raise DeliveryError("Table names must be unique.")
    req["_dir"] = path.resolve().parent
    return req


def work_dir(req: dict, override: str | None) -> Path:
    return Path(override).resolve() if override else req["_dir"] / "work" / req["request_id"]


def engine_for(req: dict):
    env = req["source"].get("url_env")
    if not env or env not in os.environ:
        raise DeliveryError(
            f"Set the environment variable `{env}` to the SQLAlchemy URL for the source.")
    return create_engine(os.environ[env])


def bound_names(sql: str) -> set[str]:
    """Named binds (:name) used in a query, ignoring '::' casts and quoted text."""
    stripped = re.sub(r"'(?:[^']|'')*'", "''", sql)
    return set(re.findall(r"(?<![:\w]):([A-Za-z_]\w*)", stripped))


def reshape_wide(df: pd.DataFrame, spec: dict) -> pd.DataFrame:
    """Pivot numbered columns (lvef_1, lvef_2, ...) to one row per measurement."""
    stems = spec["wide"]["stems"]
    idv = spec["id"]
    long = pd.wide_to_long(df[[idv] + [c for c in df.columns if re.match(
        rf"^({'|'.join(map(re.escape, stems))})_\d+$", c)]],
        stubnames=stems, i=idv, j="_visit", sep="_").reset_index()
    return long.dropna(subset=[s for s in stems if s != spec["time"]], how="all")


def tool_version(cmd: list[str]) -> str:
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return (out.stdout or out.stderr).strip().splitlines()[0]
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


# ---- Report rendering -------------------------------------------------------

def report_params(req: dict, tables: dict[str, Path], audience: str,
                  notes: Path | None, flags_out: Path | None) -> dict:
    keep = ("name", "role", "id", "date_var", "events", "time", "values", "unit",
            "baseline_window_days")
    out_tables = []
    for t in req["tables"]:
        spec = {k: t[k] for k in keep if k in t}
        if "wide" in t:
            spec["values"] = [s for s in t["wide"]["stems"] if s != t["time"]]
        spec["path"] = str(tables[t["name"]])
        out_tables.append(spec)
    ranges = {}
    if req.get("ranges"):
        ranges = yaml.safe_load((req["_dir"] / req["ranges"]).read_text()) or {}
    return {
        "request_id": req["request_id"],
        "audience": audience,
        "close_date": str(req["close_date"]) if req.get("close_date") else None,
        "unknown_codes": req.get("unknown_codes", []),
        "ranges": ranges,
        "thresholds": req.get("thresholds", {}),
        "notes": str(notes) if notes else None,
        "flags_out": str(flags_out) if flags_out else None,
        "tables": out_tables,
    }


def render(params: dict, out_html: Path) -> None:
    """Render eda.qmd in a scratch copy so concurrent renders never collide."""
    with tempfile.TemporaryDirectory(prefix="eda-") as tmp:
        tmp = Path(tmp)
        for rel in TEMPLATE_FILES:
            (tmp / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(REPORT_DIR / rel, tmp / rel)
        pfile = tmp / "params.yml"
        pfile.write_text(yaml.safe_dump(params, sort_keys=False))
        cmd = ["quarto", "render", "eda.qmd", "-P", f"config:{pfile}"]
        proc = subprocess.run(cmd, cwd=tmp, capture_output=True, text=True)
        if proc.returncode != 0:
            raw = re.sub(r"\x1b\[[0-9;]*m", "", proc.stderr + proc.stdout)
            msg = "\n".join(l for l in raw.splitlines()
                            if l.strip() and not re.match(r"^\s*(\d+/\d+|\|)", l))
            guard = re.search(r"\[(IN-[A-Z]+)\][^\n]*", msg)
            raise DeliveryError("Report did not render.\n" + (guard.group(0) if guard else msg[-3000:]))
        out_html.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(tmp / "eda.html", out_html)


# ---- Notes and the gate -----------------------------------------------------

def load_notes(path: Path) -> dict:
    return (yaml.safe_load(path.read_text()) or {}) if path.exists() else {}


def note_for(notes: dict, f: dict) -> str | None:
    n = ((notes.get(f["table"]) or {}).get(f["variable"]) or {}).get(f["check"])
    return str(n).strip() if n not in (None, "") else None


def unexplained(flags: list[dict], notes: dict) -> list[dict]:
    return [f for f in flags if f["severity"] in ("error", "warning") and not note_for(notes, f)]


def notes_template(missing: list[dict]) -> str:
    """YAML skeleton for the flags still needing notes, to paste into notes.yml."""
    tree: dict = {}
    for f in missing:
        tree.setdefault(f["table"], {}).setdefault(f["variable"], {})[f["check"]] = ""
    return yaml.safe_dump(tree, sort_keys=False)


# ---- Steps ------------------------------------------------------------------

def prepare(req: dict, wd: Path) -> int:
    if wd.exists():
        shutil.rmtree(wd)
    (wd / "data").mkdir(parents=True)
    (wd / "query").mkdir()
    engine = engine_for(req)
    binds = req.get("bind_params", {}) or {}
    tables: dict[str, Path] = {}
    state = {"request_id": req["request_id"], "prepared": dt.datetime.now().astimezone().isoformat(),
             "tables": {}, "template_sha256": template_sha256()}

    with engine.connect() as conn:
        for t in req["tables"]:
            src = req["_dir"] / t["query"]
            sql = src.read_text()
            used = bound_names(sql)
            missing = used - set(binds)
            if missing:
                raise DeliveryError(f"{t['query']} uses bind(s) not in bind_params: {sorted(missing)}.")
            df = pd.read_sql(text(sql), conn, params={k: binds[k] for k in used})
            reshaped = False
            if "wide" in t:
                df = reshape_wide(df, t)
                reshaped = True
            data = wd / "data" / f"{t['name']}.parquet"
            df.to_parquet(data, index=False)
            qcopy = wd / "query" / f"{t['name']}.sql"
            shutil.copyfile(src, qcopy)          # the executed file, byte for byte
            tables[t["name"]] = data
            state["tables"][t["name"]] = {
                "query_source": t["query"], "query_sha256": sha256(qcopy),
                "data_sha256": sha256(data), "rows": int(len(df)), "columns": int(df.shape[1]),
                "binds_used": sorted(used), "reshaped_wide_to_long": reshaped}
            print(f"  {t['name']}: {len(df):,} rows x {df.shape[1]} columns")

    flags_path = wd / "flags.json"
    params = report_params(req, tables, "internal", None, flags_path)
    render(params, wd / "internal" / "eda-internal.html")
    (wd / "state.json").write_text(json.dumps(state, indent=2))

    flags = json.loads(flags_path.read_text())
    notes = load_notes(req["_dir"] / req.get("notes", "notes.yml"))
    todo = unexplained(flags, notes)
    counts = {s: sum(f["severity"] == s for f in flags) for s in ("error", "warning", "info")}
    print(f"\nInternal report: {wd / 'internal' / 'eda-internal.html'}")
    print(f"Flags: {counts['error']} error, {counts['warning']} warning, {counts['info']} info.")
    if todo:
        print(f"\n{len(todo)} flag(s) need a note before `bundle`:")
        for f in todo:
            print(f"  {f['severity']:7} {f['check']:18} {f['table']}.{f['variable']}  {f['detail']}")
        print("\nSkeleton for notes.yml:\n")
        print(notes_template(todo))
    else:
        print("Every warning and error has a note. Ready to bundle.")
    return 0


def bundle(req: dict, wd: Path, out_root: Path) -> int:
    state_path = wd / "state.json"
    if not state_path.exists():
        raise DeliveryError("Run `prepare` first.")
    state = json.loads(state_path.read_text())

    # The data and queries must be what the internal report checked.
    for name, t in state["tables"].items():
        for kind, path in (("query", wd / "query" / f"{name}.sql"),
                           ("data", wd / "data" / f"{name}.parquet")):
            if sha256(path) != t[f"{kind}_sha256"]:
                raise DeliveryError(f"{kind} for `{name}` changed since prepare. Re-run prepare.")
        src = req["_dir"] / t["query_source"]
        if sha256(src) != t["query_sha256"]:
            raise DeliveryError(f"{t['query_source']} was edited after prepare. Re-run prepare.")
    if template_sha256() != state["template_sha256"]:
        raise DeliveryError("The report template changed since prepare. Re-run prepare.")

    flags = json.loads((wd / "flags.json").read_text())
    notes_path = req["_dir"] / req.get("notes", "notes.yml")
    notes = load_notes(notes_path)
    todo = unexplained(flags, notes)
    if todo:
        lines = "\n".join(f"  {f['check']} {f['table']}.{f['variable']}" for f in todo)
        raise DeliveryError(f"{len(todo)} flag(s) have no note in {notes_path.name}:\n{lines}\n\n"
                            + notes_template(todo))

    dest = out_root / req["request_id"]
    if dest.exists():
        shutil.rmtree(dest)
    (dest / "data").mkdir(parents=True)
    (dest / "query").mkdir()
    for name in state["tables"]:
        shutil.copyfile(wd / "data" / f"{name}.parquet", dest / "data" / f"{name}.parquet")
        shutil.copyfile(wd / "query" / f"{name}.sql", dest / "query" / f"{name}.sql")
    shutil.copyfile(notes_path, dest / "notes.yml")

    tables = {name: dest / "data" / f"{name}.parquet" for name in state["tables"]}
    params = report_params(req, tables, "delivery", dest / "notes.yml", None)
    html = dest / "report" / "eda.html"
    render(params, html)

    # No record ID from the internal flags may appear in the delivery report.
    body = html.read_text(errors="ignore")
    def ids_of(f: dict) -> list[str]:
        ids = f.get("ids") or []
        return [ids] if isinstance(ids, str) else [str(i) for i in ids]

    leaked = sorted({i for f in flags for i in ids_of(f) if re.search(
        rf"(?<![\w-]){re.escape(str(i))}(?![\w-])", body)})
    if leaked:
        shutil.rmtree(dest)
        raise DeliveryError(f"Delivery report contains record IDs ({', '.join(leaked[:5])}). Bundle removed.")

    # params.yml in the bundle points at bundle-relative paths.
    for t in params["tables"]:
        t["path"] = f"data/{t['name']}.parquet"
    params["notes"] = "notes.yml"
    (dest / "params.yml").write_text(yaml.safe_dump(params, sort_keys=False))

    manifest = {
        "request_id": req["request_id"],
        "created": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "prepared": state["prepared"],
        "source": {"kind": req["source"].get("kind"), "url_env": req["source"].get("url_env")},
        "bind_params": {k: str(v) for k, v in (req.get("bind_params") or {}).items()},
        "close_date": str(req["close_date"]) if req.get("close_date") else None,
        "tables": [{
            "name": name, "role": next(t["role"] for t in req["tables"] if t["name"] == name),
            "query": f"query/{name}.sql", "query_sha256": t["query_sha256"],
            "data": f"data/{name}.parquet", "data_sha256": t["data_sha256"],
            "rows": t["rows"], "columns": t["columns"], "binds_used": t["binds_used"],
            "reshaped_wide_to_long": t["reshaped_wide_to_long"],
        } for name, t in state["tables"].items()],
        "flags": [{k: f[k] for k in ("table", "variable", "check", "severity", "n")}
                  | {"note": note_for(notes, f)} for f in flags],
        "software": {"runner": __version__, "R": tool_version(["Rscript", "--version"]),
                     "quarto": tool_version(["quarto", "--version"]),
                     "report_template_sha256": state["template_sha256"]},
    }
    (dest / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"Bundle: {dest}")
    for p in sorted(dest.rglob("*")):
        if p.is_file():
            print(f"  {p.relative_to(dest)}")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("step", choices=["prepare", "bundle"])
    ap.add_argument("request", type=Path)
    ap.add_argument("--workdir", help="Working directory (default: <request dir>/work/<request_id>)")
    ap.add_argument("--out", help="Bundle root (default: <request dir>/bundle)")
    a = ap.parse_args(argv)
    try:
        req = load_request(a.request)
        wd = work_dir(req, a.workdir)
        if a.step == "prepare":
            return prepare(req, wd)
        out = Path(a.out).resolve() if a.out else req["_dir"] / "bundle"
        return bundle(req, wd, out)
    except DeliveryError as e:
        print(f"Stopped: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
