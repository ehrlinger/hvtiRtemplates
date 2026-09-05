#!/usr/bin/env python3
"""Generate the roadmap document's tables from the job catalog.

Two views of the catalog, and they no longer share one row list. The family
view is how the work is BATCHED, and stays filtered to the rows this repo
owes -- that is the work a batch actually schedules. The workflow view is
what a study can actually RUN end to end, and a workflow does not stop at
this repo's border: propensity matching spans ten prefixes across five
batches, and one of those ten is owed by hvtiRutilities, not here. Filtering
the workflow view to this repo's rows would hide that member entirely rather
than showing it as outstanding, which defeats the reason the view exists --
to make a cross-cutting workflow's full shape visible early, not just the
slice this repo ships. So the workflow view renders over every row in the
catalog, and marks each row owed elsewhere with the package that owes it.

Writes between `<!-- BEGIN GENERATED -->` and `<!-- END GENERATED -->` in
`2026-08-29-template-conversion-roadmap.md`. Everything outside those markers is
hand-written prose and is never touched.

Run with --check to print the rendered body without writing (used by
check-roadmap-counts.py).

The catalog itself no longer lives here. It moved to the sibling package
`hvtiR` (`inst/extdata/jobs.json`), because `hvtiR` is the package that
installs this whole family and needs to know which job type belongs to
which package. `hvtiRtemplates` must never depend on `hvtiR` -- that would
invert the family -- so the coupling is a file path, resolved by
`catalog_path()` below, never a package import. `check-roadmap-counts.py`
imports this module for the same reason: one resolver, shared, rather than
two copies that can drift.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, os.pardir, os.pardir, os.pardir)
DOC = os.path.join(HERE, os.pardir,
                   "2026-08-29-template-conversion-roadmap.md")

BEGIN = "<!-- BEGIN GENERATED -->"
END = "<!-- END GENERATED -->"


def catalog_path():
    """Find the job catalog, in order: HVTI_JOBS, then a sibling checkout.

    1. The `HVTI_JOBS` environment variable, if set -- for CI, where the
       catalog is checked out somewhere other than a sibling directory.
    2. `../hvtiR/inst/extdata/jobs.json` relative to this repo's root, for a
       developer with a sibling checkout of `hvtiR` next to this repo.
    3. Otherwise, a hard stop naming both options: guessing a third location
       would just move the failure somewhere harder to diagnose.
    """
    env = os.environ.get("HVTI_JOBS")
    if env:
        if os.path.isfile(env):
            return env
        raise SystemExit(
            f"HVTI_JOBS is set to {env!r}, but no file exists there. The job "
            f"catalog moved out of this repo and now lives in ehrlinger/hvtiR, "
            f"at inst/extdata/jobs.json. Either:\n"
            f"  - point HVTI_JOBS at the catalog's real path, or\n"
            f"  - unset HVTI_JOBS and check out hvtiR as a sibling of this "
            f"repo (../hvtiR relative to hvtiRtemplates)."
        )
    sibling = os.path.join(REPO, os.pardir, "hvtiR", "inst", "extdata",
                           "jobs.json")
    if os.path.isfile(sibling):
        return sibling
    raise SystemExit(
        "Could not find the job catalog. It moved out of this repo and now "
        "lives in ehrlinger/hvtiR, at inst/extdata/jobs.json. Either:\n"
        "  - set HVTI_JOBS to the catalog's path, or\n"
        "  - check out hvtiR as a sibling of this repo "
        "(../hvtiR relative to hvtiRtemplates)."
    )


def load_catalog(all_rows=False):
    """Load the catalog and return the rows this repo is responsible for.

    `hvtiR` writes the catalog as `{"jobs": [...]}`; the old local ledger used
    `{"prefixes": [...]}`. Both are accepted so a stray old-shaped file still
    reads, rather than failing on a key name that used to be right.

    The catalog now covers every job type in the family, with a `destination`
    field saying which package owes it. A row destined for another package
    (`hvtiPlotR`, `ggRandomForests`, ...) is not this repo's business, and
    counting it here would read as a template this repo failed to ship. By
    default, only rows destined for `hvtiRtemplates`, or not yet routed
    (`destination` absent or null), are kept -- this is what the family view
    and `check-roadmap-counts.py`'s schema check both need, since a row owed
    elsewhere carries `status: null`, which fails that schema check outright.

    Pass `all_rows=True` to get every row regardless of destination. The
    workflow view needs this: a cross-cutting workflow can include prefixes
    owed by other packages, and hiding them understates what the workflow
    actually needs before a study can run it end to end.
    """
    path = catalog_path()
    with open(path, encoding="utf-8") as fh:
        d = json.load(fh)
    if "jobs" in d:
        rows = d["jobs"]
    elif "prefixes" in d:
        rows = d["prefixes"]
    else:
        raise SystemExit(
            f"{path} has neither a top-level 'jobs' nor 'prefixes' key; "
            f"cannot tell what the row list is called."
        )
    if all_rows:
        return rows
    return [r for r in rows if r.get("destination") in (None, "hvtiRtemplates")]

FAMILY_ORDER = ["hazard-chain", "bootstrap", "bootstrap-ci", "plots", "descriptive",
                "machine-learning", "models", "distributions", "datasets",
                "documents", "unassigned"]

STATUS_MARK = {"shipped": "shipped", "revisit": "**revisit**",
               "in-flight": "*in flight*", "queued": "queued",
               "intake": "*intake*"}


def _label(r):
    """`dp-trends` where a prefix carries several job types, else `dp`.

    Two rows for one prefix render identically without this, which defeats the
    reason for splitting them. See
    dev/specs/2026-09-02-dp-dc-decomposition-design.md.
    """
    # `is not None`, not truthiness: an empty-string qualifier would render as
    # a plain `dp` and hide an invalid row rather than surfacing it.
    q = r.get("qualifier")
    return r["prefix"] + (f"-{q}" if q is not None else "")


def _num(v):
    """A measured zero and an unmeasured field must not render the same."""
    return "—" if v is None else str(v)


def render(rows, workflow_rows=None):
    """`rows` builds the scope line and the family view; `workflow_rows` builds
    the workflow section.

    Defaulting `workflow_rows` to `rows` keeps an existing single-argument
    caller working unchanged -- `check-roadmap-counts.py`'s schema and disk
    checks only ever see the filtered list, and passing just `rows` there
    renders a workflow section scoped to this repo, matching the pre-fix
    behaviour. The document itself is produced by `main()` below, which
    passes the full catalog as `workflow_rows` so the workflow section can
    see across the whole family.
    """
    if workflow_rows is None:
        workflow_rows = rows
    out = [BEGIN, "",
           "> Generated from the job catalog in `hvtiR` "
           "(`inst/extdata/jobs.json`) by",
           "> `artifacts/roadmap_render.py`. Do not hand-edit these tables —",
           "> edit the catalog and re-render. CI checks the agreement.", ""]

    on_disk = [r for r in rows if r["status"] in ("shipped", "revisit", "in-flight")]
    # "templates in scope", not "prefixes": a decomposed prefix contributes one
    # row per job type, so `dp` alone is seven of these. Counting rows and
    # calling them prefixes would overstate the vocabulary.
    out += [f"**{len(rows)} templates in scope**, of which {len(on_disk)} exist "
            f"on disk.",
            ""]

    out += ["## By family", ""]
    for fam in FAMILY_ORDER:
        fam_rows = [r for r in rows if r["family"] == fam]
        if not fam_rows:
            continue
        batches = sorted({r["batch"] for r in fam_rows if r["batch"] is not None})
        label = f"batch {batches[0]}" if len(batches) == 1 else \
                f"batches {batches[0]}–{batches[-1]}" if batches else "unscheduled"
        out += [f"### {fam} ({label})", "",
                # `breadth` and `jobs` are two different measures and get two
                # columns rather than one with a fallback. BOTH are counts of
                # distinct STUDIES, not of files: breadth counts studies having
                # a file of any extension, jobs counts studies having one with
                # a program extension. A decomposed row shows no breadth,
                # because the census emits the all-extension figure per prefix
                # and not per qualifier, and it shows jobs only where the
                # qualifier was measured: the three distributions/dp rows are
                # keyed on measurement scale, which the census does not
                # extract, so they show neither. Neither column may be summed
                # down: one study appears in every row it uses.
                # `template`, not `prefix`: a cell may read `dp-trends`, and
                # a header calling that a prefix contradicts the count above it.
                "| template | status | breadth | jobs | R exemplars | blocked on |",
                "|---|---|---|---|---|---|"]
        for r in sorted(fam_rows, key=lambda r: (r["batch"] is None,
                                                 r["batch"] or 0, _label(r))):
            out.append(f"| `{_label(r)}` | {STATUS_MARK.get(r['status'], r['status'])} | "
                       f"{_num(r['sas_breadth'])} | "
                       f"{_num(r.get('sas_breadth_jobs'))} | "
                       f"{_num(r['r_exemplars'])} | {r['blocked_on'] or '—'} |")
        out.append("")

    out += ["## By workflow", "",
            "A workflow spans the whole family, not just this repo's rows: a member "
            "owed by another package still counts toward the denominator below, and "
            "is marked with the package that owes it. That member is complete when "
            "that package ships the function, which this repo cannot see, so its "
            "`disposition` stands in -- `retire` means the function already exists "
            "in the owning package, `build` means it does not yet.", ""]
    wf = {}
    for r in workflow_rows:
        for w in r["workflows"]:
            wf.setdefault(w, []).append(r)

    def elsewhere(r):
        """A row this repo does not own: any destination other than ours or unrouted."""
        return r.get("destination") not in (None, "hvtiRtemplates")

    def is_done(r):
        # A row owed elsewhere carries `status: null` -- reading it here would be
        # reading a field this repo has no way to keep current. `disposition` is
        # the field that answers "does the function exist", so elsewhere rows are
        # judged on that instead, and `status` is never touched for them.
        if elsewhere(r):
            return r.get("disposition") == "retire"
        return r["status"] in ("shipped", "revisit", "in-flight")

    for name in sorted(wf):
        members = sorted(wf[name], key=_label)
        done = [r for r in members if is_done(r)]
        outstanding = [r for r in members if r not in done]
        here_short = [f"`{_label(r)}`" for r in outstanding if not elsewhere(r)]
        elsewhere_short = [f"`{_label(r)}` ({r.get('destination')})"
                           for r in outstanding if elsewhere(r)]
        member_labels = [f"`{_label(r)}` ({r.get('destination')})" if elsewhere(r)
                         else f"`{_label(r)}`" for r in members]
        if not outstanding:
            status_line = "**Complete.**"
        else:
            clauses = []
            if here_short:
                clauses.append("outstanding here: " + ", ".join(here_short))
            if elsewhere_short:
                clauses.append("owed by another package: " + ", ".join(elsewhere_short))
            # Not `.capitalize()`: it lowercases the rest of the string, and a
            # destination like `hvtiRutilities` would come out `hvtirutilities`.
            joined = "; ".join(clauses)
            status_line = joined[0].upper() + joined[1:] + "."
        out += [f"### {name} — {len(done)}/{len(members)}", "",
                "Members: " + ", ".join(member_labels),
                "",
                status_line,
                ""]

    out.append(END)
    return "\n".join(out)


def splice(text, body):
    if BEGIN not in text:
        raise SystemExit(f"{os.path.basename(DOC)} is missing its {BEGIN!r} "
                         f"marker; cannot splice in the rendered tables. "
                         f"Restore the marker before re-running this script.")
    if END not in text:
        raise SystemExit(f"{os.path.basename(DOC)} is missing its {END!r} "
                         f"marker; cannot splice in the rendered tables. "
                         f"Restore the marker before re-running this script.")
    i, j = text.index(BEGIN), text.index(END) + len(END)
    return text[:i] + body + text[j:]


def main():
    rows = load_catalog()
    # The workflow section needs every row in the catalog, not just this
    # repo's, so a cross-cutting workflow's members owed elsewhere still show
    # up instead of vanishing from the roster. See the module docstring.
    all_rows = load_catalog(all_rows=True)
    body = render(rows, all_rows)
    if "--check" in sys.argv:
        print(body)
        return 0
    with open(DOC, encoding="utf-8") as fh:
        text = fh.read()
    spliced = splice(text, body)
    with open(DOC, "w", encoding="utf-8") as fh:
        fh.write(spliced)
    print(f"rendered {len(rows)} template rows into "
          f"{os.path.basename(os.path.normpath(DOC))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
