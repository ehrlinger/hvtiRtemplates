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

Two conditions, and the second was added after review
----------------------------------------------------
1. Each ref must be an IMMUTABLE TAG in this family's `vX.Y.Z` form.
2. The two refs must agree with each other.

Checking only (2) was the first version of this file, and it passed states it
exists to forbid. `ref: main` in BOTH workflows agrees with itself, and so
does an empty `ref:` -- and both resolve to mutable, default-branch behaviour,
which is exactly the isolation the pin exists to provide. Equality is not
pinning: two workflows can agree perfectly on something that is not a pin.

⚠️ An empty `ref:` is the sharp edge. A checkout with NO `ref:` line yields
None and was always rejected, but `ref:` with nothing after it yields `""`,
which is not None and slid through the None check while this docstring claimed
otherwise. Shape validation closes both, and does not rely on the difference.

A commit SHA is immutable and is still rejected: `jobs-pin-drift` in `hvtiR`
compares these refs against its newest TAG NAME, so a SHA pin would read as
permanently stale there. One family, one pin format.

So the failure condition is deliberately narrow: the refs are not tag-shaped,
or they DISAGREE WITH EACH OTHER. That is unambiguous -- there is no state in which this repository
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

# The family's tag format. Straight three digits, no dev suffix and no fourth
# digit, matching the versioning rule every repo here follows.
TAG_RE = re.compile(r"^v\d+\.\d+\.\d+$")

OK = 0
ERROR = 1
DISAGREE = 2
NOT_A_PIN = 3


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

    # Shape before equality. Two workflows can agree perfectly on a value that
    # is not a pin at all -- `ref: main` in both, or an empty `ref:` in both --
    # and an equality-only check calls that success.
    unpinned = {p: r for p, r in found.items() if not TAG_RE.match(r)}
    if unpinned:
        print("These are not immutable tag pins, so the catalog they resolve "
              "to can change without any commit here:")
        for path, ref in sorted(unpinned.items()):
            shown = repr(ref) if ref.strip() == "" else f"`{ref}`"
            print(f"  {path}: {shown}")
        print(f"\nEach must be a tag in this family's `vX.Y.Z` form. A branch "
              f"name tracks whatever lands on it; an empty `ref:` takes the "
              f"default branch. A commit SHA is immutable but still wrong "
              f"here: hvtiR's `jobs-pin-drift` compares these against its "
              f"newest TAG NAME, so a SHA reads as permanently stale.")
        return NOT_A_PIN

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
