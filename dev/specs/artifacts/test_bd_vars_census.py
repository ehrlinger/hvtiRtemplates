import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("census", HERE / "2026-10-14-bd-vars-census.py")
census = importlib.util.module_from_spec(spec)
spec.loader.exec_module(census)


def cats(text):
    """Category per statement, in order, dropping scaffolding (None)."""
    out, ctx = [], {"proc": None}
    for raw in census.strip_comments(text.lower()).split(";"):
        stmt = " ".join(raw.split())
        if not stmt:
            continue
        head = stmt.split()[0]
        if head == "proc":
            ctx["proc"] = stmt.split()[1]
        elif head == "data":
            ctx["proc"] = None
        cat = census.classify(stmt, ctx)
        if head in {"run", "quit"}:
            ctx["proc"] = None
        if cat:
            out.append(cat)
    return out


class Classify(unittest.TestCase):
    def test_build_operations(self):
        text = """libname modules "/x";
        data base; set modules.bdbase (drop= sex);
          if age<18 then delete;
          if ccfid=1 then ht=170;
          if ccfid=2 then delete;
          iv_opyrs = (dt_fcst - dt_surg)/365.25;
          keep ccfid age ht;
        run;
        data b2; merge base labs; by ccfid; if hbg > 0; run;
        proc sql; create table x as select * from a left join b on a.id=b.id; quit;
        proc print data=b2; where age>80; run;"""
        self.assertEqual(cats(text), [
            "query", "query", "row_filter", "correction", "patient_removal",
            "standard_derivation", "column_drop", "join", "row_filter", "join",
            "diagnostic", "diagnostic",
        ])

    def test_vars_operations(self):
        text = """%macro vars(in=built, out=built, missing=0, propen=0);
          data &out; set &in;
          if cad_sys=0 then vd0=1;
          if 0 < age < 55 then age3grp='a';
          if nyha_pr=. then nyha_pr=2;
          if lvef=. then lvef_ms=1;
          %ln(age, age_ln);
          if matchto^=. then match=1;
          %let preop = age female nyha_pr lvef;
          proc standard data=&out out=&out replace; run;
          proc mi data=x nimpute=5 out=y; run;
        %mend;"""
        self.assertEqual(cats(text), [
            "recode", "dichotomize", "missing_fill", "missing_flag", "transform",
            "balancing_match", "variable_list", "mean_impute", "mi",
        ])

    def test_commented_code_is_not_counted(self):
        self.assertEqual(cats("/* if ccfid=1 then ht=2; */ * if age<18 then delete;"), [])

    def test_macro_definition_is_not_a_vars_call(self):
        lower = "%macro vars(in=built, missing=0); %mend; %vars(missing=1, propen=1); %vars;"
        self.assertEqual(list(census.vars_calls(lower)), [{"missing": "1", "propen": "1"}, {}])


    def test_macro_comments_are_not_counted(self):
        self.assertEqual(cats("%* if age < 18 then delete; data a; set b; run;"), [])
        self.assertEqual(list(census.vars_calls(census.strip_comments("%* %vars(impute=1);"))), [])

    def test_dated_copies_are_one_program(self):
        self.assertEqual(census.logical_program("bd.data050415.sas"), "bd.data")
        self.assertEqual(census.logical_program("bd.data_12815.sas"), "bd.data")
        self.assertNotEqual(census.logical_program("bd.mult.imput.sas"), "bd.data")


def run_census(tmp, files, mode=None):
    """Write files under tmp/studies, run main(), return (exit code, public JSON text)."""
    import sys
    root = Path(tmp) / "studies"
    for rel, text in files.items():
        f = root / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(text)
    if mode is not None:
        for rel in mode:
            (root / rel).chmod(0)
    out = Path(tmp) / "out"
    out.mkdir()
    argv = sys.argv
    sys.argv = ["x", str(root), str(out / "p.csv"), str(out / "pub.json")]
    code = 0
    try:
        census.main()
    except SystemExit as e:
        code = e.code
    finally:
        sys.argv = argv
        for rel in mode or []:
            (root / rel).chmod(0o644)
    return code, (out / "pub.json").read_text()


class Outputs(unittest.TestCase):
    def test_module_names_stay_private(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, public = run_census(tmp, {
                "c/t/s1/datasets/vars.sas": '%inc "tp.vars.secret_study.sas"; %ln(age, age_ln);',
            })
            self.assertNotIn("secret_study", public)
            self.assertEqual(json.loads(public)["programs"]["vars"]["including_tp_vars_latest"], 1)

    def test_distinct_programs_in_one_study_are_all_counted(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, public = run_census(tmp, {
                "c/t/s1/datasets/bd.data.sas": "data b; set modules.x; run;",
                "c/t/s1/datasets/bd.mult.imput.sas": "proc mi data=b out=c; run;",
            })
            cats_ = json.loads(public)["programs"]["bd"]["per_category_latest"]
            self.assertEqual(cats_["query"]["studies_with"], 1)
            self.assertEqual(cats_["mi"]["studies_with"], 1)

    @unittest.skipIf(os.name == "nt" or os.geteuid() == 0, "chmod does not deny reads here")
    def test_unreadable_file_marks_coverage_incomplete(self):
        with tempfile.TemporaryDirectory() as tmp:
            code, public = run_census(tmp, {"c/t/s1/datasets/vars.sas": "%ln(age, age_ln);"},
                                      mode=["c/t/s1/datasets/vars.sas"])
            self.assertEqual(code, 2)
            self.assertEqual(json.loads(public)["coverage"], "incomplete")

    def test_public_json_carries_no_path_or_study(self):
        with tempfile.TemporaryDirectory() as tmp:
            study = Path(tmp) / "studies" / "cardiac" / "topic" / "secret_study"
            (study / "datasets").mkdir(parents=True)
            (study / "analyses").mkdir()
            (study / "datasets" / "bd.data.sas").write_text("data b; set modules.x; if ccfid=7 then ht=1; run;")
            (study / "datasets" / "vars.sas").write_text("%macro vars(missing=0); %ln(age, age_ln); %mend;")
            (study / "analyses" / "hz.dead.sas").write_text("%vars(propen=1);")
            out = Path(tmp) / "out"
            out.mkdir()
            import sys
            argv = sys.argv
            sys.argv = ["x", str(Path(tmp) / "studies"), str(out / "p.csv"), str(out / "pub.json")]
            try:
                census.main()
            finally:
                sys.argv = argv
            public = (out / "pub.json").read_text()
            self.assertNotIn("secret_study", public)
            self.assertNotIn(tmp, public)
            data = json.loads(public)
            self.assertEqual(data["programs"]["bd"]["per_category_latest"]["correction"]["studies_with"], 1)
            self.assertEqual(data["vars_calls"]["switch_set_nonzero"]["propen"], 1)


if __name__ == "__main__":
    unittest.main()
