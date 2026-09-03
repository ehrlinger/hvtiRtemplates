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

sys.path.insert(0, HERE)
import roadmap_render  # noqa: E402  (path set immediately above)


STATUSES = {"shipped", "revisit", "in-flight", "queued", "intake", "out-of-scope"}
KINDS = {"job", "meta"}
FIELDS = ["prefix", "qualifier", "name", "folder", "family", "kind", "status",
          "batch", "sas_breadth", "sas_breadth_jobs", "r_exemplars",
          "r_jobs", "upstream",
          "downstream", "workflows", "blocked_on", "spec", "note"]

# A row in one of these states asserts a template exists on disk. Every other
# state asserts it does not. `revisit` counts as shipped: the file is there and
# incomplete, which is a different claim from absent.
ON_DISK = {"shipped", "revisit", "in-flight"}



# A measured zero and an unmeasured field must stay distinguishable: nine
# prefixes genuinely have no R job, and reading that as "not yet counted"
# would send someone to re-run a census that already answered. Every count
# field carries the same risk -- a string here renders into the table
# verbatim (sas_breadth) or breaks the renderer's sort key (batch) -- so all
# of them get the same integer-or-null check.
INT_OR_NULL_FIELDS = ["batch", "sas_breadth", "sas_breadth_jobs",
                      "r_exemplars", "r_jobs"]


def check_schema(rows):
    bad = []
    seen_prefixes = {}
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
        if r.get("family") not in roadmap_render.FAMILY_ORDER:
            bad.append(f"`{where}` has family {r.get('family')!r}, "
                       f"not one of {sorted(roadmap_render.FAMILY_ORDER)}")
        # Shape-check the qualifier rather than only handling "" at each use
        # site. Two sites collapsed empty into absent and a third would have
        # done it again; rejecting the value is what stops that recurring.
        # `str(q)` first would accept 42 as "42", which then renders and
        # resolves as `dp-42`. The contract is string-or-null, so a non-string
        # is rejected as one rather than coerced into a passing one.
        q = r.get("qualifier")
        if q is not None and (not isinstance(q, str)
                              or not re.fullmatch(r"[A-Za-z0-9_]+", q)):
            bad.append(f"`{where}` has qualifier {q!r}; use null for an "
                       f"unqualified template, else a string [A-Za-z0-9_]+")
        for field in INT_OR_NULL_FIELDS:
            v = r.get(field)
            if v is not None and not isinstance(v, int):
                bad.append(f"`{where}` has non-integer {field} {v!r}; "
                           f"use null for unmeasured")
        # Keyed on (prefix, qualifier), not prefix alone. `graphs/dp` is
        # several job types under one prefix, so one row per prefix cannot
        # express the estate; two rows for the SAME pair still cannot both be
        # right. A prefix must be wholly qualified or wholly unqualified,
        # checked below. See
        # dev/specs/2026-09-02-dp-dc-decomposition-design.md, section 8.
        prefix = r.get("prefix")
        if prefix is not None:
            key = (prefix, r.get("qualifier"))
            if key in seen_prefixes:
                shown = prefix if key[1] is None else f"{prefix}-{key[1]}"
                bad.append(f"`{shown}` appears more than once, "
                           f"at row {seen_prefixes[key]} and row {i}")
            else:
                seen_prefixes[key] = i
    # A prefix half-decomposed is a state the ledger could describe and the
    # package would then refuse to use: .select_template() errors on a mixed
    # prefix, because its ambiguity message would offer an unqualified row
    # that no caller can ask for. Catch it here, where it is cheaper.
    by_prefix = {}
    for r in rows:
        if r.get("prefix") is not None:
            by_prefix.setdefault(r["prefix"], []).append(r.get("qualifier"))
    for prefix, quals in sorted(by_prefix.items()):
        if any(q is None for q in quals) and any(q is not None for q in quals):
            bad.append(f"`{prefix}` mixes qualified and unqualified rows "
                       f"({', '.join(str(q) for q in quals)}); decomposing a "
                       f"prefix means naming every job under it")
    return bad




def _folder_dirs():
    """Taxonomy folder name -> the numbered directory holding it, from DISK.

    `20_distributions` -> {"distributions": "20_distributions"}. Read rather
    than hardcoded: a second copy of the numbering is a second thing to keep in
    step, and that is exactly what the retired `FOLDER_ORDINAL` map was. A
    directory without the digits maps to itself, so the check still works on a
    tree mid-migration.
    """
    out = {}
    if not os.path.isdir(TEMPLATES):
        return out
    for d in sorted(os.listdir(TEMPLATES)):
        if os.path.isdir(os.path.join(TEMPLATES, d)):
            out[re.sub(r"^[0-9]+_", "", d)] = d
    return out


def check_disk(rows):
    bad = []
    claimed = {}
    folder_dir = _folder_dirs()
    for r in rows:
        if r.get("status") not in ON_DISK:
            continue
        # `is not None`, not truthiness. An empty-string qualifier is falsy,
        # so `if r.get("qualifier")` would look for the UNQUALIFIED filename
        # and quietly pass. Absent and empty are different states, which is
        # the same distinction .template_fields() draws between NA and "".
        q = r.get("qualifier")
        stem = r["prefix"] + (f"-{q}" if q is not None else "")
        # The directory carries the ordering digits and the ledger row carries
        # the bare taxonomy name, so the path is resolved from what is on disk
        # rather than reconstructed from a second copy of the numbering.
        rel = os.path.join(folder_dir.get(r["folder"], r["folder"]),
                           f"{stem}.qmd")
        claimed[rel] = stem
        if not os.path.isfile(os.path.join(TEMPLATES, rel)):
            # `stem`, not `prefix`: once a prefix carries several qualifiers,
            # naming the bare prefix does not say which row is unsatisfied.
            bad.append(f"`{stem}` is {r['status']} but "
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


def check_doc(rows):
    """The document's tables must be exactly what the ledger renders."""
    with open(roadmap_render.DOC, encoding="utf-8") as fh:
        text = fh.read()
    want = roadmap_render.render(rows)
    i, j = text.find(roadmap_render.BEGIN), text.find(roadmap_render.END)
    if i < 0 or j < 0:
        return ["the roadmap document has lost its BEGIN/END GENERATED markers"]
    have = text[i:j + len(roadmap_render.END)]
    if have != want:
        return ["the roadmap document's tables are not what the ledger renders; "
                "run `python3 dev/specs/artifacts/roadmap_render.py`"]
    return []


def main():
    # Encodings are pinned, as in the sibling checks: this runs on a CI runner
    # whose locale is not ours to choose, and the ledger carries em dashes an
    # ascii default would refuse outright.
    with open(LEDGER, encoding="utf-8") as fh:
        d = json.load(fh)
    rows = d["prefixes"]

    bad = check_schema(rows) + check_disk(rows) + check_doc(rows)
    if bad:
        print("Roadmap ledger disagrees with the templates on disk:\n", file=sys.stderr)
        for b in bad:
            print(f"  - {b}", file=sys.stderr)
        print("\nThe ledger is the map. Fix the ledger, or ship the template it\n"
              "claims; do not delete the row to make the check pass.", file=sys.stderr)
        return 1

    shipped = sum(1 for r in rows if r["status"] in ON_DISK)
    print(f"Ledger agrees with disk: {len(rows)} template rows, {shipped} on disk.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
