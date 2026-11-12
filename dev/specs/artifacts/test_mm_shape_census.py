import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "2026-11-12-mm-shape-census.py"
spec = importlib.util.spec_from_file_location("census", SCRIPT)
census = importlib.util.module_from_spec(spec)
spec.loader.exec_module(census)


def found(name, text):
    return census.signals(Path("/s/study/analyses") / name, text)


def shape(name, text):
    return census.classify(found(name, text))


class Classify(unittest.TestCase):
    def test_random_statement_is_random_effects(self):
        text = "proc mixed data=x; class id; model ef = time; random intercept time / subject=id; run;"
        self.assertEqual(shape("mm.ef.sas", text), "random_effects")

    def test_repeated_statement_is_repeated_covariance(self):
        text = "proc mixed data=x; class id visit; model ef = visit; repeated visit / subject=id type=un; run;"
        self.assertEqual(shape("mm.ef.sas", text), "repeated_covariance")

    def test_both_statements(self):
        text = ("proc mixed data=x; class id; model ef = time; random intercept / subject=id;"
                " repeated / subject=id type=sp(pow)(time); run;")
        self.assertEqual(shape("mm.ef.sas", text), "random_and_repeated")

    def test_separate_random_and_repeated_fits_need_a_person(self):
        text = ("proc mixed data=x; model y = t; random intercept / subject=id; run;"
                " proc mixed data=x; model y = t; repeated / subject=id type=cs; run;")
        self.assertEqual(shape("mm.y.sas", text), "manual_review")

    def test_adjacent_proc_steps_without_run_both_count(self):
        text = ("proc mixed data=x; model y = t; repeated / subject=id type=cs;"
                " proc mixed data=x; model y = t; repeated / subject=id type=ar(1); run;")
        self.assertEqual(found("mm.y.sas", text)["cov_types"], ["ar(1)", "cs"])

    def test_mixed_with_neither_statement_needs_a_person(self):
        self.assertEqual(shape("mm.ef.sas", "proc mixed data=x; model ef = time; run;"), "manual_review")

    def test_normal_glimmix_is_mm(self):
        text = "proc glimmix data=x; model ef = time; random intercept / subject=id; run;"
        self.assertEqual(shape("mm.ef.sas", text), "random_effects")

    def test_binary_glimmix_is_a_gm_finding(self):
        text = "proc glimmix data=x; model mr = time / dist=binary; random intercept / subject=id; run;"
        self.assertEqual(shape("mm.mr.sas", text), "migration_gm")

    def test_nlmixed_is_an_nm_finding(self):
        self.assertEqual(shape("mm.ef.sas", "proc nlmixed data=x; parms a=1; model y ~ normal(a,s); run;"),
                         "migration_nm")

    def test_mixed_beside_binary_glimmix_needs_a_person(self):
        text = ("proc mixed data=x; model y = t; random intercept / subject=id; run;"
                " proc glimmix data=x; model z = t / dist=binary; run;")
        self.assertEqual(shape("mm.y.sas", text), "manual_review")

    def test_no_model_is_misfiled(self):
        self.assertEqual(shape("mm.y.sas", "proc print data=x; run;"), "misfiled")

    def test_block_commented_fit_is_ignored(self):
        self.assertEqual(shape("mm.y.sas", "/* proc mixed data=x; model y = t; random int; run; */"), "misfiled")

    def test_statement_commented_fit_is_ignored(self):
        self.assertEqual(shape("mm.y.sas", "* proc mixed data=x; random int; run;"), "misfiled")

    def test_r_lmer_is_random_effects(self):
        self.assertEqual(shape("mm.ef.R", "fit <- lmer(ef ~ time + (time | id), data = d)"), "random_effects")

    def test_r_gls_with_correlation_is_repeated(self):
        text = "fit <- gls(ef ~ visit, correlation = corSymm(form = ~ 1 | id), data = d)"
        self.assertEqual(shape("mm.ef.R", text), "repeated_covariance")

    def test_r_glmer_is_a_gm_finding(self):
        self.assertEqual(shape("mm.mr.R", "glmer(mr ~ t + (1|id), family = binomial, data = d)"), "migration_gm")

    def test_r_comment_is_ignored(self):
        self.assertEqual(shape("mm.ef.R", "# lmer(ef ~ (1|id), d)\nsummary(d)"), "misfiled")


class Signals(unittest.TestCase):
    def test_covariance_types_and_method(self):
        text = ("proc mixed data=x method=ml; class id visit; model ef = visit;"
                " repeated visit / subject=id type=ar(1); random intercept / type=un subject=id; run;")
        f = found("mm.ef.sas", text)
        self.assertEqual(f["cov_types"], ["ar(1)", "un"])
        self.assertEqual(f["method"], ["ml"])

    def test_spline_lsmeans_and_predictions(self):
        text = ("proc glimmix data=x; effect sp = spline(time); model ef = sp / outp=pred;"
                " random intercept / subject=id; lsmeans grp; run;")
        f = found("mm.ef.sas", text)
        self.assertTrue(f["spline"])
        self.assertTrue(f["lsmeans"])
        self.assertTrue(f["predictions"])

    def test_imputation_is_flagged(self):
        f = found("mm.ef.sas", "proc mixed data=x; by _imputation_; random int / subject=id; run;")
        self.assertTrue(f["mi"])

    def test_macros_skip_sas_builtins(self):
        f = found("mm.ef.sas", "%let a = %str(1); %include 'x'; %mixplot(data=x); %put %sysfunc(today());")
        self.assertEqual(f["macros"], ["mixplot"])

    def test_r_programs_report_no_macros(self):
        self.assertEqual(found("mm.ef.R", "x <- '%mixplot(a);'")["macros"], [])


class Prefix(unittest.TestCase):
    def test_prefix_is_anchored(self):
        self.assertIsNotNone(census.PREFIX_RE.search("mm.ef.sas"))
        self.assertIsNotNone(census.PREFIX_RE.search("ef-trend-mm.qmd"))
        self.assertIsNone(census.PREFIX_RE.search("hz.mm_hg.sas"))
        self.assertIsNone(census.PREFIX_RE.search("summary.sas"))


class EndToEnd(unittest.TestCase):
    def test_public_json_carries_no_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "corpus"
            for study in ("alpha", "beta", "gamma"):
                folder = root / study / "analyses"
                folder.mkdir(parents=True)
                (folder / "mm.ef.sas").write_text(
                    "proc mixed data=x; random intercept / subject=id type=un; run; %mixplot(data=x);")
            (root / "alpha" / "analyses" / "tp.mm.sas").write_text("proc mixed; random int; run;")
            out = Path(tmp) / "out"
            subprocess.run([sys.executable, "-I", str(SCRIPT), str(root), str(out / "private.csv"),
                            str(out / "public.json")], check=True)
            text = (out / "public.json").read_text()
            result = json.loads(text)
            self.assertEqual(result["shapes"]["random_effects"]["sas_studies"], 3)
            self.assertTrue(result["shapes"]["random_effects"]["two_study_gate"])
            self.assertEqual(result["template_copies_skipped"], 1)
            self.assertEqual(result["over_mixed_fits"]["cov_types"], {"un": {"programs": 3, "studies": 3}})
            self.assertEqual(result["macros_in_3_plus_studies"], {"mixplot": 3})
            for study in ("alpha", "beta", "gamma", tmp):
                self.assertNotIn(study, text)


if __name__ == "__main__":
    unittest.main()
