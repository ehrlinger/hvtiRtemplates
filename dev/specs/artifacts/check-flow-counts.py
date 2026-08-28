#!/usr/bin/env python3
"""Fail if a number in the job flow diagrams disagrees with the generated maps.

The maps (`2026-08-22-job-flow.json`, `2026-08-22-prefix-placement.json`) are
authoritative; the numbers written into the diagrams are a convenience copy.
Copies drift -- the allocation spec next door drifted three times in one day,
each time caught by a reviewer rather than by CI. This makes the agreement
mechanical for the diagrams too.

Every checkable number in the HTML carries its own anchor:

    <span data-check="n_jobs">241</span>          in prose
    <tspan data-check="n_jobs">241</tspan>        inside an SVG label

so a claim is matched by markup rather than by guessing at prose. Adding a new
one needs no change here: every folder total, prefix total and prefix-in-folder
total is already in the registry, so `data-check="files_ac"` resolves on its own.

Deliberately does NOT re-run the scans. That needs `~/Documents/template`, which
exists on John's machine and not on a CI runner -- the same division as
`check-spec-counts.py`. Regenerating the maps is a local step; this is what CI
can honestly enforce.

Numbers with no anchor are not checked, and some are deliberately left that way:
the masthead of `two-sets-one-endpoint.html` counts naming conventions and
missing checks, which are editorial readings of the corpus rather than scan
output. Anchoring them would imply a derivation that does not exist.

Exit 0 = agree. Exit 1 = drift, with every mismatch listed.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FLOW = os.path.join(HERE, "2026-08-22-job-flow.json")
PREFIX = os.path.join(HERE, "2026-08-22-prefix-placement.json")
PAGES = [
    "2026-08-22-job-set-flow.html",
    "2026-08-22-two-sets-one-endpoint.html",
    "2026-08-22-prefix-map.html",
]

ANCHOR = re.compile(r'<(span|tspan) data-check="([^"]+)">([^<]*)</\1>')
# First cell of a taxonomy row: <td class="mono"><code>ac</code>
ROW_PREFIX = re.compile(r'<td class="mono"><code>([a-z0-9]+)</code>')


def registry(flow, pfx):
    """Canonical value for every anchor key, derived from the maps."""
    reg = {k: flow[k] for k in (
        "n_jobs", "n_read_built", "n_vars", "n_members_written",
        "n_members_read", "n_linked", "n_cross_job", "n_dangling", "n_orphan")}

    rows, extra = pfx["rows"], pfx["extra"]
    reg["tax_n_rows"] = pfx["n_rows"]
    for verdict in ("agree", "disagree", "absent"):
        reg[f"tax_{verdict}"] = pfx["counts"].get(verdict, 0)
    reg["tax_extra"] = len(extra)
    reg["tax_scattered"] = sum(1 for r in rows if r.get("scattered"))

    # File counts, at three grains, so any anchor a future edit adds resolves.
    per_folder, total = {}, 0
    for r in rows:
        if r["prefix"]:
            reg[f"files_{r['prefix']}"] = r["n_files"]
        for folder, n in r["actual"].items():
            if r["prefix"]:
                reg[f"files_{r['prefix']}_{folder}"] = n
            per_folder[folder] = per_folder.get(folder, 0) + n
            total += n
    for p, counts in extra.items():
        for folder, n in counts.items():
            per_folder[folder] = per_folder.get(folder, 0) + n
            total += n
    for folder, n in per_folder.items():
        reg[f"files_{folder}"] = n
    reg["files_total"] = total
    return reg


def main():
    # Encodings are pinned throughout: this runs on a CI runner whose locale
    # is not ours to choose, and the diagrams carry em dashes and curly
    # quotes that an ascii default would refuse outright.
    with open(FLOW, encoding="utf-8") as fh:
        flow = json.load(fh)
    with open(PREFIX, encoding="utf-8") as fh:
        pfx = json.load(fh)
    reg = registry(flow, pfx)

    bad, seen, n_anchors = [], set(), 0

    for page in PAGES:
        path = os.path.join(HERE, page)
        with open(path, encoding="utf-8") as fh:
            html = fh.read()
        for _, key, value in ANCHOR.findall(html):
            n_anchors += 1
            seen.add(key)
            if key not in reg:
                bad.append(f"{page}: data-check=\"{key}\" is not a key in either map")
            elif value.strip() != str(reg[key]):
                bad.append(f"{page}: {key} reads {value.strip()}, map says {reg[key]}")

    # The taxonomy table is hand-maintained, so check its rows are the map's
    # rows -- a renamed, added or dropped prefix is drift a count would miss.
    with open(os.path.join(HERE, "2026-08-22-prefix-map.html"), encoding="utf-8") as fh:
        table = fh.read()
    listed = set(ROW_PREFIX.findall(table))
    mapped = {r["prefix"] for r in pfx["rows"] if r["prefix"]}
    for x in sorted(listed - mapped):
        bad.append(f"prefix-map table lists `{x}`, which is not in hvti_taxonomy()")
    for x in sorted(mapped - listed):
        bad.append(f"prefix-map table omits `{x}`, which hvti_taxonomy() carries")

    if bad:
        print("Diagrams disagree with the generated maps:\n", file=sys.stderr)
        for b in bad:
            print(f"  - {b}", file=sys.stderr)
        print(
            "\nThe JSON is authoritative. Re-run both scans locally and re-sync the\n"
            "anchored numbers; do not hand-edit one to match.",
            file=sys.stderr,
        )
        return 1

    unused = sorted(k for k in reg if k not in seen and not k.startswith("files_"))
    print(f"Diagrams agree with the maps: {n_anchors} anchors over {len(PAGES)} pages, "
          f"{len(listed)} taxonomy rows.")
    if unused:
        print(f"  (not quoted anywhere, so not checked: {', '.join(unused)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
