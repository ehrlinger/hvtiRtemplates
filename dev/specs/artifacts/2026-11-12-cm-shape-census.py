#!/usr/bin/env python3
"""Classify legacy cm (Cox matching) jobs without publishing study identifiers.

Sibling of 2026-10-13-rm-shape-census.py. The taxonomy glosses cm as "Cox PH
with propensity matching / IPTW", which reads as an outcome model fitted on a
cohort someone else matched or weighted. No template performs the match step
today, so the question this census answers is whether cm jobs fit only, or
also build the match themselves:

    match_and_fit   the job matches (PSMATCH, a greedy/caliper macro, MatchIt,
                    ps_match) and fits a Cox model
    fit_matched     Cox on a matched set: strata or cluster on a pair id, a
                    WHERE/filter on a match flag, or a robust variance with
                    no weight
    fit_weighted    Cox under a weight (WEIGHT statement, coxph weights=,
                    an IPTW or matching-weight variable), robust variance or not
    fit_unadjusted  Cox with none of the above
    manual_review   both pair and weight handling: a person decides
    misfiled        no Cox fit at all

Rows go to a private CSV that never leaves the server. The public JSON holds
counts only, plus the %macro names called in at least MACRO_MIN_STUDIES
studies, with their study counts.
"""

import argparse
import csv
import hashlib
import json
import os
import re
from collections import defaultdict
from datetime import date
from pathlib import Path


SHAPES = ("match_and_fit", "fit_matched", "fit_weighted", "fit_unadjusted",
          "manual_review", "misfiled")
PROGRAM_SUFFIXES = {".sas", ".r", ".rmd", ".rnw", ".qmd"}
R_SUFFIXES = {".r", ".rmd", ".rnw", ".qmd"}
FOLDERS = ("datasets", "descriptive", "distributions", "analyses", "graphs",
           "documents", "estimates")
FOLDER_RE = re.compile(r"^(?:\d\d_)?(" + "|".join(FOLDERS) + r")$", re.IGNORECASE)
# Corpus jobs are <prefix>.<variable>[.<qualifier>].<ext>; jobs scaffolded by
# add_job() before 2026-10 are <subject>-<type>-<prefix>[-<qualifier>].qmd.
PREFIX_RE = re.compile(r"^cm[._-]|-cm(?:-\w+)?\.qmd$", re.IGNORECASE)
SKIP_DIRS = {".git", ".rproj.user", "node_modules", "packrat", "renv"}
MACRO_MIN_STUDIES = 3
SAS_MACRO_WORDS = {
    "abort", "bquote", "by", "copy", "display", "do", "else", "end", "eval",
    "global", "goto", "if", "inc", "include", "index", "input", "label",
    "length", "let", "local", "macro", "mend", "nrbquote", "nrquote", "nrstr",
    "put", "qscan", "qsubstr", "qsysfunc", "qupcase", "quote", "return", "scan",
    "str", "substr", "superq", "symdel", "symexist", "symglobl", "symlocal",
    "syscall", "sysevalf", "sysexec", "sysfunc", "sysget", "sysrput", "then",
    "to", "unquote", "until", "upcase", "while", "window",
}


def folder_index(parts):
    """Index of the first taxonomy folder in parts, or None.

    The first, not the deepest: a study can nest graphs/ inside analyses/, and
    taking the deepest would split one study into several keys, which inflates
    the study counts the public macro list is gated on.
    """
    return next((i for i, part in enumerate(parts) if FOLDER_RE.match(part)), None)


def relative_parts(path, root):
    return path.relative_to(root).parts


def study_key(path, root=Path("/")):
    parts = relative_parts(path, root)
    return str(Path(root, *parts[:folder_index(parts)]))


def folder_name(path, root=Path("/")):
    parts = relative_parts(path, root)
    return FOLDER_RE.match(parts[folder_index(parts)]).group(1).lower()


def strip_comments(text, suffix):
    """Drop comments so commented-out fits do not count as fits.

    SAS comment forms only in .sas files: in Rmd and qmd prose a "* item"
    bullet after a ";" would swallow text up to the next ";".
    """
    if suffix.lower() in R_SUFFIXES:
        return re.sub(r"#[^\n]*", "", text)
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.DOTALL)
    # A statement comment starts at text start or after a ";". Consecutive
    # comments share a ";", so repeat until the text stops changing.
    while True:
        stripped = re.sub(r"(^|;)(\s*)\*[^;]*;", r"\1\2", text)
        if stripped == text:
            break
        text = stripped
    return text


def phreg_steps(lower):
    """The body of every PROC PHREG step."""
    return [m.group(1) for m in re.finditer(
        r"\bproc\s+phreg\b(.*?)(?=\brun\s*;|\bquit\s*;|\bproc\s|\bdata(?!\s*=)\s|\Z)",
        lower, re.DOTALL)]


def coxph_calls(lower):
    """The argument text of every coxph( call, parentheses balanced."""
    calls = []
    for match in re.finditer(r"\bcoxph\s*\(", lower):
        depth, i = 1, match.end()
        while i < len(lower) and depth:
            depth += {"(": 1, ")": -1}.get(lower[i], 0)
            i += 1
        calls.append(lower[match.end():i - 1])
    return calls


# A pair-id stem at the start of a name or after "_", so dataset_id, repair
# and mismatch do not count. subclass is MatchIt's matched-set column.
PAIR_NAME = r"\b(?:\w*_)?(?:pair|match|mtch|set_?id|subclass)\w*"
WEIGHT_NAME = r"\b(?:iptw\w*|\w*mtwt\w*|\w*match_?wt\w*|\w*matchwt\w*|\w*mw_?wt\w*|ps_?wt\w*)\b"


def signals(path, text):
    lower = strip_comments(text.lower(), path.suffix)
    steps = phreg_steps(lower)
    calls = coxph_calls(lower)
    sas = path.suffix.lower() == ".sas"
    sas_weight = any(re.search(r"(?:^|;)\s*weight\s+\w+", step) for step in steps)
    # STRATA on a pair id, any position in the list, is a matched-set analysis.
    # COVS(AGGREGATE) needs an ID statement: on a pair id it is matched sets,
    # on anything else it is the robust variance that goes with a weight. A
    # bare ID without COVS only labels output and counts as neither.
    sas_aggregate = [step for step in steps if re.search(r"\bcovs(?:andwich)?\s*\(\s*aggr", step)]
    sas_pair = any(re.search(r"(?:^|;)\s*strata\s+[^;/]*" + PAIR_NAME, step) for step in steps) \
        or any(re.search(r"(?:^|;)\s*id\s+[^;]*" + PAIR_NAME, step) for step in sas_aggregate)
    sas_robust = bool(sas_aggregate) and not sas_pair
    r_weight = any(re.search(r"\bweights\s*=", call) for call in calls)
    r_pair = any(
        re.search(r"\b(?:cluster|strata)\s*\([^)]*" + PAIR_NAME, call)
        or re.search(r"\bcluster\s*=\s*" + PAIR_NAME, call)
        for call in calls)
    r_robust = not r_pair and any(
        re.search(r"\bcluster\s*[(=]|\brobust\s*=\s*t", call) for call in calls)
    return {
        "cox": bool(steps or calls),
        "match": bool(re.search(
            r"\bproc\s+psmatch\b"
            r"|\bmatchit\s*\(|\bmatching::match\s*\(|\bmatch\s*\(\s*(?:y|tr)\s*=|\bps_match\s*\(",
            lower)) or (sas and bool(re.search(
                r"%(?:gmatch|match|vmatch|nnmatch|greedy\w*|onetomany\w*|\w*caliper\w*)\b", lower))),
        "weight": sas_weight or r_weight
        or bool(re.search(WEIGHT_NAME + r"|\bps_weight\s*\(", lower)),
        "pair": sas_pair or r_pair,
        "robust": sas_robust or r_robust,
        # WHERE only in SAS: R has no ";" to end it, so prose would run on.
        "match_subset": bool(
            (sas and re.search(r"\bwhere\b[^;]*" + PAIR_NAME + r"\s*(?:=|eq|ne|in\b|>|\^=)", lower))
            or re.search(r"\bfilter\s*\([^)]*" + PAIR_NAME + r"\s*(?:==|%in%|>|!=)", lower)),
        "ps_fit": bool(re.search(
            r"\bproc\s+logistic\b|\bps_logistic\s*\(|\bglm\s*\([^)]*binomial", lower, re.DOTALL)),
        "mi": bool(re.search(r"_imputation_|\bimputation(?:_col)?\b|\bproc\s+mianalyze\b", lower)),
    }


def classify(found):
    if not found["cox"]:
        return "misfiled"
    if found["match"]:
        return "match_and_fit"
    matched = found["pair"] or found["match_subset"]
    if matched and found["weight"]:
        return "manual_review"
    if found["weight"]:
        return "fit_weighted"
    # A robust variance with no weight is the usual analysis of matched sets.
    if matched or found["robust"]:
        return "fit_matched"
    return "fit_unadjusted"


def called_macros(text, suffix):
    """%name calls in a SAS program, less macro-language words and local definitions."""
    if suffix.lower() != ".sas":
        return set()
    lower = strip_comments(text.lower(), suffix)
    defined = set(re.findall(r"%macro\s+([a-z_]\w*)", lower))
    called = set(re.findall(r"%([a-z_]\w*)", lower))
    return called - defined - SAS_MACRO_WORDS


def candidate_files(root):
    out = []
    template_copies = 0
    traversal_errors = []
    for directory, subdirs, files in os.walk(str(root), onerror=traversal_errors.append):
        subdirs[:] = [name for name in subdirs if name.lower() not in SKIP_DIRS]
        base = Path(directory)
        if folder_index(relative_parts(base, root)) is None:
            continue
        for name in files:
            if Path(name).suffix.lower() not in PROGRAM_SUFFIXES:
                continue
            if name.lower().startswith("tp.") and PREFIX_RE.search(name[3:]):
                template_copies += 1
                continue
            if PREFIX_RE.search(name):
                out.append(base / name)
    return sorted(out), len(traversal_errors), template_copies


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("corpus_root", type=Path)
    parser.add_argument("private_csv", type=Path)
    parser.add_argument("public_json", type=Path)
    args = parser.parse_args()

    rows = []
    macro_studies = defaultdict(set)
    unreadable_candidates = 0
    candidates, traversal_errors, template_copies = candidate_files(args.corpus_root)
    for path in candidates:
        try:
            raw = path.read_bytes()
        except OSError:
            unreadable_candidates += 1
            continue
        text = raw.decode("utf-8", errors="ignore")
        found = signals(path, text)
        study = study_key(path, args.corpus_root)
        for name in called_macros(text, path.suffix):
            macro_studies[name].add(study)
        rows.append({
            "sha256": hashlib.sha256(raw).hexdigest(),
            "extension": path.suffix.lower(),
            "path": str(path),
            "study": study,
            "folder": folder_name(path, args.corpus_root),
            "shape": classify(found),
            **{key: found[key] for key in ("match", "weight", "pair", "robust", "match_subset", "ps_fit", "mi")},
        })
    if not rows:
        if candidates:
            raise SystemExit(f"{len(candidates)} cm candidates found but none could be read.")
        raise SystemExit("No cm candidates found: check the corpus root and the mount name.")

    args.private_csv.parent.mkdir(parents=True, exist_ok=True)
    # backslashreplace: a non-UTF-8 file name on the server must not lose the scan.
    with args.private_csv.open("w", newline="", encoding="utf-8", errors="backslashreplace") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    aggregate = defaultdict(lambda: {
        "sas_programs": 0, "sas_studies": set(), "r_jobs": 0, "r_studies": set(),
        "mi_programs": 0, "ps_fit_programs": 0,
    })
    for row in rows:
        values = aggregate[row["shape"]]
        if row["extension"] == ".sas":
            values["sas_programs"] += 1
            values["sas_studies"].add(row["study"])
            values["mi_programs"] += int(row["mi"])
            values["ps_fit_programs"] += int(row["ps_fit"])
        else:
            values["r_jobs"] += 1
            values["r_studies"].add(row["study"])

    def public(shape):
        values = aggregate[shape]
        sas_studies, r_studies = len(values["sas_studies"]), len(values["r_studies"])
        return {
            "sas_programs": values["sas_programs"],
            "sas_studies": sas_studies,
            "r_jobs": values["r_jobs"],
            "r_studies": r_studies,
            "mi_programs": values["mi_programs"],
            "ps_fit_programs": values["ps_fit_programs"],
            "two_study_gate": max(sas_studies, r_studies) >= 2,
        }

    by_folder = defaultdict(lambda: {"programs": 0, "studies": set()})
    for row in rows:
        by_folder[row["folder"]]["programs"] += 1
        by_folder[row["folder"]]["studies"].add(row["study"])

    sas_rows = [row for row in rows if row["extension"] == ".sas"]
    result = {
        "date": date.today().isoformat(),
        "corpus_programs": len(sas_rows),
        "r_jobs": len(rows) - len(sas_rows),
        "studies": len({row["study"] for row in rows}),
        "sas_studies": len({row["study"] for row in sas_rows}),
        "match_step_programs": sum(row["match"] for row in rows),
        "match_step_studies": len({row["study"] for row in rows if row["match"]}),
        "template_copies_skipped": template_copies,
        "traversal_errors": traversal_errors,
        "unreadable_candidates": unreadable_candidates,
        "shapes": {shape: public(shape) for shape in SHAPES},
        "folders": {
            name: {"programs": v["programs"], "studies": len(v["studies"])}
            for name, v in sorted(by_folder.items())
        },
        "macros": {
            name: len(studies)
            for name, studies in sorted(macro_studies.items(), key=lambda kv: (-len(kv[1]), kv[0]))
            if len(studies) >= MACRO_MIN_STUDIES
        },
    }
    args.public_json.parent.mkdir(parents=True, exist_ok=True)
    args.public_json.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
