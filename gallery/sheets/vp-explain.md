# vp-explain: VarPro: explain

[← The template
gallery](https://ehrlinger.github.io/hvtiRtemplates/gallery/index.md)

# vp-explain: VarPro: explain

Run sheet

## What it does

VarPro partial dependence for the variables a vp-fit screen selected. It
never fits varPro. [See the report it
produces](https://ehrlinger.github.io/hvtiRtemplates/gallery/reports/vp-explain.md)
on the gallery's synthetic study.

## Prerequisites

- **A study.** The job runs inside a study folder set up with
  `_study.yml`. [Start a new
  study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.html)
  shows how.
- **The job it reads from.** Render **vp-fit** first, in this same set:
  the same `subject` and `type` as this job, which is how it finds what
  that job saved (`vp.rds`). For a final render, render it final too: a
  final render refuses a hand-off saved from unregistered data.
- **Packages:** `varPro` (\>= 3.2.0), `ggRandomForests` (\>= 4.0.0),
  `hvtiRutilities`, `randomForestSRC` (\>= 3.7.0). The job checks each
  floor when it starts, so an older library stops it at the top rather
  than partway through.

## Outline

These are the job's own sections, in order. The detail lives in the
template: the comments at each `EDIT:` marker say what to set and why,
and [Work a
job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change)
shows three ways to find them.

1.  **Above the first section**: 1 choice marked `EDIT:`.
2.  **Study choices**: 4 choices marked `EDIT:`.
3.  **The screen**: reads what **vp-fit** saved (`vp.rds`).
4.  **Dependence**: fits and caches its results, so a later render
    reloads them (`REFIT <- TRUE` recomputes them).

## Run it

**Render a draft as you go.** `render_job(job)` runs the whole job in a
clean R session and writes the report beside it. Render early and often:
while any `EDIT:` marker is left, the report opens with a DRAFT banner
listing them, and its numbers are not a result. [Work a
job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#render-as-you-go)
explains why to render rather than run chunks by hand.

**Then the final.** Once no marker is left,
`render_job(job, final = TRUE)` renders the accepted result. It refuses
an open marker, a skipped chunk, `stop_here()` and unregistered data,
and it records the job's provenance beside the report.

Generated from the template by hvtiRtemplates, 1.5.3 · built 2026-10-28.
The template holds the details; this sheet is its outline.
