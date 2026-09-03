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
FIELDS = ["prefix", "qualifier", "name", "folder", "family", "kind", "status",
          "ordinal",
          "batch", "sas_breadth", "sas_breadth_jobs", "r_exemplars",
          "r_jobs", "upstream",
          "downstream", "workflows", "blocked_on", "spec", "note"]

# A row in one of these states asserts a template exists on disk. Every other
# state asserts it does not. `revisit` counts as shipped: the file is there and
# incomplete, which is a different claim from absent.
ON_DISK = {"shipped", "revisit", "in-flight"}

# `retired_ordinals` is ledger data and gets the same treatment as a prefix row.
RETIRED_FIELDS = ["ordinal", "prefix", "retired", "reason"]


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


def check_ordinals(rows, retired=()):
    """An ordinal is a KEY, assigned once, not a position.

    It is NOT derived from the prefix's row position in `hvti_taxonomy()`, and
    must not be recomputed from it. That derivation is what put `bh` at 04.06:
    it was 6th in `analyses` when the number was assigned, hvtiRutilities
    aeb20f2 moved `hs` out to `graphs`, and every prefix below it shifted up
    one while the shipped filename stayed put. Nothing caught it, because the
    checks below verify format, folder-major and uniqueness -- never position.

    Row order may drift. Ordinals may not. Same rule pub_kb reached for
    document_key on 2026-08-06: identity is assigned once and only accumulates.
    """
    bad = []
    seen = {}
    # Only well-formed entries. A malformed one is REPORTED by check_retired()
    # rather than raised here: this script exists to name a ledger's shape
    # problems, and a KeyError names only its own traceback.
    retired_by = {r["ordinal"]: r for r in retired
                  if isinstance(r, dict) and isinstance(r.get("ordinal"), str)}
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
        if ordinal in retired_by:
            was = retired_by[ordinal]
            bad.append(f"`{prefix}` uses ordinal {ordinal}, retired "
                       f"{was.get('retired', '?')} from `{was.get('prefix', '?')}`. "
                       f"A retired ordinal "
                       f"has already shipped in a scaffolded filename somewhere and "
                       f"cannot be reissued; take the next free minor instead")
        if ordinal in seen:
            bad.append(f"ordinal {ordinal} is used by both "
                       f"`{seen[ordinal]}` and `{prefix}`")
        else:
            seen[ordinal] = prefix
    return bad


def check_retired(retired):
    """Validate `retired_ordinals` itself, so a malformed entry reads as a
    ledger defect rather than a traceback."""
    if not isinstance(retired, list):
        return [f"`retired_ordinals` must be a list, got "
                f"{type(retired).__name__}"]
    bad = []
    seen = {}
    for i, r in enumerate(retired):
        where = f"retired_ordinals[{i}]"
        if not isinstance(r, dict):
            bad.append(f"{where} is a {type(r).__name__}, not an object")
            continue
        missing = [f for f in RETIRED_FIELDS if f not in r]
        extra = [k for k in r if k not in RETIRED_FIELDS]
        if missing:
            bad.append(f"{where} is missing field(s): {', '.join(missing)}")
        if extra:
            bad.append(f"{where} has unknown field(s): {', '.join(extra)}")
        # Absent is already reported above. PRESENT-but-null is not, and must
        # not fall through: `"ordinal": null` is a different defect from a
        # missing key, and skipping it let one through silently.
        if "ordinal" not in r:
            continue
        ordinal = r["ordinal"]
        if not isinstance(ordinal, str) or not re.fullmatch(r"\d{2}[.]\d{2}", ordinal):
            bad.append(f"{where} has ordinal {ordinal!r}, not zero-padded NN.MM")
        elif ordinal in seen:
            bad.append(f"ordinal {ordinal} is retired twice, at "
                       f"retired_ordinals[{seen[ordinal]}] and {where}")
        else:
            seen[ordinal] = i
    return bad


def check_disk(rows):
    bad = []
    claimed = {}
    for r in rows:
        if r.get("status") not in ON_DISK or not r.get("ordinal"):
            continue
        # `is not None`, not truthiness. An empty-string qualifier is falsy,
        # so `if r.get("qualifier")` would look for the UNQUALIFIED filename
        # and quietly pass. Absent and empty are different states, which is
        # the same distinction .template_fields() draws between NA and "".
        q = r.get("qualifier")
        stem = r["prefix"] + (f"-{q}" if q is not None else "")
        rel = os.path.join(r["folder"], f"{r['ordinal']}-{stem}.qmd")
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

    retired = d.get("retired_ordinals", [])

    bad = (check_schema(rows) + check_retired(retired)
           + check_ordinals(rows, retired) + check_disk(rows) + check_doc(rows))
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
