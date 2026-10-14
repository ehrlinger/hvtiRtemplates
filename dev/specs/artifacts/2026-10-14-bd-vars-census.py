#!/usr/bin/env python3
"""Classify the operations in every study's SAS build (bd) and vars programs.

Design: hvtiRtemplates dev/specs/2026-10-14-bd-vars-action-items-design.md.

A static, statement-level scan. Each SAS statement in a study's bd*, vars*
and *SAStoR* program is assigned ONE operation category, so the output says
what people actually do in these programs and how often. Job programs in the
other study folders are read only for their %vars(...) calls, to count which
vars switches (IMPUTE=, MISSING=, PROPEN=, MATCH=, TRANSF=) jobs turn on.

No value is read out. A correction is recognised by its shape (a patient key
compared with a literal), and the literal is never written anywhere. The
private CSV holds paths and per-file counts; the public JSON holds aggregate
counts only, and is safe to commit.

Blind spots, by construction: macro-generated code is not expanded, and a
PROC SQL step is classified by keyword (query / join / filter), not parsed.
"""

import argparse
import csv
import hashlib
import json
import os
import re
import statistics
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path


CATEGORIES = (
    "query",              # read a source: set lib.ds, libname, ODBC pass-through, import
    "join",               # merge, SQL join
    "correction",         # if <key> = <literal> then <var> = ...   (value fix for one patient)
    "patient_removal",    # if <key> = <literal> then delete          (one patient dropped by key)
    "row_filter",         # delete, subsetting if, where
    "column_drop",        # keep, drop, keep=/drop= options
    "standard_derivation",  # intervals, age, BSA/BMI
    "recode",             # categorical recode, select/when, proc format
    "dichotomize",        # cut-point into a new indicator or group
    "missing_flag",       # if x = . then x_miss = 1
    "missing_fill",       # if x = . then x = <constant>  (informative / value fill)
    "transform",          # log, inverse, square, sqrt; %ln, %inv
    "mean_impute",        # proc standard replace, proc stdize, MISSING= branch
    "mi",                 # proc mi, mianalyze, imputation macros
    "balancing_match",    # propensity merge, matching macros, match ids
    "variable_list",      # %let <list> = <several variables>
    "diagnostic",         # proc print/means/freq/contents/...
    "other",              # assignments and statements matching none of the above
)
ADMIN_RE = re.compile(
    r"^(run|quit|label|format|informat|length|attrib|retain|by|title\d*|footnote\d*|"
    r"options|ods|output|end|do|else|%end|%mend|%do|%else|%then|%if|%put|%global|%local|"
    r"proc\s+sort|proc\s+datasets|class|var|tables|id|filename|x|call\s+symput\w*)\b"
)
DIAGNOSTIC_PROCS = {
    "print", "means", "freq", "contents", "univariate", "tabulate", "summary",
    "compare", "report", "sgplot", "gplot", "plot", "corr", "chart",
}
WORK_LIBS = {"work", ""}
KEY_RE = r"(?:ccfid|mrn|emrn|patid|pat_id|patient_id|ptid|studyid|study_id|id)"
CORRECTION_RE = re.compile(
    r"^if\s+\(?\s*" + KEY_RE + r"\s*(?:=|eq|in)\s*[\(\"'\d]", re.IGNORECASE
)
MI_RE = re.compile(r"\bproc\s+mi(?:analyze)?\b|%\s*(?:mult_?imput\w*|imputsub\w*|mi_\w+)\s*\(")
MATCH_RE = re.compile(
    r"\bpropen\w*|\bmatch(?:to|_id|id|ed|es)?\b|%\s*\w*match\w*\s*\(|\bproc\s+psmatch\b|"
    r"\bbalanc\w*|\bprop_?score\b|\b_?ps_?score\b"
)
TRANSFORM_RE = re.compile(
    r"%\s*(?:ln|inv|log\w*|sq\w*|sqrt)\s*\(|\b(?:log|log10|log2|exp|sqrt)\s*\(|\*\*\s*[23]\b|=\s*1\s*/"
)
DERIVE_RE = re.compile(
    r"\b(?:intck|intnx|yrdif|datdif)\s*\(|/\s*365(?:\.25)?\b|/\s*30\.4\d*\b|/\s*12\b"
)
DERIVE_TARGET_RE = re.compile(r"^(?:iv_\w+|age\w*|bsa\w*|bmi\w*|wtht\w*|dt_\w+|crcl\w*|gfr\w*)$")
ASSIGN_RE = re.compile(r"^(?:if\s+(?P<cond>.+?)\s+then\s+)?(?P<target>[a-z_]\w*)\s*=\s*(?P<rhs>[^=].*)$", re.DOTALL)
MISS_COND_RE = re.compile(r"^\(?\s*(?P<var>[a-z_]\w*)\s*(?:=|eq)\s*\.\s*\)?$|^missing\s*\(\s*(?P<mvar>[a-z_]\w*)\s*\)$")
CUT_COND_RE = re.compile(r"(?:<=?|>=?|\blt\b|\ble\b|\bgt\b|\bge\b)\s*-?\d")
LITERAL_RE = re.compile(r"^(?:-?\d+(?:\.\d*)?|\.|'[^']*'|\"[^\"]*\")$")
VARS_CALL_RE = re.compile(r"%\s*vars\b\s*(\((?P<args>[^)]*)\))?", re.IGNORECASE)
TP_VARS_RE = re.compile(r"tp\.vars[\w.]*", re.IGNORECASE)
SWITCHES = ("impute", "missing", "propen", "match", "transf")

PROGRAM_KINDS = (
    ("sastor", re.compile(r"sas_?to_?r", re.IGNORECASE)),
    ("bd", re.compile(r"^(?:tp\.)?bd[._]", re.IGNORECASE)),
    ("vars", re.compile(r"^(?:tp\.)?vars", re.IGNORECASE)),
)
DATASET_DIRS = {"datasets", "00_datasets"}
JOB_DIRS = {
    "descriptive", "10_descriptive", "distributions", "20_distributions",
    "analyses", "30_analyses", "graphs", "40_graphs", "documents", "50_documents",
}
SKIP_DIRS = {".git", ".rproj.user", "node_modules", "packrat", "renv", "__pycache__"}


def strip_comments(text):
    """Drop /* */ and statement comments so commented-out code does not count."""
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.DOTALL)
    while True:
        stripped = re.sub(r"(^|;)(\s*)\*[^;]*;", r"\1\2", text)
        if stripped == text:
            return text
        text = stripped


def program_kind(name):
    for kind, pattern in PROGRAM_KINDS:
        if pattern.search(name):
            return kind
    return None


def classify(stmt, ctx):
    """Return one category for a normalised (lower-case, one-line) statement.

    ctx carries the enclosing step: ctx["proc"] is the open PROC name or None.
    The order of the tests is the precedence: a statement that is both a
    patient-keyed fix and a transform is a correction first.
    """
    head = stmt.split(None, 1)[0] if stmt else ""
    proc = ctx.get("proc")

    if head in {"run", "quit"}:
        return None
    if head == "proc":
        name = (stmt.split() + ["", ""])[1]
        if name in DIAGNOSTIC_PROCS:
            return "diagnostic"
        if name in {"mi", "mianalyze"}:
            return "mi"
        if name in {"standard", "stdize"}:
            return "mean_impute" if re.search(r"\breplace\b|\breponly\b|missing\s*=\s*mean", stmt) else "transform"
        if name == "psmatch":
            return "balancing_match"
        if name == "format":
            return "recode"
        if name == "import":
            return "query"
        if name in {"sql", "sort", "datasets", "transpose"}:
            return None
        return "other"
    if proc in DIAGNOSTIC_PROCS:
        return "diagnostic"
    if proc == "format" and head in {"value", "invalue"}:
        return "recode"
    if proc == "sql":
        if MATCH_RE.search(stmt):
            return "balancing_match"
        if re.search(r"\bjoin\b|\bfrom\s+[\w.]+\s*(?:as\s+)?\w*\s*,\s*[\w.]+", stmt):
            return "join"
        if re.search(r"connection\s+to|\bconnect\s+to\b|\bfrom\s+(?!work\.)[a-z_]\w*\.\w+", stmt):
            return "query"
        if re.search(r"\bdelete\b|\bwhere\b|\bhaving\b", stmt):
            return "row_filter"
        return "other"

    if head == "data" and re.search(r"\b(?:keep|drop)\s*=", stmt):
        return "column_drop"
    if head in {"data", "%macro", "%mend", "%inc", "%include"}:
        return None                     # step and macro scaffolding, not an operation
    if CORRECTION_RE.match(stmt):
        return "patient_removal" if re.search(r"\bthen\s+delete\b", stmt) else "correction"
    if MI_RE.search(stmt):
        return "mi"
    if MATCH_RE.search(stmt) and head not in {"label", "format"}:
        return "balancing_match"
    if re.search(r"%\s*if\s+&\s*missing\b", stmt):
        return "mean_impute"
    if head == "libname" or re.search(r"\bconnect\s+to\s+odbc\b|\binfile\b", stmt):
        return "query"
    if head == "set":
        libs = {m.group(1) for m in re.finditer(r"\b([a-z_]\w*)\.\w+", stmt.split("(")[0] if "(" in stmt else stmt)}
        if libs - WORK_LIBS:
            return "query"
        if re.search(r"\b(?:keep|drop)\s*=", stmt):
            return "column_drop"
        return None                     # a work-to-work SET passes rows through
    if head == "merge":
        return "join"
    if head in {"keep", "drop"}:
        return "column_drop"
    if head == "delete" or re.search(r"\bthen\s+delete\b", stmt):
        return "row_filter"
    if head == "where":
        return "row_filter"
    if head == "if" and " then " not in f" {stmt} ":
        return "row_filter"            # subsetting IF
    if head == "%let":
        rhs = stmt.split("=", 1)[1] if "=" in stmt else ""
        words = [w for w in rhs.split() if re.match(r"^[a-z_][\w:]*$", w)]
        return "variable_list" if len(words) >= 3 else "other"
    if head == "select" or head == "when":
        return "recode"
    if TRANSFORM_RE.search(stmt):
        return "transform"

    m = ASSIGN_RE.match(stmt)
    if m:
        cond, target, rhs = (m.group("cond") or "").strip(), m.group("target"), m.group("rhs").strip()
        miss = MISS_COND_RE.match(cond) if cond else None
        if miss:
            var = miss.group("var") or miss.group("mvar")
            return "missing_fill" if target == var else "missing_flag"
        if re.match(r"^missing\s*\(", rhs) or re.match(r"^\(\s*[a-z_]\w*\s*(?:=|eq)\s*\.\s*\)$", rhs):
            return "missing_flag"
        if DERIVE_RE.search(rhs) or (DERIVE_TARGET_RE.match(target) and re.search(r"\bdt_\w+\s*-\s*dt_\w+", rhs)):
            return "standard_derivation"
        if cond and CUT_COND_RE.search(cond):
            return "dichotomize"
        if not cond and re.match(r"^\(.*(?:<|>|\blt\b|\ble\b|\bgt\b|\bge\b).*\)$", rhs):
            return "dichotomize"
        if cond and LITERAL_RE.match(rhs):
            return "recode"
        if DERIVE_TARGET_RE.match(target):
            return "standard_derivation"
    if ADMIN_RE.match(stmt):
        return None                     # bookkeeping, not an operation
    return "other"


def scan_program(text):
    """Count categories over one program's statements."""
    counts = Counter()
    lower = strip_comments(text.lower())
    ctx = {"proc": None}
    for raw in lower.split(";"):
        stmt = " ".join(raw.split())
        if not stmt:
            continue
        head = stmt.split(None, 1)[0]
        if head == "proc":
            ctx["proc"] = (stmt.split() + [""])[1]
        elif head == "data" and not stmt.startswith("data="):
            ctx["proc"] = None
        cat = classify(stmt, ctx)
        if head in {"run", "quit"}:
            ctx["proc"] = None
        if cat:
            counts[cat] += 1
    return counts, lower


def vars_calls(lower):
    """Yield one dict of switch -> value per %vars call (empty dict = defaults)."""
    for m in VARS_CALL_RE.finditer(lower):
        if re.search(r"%macro\s*$", lower[max(0, m.start() - 12):m.start()]):
            continue                    # the definition, not a call
        args = {}
        for part in (m.group("args") or "").split(","):
            if "=" in part:
                key, value = (s.strip() for s in part.split("=", 1))
                if key in SWITCHES:
                    args[key] = value
        yield args


def study_key(path, marker_dirs):
    parts = path.parts
    at = max(i for i, p in enumerate(parts) if p.lower() in marker_dirs)
    return str(Path(*parts[:at]))


def walk(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d.lower() not in SKIP_DIRS and not d.startswith(".")]
        here = Path(dirpath)
        parts = {p.lower() for p in here.parts}
        for name in filenames:
            if name.lower().endswith(".sas"):
                yield here / name, parts


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("root", help="corpus root, e.g. /studies")
    parser.add_argument("private_csv")
    parser.add_argument("public_json")
    args = parser.parse_args()

    rows = []
    calls = []
    for path, parts in walk(args.root):
        try:
            data = path.read_bytes()
        except OSError:
            continue
        text = data.decode("latin-1")
        if parts & DATASET_DIRS:
            kind = program_kind(path.name)
            if kind:
                counts, lower = scan_program(text)
                rows.append({
                    "study": study_key(path, DATASET_DIRS),
                    "path": str(path),
                    "kind": kind,
                    "template": path.name.lower().startswith("tp."),
                    "sha256": hashlib.sha256(data).hexdigest(),
                    "mtime": int(path.stat().st_mtime),
                    "lines": text.count("\n") + 1,
                    "calls_vars": bool(list(vars_calls(lower))),
                    "tp_vars": sorted({m.lower() for m in TP_VARS_RE.findall(lower) if m.lower() != path.name.lower()[:-4]}),
                    **{c: counts.get(c, 0) for c in CATEGORIES},
                })
        elif parts & JOB_DIRS and "%vars" in text.lower():
            lower = strip_comments(text.lower())
            for call in vars_calls(lower):
                calls.append({"study": study_key(path, JOB_DIRS), "path": str(path), **call})

    with open(args.private_csv, "w", newline="") as fh:
        fields = ["study", "path", "kind", "template", "sha256", "mtime", "lines", "calls_vars", "tp_vars", *CATEGORIES]
        writer = csv.DictWriter(fh, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow({**row, "tp_vars": " ".join(row["tp_vars"])})
    with open(Path(args.private_csv).with_name(Path(args.private_csv).stem + "-vars-calls.csv"), "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=["study", "path", *SWITCHES])
        writer.writeheader()
        writer.writerows(calls)

    with open(args.public_json, "w") as fh:
        json.dump(summarise(rows, calls), fh, indent=2)


def summarise(rows, calls):
    """Aggregate counts only: no path, study name, hash or value."""
    out = {"generated": date.today().isoformat(), "categories": list(CATEGORIES), "programs": {}}
    for kind in ("bd", "vars", "sastor"):
        for template in (False, True):
            sel = [r for r in rows if r["kind"] == kind and r["template"] == template]
            if not sel:
                continue
            latest = {}
            for r in sel:                   # the most recently modified copy per study
                if r["study"] not in latest or r["mtime"] > latest[r["study"]]["mtime"]:
                    latest[r["study"]] = r
            cur = list(latest.values())
            entry = {
                "files": len(sel),
                "studies": len(latest),
                "median_lines_latest": statistics.median(r["lines"] for r in cur),
                "calls_vars_latest": sum(r["calls_vars"] for r in cur),
                "per_category_latest": {
                    c: {
                        "studies_with": sum(1 for r in cur if r[c] > 0),
                        "statements": sum(r[c] for r in cur),
                        "median_when_present": statistics.median([r[c] for r in cur if r[c] > 0] or [0]),
                    }
                    for c in CATEGORIES
                },
                "tp_vars_modules_latest": dict(Counter(m for r in cur for m in r["tp_vars"]).most_common()),
            }
            out["programs"][f"{kind}{'_template' if template else ''}"] = entry
    switch_on = {s: sum(1 for c in calls if c.get(s, "").strip() not in {"", "0"}) for s in SWITCHES}
    out["vars_calls"] = {
        "calls": len(calls),
        "job_files": len({c["path"] for c in calls}),
        "studies": len({c["study"] for c in calls}),
        "default_calls": sum(1 for c in calls if not any(c.get(s) for s in SWITCHES)),
        "switch_set_nonzero": switch_on,
    }
    out["blind_spots"] = [
        "macro-generated code is not expanded",
        "PROC SQL steps are classified by keyword, not parsed",
        "each statement gets one category; precedence is the order of tests in classify()",
    ]
    return out


if __name__ == "__main__":
    main()
