import importlib.util
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("census", HERE / "2026-10-13-rm-shape-census.py")
census = importlib.util.module_from_spec(spec)
spec.loader.exec_module(census)


def shape(name, text):
    return census.classify(census.signals(Path("/s/study/analyses") / name, text))


class Classify(unittest.TestCase):
    def test_proc_reg_outcome_is_linear(self):
        self.assertEqual(shape("rm.los.sas", "proc reg data=x; model los = age female; run;"), "linear")

    def test_proc_glm_outcome_is_linear(self):
        self.assertEqual(shape("rm.ef.sas", "proc glm data=x; class sex; model ef = age sex; run;"), "linear")

    def test_r_lm_is_linear(self):
        self.assertEqual(shape("rm.ef.R", "fit <- lm(ef ~ age, data = d)"), "linear")

    def test_balancing_score_wins_over_linear(self):
        text = "proc reg data=x; model hct_nadr = age; output out=o p=xb; run; %grp(bs)"
        self.assertEqual(shape("rm.continuous.balncing_score.sas", text), "balancing_continuous")

    def test_mixed_is_a_migration_finding(self):
        self.assertEqual(shape("rm.ef.sas", "proc mixed data=x; model ef = time; repeated; run;"), "migration_mm")

    def test_genmod_is_a_migration_finding(self):
        self.assertEqual(shape("rm.cnt.sas", "proc genmod data=x; model n = a / dist=poisson; run;"), "migration_gm")

    def test_nlin_is_a_migration_finding(self):
        self.assertEqual(shape("rm.curve.sas", "proc nlin data=x; parms a=1; model y = a*exp(t); run;"), "migration_nm")

    def test_mixed_beside_reg_needs_a_person(self):
        text = "proc reg data=x; model y = a; run; proc mixed data=x; model y = a; run;"
        self.assertEqual(shape("rm.y.sas", text), "manual_review")

    def test_no_model_is_misfiled(self):
        self.assertEqual(shape("rm.y.sas", "proc print data=x; run;"), "misfiled")

    def test_log_outcome_is_flagged_transformed(self):
        found = census.signals(Path("/s/study/analyses/rm.los.sas"), "ln_los = log(los); proc reg; model ln_los = a; run;")
        self.assertTrue(found["transformed"])

    def test_prefix_must_be_a_field(self):
        self.assertIsNone(census.PREFIX_RE.search("form.sas"))
        self.assertIsNotNone(census.PREFIX_RE.search("rm.los.sas"))

    def test_block_commented_mixed_is_ignored(self):
        text = "/* proc mixed data=x; model y = a; run; */ proc reg data=x; model y = a; run;"
        self.assertEqual(shape("rm.y.sas", text), "linear")

    def test_statement_commented_fit_is_ignored(self):
        self.assertEqual(shape("rm.y.sas", "* proc reg data=x; model y = a; run;"), "misfiled")

    def test_multiplication_is_not_a_comment(self):
        self.assertEqual(shape("rm.y.sas", "x = a * b; proc reg; model y = x; run;"), "linear")

    def test_r_line_comment_is_ignored(self):
        text = "# fit <- lmer(y ~ (1|id), d)\nfit <- lm(y ~ a, d)"
        self.assertEqual(shape("rm.y.R", text), "linear")

    def test_glm_with_repeated_is_mm(self):
        text = "proc glm data=x; class t; model y1 y2 y3 = grp; repeated time 3; run;"
        self.assertEqual(shape("rm.y.sas", text), "migration_mm")

    def test_glm_with_repeated_beside_reg_needs_a_person(self):
        text = "proc reg data=x; model y = a; run; proc glm data=x; model y1 y2 = g; repeated time 2; run;"
        self.assertEqual(shape("rm.y.sas", text), "manual_review")


if __name__ == "__main__":
    unittest.main()
