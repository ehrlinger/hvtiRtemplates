#!/usr/bin/env python3
"""Fail if the allocation spec's prose disagrees with the generated map.

The map (`2026-08-14-macro-allocation.json`) is authoritative; the spec's
tables and per-package lists are a convenience copy. Copies drift. This drifted
three times in one day -- each time a count was hand-synced in one place and not
another, and each time it took a reviewer to notice -- so the agreement is
checked mechanically rather than by discipline.

Deliberately does NOT re-run the scan. That needs `~/Documents/macro.library`
and `~/Documents/template`, which exist on John's machine and not on a CI
runner. Regenerating the map is a local step; this check is what CI can honestly
enforce.

Exit 0 = agree. Exit 1 = drift, with every mismatch listed.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MAP = os.path.join(HERE, "2026-08-14-macro-allocation.json")
SPEC = os.path.join(HERE, os.pardir, "2026-08-14-macro-allocation-design.md")

TIER_ROWS = {                      # spec table label -> key in counts
    "Allocated": "allocated",
    "Travels with a dependent": "travels_with_dependent",
    "Blocked on an unowned prefix": "blocked",
    "Corpus-only": "corpus_only",
}


def main():
    # Encodings are pinned, as in `check-flow-counts.py`: this runs on a CI
    # runner whose locale is not ours to choose, and the spec carries em dashes
    # that an ascii default would refuse outright.
    with open(MAP, encoding="utf-8") as fh:
        d = json.load(fh)
    counts, by_dest = d["counts"], d["by_destination"]
    with open(SPEC, encoding="utf-8") as fh:
        spec = fh.read()
    bad = []

    # 1. summary-table row per destination package
    for pkg, files in sorted(by_dest.items()):
        if pkg.startswith("_"):
            continue
        m = re.search(rf"\| `{re.escape(pkg)}`[^|\n]*\| \*?\*?(\d+)\*?\*? \|", spec)
        if not m:
            bad.append(f"summary table has no row for `{pkg}` (map: {len(files)})")
        elif int(m.group(1)) != len(files):
            bad.append(f"summary table `{pkg}` = {m.group(1)}, map = {len(files)}")

    # 2. tier totals, and that they reconcile to the file count
    for label, key in TIER_ROWS.items():
        m = re.search(rf"\| \*?\*?{re.escape(label)}\*?\*? \| \*?\*?(\d+)\*?\*? \|", spec)
        if not m:
            bad.append(f"summary table has no `{label}` row (map: {counts[key]})")
        elif int(m.group(1)) != counts[key]:
            bad.append(f"summary table `{label}` = {m.group(1)}, map = {counts[key]}")

    total = sum(counts[k] for k in TIER_ROWS.values())
    if total != counts["macro_files"]:
        bad.append(f"tiers sum to {total}, map has {counts['macro_files']} macro files")
    m = re.search(r"\| \*\*Total\*\* \| \*\*(\d+)\*\* \|", spec)
    if m and int(m.group(1)) != total:
        bad.append(f"summary table Total = {m.group(1)}, tiers sum to {total}")

    # 3. per-package sections: heading count AND the files actually listed.
    # Only sections the spec actually carries. `_blocked` is presented as a
    # prefix table, not a file list, and `_corpus-only` is described in prose --
    # neither has a per-file section to check.
    SECTIONS = {k: f"### `{k}`" for k in by_dest if not k.startswith("_")}
    SECTIONS["_travels-with-dependent"] = "### Travels with a dependent"
    for pkg, head in sorted(SECTIONS.items()):
        files = by_dest[pkg]
        m = re.search(
            re.escape(head) + r"[^\n(]*\((\d+)\)\n\n([^\n]+)\n", spec)
        if not m:
            bad.append(f"no section found for `{pkg}`")
            continue
        if int(m.group(1)) != len(files):
            bad.append(f"section `{head}` heading = {m.group(1)}, map = {len(files)}")
        listed = {x.strip(" `") for x in m.group(2).split(",")}
        if listed != set(files):
            for extra in sorted(listed - set(files)):
                bad.append(f"section `{head}` lists `{extra}`, not in the map")
            for miss in sorted(set(files) - listed):
                bad.append(f"section `{head}` omits `{miss}`, which the map assigns there")

    if bad:
        print("Spec prose disagrees with the generated map:\n", file=sys.stderr)
        for b in bad:
            print(f"  - {b}", file=sys.stderr)
        print(
            "\nThe JSON is authoritative. Re-run the scan locally and re-sync the\n"
            "spec's tables and per-package lists; do not hand-edit a count.",
            file=sys.stderr,
        )
        return 1

    n = sum(len(v) for v in by_dest.values())
    print(f"Spec agrees with the map: {len(by_dest)} sections, {n} files, "
          f"{counts['macro_files']} total.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
