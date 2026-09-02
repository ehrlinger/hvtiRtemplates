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

    # 4. the cross-package dependency graph.
    #
    # This is here because it is the one number in the document that was NOT
    # anchored, and it drifted for nineteen days: the prose said 19 across 3
    # pairs, correct on 2026-08-14 and stale from `77734a9` the same day, when
    # hvtiRbootstrap added 24 dependencies across 2 more pairs. Every count
    # guarded below was re-synced repeatedly over that period. The unguarded
    # one was not, which is the argument for guarding it.
    xd = d.get("cross_package_dependencies")
    if xd is None:
        bad.append("map has no `cross_package_dependencies`; re-run the scan")
    else:
        m = re.search(r"\*\*(\d+)\*\* file-level dependencies span "
                      r"\*\*(\d+)\*\* package pairs", spec)
        if not m:
            bad.append(
                f"no anchored dependency sentence found (map: "
                f"{xd['n_dependencies']} across {xd['n_package_pairs']} pairs). "
                f"Expected `**N** file-level dependencies span **M** package "
                f"pairs`")
        else:
            if int(m.group(1)) != xd["n_dependencies"]:
                bad.append(f"prose says {m.group(1)} dependencies, "
                           f"map = {xd['n_dependencies']}")
            if int(m.group(2)) != xd["n_package_pairs"]:
                bad.append(f"prose says {m.group(2)} package pairs, "
                           f"map = {xd['n_package_pairs']}")

        # The edge list is a copy of the map and drifts the same way the
        # per-package lists do, so it gets the same row-by-row treatment.
        for e in xd["edges"]:
            pat = (rf"{re.escape(e['dependent'])}\s*->\s*"
                   rf"{re.escape(e['dependency'])}\s*\((\d+)\)")
            m2 = re.search(pat, spec)
            if not m2:
                bad.append(f"dependency block omits `{e['dependent']} -> "
                           f"{e['dependency']}` ({e['n']}), which the map has")
            elif int(m2.group(1)) != e["n"]:
                bad.append(f"dependency block `{e['dependent']} -> "
                           f"{e['dependency']}` = {m2.group(1)}, map = {e['n']}")

        # "acyclic" is a claim, not a count. The scan verifies it; the spec
        # must not assert it when the scan says otherwise.
        claims_acyclic = re.search(r"graph is \*\*acyclic\*\*", spec) is not None
        if claims_acyclic and not xd["acyclic"]:
            bad.append("spec calls the dependency graph acyclic; the map does not")
        if xd["acyclic"] and not claims_acyclic:
            bad.append("map reports an acyclic graph; the spec no longer says so")

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
    xd = d["cross_package_dependencies"]
    print(f"Spec agrees with the map: {len(by_dest)} sections, {n} files, "
          f"{counts['macro_files']} total, {xd['n_dependencies']} cross-package "
          f"dependencies over {xd['n_package_pairs']} pairs"
          f"{', acyclic' if xd['acyclic'] else ', CYCLIC'}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
