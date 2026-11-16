#!/usr/bin/env python3
"""Fail when this package's boostmtree pin disagrees with ggBoostedTrees' pin.

Both DESCRIPTIONs carry `boostmtree=ehrlinger/boostmtree_src/boostmtree@<tag>`
in `Remotes:`. Both pins are needed: ggBoostedTrees imports boostmtree, and
this package's pin is what makes `remotes::install_github(dependencies = TRUE)`
install the fork rather than CRAN's 2.0.0 (#557). pak accepts only one GitHub
ref per package, so when the two disagree the dependency install fails before
any test runs, with an error that does not name the cause. This check runs
without installing anything and names it.

It also checks the tag in nb-boostmtree's install line, the third copy.

Usage: python3 dev/check-boostmtree-pin.py [path/to/ggBoostedTrees/DESCRIPTION]
With no argument it reads ggBoostedTrees' DESCRIPTION from GitHub `main`.
"""
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GGBT_URL = "https://raw.githubusercontent.com/ehrlinger/ggBoostedTrees/main/DESCRIPTION"
TEMPLATE = ROOT / "inst" / "templates" / "30_analyses" / "nb-boostmtree.qmd"
PIN = re.compile(r"boostmtree=ehrlinger/boostmtree_src/boostmtree@([^\s,]+)")


def remotes_field(text):
    """The Remotes field of a DESCRIPTION, continuation lines joined."""
    match = re.search(r"^Remotes:(.*(?:\n[ \t].*)*)", text, flags=re.MULTILINE)
    return match.group(1) if match else ""


def pin_of(text, where):
    pins = PIN.findall(remotes_field(text))
    if len(pins) != 1:
        sys.exit(f"check-boostmtree-pin: expected one boostmtree pin in {where}'s Remotes, found {len(pins)}.")
    return pins[0]


def main():
    ours = pin_of((ROOT / "DESCRIPTION").read_text(encoding="utf-8"), "hvtiRtemplates")
    if len(sys.argv) > 1:
        ggbt_text = Path(sys.argv[1]).read_text(encoding="utf-8")
    else:
        try:
            with urllib.request.urlopen(GGBT_URL, timeout=30) as response:
                ggbt_text = response.read().decode("utf-8")
        except OSError as err:  # URLError and timeouts are OSErrors
            sys.exit(f"check-boostmtree-pin: could not read {GGBT_URL}: {err}. "
                     f"Pass a local copy of ggBoostedTrees' DESCRIPTION as the argument.")
    theirs = pin_of(ggbt_text, "ggBoostedTrees")
    hint = re.findall(r'ref = \\"([^"\\]+)\\"', TEMPLATE.read_text(encoding="utf-8"))

    problems = []
    if ours != theirs:
        problems.append(
            f"DESCRIPTION pins boostmtree @{ours} but ggBoostedTrees pins @{theirs}. pak refuses two refs for one "
            f"package, so the dependency install fails. Set both to the same tag."
        )
    if hint != [ours]:
        problems.append(
            f"nb-boostmtree.qmd's install line names {hint or 'no tag'}, not the DESCRIPTION pin @{ours}."
        )
    if problems:
        sys.exit("check-boostmtree-pin:\n  " + "\n  ".join(problems))
    print(f"boostmtree pin @{ours}: DESCRIPTION, ggBoostedTrees and nb-boostmtree's install line agree.")


if __name__ == "__main__":
    main()
