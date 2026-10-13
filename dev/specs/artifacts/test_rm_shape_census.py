import importlib.util
import tempfile
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

    def test_consecutive_statement_comments_are_both_stripped(self):
        text = "* note;\n* proc reg data=x; model y = a; run;"
        self.assertEqual(shape("rm.y.sas", text), "misfiled")

    def test_second_commented_fit_does_not_hide_live_mixed(self):
        text = "* note;\n* proc reg data=x; model y = a; run;\nproc mixed data=x; model y = a; run;"
        self.assertEqual(shape("rm.y.sas", text), "migration_mm")

    def test_repeated_outside_glm_step_is_ignored(self):
        text = 'title "repeated measures"; proc glm data=x; model y = a; run;'
        self.assertEqual(shape("rm.y.sas", text), "linear")

    def test_repeated_after_glm_step_ends_is_ignored(self):
        text = "proc glm data=x; model y = a; run; proc print; var repeated; run;"
        self.assertEqual(shape("rm.y.sas", text), "linear")

    def test_transform_of_a_covariate_is_not_flagged(self):
        found = census.signals(Path("/s/study/analyses/rm.y.sas"), "x = log(a); proc reg; model y = x; run;")
        self.assertFalse(found["transformed"])

    def test_response_assigned_from_log_is_flagged(self):
        found = census.signals(Path("/s/study/analyses/rm.y.sas"), "yy = LOG10 (y); proc reg; model yy = a; run;")
        self.assertTrue(found["transformed"])

    def test_response_named_log_is_flagged(self):
        found = census.signals(Path("/s/study/analyses/rm.y.sas"), "proc glm; model log_y = a; run;")
        self.assertTrue(found["transformed"])

    def test_r_log_response_is_flagged(self):
        found = census.signals(Path("/s/study/analyses/rm.y.R"), "fit <- lm(log(y) ~ a, d)")
        self.assertTrue(found["transformed"])

    def test_r_log_covariate_is_not_flagged(self):
        found = census.signals(Path("/s/study/analyses/rm.y.R"), "fit <- lm(y ~ log(a), d)")
        self.assertFalse(found["transformed"])


class Round2(unittest.TestCase):
    def test_glm_step_ends_at_next_proc(self):
        text = "proc glm; model y=x; proc mixed; repeated / subject=id; run;"
        self.assertEqual(shape("rm.y.sas", text), "manual_review")

    def test_glm_step_ends_at_next_data(self):
        text = "proc glm; model y=x; data b; set a; repeated = 1; run;"
        self.assertNotEqual(shape("rm.y.sas", text), "migration_mm")

    def test_glm_repeated_still_migration(self):
        text = "proc glm; class t; model y1 y2 y3 = g; repeated time 3; run;"
        self.assertEqual(shape("rm.y.sas", text), "migration_mm")

    def test_plain_glm_linear(self):
        self.assertEqual(shape("rm.y.sas", "proc glm; model y = a; run;"), "linear")

    def _t(self, text):
        return census.signals(Path("/s/study/analyses/rm.y.sas"), text)["transformed"]

    def test_log_names_not_transformed(self):
        self.assertFalse(self._t("proc reg; model logistic_score = a; run;"))
        self.assertFalse(self._t("proc reg; model logrank = a; run;"))
        self.assertFalse(self._t("proc reg; model lvef = a; run;"))
        self.assertFalse(self._t("proc reg; model los = a; run;"))

    def test_log_names_transformed(self):
        for n in ("log_los", "ln_los", "l_los", "log10_x", "log"):
            self.assertTrue(self._t("proc reg; model %s = a; run;" % n), n)

    def test_model_statement_log_covariate_not_transformed(self):
        self.assertFalse(self._t("proc reg; model los = log(age) lap; run;"))

    def test_assignment_log_still_transformed(self):
        self.assertTrue(self._t("data a; ly = log(los); run; proc reg; model ly = age; run;"))


class Candidates(unittest.TestCase):
    def test_tp_template_copies_are_skipped_and_counted(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "study" / "analyses"
            folder.mkdir(parents=True)
            for name in ("tp.rm.x.sas", "TP.rm.y.sas", "rm.x.sas"):
                (folder / name).write_text("proc reg; run;")
            found, errors, skipped = census.candidate_files(tmp)
        self.assertEqual([p.name for p in found], ["rm.x.sas"])
        self.assertEqual(errors, 0)
        self.assertEqual(skipped, 2)


if __name__ == "__main__":
    unittest.main()
