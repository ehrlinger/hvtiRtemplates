#!/usr/bin/env python3
"""Classify legacy rm analysis jobs without publishing study identifiers.

Sibling of 2026-09-21-lm-shape-census.py; see the rm family design, section 2.
Only PROC REG / PROC GLM (or R lm()) with a continuous response is an rm shape.
MIXED, GENMOD and NLIN fits filed as rm are migration findings for mm, gm, nm.
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


SHAPES = ("balancing_continuous", "linear")
MIGRATIONS = ("migration_mm", "migration_gm", "migration_nm")
PROGRAM_SUFFIXES = {".sas", ".r", ".rmd", ".rnw", ".qmd"}
R_SUFFIXES = {".r", ".rmd", ".rnw", ".qmd"}
PREFIX_RE = re.compile(r"(?:^|[._-])(rm)(?:[._-]|$)", re.IGNORECASE)
SKIP_DIRS = {".git", ".rproj.user", "node_modules", "packrat", "renv"}


def study_key(path):
    parts = path.parts
    lowered = [part.lower() for part in parts]
    at = next(
        i for i, part in enumerate(lowered)
        if part in {"analyses", "30_analyses"}
    )
    return str(Path(*parts[:at]))


def strip_comments(text, suffix):
    """Drop comments so commented-out fits do not count as fits."""
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.DOTALL)
    text = re.sub(r"(^|;)(\s*)\*[^;]*;", r"\1\2", text)
    if suffix.lower() in R_SUFFIXES:
        text = re.sub(r"#[^\n]*", "", text)
    return text


def signals(path, text):
    lower_name = path.name.lower()
    lower = strip_comments(text.lower(), path.suffix)
    glm_repeated = bool(re.search(r"\bproc\s+glm\b", lower) and re.search(r"\brepeated\b", lower))
    both = lower_name + "\n" + lower
    return {
        "ols": bool(re.search(r"\bproc\s+reg\b|(?<![._a-z])lm\s*\(", lower))
        or (bool(re.search(r"\bproc\s+glm\b", lower)) and not glm_repeated),
        "mixed": glm_repeated
        or bool(re.search(r"\bproc\s+(?:mixed|glimmix)\b|\blmer?\s*\(|\blme\s*\(", lower)),
        "genmod": bool(re.search(r"\bproc\s+genmod\b|\bglm\.nb\s*\(|(?<![._a-z])glm\s*\(", lower)),
        "nlin": bool(re.search(r"\bproc\s+nlin\b|\bnls\s*\(", lower)),
        "balancing": bool(re.search(
            r"balanc(?:e|ing)[ _-]*score|balncing|%grp\b|\bbs_continuous\s*\(", both
        )),
        "transformed": bool(re.search(r"\blog\s*\(|\blog10\s*\(|\bsqrt\s*\(|\bln_", lower)),
        "mi": bool(re.search(r"_imputation_|\bimputation(?:_col)?\b|\bproc\s+mianalyze\b", lower)),
    }


def classify(found):
    others = [name for name in ("mixed", "genmod", "nlin") if found[name]]
    if found["ols"] and others:
        return "manual_review"
    if found["ols"]:
        return "balancing_continuous" if found["balancing"] else "linear"
    if len(others) > 1:
        return "manual_review"
    if others:
        return {"mixed": "migration_mm", "genmod": "migration_gm", "nlin": "migration_nm"}[others[0]]
    return "misfiled"


def candidate_files(root):
    out = []
    traversal_errors = []
    for directory, subdirs, files in os.walk(
            str(root), onerror=traversal_errors.append):
        subdirs[:] = [name for name in subdirs if name.lower() not in SKIP_DIRS]
        base = Path(directory)
        folders = {part.lower() for part in base.parts}
        if not folders.intersection({"analyses", "30_analyses"}):
            continue
        for name in files:
            if PREFIX_RE.search(name) and Path(name).suffix.lower() in PROGRAM_SUFFIXES:
                out.append(base / name)
    return sorted(out), len(traversal_errors)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("corpus_root", type=Path)
    parser.add_argument("private_csv", type=Path)
    parser.add_argument("public_json", type=Path)
    args = parser.parse_args()

    rows = []
    unreadable_candidates = 0
    candidates, traversal_errors = candidate_files(args.corpus_root)
    for path in candidates:
        try:
            raw = path.read_bytes()
        except OSError:
            unreadable_candidates += 1
            continue
        found = signals(path, raw.decode("utf-8", errors="ignore"))
        rows.append({
            "sha256": hashlib.sha256(raw).hexdigest(),
            "extension": path.suffix.lower(),
            "path": str(path),
            "study": study_key(path),
            "shape": classify(found),
            "mi": found["mi"],
            "transformed": found["transformed"],
        })
    if not rows:
        if candidates:
            raise SystemExit(f"{len(candidates)} rm candidates found but none could be read.")
        raise SystemExit("No rm candidates found: check the corpus root and the mount name.")

    args.private_csv.parent.mkdir(parents=True, exist_ok=True)
    with args.private_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    aggregate = defaultdict(lambda: {
        "sas_programs": 0, "sas_studies": set(), "r_jobs": 0, "r_studies": set(),
        "mi_programs": 0, "transformed_programs": 0, "transformed_studies": set(),
    })
    for row in rows:
        values = aggregate[row["shape"]]
        if row["extension"] == ".sas":
            values["sas_programs"] += 1
            values["sas_studies"].add(row["study"])
            values["mi_programs"] += int(row["mi"])
            if row["transformed"]:
                values["transformed_programs"] += 1
                values["transformed_studies"].add(row["study"])
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
            "transformed_programs": values["transformed_programs"],
            "transformed_studies": len(values["transformed_studies"]),
            "two_study_gate": max(sas_studies, r_studies) >= 2,
        }

    sas_rows = [row for row in rows if row["extension"] == ".sas"]
    result = {
        "date": date.today().isoformat(),
        "corpus_programs": len(sas_rows),
        "sas_breadth": len({row["study"] for row in rows}),
        "sas_breadth_jobs": len({row["study"] for row in sas_rows}),
        "manual_review_programs": sum(r["shape"] == "manual_review" for r in sas_rows),
        "misfiled_programs": sum(r["shape"] == "misfiled" for r in sas_rows),
        "traversal_errors": traversal_errors,
        "unreadable_candidates": unreadable_candidates,
        "shapes": {shape: public(shape) for shape in SHAPES},
        "migrations": {shape: public(shape)["sas_programs"] for shape in MIGRATIONS},
    }
    args.public_json.parent.mkdir(parents=True, exist_ok=True)
    args.public_json.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
