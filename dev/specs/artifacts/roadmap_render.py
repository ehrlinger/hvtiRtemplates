#!/usr/bin/env python3
"""Generate the roadmap document's tables from the ledger.

Two views of the same 45 rows. The family view is how the work is BATCHED; the
workflow view is what a study can actually RUN end to end. Family batching
amortises the design spec across a family, but it delivers a cross-cutting
workflow piecemeal -- propensity matching spans ten prefixes across five
batches -- so the second view exists to make that visible early rather than at
batch eight.

Writes between `<!-- BEGIN GENERATED -->` and `<!-- END GENERATED -->` in
`2026-08-29-template-conversion-roadmap.md`. Everything outside those markers is
hand-written prose and is never touched.

Run with --check to print the rendered body without writing (used by
check-roadmap-counts.py).
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LEDGER = os.path.join(HERE, "2026-08-29-template-roadmap.json")
DOC = os.path.join(HERE, os.pardir,
                   "2026-08-29-template-conversion-roadmap.md")

BEGIN = "<!-- BEGIN GENERATED -->"
END = "<!-- END GENERATED -->"

FAMILY_ORDER = ["hazard-chain", "bootstrap", "bootstrap-ci", "plots", "descriptive",
                "machine-learning", "models", "distributions", "datasets",
                "documents", "unassigned"]

STATUS_MARK = {"shipped": "shipped", "revisit": "**revisit**",
               "in-flight": "*in flight*", "queued": "queued",
               "intake": "*intake*", "out-of-scope": "~~umbrella~~"}


def _label(r):
    """`dp-trends` where a prefix carries several job types, else `dp`.

    Two rows for one prefix render identically without this, which defeats the
    reason for splitting them. See
    dev/specs/2026-09-02-dp-dc-decomposition-design.md.
    """
    return r["prefix"] + (f"-{r['qualifier']}" if r.get("qualifier") else "")


def _num(v):
    """A measured zero and an unmeasured field must not render the same."""
    return "—" if v is None else str(v)


def render(rows):
    out = [BEGIN, "",
           "> Generated from `artifacts/2026-08-29-template-roadmap.json` by",
           "> `artifacts/roadmap_render.py`. Do not hand-edit these tables —",
           "> edit the ledger and re-render. CI checks the agreement.", ""]

    live = [r for r in rows if r["status"] != "out-of-scope"]
    on_disk = [r for r in live if r["status"] in ("shipped", "revisit", "in-flight")]
    out += [f"**{len(live)} prefixes in scope**, of which {len(on_disk)} have a "
            f"template on disk. {len(rows) - len(live)} demoted to umbrella rows.",
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
                "| prefix | status | ordinal | breadth | R exemplars | blocked on |",
                "|---|---|---|---|---|---|"]
        for r in sorted(fam_rows, key=lambda r: (r["batch"] is None,
                                                 r["batch"] or 0, _label(r))):
            out.append(f"| `{_label(r)}` | {STATUS_MARK.get(r['status'], r['status'])} | "
                       f"{r['ordinal'] or '—'} | {_num(r['sas_breadth'])} | "
                       f"{_num(r['r_exemplars'])} | {r['blocked_on'] or '—'} |")
        out.append("")

    out += ["## By workflow", "",
            "A workflow is complete when every prefix in it is on disk.", ""]
    wf = {}
    for r in rows:
        for w in r["workflows"]:
            wf.setdefault(w, []).append(r)
    for name in sorted(wf):
        members = sorted(wf[name], key=_label)
        done = [r for r in members
                if r["status"] in ("shipped", "revisit", "in-flight")]
        short = [_label(r) for r in members if r not in done]
        out += [f"### {name} — {len(done)}/{len(members)}", "",
                "Members: " + ", ".join(f"`{_label(r)}`" for r in members),
                "",
                ("**Complete.**" if not short else
                 "Outstanding: " + ", ".join(f"`{p}`" for p in short) + "."),
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
    with open(LEDGER, encoding="utf-8") as fh:
        rows = json.load(fh)["prefixes"]
    body = render(rows)
    if "--check" in sys.argv:
        print(body)
        return 0
    with open(DOC, encoding="utf-8") as fh:
        text = fh.read()
    spliced = splice(text, body)
    with open(DOC, "w", encoding="utf-8") as fh:
        fh.write(spliced)
    print(f"rendered {len(rows)} prefixes into "
          f"{os.path.basename(os.path.normpath(DOC))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
