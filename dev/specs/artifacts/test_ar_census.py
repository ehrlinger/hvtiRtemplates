import importlib.util
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("census", HERE / "2026-11-12-ar-census.py")
census = importlib.util.module_from_spec(spec)
spec.loader.exec_module(census)

COLS = census.resolve_columns(["path", "study", "folder", "status", "naming",
                               "is_template", "stem", "ext"])


def row(stem, ext="docx", study="s1", folder="documents", template="FALSE"):
    return {"path": f"/x/{study}/{folder}/{stem}.{ext}", "study": study,
            "folder": folder, "status": "placed", "naming": "NA",
            "is_template": template, "stem": stem, "ext": ext}


def run(rows, **kw):
    return census.count(rows, COLS, **kw)[0]


class Exclusions(unittest.TestCase):
    # Every one of these was excluded by the substring rule this replaced.
    def test_clinical_vocabulary_is_kept(self):
        for stem in ("lv_recovery_report", "posterior_leaflet_analysis",
                     "SAPIEN_outcomes", "cvd_mortality", "lcvh_echo",
                     "cpb_minutes_los", "treatment_response",
                     "redo_revision_surgery"):
            with self.subTest(stem=stem):
                self.assertIsNone(census.classify_exclusion(stem))

    def test_whole_tokens_still_exclude(self):
        cases = {"cover_letter": "correspondence", "SAP_v2": "protocol",
                 "AATS_abstract2019": "abstract_or_talk", "posters": "abstract_or_talk",
                 "consent-form": "consent_or_irb", "draft_ms_jtcvs": "manuscript",
                 "variable_list": "data_dictionary"}
        for stem, bucket in cases.items():
            with self.subTest(stem=stem):
                self.assertEqual(census.classify_exclusion(stem), bucket)

    def test_lock_and_appledouble_files_are_system_artifacts(self):
        for stem in ("~$analysis_report", "._analysis_report", ".~lock.analysis_report#"):
            with self.subTest(stem=stem):
                self.assertEqual(census.classify_exclusion(stem), "system_artifact")


class Counts(unittest.TestCase):
    def test_system_artifacts_are_not_in_stage1(self):
        s = run([row("report"), row("~$report"), row("._report")])
        self.assertEqual(s["stage1_upper_bound"]["volume_files"], 1)
        self.assertEqual(s["stage2_after_named_exclusions"]["excluded_by_bucket"],
                         {"system_artifact": 2})

    def test_artifact_only_study_adds_no_breadth(self):
        s = run([row("report"), row("._report", study="s2")])
        self.assertEqual(s["stage1_upper_bound"]["breadth_studies"], 1)

    def test_drafts_collapse_within_a_study_only(self):
        s = run([row("report_v1"), row("report_v2"), row("report_final"),
                 row("report_2019_06"), row("report_v1", study="s2")])
        s2 = s["stage2_after_named_exclusions"]
        self.assertEqual(s2["volume_files"], 5)
        self.assertEqual(s2["volume_reports_drafts_collapsed"], 2)

    def test_unplaced_is_split_by_extension(self):
        s = run([row("report", study="NA", folder="NA"),
                 row("report", ext="pdf", study="NA", folder="NA")])
        self.assertEqual(s["skipped"]["unplaced"]["by_extension"], {"docx": 1, "pdf": 1})
        self.assertEqual(s["stage1_upper_bound"]["volume_files"], 0)

    def test_templates_and_pdfs_are_not_counted(self):
        s = run([row("tp.report", template="TRUE"), row("report", ext="PDF")])
        self.assertEqual(s["stage1_upper_bound"]["volume_files"], 0)
        self.assertEqual(s["skipped"]["templates"], 1)
        self.assertEqual(s["exports_not_counted"]["by_folder"], {"documents": 1})

    def test_excluded_rows_feed_the_audit_sample(self):
        _, kept, audit, _ = census.count([row("report"), row("cover_letter")], COLS)
        self.assertEqual([s for s, _ in kept.items], ["kept"])
        self.assertEqual([s for s, _ in audit.items], ["correspondence"])

    def test_no_path_column_says_samples_skipped(self):
        cols = {k: v for k, v in COLS.items() if k != "path"}
        s, kept, audit, studies = census.count([row("report")], cols)
        self.assertIn("SKIPPED", s["_provenance"]["samples"])
        self.assertEqual(kept.items + audit.items + studies, [])

    def test_study_sample_lists_every_kept_file_of_a_drawn_study(self):
        rows = [row(f"doc{i}", study="big") for i in range(9)] + [row("report", study="small")]
        rows.append(row("cover_letter", study="small"))
        _, _, _, studies = census.count(rows, COLS, studies=2)
        got = dict(studies)
        self.assertEqual(sorted(got), ["big", "small"])
        self.assertEqual(len(got["big"]), 9)
        self.assertEqual(len(got["small"]), 1)   # excluded files are not candidates


class Sampling(unittest.TestCase):
    def test_study_sample_is_uniform_over_studies_not_files(self):
        # One study holds 90 of 100 kept files. A file-weighted draw of one
        # study would pick it ~90% of the time; a uniform one ~10%.
        rows = [row(f"d{i}", study="big") for i in range(90)]
        rows += [row("r", study=f"s{i}") for i in range(9)]
        picks = sum(dict(census.count(rows, COLS, studies=1, seed=s)[3]).get("big") is not None
                    for s in range(1000))
        self.assertTrue(50 < picks < 150, picks)

    def test_reservoir_is_uniform_enough(self):
        import random
        hits = [0] * 10
        for seed in range(2000):
            r = census.Reservoir(3, random.Random(seed))
            for i in range(10):
                r.offer(i)
            for i in r.items:
                hits[i] += 1
        # each item expected 600 times (2000 * 3 / 10)
        for h in hits:
            self.assertTrue(520 < h < 680, hits)


if __name__ == "__main__":
    unittest.main()
