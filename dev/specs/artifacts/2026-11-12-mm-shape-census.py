#!/usr/bin/env python3
"""Classify legacy mm (mixed model) jobs without publishing study identifiers.

Sibling of 2026-10-13-rm-shape-census.py. The mm template is designed from
these numbers, so the census measures the choices a template would have to
make: random effects or a REPEATED covariance structure, which covariance
types, ML or REML, splines in time, what the job reports (LSMEANS, ESTIMATE,
saved predictions for an mp plot) and multiple imputation.

A GLIMMIX fit with a non-normal distribution is a migration finding for gm,
and NLMIXED (or R nlme::nlme) is one for nm. A program that fits no mixed
model is misfiled.

The private CSV carries paths and must stay on the server. The public JSON
carries counts only; a macro name is published only when at least
MACRO_MIN_STUDIES studies call it, so a study-specific macro cannot leak.
"""

import argparse
import csv
import hashlib
import json
import os
import re
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path


SHAPES = ("random_effects", "repeated_covariance", "random_and_repeated")
MIGRATIONS = ("migration_gm", "migration_nm")
PROGRAM_SUFFIXES = {".sas", ".r", ".rmd", ".rnw", ".qmd"}
R_SUFFIXES = {".r", ".rmd", ".rnw", ".qmd"}
# Corpus jobs are <prefix>.<variable>[.<qualifier>].<ext>; jobs scaffolded
# before 2026-10 are <subject>-<type>-<prefix>[-<qualifier>].qmd.
PREFIX_RE = re.compile(r"^mm[._-]|-mm(?:-\w+)?\.qmd$", re.IGNORECASE)
FOLDERS = {"analyses", "30_analyses"}
SKIP_DIRS = {".git", ".rproj.user", "node_modules", "packrat", "renv"}
MACRO_MIN_STUDIES = 3
# SAS statements and functions spelled with %, which are not macro calls.
SAS_BUILTINS = {
    "let", "put", "if", "then", "else", "do", "end", "to", "macro", "mend",
    "include", "global", "local", "eval", "sysevalf", "str", "nrstr", "quote",
    "upcase", "substr", "scan", "index", "length", "sysfunc", "symexist",
    "goto", "return", "abort", "inc", "by", "while", "until", "superq", "bquote",
    "unquote", "qscan", "qsubstr", "qupcase", "sysget", "syscall", "window",
}


def study_key(path):
    parts = path.parts
    lowered = [part.lower() for part in parts]
    at = next(i for i, part in enumerate(lowered) if part in FOLDERS)
    return str(Path(*parts[:at]))


def strip_comments(text, suffix):
    """Drop comments so commented-out fits do not count as fits."""
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.DOTALL)
    # A statement comment starts at text start or after a ";". Consecutive
    # comments share a ";", so repeat until the text stops changing.
    while True:
        stripped = re.sub(r"(^|;)(\s*)\*[^;]*;", r"\1\2", text)
        if stripped == text:
            break
        text = stripped
    if suffix.lower() in R_SUFFIXES:
        text = re.sub(r"#[^\n]*", "", text)
    return text


# A lookahead, so the next PROC or DATA step stays in the text for the next match.
STEP_END = r"(?=\brun\s*;|\bquit\s*;|\bproc\s|\bdata(?!\s*=)\s|\Z)"


def proc_steps(lower, name):
    """The bodies of every PROC <name> step."""
    pattern = r"\bproc\s+" + name + r"\b(.*?)" + STEP_END
    return [m.group(1) for m in re.finditer(pattern, lower, re.DOTALL)]


def statements(step, keyword):
    return re.findall(r"(?:^|;)\s*" + keyword + r"\b([^;]*)", step)


def sas_signals(lower):
    mixed = proc_steps(lower, "mixed")
    glimmix = proc_steps(lower, "glimmix")
    glimmix_normal, glimmix_other = [], []
    for step in glimmix:
        dist = re.search(r"\bdist(?:ribution)?\s*=\s*(\w+)", step)
        if dist and dist.group(1) not in {"normal", "gaussian", "n"}:
            glimmix_other.append(step)
        else:
            glimmix_normal.append(step)
    steps = mixed + glimmix_normal
    joined = ";".join(steps)
    types = set()
    for stmt in statements(joined, "random") + statements(joined, "repeated"):
        for found in re.findall(r"\btype\s*=\s*([a-z]+(?:\s*\(\s*[a-z0-9]+\s*\))?)", stmt):
            types.add(re.sub(r"\s+", "", found))
    method = set(re.findall(r"\bmethod\s*=\s*(\w+)", " ".join(
        re.match(r"[^;]*", step).group(0) for step in steps)))
    return {
        "mixed_fit": bool(steps),
        "gm": bool(glimmix_other),
        "nm": bool(proc_steps(lower, "nlmixed")),
        "random": bool(statements(joined, "random")),
        "repeated": bool(statements(joined, "repeated")),
        # Both statements in ONE step, not a RANDOM fit beside a separate REPEATED fit.
        "combined": any(statements(step, "random") and statements(step, "repeated") for step in steps),
        "cov_types": sorted(types),
        "method": sorted(method),
        "spline": bool(re.search(r"\beffect\s+\w+\s*=\s*spl|%spline|\brcs\b|\bspline\b", joined)),
        "lsmeans": bool(statements(joined, "lsmeans") or statements(joined, "lsmestimate")),
        "estimate": bool(statements(joined, "estimate") or statements(joined, "contrast")),
        "predictions": bool(re.search(r"\boutpm?\s*=|\boutput\s+out\s*=|\bods\s+output\s+[^;]*\bpred", joined + ";" + lower)),
    }


def r_signals(lower):
    lme4 = bool(re.search(r"(?<![._a-z])lmer\s*\(", lower))
    nlme_lme = bool(re.search(r"(?<![._a-z])lme\s*\(", lower))
    gls = bool(re.search(r"(?<![._a-z])gls\s*\(", lower))
    correlation = bool(re.search(r"\bcorrelation\s*=|\bcor(?:ar1|cs|sym|exp|car1|compsymm)\s*\(", lower))
    types = sorted(set(re.findall(r"\bcor(ar1|car1|compsymm|symm|exp|gaus|lin|ratio|spher)\s*\(", lower)))
    return {
        "mixed_fit": lme4 or nlme_lme or gls,
        "gm": bool(re.search(r"(?<![._a-z])glmer(?:\.nb)?\s*\(|\bglmmtmb\s*\(|\bglmmpql\s*\(", lower)),
        "nm": bool(re.search(r"(?<![._a-z])nlmer?\s*\(|\bnlme::nlme\s*\(", lower)),
        "random": lme4 or nlme_lme,
        "repeated": correlation,
        "combined": nlme_lme and correlation,
        "cov_types": types,
        "method": sorted(set(re.findall(r"\bmethod\s*=\s*[\"'](\w+)", lower)) | (
            {"reml_false"} if re.search(r"\breml\s*=\s*(?:false|f)\b", lower) else set())),
        "spline": bool(re.search(r"(?<![._a-z])(?:ns|bs|rcs)\s*\(", lower)),
        "lsmeans": bool(re.search(r"\b(?:emmeans|lsmeans)\s*\(", lower)),
        "estimate": bool(re.search(r"\b(?:contrast|glht|emtrends)\s*\(", lower)),
        "predictions": bool(re.search(r"\bpredict\s*\(|\bfitted\s*\(|\baugment\s*\(", lower)),
    }


def signals(path, text):
    suffix = path.suffix.lower()
    lower = strip_comments(text.lower(), suffix)
    found = r_signals(lower) if suffix in R_SUFFIXES else sas_signals(lower)
    found["mi"] = bool(re.search(r"_imputation_|\bimputation(?:_col)?\b|\bproc\s+mianalyze\b|\bpool\s*\(", lower))
    found["macros"] = sorted(
        set(re.findall(r"%([a-z_]\w*)\s*[(;]", lower)) - SAS_BUILTINS
    ) if suffix == ".sas" else []
    return found


def classify(found):
    if found["mixed_fit"] and (found["gm"] or found["nm"]):
        return "manual_review"
    if found["mixed_fit"]:
        if found["random"] and found["repeated"]:
            # Separate RANDOM-only and REPEATED-only fits are two shapes in one
            # program; a person decides which the job is.
            return "random_and_repeated" if found["combined"] else "manual_review"
        if found["repeated"]:
            return "repeated_covariance"
        # A MIXED step with neither statement is a fixed-effects fit; a person
        # should see it before it counts toward either shape.
        return "random_effects" if found["random"] else "manual_review"
    if found["gm"] and found["nm"]:
        return "manual_review"
    if found["gm"]:
        return "migration_gm"
    if found["nm"]:
        return "migration_nm"
    return "misfiled"


def candidate_files(root):
    out = []
    template_copies = 0
    traversal_errors = []
    for directory, subdirs, files in os.walk(str(root), onerror=traversal_errors.append):
        subdirs[:] = [name for name in subdirs if name.lower() not in SKIP_DIRS]
        base = Path(directory)
        if not {part.lower() for part in base.parts}.intersection(FOLDERS):
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


def summarise(rows):
    """The public JSON body: counts only, no paths, no study keys."""
    aggregate = defaultdict(lambda: {
        "sas_programs": 0, "sas_studies": set(), "r_jobs": 0, "r_studies": set(), "mi_programs": 0,
    })
    for row in rows:
        values = aggregate[row["shape"]]
        if row["extension"] == ".sas":
            values["sas_programs"] += 1
            values["sas_studies"].add(row["study"])
            values["mi_programs"] += int(row["mi"])
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
            "two_study_gate": max(sas_studies, r_studies) >= 2,
        }

    fits = [row for row in rows if row["shape"] in SHAPES]

    def tally(field):
        """Programs and studies per value of a list field, over mixed fits."""
        programs, studies = Counter(), defaultdict(set)
        for row in fits:
            for value in row[field]:
                programs[value] += 1
                studies[value].add(row["study"])
        return {value: {"programs": programs[value], "studies": len(studies[value])}
                for value in sorted(programs)}

    def flag(field):
        hit = [row for row in fits if row[field]]
        return {"programs": len(hit), "studies": len({row["study"] for row in hit})}

    macro_studies = defaultdict(set)
    for row in rows:
        for macro in row["macros"]:
            macro_studies[macro].add(row["study"])

    sas_rows = [row for row in rows if row["extension"] == ".sas"]
    return {
        "corpus_programs": len(sas_rows),
        "r_jobs": len(rows) - len(sas_rows),
        "sas_breadth": len({row["study"] for row in rows}),
        "sas_breadth_jobs": len({row["study"] for row in sas_rows}),
        "manual_review_programs": sum(row["shape"] == "manual_review" for row in rows),
        "misfiled_programs": sum(row["shape"] == "misfiled" for row in rows),
        "shapes": {shape: public(shape) for shape in SHAPES},
        "migrations": {shape: public(shape)["sas_programs"] for shape in MIGRATIONS},
        "over_mixed_fits": {
            "cov_types": tally("cov_types"),
            "method": tally("method"),
            "spline": flag("spline"),
            "lsmeans": flag("lsmeans"),
            "estimate": flag("estimate"),
            "predictions": flag("predictions"),
            "mi": flag("mi"),
        },
        "macros_in_3_plus_studies": {
            macro: len(studies) for macro, studies in sorted(macro_studies.items())
            if len(studies) >= MACRO_MIN_STUDIES
        },
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("corpus_root", type=Path)
    parser.add_argument("private_csv", type=Path)
    parser.add_argument("public_json", type=Path)
    args = parser.parse_args()

    rows = []
    unreadable_candidates = 0
    candidates, traversal_errors, template_copies = candidate_files(args.corpus_root)
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
            **{key: found[key] for key in (
                "mi", "spline", "lsmeans", "estimate", "predictions", "cov_types", "method", "macros")},
        })
    if not rows:
        if candidates:
            raise SystemExit(f"{len(candidates)} mm candidates found but none could be read.")
        raise SystemExit("No mm candidates found: check the corpus root and the mount name.")

    args.private_csv.parent.mkdir(parents=True, exist_ok=True)
    with args.private_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        for row in rows:
            writer.writerow({key: ";".join(value) if isinstance(value, list) else value
                             for key, value in row.items()})

    result = {
        "date": date.today().isoformat(),
        **summarise(rows),
        "template_copies_skipped": template_copies,
        "traversal_errors": traversal_errors,
        "unreadable_candidates": unreadable_candidates,
    }
    args.public_json.parent.mkdir(parents=True, exist_ok=True)
    args.public_json.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
