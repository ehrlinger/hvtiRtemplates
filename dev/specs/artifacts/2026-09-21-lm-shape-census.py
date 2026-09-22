#!/usr/bin/env python3
"""Classify legacy lm/pm analysis jobs without publishing study identifiers."""

import argparse
import csv
import hashlib
import json
import os
import re
from collections import defaultdict
from datetime import date
from pathlib import Path


SHAPES = (
    "binary",
    "ordinal",
    "nominal",
    "propensity_binary",
    "propensity_ordinal",
    "propensity_nominal",
    "checkpred",
    "balancing_count",
)
PROGRAM_SUFFIXES = {".sas", ".r", ".rmd", ".rnw", ".qmd"}
PREFIX_RE = re.compile(r"(?:^|[._-])(lm|pm)(?:[._-]|$)", re.IGNORECASE)
SKIP_DIRS = {".git", ".rproj.user", "node_modules", "packrat", "renv"}


def study_key(path):
    parts = path.parts
    lowered = [part.lower() for part in parts]
    at = next(
        i for i, part in enumerate(lowered)
        if part in {"analyses", "30_analyses"}
    )
    return str(Path(*parts[:at]))


def signals(path, text):
    lower_name = path.name.lower()
    lower = text.lower()
    prefix_match = PREFIX_RE.search(lower_name)
    prefix = prefix_match.group(1).lower() if prefix_match else ""
    return {
        "prefix": prefix,
        "checkpred": bool(re.search(
            r"checkpred|\binmodel\s*=|\bscore\s+data\s*=|\bproc\s+plm\b|\brestore\s*=",
            lower_name + "\n" + lower,
        )),
        "count": prefix == "pm" or bool(re.search(
            r"dist\s*=\s*(?:nb|negbin|negative\s*binomial|poisson)", lower
        )),
        "propensity": bool(re.search(
            r"propen|propensity|balanc(?:e|ing)[ _-]*score|matching[ _-]*weight|\bmt_wt\b",
            lower_name + "\n" + lower,
        )),
        "nominal": bool(re.search(
            r"link\s*=\s*glogit|\bglogit\b|multinom|polytom|nominal",
            lower_name + "\n" + lower,
        )),
        "ordinal": bool(re.search(
            r"ordinal|cumulative[ _-]*logit|\bclogit\b|\bpolr\s*\(",
            lower_name + "\n" + lower,
        )),
        "binary": bool(re.search(
            r"binary|\bevent\s*=|\bdescending\b|family\s*=\s*(?:stats::)?binomial",
            lower_name + "\n" + lower,
        )),
        "mi": bool(re.search(r"_imputation_|\bimputation(?:_col)?\b|\bproc\s+mianalyze\b", lower)),
        "logistic": bool(re.search(r"\bproc\s+logistic\b|\bglm\s*\(|fit_logistic\s*\(", lower)),
    }


def classify(found):
    if found["checkpred"]:
        return "checkpred"
    if found["count"] and (found["prefix"] == "pm" or found["propensity"]):
        return "balancing_count"
    suffix = ""
    if found["nominal"]:
        suffix = "nominal"
    elif found["ordinal"]:
        suffix = "ordinal"
    elif found["binary"]:
        suffix = "binary"
    if suffix and found["propensity"]:
        return f"propensity_{suffix}"
    if suffix:
        return suffix
    if found["logistic"]:
        return "manual_review"
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
            if PREFIX_RE.search(name):
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
        text = raw.decode("utf-8", errors="ignore")
        found = signals(path, text)
        rows.append({
            "sha256": hashlib.sha256(raw).hexdigest(),
            "extension": path.suffix.lower(),
            "path": str(path),
            "study": study_key(path),
            "prefix": found["prefix"],
            "shape": classify(found),
            "mi": found["mi"],
            "propensity": found["propensity"],
            "nominal": found["nominal"],
            "ordinal": found["ordinal"],
            "binary": found["binary"],
        })

    args.private_csv.parent.mkdir(parents=True, exist_ok=True)
    with args.private_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    aggregate = defaultdict(lambda: {
        "sas_programs": 0,
        "sas_studies": set(),
        "r_jobs": 0,
        "r_studies": set(),
        "mi_programs": 0,
    })
    for row in rows:
        shape = str(row["shape"])
        if shape not in SHAPES:
            continue
        if row["extension"] == ".sas":
            aggregate[shape]["sas_programs"] += 1
            aggregate[shape]["sas_studies"].add(row["study"])
            if row["mi"]:
                aggregate[shape]["mi_programs"] += 1
        elif row["extension"] in PROGRAM_SUFFIXES:
            aggregate[shape]["r_jobs"] += 1
            aggregate[shape]["r_studies"].add(row["study"])

    public_shapes = {}
    for shape in SHAPES:
        values = aggregate[shape]
        sas_studies = len(values["sas_studies"])
        r_studies = len(values["r_studies"])
        public_shapes[shape] = {
            "sas_programs": values["sas_programs"],
            "sas_studies": sas_studies,
            "r_jobs": values["r_jobs"],
            "r_studies": r_studies,
            "mi_programs": values["mi_programs"],
            "two_study_gate": max(sas_studies, r_studies) >= 2,
        }

    sas_rows = [row for row in rows if row["extension"] == ".sas"]
    all_studies = {row["study"] for row in rows}
    sas_studies = {row["study"] for row in sas_rows}
    public = {
        "date": date.today().isoformat(),
        "corpus_programs": len(sas_rows),
        "sas_breadth": len(all_studies),
        "sas_breadth_jobs": len(sas_studies),
        "manual_review_programs": sum(
            row["extension"] == ".sas" and row["shape"] == "manual_review"
            for row in rows
        ),
        "misfiled_programs": sum(
            row["extension"] == ".sas" and row["shape"] == "misfiled"
            for row in rows
        ),
        "traversal_errors": traversal_errors,
        "unreadable_candidates": unreadable_candidates,
        "shapes": public_shapes,
    }
    args.public_json.parent.mkdir(parents=True, exist_ok=True)
    args.public_json.write_text(json.dumps(public, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
