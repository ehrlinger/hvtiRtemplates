#!/usr/bin/env python3
"""Fail if the roadmap ledger disagrees with the templates on disk.

The ledger (`2026-08-29-template-roadmap.json`) is authoritative for status,
family and batch; `inst/templates/` is authoritative for what actually ships.
This checks they agree, in both directions -- a ledger row claiming a template
that is absent is a lie, and a template no row claims is a template nobody
scheduled.

Deliberately does NOT read `hvti_taxonomy()`. That needs R, and this runs in a
Python step. The vocabulary check lives in `tests/testthat/test-roadmap.R`,
where R is already present. Splitting them keeps each guard in the language
that already has what it needs.

Exit 0 = agree. Exit 1 = drift, with every mismatch listed.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LEDGER = os.path.join(HERE, "2026-08-29-template-roadmap.json")
REPO = os.path.join(HERE, os.pardir, os.pardir, os.pardir)
TEMPLATES = os.path.join(REPO, "inst", "templates")

# The ordinal's major field is the taxonomy folder's position, and the two must
# agree or a template sorts into the wrong run order. Taken from the order of
# `hvti_taxonomy()`'s folder column, which is stable and is itself asserted in
# tests/testthat/test-taxonomy.R.
FOLDER_ORDINAL = {
    "datasets": "01",
    "descriptive": "02",
    "distributions": "03",
    "analyses": "04",
    "estimates": "05",
    "graphs": "06",
    "documents": "07",
}

STATUSES = {"shipped", "revisit", "in-flight", "queued", "intake", "out-of-scope"}
KINDS = {"job", "meta"}
FIELDS = ["prefix", "name", "folder", "family", "kind", "status", "ordinal",
          "batch", "sas_breadth", "r_exemplars", "r_jobs", "upstream",
          "downstream", "workflows", "blocked_on", "spec", "note"]

# A row in one of these states asserts a template exists on disk. Every other
# state asserts it does not. `revisit` counts as shipped: the file is there and
# incomplete, which is a different claim from absent.
ON_DISK = {"shipped", "revisit", "in-flight"}


def check_schema(rows):
    bad = []
    for i, r in enumerate(rows):
        where = r.get("prefix") or f"row {i}"
        missing = [f for f in FIELDS if f not in r]
        extra = [k for k in r if k not in FIELDS]
        if missing:
            bad.append(f"`{where}` is missing field(s): {', '.join(missing)}")
        if extra:
            bad.append(f"`{where}` has unknown field(s): {', '.join(extra)}")
        if r.get("status") not in STATUSES:
            bad.append(f"`{where}` has status {r.get('status')!r}, "
                       f"not one of {sorted(STATUSES)}")
        if r.get("kind") not in KINDS:
            bad.append(f"`{where}` has kind {r.get('kind')!r}, "
                       f"not one of {sorted(KINDS)}")
        # A measured zero and an unmeasured field must stay distinguishable:
        # nine prefixes genuinely have no R job, and reading that as "not yet
        # counted" would send someone to re-run a census that already answered.
        if r.get("r_exemplars") is not None and not isinstance(r["r_exemplars"], int):
            bad.append(f"`{where}` has non-integer r_exemplars "
                       f"{r['r_exemplars']!r}; use null for unmeasured")
    return bad


def check_ordinals(rows):
    bad = []
    seen = {}
    for r in rows:
        ordinal, folder, prefix = r.get("ordinal"), r.get("folder"), r.get("prefix")
        if ordinal is None:
            if r.get("status") in ON_DISK:
                bad.append(f"`{prefix}` is {r['status']} but has no ordinal")
            continue
        if not re.fullmatch(r"\d{2}[.]\d{2}", ordinal):
            bad.append(f"`{prefix}` has ordinal {ordinal!r}, not zero-padded NN.MM")
            continue
        major = ordinal.split(".")[0]
        want = FOLDER_ORDINAL.get(folder)
        if want is None:
            bad.append(f"`{prefix}` has unknown folder {folder!r}")
        elif major != want:
            bad.append(f"`{prefix}` is in {folder} (ordinal {want}) "
                       f"but its ordinal starts {major}")
        if ordinal in seen:
            bad.append(f"ordinal {ordinal} is used by both "
                       f"`{seen[ordinal]}` and `{prefix}`")
        else:
            seen[ordinal] = prefix
    return bad


def check_disk(rows):
    bad = []
    claimed = {}
    for r in rows:
        if r.get("status") not in ON_DISK or not r.get("ordinal"):
            continue
        rel = os.path.join(r["folder"], f"{r['ordinal']}-{r['prefix']}.qmd")
        claimed[rel] = r["prefix"]
        if not os.path.isfile(os.path.join(TEMPLATES, rel)):
            bad.append(f"`{r['prefix']}` is {r['status']} but "
                       f"inst/templates/{rel} does not exist")

    on_disk = []
    for root, _dirs, files in os.walk(TEMPLATES):
        for f in files:
            if f.endswith(".qmd"):
                rel = os.path.relpath(os.path.join(root, f), TEMPLATES)
                on_disk.append(rel)
    for rel in sorted(on_disk):
        if rel not in claimed:
            bad.append(f"inst/templates/{rel} exists but no ledger row claims it")
    return bad


def main():
    # Encodings are pinned, as in the sibling checks: this runs on a CI runner
    # whose locale is not ours to choose, and the ledger carries em dashes an
    # ascii default would refuse outright.
    with open(LEDGER, encoding="utf-8") as fh:
        d = json.load(fh)
    rows = d["prefixes"]

    bad = check_schema(rows) + check_ordinals(rows) + check_disk(rows)
    if bad:
        print("Roadmap ledger disagrees with the templates on disk:\n", file=sys.stderr)
        for b in bad:
            print(f"  - {b}", file=sys.stderr)
        print("\nThe ledger is the map. Fix the ledger, or ship the template it\n"
              "claims; do not delete the row to make the check pass.", file=sys.stderr)
        return 1

    shipped = sum(1 for r in rows if r["status"] in ON_DISK)
    print(f"Ledger agrees with disk: {len(rows)} prefixes, {shipped} on disk.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
