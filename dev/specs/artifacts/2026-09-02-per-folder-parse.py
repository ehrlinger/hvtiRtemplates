#!/usr/bin/env python3
"""Re-parse the job census with the qualifier fields the old parser discarded.

WHY THIS EXISTS
---------------
`hvtiRutilities:::.job_name_fields()` captured the first dot-field of a legacy
name as the prefix and threw the rest away. So `dp.trends`, `dp.gfup` and
`dp.spaghetti.echo` all reduced to one bucket called `dp`, and
`2026-08-29-roadmap-seed.py` ordered the conversion work by the size of
buckets like that one. A bucket cannot be templated.

The fix landed upstream (hvtiRutilities, `qualifier1` / `qualifiers` /
`n_qualifiers`). This script applies the SAME rule to the existing raw
catalogue rather than re-walking 2.24M files over a share, which is sound
because the parse is a pure function of the `stem` and `folder` columns the
catalogue already carries.

The evidence that this Python parse agrees with the R one is that it
reproduces the 2026-08-29 all-extension count EXACTLY for all 42 prefixes,
and that file was written by the R parser. `--selftest` runs fixed cases in
this file and checks nothing about R.

WHAT IT DELIBERATELY DOES NOT DO
--------------------------------
It does not name what the qualifier MEANS. Measured here, the first qualifier
is an outcome in `analyses`, a table type in `descriptive`, a clinical
variable in `distributions` and a mix in `graphs`. One name for all four is
the assumption-at-scale error this whole exercise is undoing. Classification
is a separate, curated step; see the design note.

INPUT
-----
The raw catalogue path is an ARGUMENT, never a literal. Every row of
census-ALL.csv is a study path and this is a public repository.

    python3 2026-09-02-per-folder-parse.py <census-ALL.csv> [-o OUTDIR]
"""

import argparse
import collections
import csv
import json
import os
import sys

# Extensions that are a PROGRAM. Everything else in the corpus is something a
# program produced (lst, log, pdf, ps, cgm), something a dataset lives in
# (sas7bdat, ssd01, rda, RData), or an editor backup (sas~, R~, BAK). The
# 2026-08-29 census counted every extension and said so in its own caveat;
# that is why `estimates` looked like 24,358 hazard jobs when it holds 24,358
# hazard RESULTS.
PROGRAM_EXT = {
    "sas", "R", "r", "S", "qmd", "Rmd", "rmd", "Rnw", "sql", "py", "do",
}

# Folders whose content is output rather than work. `datasets` is NOT one of
# them: it holds 27,231 .sas programs that BUILD datasets, and dropping it
# would repeat this bug with the opposite sign.
OUTPUT_FOLDERS = {"estimates"}

# A qualifier that is a naming defect rather than a thing the job does.
# `tp.br.linear_regression_summary` states the analysis and omits the
# endpoint, where the analyses grammar is <prefix>.<outcome>[.<qualifier>].
# Flagged, counted and reported -- never quietly bucketed.
#
# Every entry here FIRES on the corpus: linear_regression_summary and
# linear_regression_bagging at 2 studies each, bagging at 1. A bare `summary`
# was listed until Copilot pointed out that it contradicts the design note,
# which corrects the handoff's claim that `tp.br.summary` is the malformed
# case. It is not; it does not occur. A filter for a form the corpus does not
# contain, sitting next to prose saying it does not contain it, is the same
# kind of unchecked assumption as the bug being fixed.
MALFORMED_ANALYSES_Q1 = {
    "linear_regression_bagging", "linear_regression_summary", "bagging",
}


def qualifiers(stem):
    """The dot-fields between the prefix and the extension.

    `stem` from the catalogue already has the extension stripped, so unlike
    the R function this drops only the FIRST field. The R function is handed
    a full basename and must drop the last field too.

    `--selftest` does NOT check that against R. It runs fixed cases in this
    file and nothing else, so it catches a typo here and would not notice
    the two implementations diverging. The real cross-check is that this
    script reproduces the 2026-08-29 all-extension count EXACTLY for all 42
    prefixes, and that file was produced by the R parser: agreement on
    every prefix over 2.24M rows is a stronger statement than any fixture,
    and it is checked by comparing the two JSON files rather than here.
    """
    s = stem[3:] if stem.startswith("tp.") else stem
    parts = s.split(".")
    return parts[0], parts[1:]


def selftest():
    cases = [
        ("hz.dead", "hz", ["dead"]),
        ("tp.dp.spaghetti.echo", "dp", ["spaghetti", "echo"]),
        ("hzdead", "hzdead", []),
        ("dp.afib", "dp", ["afib"]),
        ("tp.br.linear_regression_summary", "br",
         ["linear_regression_summary"]),
    ]
    # Fixed cases only. This asserts nothing about the R implementation; see
    # the note in qualifiers() for what actually cross-checks the two.
    bad = [(s, qualifiers(s), (p, q)) for s, p, q in cases
           if qualifiers(s) != (p, q)]
    for s, got, want in bad:
        print(f"SELFTEST FAIL {s!r}: got {got}, want {want}", file=sys.stderr)
    print(f"selftest: {len(cases) - len(bad)}/{len(cases)} pass")
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("census", help="path to census-ALL.csv (NOT committed)")
    ap.add_argument("-o", "--outdir", default=os.path.dirname(
        os.path.abspath(__file__)))
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        sys.exit(selftest())

    csv.field_size_limit(10 ** 7)

    # (folder, prefix) -> studies, and (folder, prefix, q1) -> studies.
    # Sets of study ids, because "how many studies use this" is the question
    # the batch order is built on, and a study with 40 copies of one job is
    # still one study. The study ids never leave this process.
    breadth = collections.defaultdict(set)          # prefix -> studies (jobs)
    breadth_all = collections.defaultdict(set)      # prefix -> studies (any ext)
    fq = collections.defaultdict(lambda: collections.defaultdict(set))
    fq_rows = collections.defaultdict(collections.Counter)
    r_breadth = collections.defaultdict(set)
    fam_studies = collections.defaultdict(set)      # (folder, prefix) -> studies
    malformed = collections.defaultdict(set)
    depth_hist = collections.defaultdict(collections.Counter)
    unknown_est = collections.defaultdict(set)
    n_rows = n_job_rows = 0

    R_EXT = {"R", "r", "Rmd", "rmd", "qmd", "Rnw", "S"}

    with open(a.census, newline="") as fh:
        for x in csv.DictReader(fh):
            n_rows += 1
            if x["naming"] != "legacy":
                continue
            folder, study, ext = x["folder"], x["study"], x["ext"]
            # An unplaced file has no taxonomy folder above it, so there is
            # no study to attribute it to. The catalogue writes the literal
            # string "NA" there, and counting it as a study added exactly one
            # phantom study to 35 of the 42 prefixes -- a uniform +1, which
            # is what made it findable.
            if study == "NA":
                continue
            p, qs = qualifiers(x["stem"])
            q1 = qs[0] if qs else None

            if x["prefix_class"] == "unknown":
                # The fused names the roadmap hand-corrected. Recorded with
                # their folder so the correction can be judged rather than
                # assumed.
                if folder in OUTPUT_FOLDERS:
                    unknown_est[p].add(study)
                continue
            if x["prefix_class"] != "known":
                continue

            # Templates are excluded from BOTH counts. A `tp.*` file is
            # copied into nearly every study, so counting them answers "how
            # many studies hold a copy of the template library", which came
            # out at ~1,100 for every prefix alike -- a uniform number is the
            # tell. The 2026-08-29 census excluded them too; this is what
            # makes `sas_breadth_all_ext` comparable to its distinct_studies.
            if x["is_template"] == "TRUE":
                continue
            breadth_all[p].add(study)
            is_job = (ext in PROGRAM_EXT and folder not in OUTPUT_FOLDERS)
            if not is_job:
                continue
            n_job_rows += 1
            breadth[p].add(study)
            if ext in R_EXT:
                r_breadth[p].add(study)
            depth_hist[folder][min(len(qs), 5)] += 1
            fam_studies[(folder, p)].add(study)
            if q1 is not None:
                fq[(folder, p)][q1].add(study)
                fq_rows[(folder, p)][q1] += 1
            if folder == "analyses" and q1 in MALFORMED_ANALYSES_Q1:
                malformed[(p, q1)].add(study)

    # ---- emit, counts only ----------------------------------------------
    # Every sort below carries a secondary key on the NAME. Python's sort is
    # stable, so ties would otherwise fall back to dict insertion order, which
    # is the order rows happened to appear in the catalogue. Two runs over
    # equivalent sweeps would then produce byte-different JSON carrying
    # identical data, and a regenerated artifact whose diff is noise is one
    # nobody reads. Raised by Copilot on #72.
    prefixes = sorted(breadth_all, key=lambda p: (-len(breadth_all[p]), p))
    known = [{
        "prefix": p,
        "sas_breadth_all_ext": len(breadth_all[p]),
        "sas_breadth_jobs": len(breadth[p]),
        "r_studies": len(r_breadth[p]),
    } for p in prefixes]

    families = []
    # Ordered by DISTINCT studies in the folder, not by the sum over
    # qualifiers. Summing double-counts a study that runs both dp.trends and
    # dp.gfup, which is the exact arithmetic this file's own provenance warns
    # against, and it ranked families by how many job types they spread over
    # rather than by how widely they are used. Raised by Copilot on #72.
    for (folder, p), d in sorted(fq.items(), key=lambda kv: (
            -len(fam_studies[kv[0]]), kv[0])):
        top = sorted(d.items(), key=lambda kv: (-len(kv[1]), kv[0]))
        families.append({
            "folder": folder,
            "prefix": p,
            "distinct_qualifier1": len(d),
            # Scoped to THIS folder. The prefix-wide count read 310 for
            # analyses/lp, a folder holding one lp job, which is the same
            # kind of mis-scoping the qualifier fix exists to undo.
            "job_studies_in_folder": len(fam_studies[(folder, p)]),
            "job_studies_all_folders": len(breadth[p]),
            "qualifier1_top": [
                {"qualifier1": q, "studies": len(s), "rows": fq_rows[
                    (folder, p)][q]} for q, s in top[:25]
            ],
        })

    out = {
        "_provenance": {
            "source": "re-parse of census-ALL.csv (2026-08-27 06:42 sweep) "
                      "with the qualifier fields restored",
            "supersedes": "2026-08-29-job-census-summary.json",
            "parser_fix": "hvtiRutilities .job_name_fields(), "
                          "qualifier1/qualifiers/n_qualifiers",
            "rows_read": n_rows,
            "job_rows": n_job_rows,
            "job_definition": {
                "program_ext": sorted(PROGRAM_EXT),
                "output_folders_excluded": sorted(OUTPUT_FOLDERS),
                "templates_excluded": "is_template == TRUE",
                "why": "the 2026-08-29 census counted every extension, so a "
                       ".lst, a .log, a .pdf and a .sas7bdat each counted as "
                       "evidence that a study runs a job of that type",
            },
            "identifiers": "counts only. No path, study name, filename stem "
                           "or patient identifier leaves this script. "
                           "qualifier1 values DO include generic clinical "
                           "variable names (echo, afib, lvmassi) under "
                           "distributions, because that is the finding: the "
                           "qualifier is a variable there. They are shared "
                           "clinical vocabulary, not study-specific.",
            "qualifier1_is_positional": "it is an outcome in analyses, a "
                                        "table type in descriptive, a "
                                        "clinical variable in distributions "
                                        "and a mix in graphs. See the design "
                                        "note; do not name it in one word.",
        },
        "known": known,
        "families": families,
        "malformed_analyses": sorted(
            ({"prefix": p, "qualifier1": q, "studies": len(s)}
             for (p, q), s in malformed.items()),
            key=lambda d: (-d["studies"], d["prefix"], d["qualifier1"])),
        "output_folder_unknowns": sorted(
            ({"stem_head": p, "studies": len(s)}
             for p, s in unknown_est.items() if len(s) >= 20),
            key=lambda d: (-d["studies"], d["stem_head"])),
        "qualifier_depth_by_folder": {
            f: dict(sorted(c.items())) for f, c in sorted(depth_hist.items())
        },
    }
    dest = os.path.join(a.outdir, "2026-09-02-job-census-summary.json")
    with open(dest, "w") as fh:
        json.dump(out, fh, indent=1, sort_keys=False)
        fh.write("\n")
    print(f"wrote {dest}: {len(known)} known prefixes, {len(families)} "
          f"(folder, prefix) families, {n_job_rows} job rows of {n_rows}")


if __name__ == "__main__":
    main()
