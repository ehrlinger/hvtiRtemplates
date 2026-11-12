import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("census", HERE / "2026-11-12-cm-shape-census.py")
census = importlib.util.module_from_spec(spec)
spec.loader.exec_module(census)


def shape(name, text):
    return census.classify(census.signals(Path("/s/study/analyses") / name, text))


class Classify(unittest.TestCase):
    def test_psmatch_then_phreg_matches_and_fits(self):
        text = "proc psmatch data=x; class trt; psmodel trt = age; match method=greedy; run;" \
               "proc phreg data=m; model (t0,t)*dead(0) = trt; strata _matchid; run;"
        self.assertEqual(shape("cm.dead.sas", text), "match_and_fit")

    def test_greedy_macro_matches_and_fits(self):
        text = "%gmatch(data=ps, group=trt, id=id, mvars=prob, dmaxk=0.2); " \
               "proc phreg data=m; model int_dead*dead(0) = trt; run;"
        self.assertEqual(shape("cm.dead.sas", text), "match_and_fit")

    def test_matchit_matches_and_fits(self):
        text = "m <- MatchIt::matchit(trt ~ age, data = d, caliper = 0.2)\n" \
               "fit <- survival::coxph(Surv(t, dead) ~ trt, data = match.data(m))"
        self.assertEqual(shape("cm.dead.R", text), "match_and_fit")

    def test_ps_match_matches_and_fits(self):
        text = "m <- hvtiRpropensity::ps_match(ps)\nfit <- coxph(Surv(t, dead) ~ trt, data = m)"
        self.assertEqual(shape("cm.dead.R", text), "match_and_fit")

    def test_pair_strata_is_fit_matched(self):
        text = "proc phreg data=m; model t*dead(0) = trt; strata pair_id; run;"
        self.assertEqual(shape("cm.dead.sas", text), "fit_matched")

    def test_covsandwich_is_fit_matched(self):
        text = "proc phreg data=m covsandwich(aggregate); model t*dead(0) = trt; id setid; run;"
        self.assertEqual(shape("cm.dead.sas", text), "fit_matched")

    def test_where_on_match_flag_is_fit_matched(self):
        text = "proc phreg data=x; where matched = 1; model t*dead(0) = trt; run;"
        self.assertEqual(shape("cm.dead.sas", text), "fit_matched")

    def test_coxph_cluster_is_fit_matched(self):
        text = "fit <- coxph(Surv(t, dead) ~ trt + cluster(pair), data = d)"
        self.assertEqual(shape("cm.dead.R", text), "fit_matched")

    def test_phreg_weight_is_fit_weighted(self):
        text = "proc phreg data=x; model t*dead(0) = trt; weight iptw; run;"
        self.assertEqual(shape("cm.dead.sas", text), "fit_weighted")

    def test_coxph_weights_is_fit_weighted(self):
        text = "fit <- coxph(Surv(t, dead) ~ trt, data = d,\n  weights = w)"
        self.assertEqual(shape("cm.dead.R", text), "fit_weighted")

    def test_matching_weight_name_is_fit_weighted(self):
        text = "data w; set x; mtwt = min(p, 1-p) / p; run; proc phreg data=w; model t*dead(0) = trt; run;"
        self.assertEqual(shape("cm.dead.sas", text), "fit_weighted")

    def test_plain_phreg_is_unadjusted(self):
        self.assertEqual(shape("cm.dead.sas", "proc phreg data=x; model t*dead(0) = trt age; run;"),
                         "fit_unadjusted")

    def test_pairs_and_weights_need_a_person(self):
        text = "proc phreg data=m; model t*dead(0) = trt; strata pair; weight mtwt; run;"
        self.assertEqual(shape("cm.dead.sas", text), "manual_review")

    def test_no_cox_is_misfiled(self):
        self.assertEqual(shape("cm.dead.sas", "proc lifetest data=x; time t*dead(0); run;"), "misfiled")

    def test_block_commented_match_is_ignored(self):
        text = "/* proc psmatch data=x; run; */ proc phreg data=x; model t*dead(0) = trt; run;"
        self.assertEqual(shape("cm.dead.sas", text), "fit_unadjusted")

    def test_statement_commented_fit_is_ignored(self):
        self.assertEqual(shape("cm.dead.sas", "* proc phreg data=x; model t*dead(0) = trt; run;"),
                         "misfiled")

    def test_r_line_comment_is_ignored(self):
        text = "# m <- matchit(trt ~ age, data = d)\nfit <- coxph(Surv(t, dead) ~ trt, data = d)"
        self.assertEqual(shape("cm.dead.R", text), "fit_unadjusted")

    def test_propensity_fit_in_the_job_is_flagged(self):
        found = census.signals(Path("/s/study/analyses/cm.dead.sas"),
                               "proc logistic data=x; model trt = age; run; proc phreg data=x; model t*d(0)=trt; run;")
        self.assertTrue(found["ps_fit"])


class Names(unittest.TestCase):
    def test_prefix_is_anchored(self):
        for name in ("cm.dead.sas", "cm_dead.sas", "CM.dead.SAS", "dead-surv-cm.qmd", "dead-surv-cm-iptw.qmd"):
            self.assertIsNotNone(census.PREFIX_RE.search(name), name)
        for name in ("hm.cm.sas", "dcm.dead.sas", "acm.sas", "dead-cm.sas.bak"):
            self.assertIsNone(census.PREFIX_RE.search(name), name)

    def test_numbered_and_bare_folders(self):
        self.assertEqual(census.folder_name(Path("/s/a/30_analyses/cm.x.sas")), "analyses")
        self.assertEqual(census.folder_name(Path("/s/a/graphs/cm.x.sas")), "graphs")
        self.assertEqual(census.study_key(Path("/s/a/30_analyses/cm.x.sas")), "/s/a")

    def test_macros_drop_language_words_and_local_definitions(self):
        text = "%let x = 1; %macro local_one; %mend; %local_one; %gmatch(data=x); %hazard(data=y);"
        self.assertEqual(census.called_macros(text, ".sas"), {"gmatch", "hazard"})


class EndToEnd(unittest.TestCase):
    def test_public_json_carries_no_paths_and_gates_macros(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "studies"
            for study in ("s1", "s2", "s3"):
                folder = root / study / "analyses"
                folder.mkdir(parents=True)
                (folder / "cm.dead.sas").write_text(
                    "%gmatch(data=x); %only_" + study + "(a); proc phreg data=m; model t*d(0)=trt; run;")
            (root / "s1" / "analyses" / "tp.cm.dead.sas").write_text("proc phreg; run;")
            (root / "s2" / "40_graphs").mkdir()
            (root / "s2" / "40_graphs" / "cm.dead.R").write_text("coxph(Surv(t, d) ~ trt, weights = w)")
            private, public = Path(tmp) / "out" / "rows.csv", Path(tmp) / "out" / "summary.json"
            import sys
            argv, sys.argv = sys.argv, ["census", str(root), str(private), str(public)]
            try:
                census.main()
            finally:
                sys.argv = argv
            text = public.read_text()
            result = json.loads(text)
            self.assertNotIn(tmp, text)
            self.assertNotIn("s1", text)
            self.assertEqual(result["corpus_programs"], 3)
            self.assertEqual(result["r_jobs"], 1)
            self.assertEqual(result["template_copies_skipped"], 1)
            self.assertEqual(result["shapes"]["match_and_fit"]["sas_studies"], 3)
            self.assertEqual(result["shapes"]["fit_weighted"]["r_jobs"], 1)
            self.assertEqual(result["match_step_studies"], 3)
            self.assertEqual(result["folders"]["graphs"], {"programs": 1, "studies": 1})
            self.assertEqual(result["macros"], {"gmatch": 3})


if __name__ == "__main__":
    unittest.main()
