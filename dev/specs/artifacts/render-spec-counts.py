#!/usr/bin/env python3
"""Re-sync the allocation spec's tables and lists from the generated map.

The write-side companion to `check-spec-counts.py`, which is read-only and
fails a PR when the two disagree. Until now the fix for that failure was a
careful hand-edit of six tables and nine file lists -- the very thing the
check's own error message tells you not to do, and the reason the document
drifted three times in one day. Same pairing as `roadmap_render.py` beside
`check-roadmap-counts.py`.

Rewrites ONLY mechanical regions: the summary table's numbers, the per-package
heading counts and their one-line file lists, the corpus-only heading count,
the anchored dependency sentence, and the dependency block. Prose is never
touched -- a claim that has gone false is a paragraph to rewrite, not a number
to re-sync, and this script says so rather than silently patching around it.

Run after regenerating the map, then run check-spec-counts.py:

    python3 2026-08-14-macro-allocation-scan.py
    python3 render-spec-counts.py
    python3 check-spec-counts.py
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MAP = os.path.join(HERE, "2026-08-14-macro-allocation.json")
SPEC = os.path.join(HERE, os.pardir, "2026-08-14-macro-allocation-design.md")

# Summary-table row label -> key in `counts`. Mirrors check-spec-counts.py's
# TIER_ROWS; if one gains a tier the other must too.
TIER_ROWS = {
    "Allocated": "allocated",
    "Travels with a dependent": "travels_with_dependent",
    "Blocked on an unowned prefix": "blocked",
    "Corpus-only": "corpus_only",
}


def files_line(files):
    return ", ".join(f"`{f}`" for f in sorted(files))


def main():
    with open(MAP, encoding="utf-8") as fh:
        d = json.load(fh)
    with open(SPEC, encoding="utf-8") as fh:
        spec = fh.read()
    counts, by_dest, xd = d["counts"], d["by_destination"], \
        d["cross_package_dependencies"]
    edits, warn = 0, []

    # 1. summary table: one row per destination package, then the tier rows.
    for pkg, files in by_dest.items():
        if pkg.startswith("_"):
            continue
        pat = re.compile(rf"(\| `{re.escape(pkg)}`[^|\n]*\| )\*?\*?\d+\*?\*?( \|)")
        spec, n = pat.subn(rf"\g<1>{len(files)}\g<2>", spec)
        if n:
            edits += n
        else:
            warn.append(f"summary table has no row for `{pkg}` "
                        f"({len(files)} files) -- add it by hand")

    for label, key in TIER_ROWS.items():
        bold = label == "Allocated"
        val = f"**{counts[key]}**" if bold else str(counts[key])
        pat = re.compile(rf"(\| \*?\*?{re.escape(label)}\*?\*? \| )"
                         rf"\*?\*?\d+\*?\*?( \|)")
        spec, n = pat.subn(rf"\g<1>{val}\g<2>", spec)
        edits += n

    total = sum(counts[k] for k in TIER_ROWS.values())
    spec, n = re.subn(r"(\| \*\*Total\*\* \| \*\*)\d+(\*\* \|)",
                      rf"\g<1>{total}\g<2>", spec)
    edits += n
    if total != counts["macro_files"]:
        warn.append(f"tiers sum to {total}, map has {counts['macro_files']} "
                    f"files -- the map is inconsistent, do not ship this")

    # 2. per-package sections: heading count and the file list beneath it.
    # The heading may carry a qualifier (`- shared`, `- override`) and the
    # list may be followed by further prose; both are preserved.
    sections = {k: f"### `{k}`" for k in by_dest if not k.startswith("_")}
    sections["_travels-with-dependent"] = "### Travels with a dependent"
    for pkg, head in sections.items():
        files = by_dest[pkg]
        pat = re.compile(re.escape(head) + r"([^\n(]*)\(\d+\)\n\n[^\n]+\n")
        rep = f"{head}\\g<1>({len(files)})\n\n{files_line(files)}\n"
        spec, n = pat.subn(lambda m: rep.replace("\\g<1>", m.group(1)), spec)
        if n:
            edits += n
        else:
            warn.append(f"no section found for `{pkg}` -- expected a heading "
                        f"`{head} (N)` followed by a blank line and one list line")

    # 3. the corpus-only heading, whose count is in its title and is not
    # guarded by check-spec-counts.py -- it has no file list to check.
    spec, n = re.subn(r"(## Corpus-only files \()\d+(\))",
                      rf"\g<1>{counts['corpus_only']}\g<2>", spec)
    edits += n

    # 4. the anchored dependency sentence and the edge block.
    spec, n = re.subn(r"\*\*\d+\*\* file-level dependencies span "
                      r"\*\*\d+\*\* package pairs",
                      f"**{xd['n_dependencies']}** file-level dependencies "
                      f"span **{xd['n_package_pairs']}** package pairs", spec)
    edits += n

    # An empty edge list is a legitimate map -- an allocation where nothing
    # crosses a package boundary -- and max() raises ValueError on it, which
    # would crash the renderer BEFORE it writes, leaving the spec unsynced
    # behind a traceback. check-spec-counts.py handles the empty case, so
    # this must too.
    if xd["edges"]:
        w = max(len(e["dependent"]) for e in xd["edges"])
        w2 = max(len(e["dependency"]) for e in xd["edges"])
        # The count is NOT padded inside the parens. check-spec-counts.py
        # reads these edges back with `\((\d+)\)`, which does not match
        # `( 8)`, so a right-aligned number makes the block parse as three
        # edges instead of six -- a renderer that silently defeats its own
        # checker.
        block = "\n".join(
            f"{e['dependent']:<{w}}  -> {e['dependency']:<{w2}}  ({e['n']})"
            for e in sorted(xd["edges"], key=lambda e: -e["n"]))
    else:
        block = "(none -- no dependency crosses a package boundary)"
    spec, n = re.subn(r"(package pairs.*?```\n).*?(```)", 
                      lambda m: m.group(1) + block + "\n" + m.group(2),
                      spec, flags=re.S)
    edits += n

    # 5. acyclicity is a CLAIM, not a count. Never patched silently.
    acyclic = xd["acyclic_packages"] and xd["acyclic_files"]
    claims = re.search(r"graph is \*\*acyclic\*\*", spec) is not None
    if claims and not acyclic:
        where = "packages" if not xd["acyclic_packages"] else "files"
        warn.append(
            f"the spec calls the graph **acyclic** and the map reports a cycle "
            f"at the {where} level. NOT rewritten: a cycle between two packages "
            f"is a design problem to resolve, not a word to swap. Fix the "
            f"allocation or rewrite the paragraph deliberately.")
    if acyclic and not claims:
        warn.append("the map reports an acyclic graph and the spec no longer "
                    "says so -- restore the claim by hand if it is meant.")

    with open(SPEC, "w", encoding="utf-8") as fh:
        fh.write(spec)
    print(f"re-synced {edits} region(s) in {os.path.basename(SPEC)}")
    for w_ in warn:
        print(f"  ! {w_}", file=sys.stderr)
    return 1 if warn else 0


if __name__ == "__main__":
    sys.exit(main())
