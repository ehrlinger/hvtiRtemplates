#!/usr/bin/env python3
"""Count the analysis reports in the studies corpus, when they are Word files
under many different names.

WHY THIS EXISTS
---------------
`ar`'s catalog breadth reads 394. That is a count of distinct studies holding a
file whose NAME parses to the prefix `ar` and whose extension is a PROGRAM
extension. Neither condition holds for an analysis report: it is a Word
document, and the corpus did not name it `ar.*`. The figure was withdrawn on
2026-11-12 rather than re-measured, because nothing measures this today.

This script is the measurement. It does NOT re-walk the share. The
2026-08-27 sweep enumerated 2,240,570 files (`files_scanned` in
2026-08-29-job-census-summary.json), and the 2026-09-02 parse kept only 59,963
of them as job rows (`job_rows` in 2026-09-02-job-census-summary.json). Every
other file is still a row in `census-ALL.csv`, names that do not parse
included (`naming` is NA for those), so every Word document in the corpus is
already catalogued; what excluded them was the filter, not the walk. This
reads the same catalogue with a different filter.

THE THREE STAGES, AND WHY IT IS NOT ONE NUMBER
----------------------------------------------
1. UPPER BOUND. Every document-class file attributable to a study. Exact,
   cheap, and already a better figure than 394. It is an upper bound because
   a study's `documents` folder also holds manuscripts, protocols, letters
   and abstracts.
2. NAMED EXCLUSIONS. Obvious non-reports removed by name, each to a NAMED
   bucket with a count. Never silently absorbed: the handoff for the last
   parse is explicit that the unmatched bucket grew to 103,454 rows because
   nobody reported it.
3. A SAMPLE TO HAND-LABEL. Stages 1 and 2 cannot tell a report from a
   manuscript, and no name rule will. A random sample, labelled by a person,
   turns the remainder into an estimate with an interval instead of a guess.
   This is the same shape as the 9 September macro denominator correction:
   measure the frame exactly, estimate the proportion honestly. A second,
   smaller sample is drawn from the EXCLUDED rows, because a wrong exclusion
   is otherwise invisible: the main sample only ever sees what survived.

   The FILE sample estimates VOLUME and nothing else. It cannot estimate
   breadth: it draws a study with many documents more often than one with
   few, and a study counts toward breadth when ANY of its files is a report,
   which is not the fraction of its files that are. 100 studies each holding
   one report and nine other documents give a file proportion of 10% and a
   breadth of 100%. Breadth therefore gets its own sample: studies drawn
   uniformly from those with a kept file, each listed with ALL its kept
   files, labelled once per study for "holds at least one report".

TWO FIGURES, NOT ONE
--------------------
BREADTH is distinct studies holding at least one, and is what the catalog's
column wants. VOLUME is the number of reports, and is what the work estimate
wants. They are far apart here: there is at least one report per study and a
study has one per research question, so volume exceeds breadth by a multiple
that this script measures rather than assumes. Volume is reported twice: as
files, and after collapsing drafts (`report_v1`, `report_v2`,
`report_final`) to one report per normalised stem within a study. Report both;
never sum buckets.

WHAT THE CATALOGUE CANNOT SEE
-----------------------------
A file with no taxonomy folder above it has no study: in the catalogue
`study`, `folder` and `status` read NA, NA and `unplaced` together. 40% of the
R-side rows are like that. A report kept in a study with no taxonomy folders
is therefore uncountable here, and both breadth and volume are LOWER bounds on
the corpus over placed files. The unplaced count is reported by extension so
the size of that gap is visible.

PRIVACY
-------
The JSON output is COUNTS ONLY, to the same standard as the existing census
summaries: no path, study name or filename stem leaves this script. The
hand-labelling sample DOES carry paths, by necessity, and is written to a
separate file that is marked for a local directory and must not be committed.

USAGE
    python3 2026-11-12-ar-census.py <census-ALL.csv> [-o OUTDIR]
        [--sample N] [--audit N] [--seed N]

The catalogue path is an ARGUMENT, never a literal, because every row of it is
a study path and these scripts live in a public repository. Run it on lri, not
over the Mac's mount. Tests: `python3 -m unittest test_ar_census` from this
directory.
"""

import argparse
import collections
import csv
import json
import random
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------- vocabulary

# What an analysis report can be stored as. `.doc` dominates the older corpus
# and is a binary format: see the note on stage 3 about reading it.
DOC_EXT = {"doc", "docx", "rtf", "odt"}

# Carried separately rather than folded in. A PDF is usually an EXPORT of a
# report that also exists as Word, so counting it with the Word files would
# double-count the same report; counting it as nothing would miss a report
# whose Word original is gone. Reported on its own so the decision is visible.
EXPORT_EXT = {"pdf"}

# The folder an analysis report is SUPPOSED to live in. Used to report the
# split, NOT to filter: the question that prompted this says many of them sit
# in `documents` and implies others do not, and a filter on folder would bake
# that assumption into the answer.
REPORT_FOLDER = "documents"

# Files the OS or Office writes beside a document. `~$name.docx` is Word's
# owner (lock) file, `.~lock.name#` LibreOffice's, and `._name.docx` is the
# AppleDouble resource fork a Mac writes on an SMB share, often one per real
# document. None is a report and each would count as one, so they are removed
# FIRST, to a bucket of their own.
SYSTEM_PREFIXES = ("~$", "._", ".~lock")

# Files copied into most studies by the scaffold or by habit: the binder
# summary, the reference list, the GFR formula, the survival-dates note, the
# standard methods write-ups, and the filled-in proposal and project-plan
# forms. None is an analysis report. Read in the 2026-11-12 study sample, where
# seven of the twenty studies labelled `no` held nothing else, which is why
# nearly every study had a kept file. Matched on the stem's TOKENS (see
# `tokens()`): it must START with one of these sequences, and every token after
# it must be a number or a word in BOILERPLATE_TAIL. The copies carry suffixes
# such as " (2)", "_v1", "[approved]", a study number or a date, and the tail
# list admits those. Anything else after the name, a title word such as
# `outcomes` or `report`, keeps the file: `Proposal valve outcomes analysis
# report` may be a report, and only a person can say. A bare prefix match
# excluded it, and with it any study whose only report was named that way
# (raised by Codex on #537).
BOILERPLATE = (
    ("binder", "summaries"), ("stat", "refs"), ("gfr", "ckd", "epi", "formula"),
    ("dates", "4", "survival"), ("vars", "sas", "script", "doc"),
    ("methods", "rf", "and", "boosting"), ("methods", "rf", "boosting"),
    ("methods", "boosting"), ("rf", "stat", "method", "desc"),
    ("boostmtree", "method", "description"), ("projectplan",),
    ("projectplandatasources",), ("proposal",),
    ("guidelines", "follow", "up", "cohort"), ("request", "for", "fup"),
)
BOILERPLATE_TAIL = {"v", "ver", "version", "final", "draft", "rev", "revised",
                    "copy", "old", "new", "updated", "study", "st", "stxxxx",
                    "approved", "data", "only", "from", "and", "proposal"}


def is_boilerplate(stem):
    t = tokens(stem)
    return any(tuple(t[:len(seq)]) == seq
               and all(x.isdigit() or x in BOILERPLATE_TAIL for x in t[len(seq):])
               for seq in BOILERPLATE)

# Stage 2. Each entry gets its own named bucket and its own count. Matched as
# WHOLE TOKENS of the lowercased stem (see `tokens()`), with an optional plural
# `s`, never as substrings. Substring matching removed real reports in this
# corpus's vocabulary: `sap` matched SAPIEN, `cover` recovery, `poster`
# posterior, `cv` cvd, `minutes` cpb_minutes, `response` treatment_response,
# `revision` a reoperation. `cv`, `minutes`, `response` and `revision` are
# dropped outright, because even as a whole token each is ordinary clinical
# vocabulary. A pattern here must be something that is NOT an analysis report
# under any reading; the audit sample is how that claim gets checked.
# A multi-word entry (`draft_ms`) matches those tokens in sequence.
EXCLUDE = {
    "consent_or_irb":  ("consent", "irb", "icf", "hipaa", "assent"),
    "protocol":        ("protocol", "sap", "charter"),
    "correspondence":  ("letter", "memo", "email", "cover", "rebuttal"),
    "manuscript":      ("manuscript", "paper", "draft_ms", "submission",
                        "galley", "proof"),
    "abstract_or_talk": ("abstract", "poster", "slide", "talk", "presentation"),
    "admin":           ("budget", "invoice", "agenda", "roster",
                        "timeline", "checklist"),
    "data_dictionary": ("dictionary", "codebook", "variable_list", "varlist"),
}

# Tokens that mark a version of a report rather than a different report.
# Stripped, along with bare numbers, before stems are compared for the
# deduplicated volume.
VERSION_TOKENS = {"v", "ver", "version", "final", "draft", "rev", "revised",
                  "copy", "old", "new", "updated", "edit", "edits"}


def tokens(stem):
    """Lowercased runs of letters and of digits. Digits split from letters so
    `abstract2019` and `report_v3` tokenise as `abstract 2019`, `report v 3`."""
    return re.findall(r"[a-z]+|[0-9]+", stem.lower())


_EXCLUDE_RE = {
    bucket: re.compile(r"(?:^|_)(?:" + "|".join(
        re.escape(p) + "s?" for p in pats) + r")(?:_|$)")
    for bucket, pats in EXCLUDE.items()
}


# Manuscripts the name rule misses sit under a manuscript folder: names run
# together (`...Manuscript`), misspelt (`Mansucript`), abbreviated (`Revised ms`)
# or named for the journal. They were a fifth of kept files in both 2026-11-12
# runs. Only folders BELOW the taxonomy folder are read (see `subfolders()`): a
# study path such as `ms_outcomes` says nothing about one file. The rule runs
# AFTER the name buckets, so a name that says what the file is still decides,
# and an `ar`-named file is kept even inside a manuscript folder, because an
# analyst who files the final report beside the paper has not made it a paper.
_MS_DIR_STEMS = ("manuscrip", "manuscrpt", "mansucrip")


def subfolders(path, study):
    """The folders between the taxonomy folder and the file, or () when the
    study key cannot be found in the path."""
    p = (path or "").replace("\\", "/")
    i = p.find("/" + study + "/")
    if not study or i < 0:
        return ()
    parts = p[i + len(study) + 2:].split("/")
    return tuple(parts[1:-1])


def is_manuscript_folder(name):
    t = tokens(name)
    return (any(x in "".join(t) for x in _MS_DIR_STEMS)
            or "ms" in t
            or bool(_EXCLUDE_RE["manuscript"].search("_".join(t))))


def classify_exclusion(stem, subdirs=()):
    """The FIRST bucket a file matches, or None. First-match rather than
    all-match so the buckets sum to the excluded total and can be reported as
    a partition. `subdirs` is `subfolders()` of the file's path; without it
    the folder rule is skipped."""
    if stem.startswith(SYSTEM_PREFIXES):
        return "system_artifact"
    if is_boilerplate(stem):
        return "boilerplate"
    t = tokens(stem)
    joined = "_".join(t)
    for bucket, rx in _EXCLUDE_RE.items():
        if rx.search(joined):
            return bucket
    if t[:1] != ["ar"] and any(is_manuscript_folder(d) for d in subdirs):
        return "manuscript_folder"
    return None


def report_key(stem):
    """The stem with version and date tokens removed, so drafts of one report
    collapse together. Falls back to the full token string when stripping
    would leave nothing (a file named `final.docx`)."""
    t = tokens(stem)
    kept = [x for x in t if x not in VERSION_TOKENS and not x.isdigit()]
    return "_".join(kept or t)


# ---------------------------------------------------------------- the columns

def resolve_columns(fieldnames):
    """The catalogue's column names are detected, not assumed.

    This script is run once, possibly a year after the catalogue was written,
    by someone who did not write either. A KeyError two million rows into a
    479 MB file is the worst way to find out a column was renamed, so the
    header is checked before the first row is read."""
    if not fieldnames:
        sys.exit("census has no header row")
    have = {f.lower(): f for f in fieldnames}
    need = {}
    for want, alts in (("stem", ("stem", "name", "basename")),
                       ("ext", ("ext", "extension", "suffix")),
                       ("folder", ("folder", "taxonomy_folder")),
                       ("study", ("study", "study_id"))):
        for a in alts:
            if a in have:
                need[want] = have[a]
                break
        else:
            sys.exit(f"census is missing a column for {want!r}; "
                     f"header is: {', '.join(fieldnames)}")
    # Optional. Templates are copied into nearly every study, so counting them
    # returned a near-uniform ~1,100 studies for every prefix alike in the
    # 2026-09-02 parse. If the column is absent the `tp.` stem rule still
    # catches most of them, and the output says which test was used.
    for a in ("is_template", "template"):
        if a in have:
            need["is_template"] = have[a]
            break
    # Optional, and only needed for the samples.
    for a in ("path", "fullpath", "file", "relpath"):
        if a in have:
            need["path"] = have[a]
            break
    return need


def is_template(row, cols):
    if "is_template" in cols:
        v = str(row[cols["is_template"]]).strip().lower()
        if v in ("true", "t", "1", "yes"):
            return True
        if v in ("false", "f", "0", "no", ""):
            return False
    return row[cols["stem"]].startswith("tp.")


class Reservoir:
    """Algorithm R: one pass, and every offered item has the same probability
    of being kept. Used so the 479 MB file is read once."""

    def __init__(self, k, rng):
        self.k, self.rng, self.seen, self.items = k, rng, 0, []

    def offer(self, item):
        self.seen += 1
        if len(self.items) < self.k:
            self.items.append(item)
        else:
            j = self.rng.randrange(self.seen)
            if j < self.k:
                self.items[j] = item


# ---------------------------------------------------------------- the pass

def count(rows, cols, sample=120, audit=40, studies=40, seed=20261112):
    """Every count, from an iterable of catalogue rows. Returns the summary
    dict (counts only), the file sample, the audit sample (paths), and the
    study sample: a list of (study, [paths]) drawn uniformly over studies."""
    rng = random.Random(seed)
    has_path = "path" in cols
    kept_sample = Reservoir(sample, rng)
    audit_sample = Reservoir(audit, rng)
    # Every kept path, by study, for the study sample. Held in memory: kept
    # document rows are a small fraction of the 2.24M, and a study can only be
    # labelled "holds a report" by seeing all of its candidates.
    study_files = collections.defaultdict(list)

    studies_any = set()                                   # breadth, upper bound
    studies_kept = set()                                  # breadth, after exclusions
    by_folder = collections.Counter()                     # volume by folder
    by_ext = collections.Counter()                        # volume by extension
    excluded = collections.Counter()                      # volume by named bucket
    exports_by_folder = collections.Counter()
    per_study_kept = collections.Counter()                # volume per study, for the ratio
    report_keys = set()                                   # (study, report_key)
    unplaced = collections.Counter()                      # by extension
    templates_skipped = 0
    rows_read = 0
    kept_total = 0

    for row in rows:
        rows_read += 1
        ext = (row[cols["ext"]] or "").strip().lstrip(".").lower()
        if ext not in DOC_EXT and ext not in EXPORT_EXT:
            continue

        study = (row[cols["study"]] or "").strip()
        # The catalogue writes the literal string "NA" for a file with no
        # taxonomy folder above it. Counting it as a study added exactly one
        # phantom study to 35 of 42 prefixes last time.
        if study == "NA" or study == "":
            unplaced[ext] += 1
            continue
        if is_template(row, cols):
            templates_skipped += 1
            continue

        folder = (row[cols["folder"]] or "NA").strip()

        if ext in EXPORT_EXT:
            exports_by_folder[folder] += 1
            continue

        stem = row[cols["stem"]] or ""
        bucket = classify_exclusion(
            stem, subfolders(row[cols["path"]], study) if has_path else ())
        if bucket == "system_artifact":
            # Not a document at all, so it is kept out of stage 1 too.
            excluded[bucket] += 1
            continue

        studies_any.add(study)
        by_folder[folder] += 1
        by_ext[ext] += 1

        if bucket:
            excluded[bucket] += 1
            if has_path:
                audit_sample.offer((bucket, row[cols["path"]]))
            continue

        studies_kept.add(study)
        per_study_kept[study] += 1
        report_keys.add((study, report_key(stem)))
        kept_total += 1
        if has_path:
            kept_sample.offer(("kept", row[cols["path"]]))
            study_files[study].append(row[cols["path"]])

    # Uniform over studies, not files: this is what makes the labelled
    # proportion an estimate of breadth. Sorted first so the draw depends on
    # the seed and not on the catalogue's row order.
    drawn = rng.sample(sorted(study_files), min(studies, len(study_files)))
    study_sample = [(s, study_files[s]) for s in drawn]

    # The ratio this whole exercise is about: reports per study, measured.
    counts = sorted(per_study_kept.values())
    n = len(counts)

    def pct(p):
        return counts[min(n - 1, int(p * n))] if n else 0

    summary = {
        "_provenance": {
            "rows_read": rows_read,
            "method": "document-class extensions attributable to a study, from the "
                      "existing corpus catalogue. No re-walk of the share.",
            "identifiers": "counts only. No path, study name or filename stem is in "
                           "this file. The sample file carries paths and is local.",
            "doc_ext": sorted(DOC_EXT),
            "export_ext_counted_separately": sorted(EXPORT_EXT),
            "exclusion_match": "first match wins, in this order: system files by raw "
                               "prefix " + ", ".join(SYSTEM_PREFIXES) + "; then "
                               "boilerplate by a known leading token sequence followed "
                               "only by numbers or version, study and approval words; then the named buckets by "
                               "whole tokens of the lowercased stem, optional plural s; "
                               "last, a file not named ar under a folder below the taxonomy "
                               "folder whose name reads as a manuscript",
            "template_test": "is_template column" if "is_template" in cols
                             else "stem starts with 'tp.'",
            "seed": seed,
            "samples": "written" if has_path else "SKIPPED: the census has no path column",
            "coverage": "placed files only. A file with no taxonomy folder above it "
                        "has no study and cannot be counted, so breadth and volume "
                        "are LOWER bounds on the corpus; see skipped.unplaced.",
        },
        "stage1_upper_bound": {
            "volume_files": sum(by_folder.values()),
            "breadth_studies": len(studies_any),
            "by_folder": dict(by_folder.most_common()),
            "by_extension": dict(by_ext.most_common()),
            "in_report_folder": by_folder.get(REPORT_FOLDER, 0),
            "outside_report_folder": sum(v for k, v in by_folder.items()
                                         if k != REPORT_FOLDER),
            "_note": "the folder split is REPORTED, not filtered on. Anything outside "
                     "the documents folder is the part a folder-based rule would miss. "
                     "System files (lock, AppleDouble) are not in this stage.",
        },
        "stage2_after_named_exclusions": {
            "volume_files": kept_total,
            "volume_reports_drafts_collapsed": len(report_keys),
            "breadth_studies": len(studies_kept),
            "excluded_by_bucket": dict(excluded.most_common()),
            "excluded_total": sum(excluded.values()),
            "_note": "a partition: each stem lands in its FIRST matching bucket, so the "
                     "buckets sum to excluded_total. system_artifact rows were never in "
                     "stage 1, so stage1 - stage2 = excluded_total - system_artifact.",
        },
        "reports_per_study": {
            "_note": "the figure that decides whether breadth or volume is the right "
                     "column. Measured, not assumed. Counts files, so drafts inflate "
                     "it; compare volume_reports_drafts_collapsed.",
            "mean": round(kept_total / len(studies_kept), 2) if studies_kept else None,
            "mean_drafts_collapsed": round(len(report_keys) / len(studies_kept), 2)
                                     if studies_kept else None,
            "median": pct(0.50),
            "p90": pct(0.90),
            "max": counts[-1] if counts else 0,
        },
        "skipped": {
            "templates": templates_skipped,
            "unplaced": {
                "by_extension": dict(unplaced.most_common()),
                "total": sum(unplaced.values()),
                "_note": "no taxonomy folder above the file, so no study. Reports kept "
                         "this way are invisible to every other figure here.",
            },
        },
        "exports_not_counted": {
            "by_folder": dict(exports_by_folder.most_common()),
            "_note": "a PDF is usually an export of a report that also exists as Word, "
                     "so counting it here would double-count. Carried so the decision "
                     "is visible rather than silent.",
        },
        "what_this_still_does_not_know": [
            "Which of the kept files is an analysis report rather than a manuscript, "
            "a summary of one table, or a document nobody finished. Stage 3 answers "
            "this and nothing else can.",
            "Whether a report covers one research question or several. The 2026-11-11 "
            "design scaffolds one job per question; the corpus may not have worked "
            "that way, and if it did not, the template count and the report count are "
            "different numbers again.",
        ],
    }
    return summary, kept_sample, audit_sample, study_sample


def write_study_sample(path, study_sample, n_studies, seed):
    # PATHS and study names. Local only. One label per STUDY, on its first
    # row; the rows under it are what the label is judged from.
    lines = ["study_label\tstudy\tpath",
             "# label each STUDY once, on its first row: yes | no | unreadable",
             "#   yes = at least one of its files is an analysis report",
             f"# {len(study_sample)} studies drawn uniformly from {n_studies} with a "
             f"kept file, seed {seed}; the 'yes' proportion scales to {n_studies} "
             "studies (BREADTH). Do not scale the file sample to studies.",
             "# DO NOT COMMIT THIS FILE: it carries study paths."]
    for study, paths in study_sample:
        lines += [f"\t{study}\t{p}" for p in paths]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_sample(path, kept, audit, kept_total, seed):
    # PATHS. Local only. Written as a labelling worksheet rather than a list,
    # because the labelling is the expensive step and it should be possible to
    # stop halfway and still have a usable denominator.
    lines = ["label\tdrawn_from\tpath",
             "# label each row: report | manuscript | other | unreadable",
             f"# 'kept' rows: drawn from {kept_total} kept files, seed {seed}; the "
             f"labelled proportion scales to {kept_total} FILES (volume) only. It does "
             "not estimate breadth: use ar-studies-LOCAL.tsv for that",
             f"# other rows: drawn from {audit.seen} EXCLUDED files; a 'report' label "
             "there is a wrong exclusion, and names the bucket that made it",
             "# DO NOT COMMIT THIS FILE: it carries study paths."]
    lines += [f"\t{src}\t{p}" for src, p in kept.items + audit.items]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("census", help="census-ALL.csv from the corpus sweep (NOT committed)")
    ap.add_argument("-o", "--outdir", default=".", help="where to write the results")
    ap.add_argument("--sample", type=int, default=120,
                    help="kept rows to draw for hand-labelling (default 120)")
    ap.add_argument("--audit", type=int, default=40,
                    help="excluded rows to draw for checking the exclusions (default 40)")
    ap.add_argument("--studies", type=int, default=40,
                    help="studies to draw for estimating breadth (default 40)")
    ap.add_argument("--seed", type=int, default=20261112,
                    help="sampling seed, recorded in the output so the draw is repeatable")
    args = ap.parse_args()

    out = Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)
    # A long path field otherwise raises _csv.Error partway through the file.
    # The 2026-09-02 parse of the same catalogue sets the same limit.
    csv.field_size_limit(10 ** 7)

    with open(args.census, newline="", encoding="utf-8", errors="replace") as fh:
        rdr = csv.DictReader(fh)
        cols = resolve_columns(rdr.fieldnames)
        if "path" not in cols:
            print("WARNING: the census has no path column, so no sample can be drawn "
                  "and stage 3 is skipped", file=sys.stderr)
        summary, kept, audit, study_sample = count(
            rdr, cols, args.sample, args.audit, args.studies, args.seed)

    summary["_provenance"]["source"] = Path(args.census).name
    (out / "ar-census-summary.json").write_text(
        json.dumps(summary, indent=2) + "\n", encoding="utf-8")

    s1, s2 = summary["stage1_upper_bound"], summary["stage2_after_named_exclusions"]
    print(f"read {summary['_provenance']['rows_read']:,} rows")
    print(f"stage 1 upper bound : {s1['volume_files']:,} files in "
          f"{s1['breadth_studies']:,} studies")
    print(f"stage 2 after names : {s2['volume_files']:,} files "
          f"({s2['volume_reports_drafts_collapsed']:,} with drafts collapsed) in "
          f"{s2['breadth_studies']:,} studies")
    r = summary["reports_per_study"]
    if r["mean"] is not None:
        print(f"reports per study   : mean {r['mean']:.2f} "
              f"({r['mean_drafts_collapsed']:.2f} drafts collapsed), "
              f"median {r['median']}, p90 {r['p90']}")
    print(f"unplaced, uncounted : {summary['skipped']['unplaced']['total']:,} files")
    print(f"wrote {out / 'ar-census-summary.json'}")
    if kept.items or audit.items:
        p = out / "ar-sample-LOCAL.tsv"
        write_sample(p, kept, audit, s2["volume_files"], args.seed)
        print(f"wrote {p} ({len(kept.items)} kept + {len(audit.items)} excluded rows to label)")
    if study_sample:
        p = out / "ar-studies-LOCAL.tsv"
        write_study_sample(p, study_sample, s2["breadth_studies"], args.seed)
        print(f"wrote {p} ({len(study_sample)} studies to label, for breadth)")


if __name__ == "__main__":
    main()
