"""Fail when this repo's two hvtiR pins disagree with each other.

The pin
-------
`jobs.json` lives in `hvtiR` and is read here by TAG, not as a dependency --
`hvtiR` installs this package, so a `DESCRIPTION` entry would invert the
family, and tracking `main` would let an edit there fail every pull request
here. `R-CMD-check.yaml` and `spec-counts.yaml` each check it out
independently.

What this catches that hvtiR's detector does not
------------------------------------------------
`hvtiR` 1.1.6 ships `jobs-pin-drift`, which reads both of these files and
reports when either lags its newest tag. That is the right home for the
"time to cut a release" alarm, and this script does not duplicate it.

The gap is TIMING and SCOPE. Two refs are advanced by hand, in one pull
request, and advancing one and forgetting the other is the realistic mistake.
hvtiR notices on its next scheduled run -- up to a week later, in another
repository, to someone who was not making this change. This notices in the
pull request that caused it, where the fix is one line and the author is
already looking.

So the failure condition is deliberately narrow: the two refs DISAGREE WITH
EACH OTHER. That is unambiguous -- there is no state in which this repository
should read two different catalogs -- and it can only arise from a change
someone made here.

Lagging hvtiR's newest tag is reported as a NOTICE and never fails. Every pull
request would otherwise turn red the moment hvtiR cut a tag, for a reason
having nothing to do with the change under review, which is how a check gets
ignored. That alarm belongs to `jobs-pin-drift`, on a schedule, with a grace
period.

Standard library only -- no pip install step on the runner.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

WORKFLOWS = (
    Path(".github/workflows/R-CMD-check.yaml"),
    Path(".github/workflows/spec-counts.yaml"),
)
REPOSITORY = "ehrlinger/hvtiR"

OK = 0
ERROR = 1
DISAGREE = 2


def extract_pinned_ref(text: str, repository: str = REPOSITORY) -> str | None:
    """The `ref:` of the checkout step naming `repository`, or None.

    Scoped to the same `with:` block: a later unrelated checkout must not
    donate its ref to this one. None means "no pin found", which includes a
    checkout carrying no `ref:` at all -- that takes the default branch, which
    is not a pin and must never compare equal to one.
    """
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.strip() != f"repository: {repository}":
            continue
        indent = len(line) - len(line.lstrip())
        for follow in lines[i + 1:]:
            if not follow.strip():
                continue
            follow_indent = len(follow) - len(follow.lstrip())
            if follow_indent < indent:
                break
            if follow_indent == indent and follow.strip().startswith("ref:"):
                return follow.strip()[len("ref:"):].strip().strip("'\"")
        return None
    return None


def main() -> int:
    found: dict[str, str | None] = {}
    for path in WORKFLOWS:
        if not path.exists():
            # A moved or renamed workflow must be loud. Silently checking one
            # file, or none, is the failure this repo's spec-counts header
            # already warns about: a guard that stops existing goes green.
            print(f"error: {path} does not exist; the pin cannot be checked. "
                  f"If it moved, update WORKFLOWS in {__file__}.",
                  file=sys.stderr)
            return ERROR
        found[str(path)] = extract_pinned_ref(path.read_text())

    missing = [p for p, r in found.items() if r is None]
    if missing:
        print("error: no pinned ref found for "
              f"{REPOSITORY} in: {', '.join(missing)}. A checkout with no "
              "`ref:` takes the default branch, which is not a pin.",
              file=sys.stderr)
        return ERROR

    refs = set(found.values())
    if len(refs) > 1:
        print("The two hvtiR pins disagree, so this repository would validate "
              "against two different job catalogs:")
        for path, ref in sorted(found.items()):
            print(f"  {path}: {ref}")
        print("\nThey are pinned independently and must move together. "
              "Advancing one and forgetting the other is the mistake this "
              "check exists to catch.")
        return DISAGREE

    ref = refs.pop()
    print(f"Both workflows pin {REPOSITORY} at {ref}.")
    return OK


if __name__ == "__main__":
    sys.exit(main())
