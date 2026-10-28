# sid-clusters: SID clustering: clusters

[← The template
gallery](https://ehrlinger.github.io/hvtiRtemplates/gallery/index.md)

# sid-clusters: SID clustering: clusters

Run sheet

## What it does

PAM on a sid-fit dissimilarity over a range of K: metrics for choosing
K, letters stable across K, a Sankey, and the assignments registered for
later jobs to join. [See the report it
produces](https://ehrlinger.github.io/hvtiRtemplates/gallery/reports/sid-clusters.md)
on the gallery's synthetic study.

## Prerequisites

- **A study.** The job runs inside a study folder set up with
  `_study.yml`. [Start a new
  study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.html)
  shows how.
- **The job it reads from.** Render **sid-fit** first, in this same set:
  the same `subject` and `type` as this job, which is how it finds what
  that job saved (`sid.rds`). For a final render, render it final too: a
  final render refuses a hand-off saved from unregistered data.
- **Packages:** `cluster` (\>= 2.1.8), `hvtiPlotR` (\>= 2.8.9),
  `hvtiRutilities`. The job checks each floor when it starts, so an
  older library stops it at the top rather than partway through.

## Outline

These are the job's own sections, in order. The detail lives in the
template: the comments at each `EDIT:` marker say what to set and why,
and [Work a
job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change)
shows three ways to find them.

1.  **Study choices**: 6 choices marked `EDIT:`.
2.  **The dissimilarity**: reads what **sid-fit** saved (`sid.rds`).
3.  **PAM over K**
4.  **Choosing K**
5.  **Letters across K**
6.  **The solution at K**
7.  **Reading the result**
8.  **Save**: saves `sid-clusters.rds`, which **vt-explain** can read.

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

## Where to go next

- **vt-explain** can read what this job saves; its choices marked
  `EDIT:` name the file and its set. Add it with
  `add_job("vt.explain", subject = "<subject>", type = "<type>")`.

Generated from the template by hvtiRtemplates, 1.5.3 · built 2026-10-28.
The template holds the details; this sheet is its outline.
