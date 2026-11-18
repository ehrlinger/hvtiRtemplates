# ar: Analysis report

[← The template
gallery](https://ehrlinger.github.io/hvtiRtemplates/gallery/index.md)

# ar: Analysis report

Run sheet

## What it does

One research question answered from finished jobs: numbered figures,
tables and values, each with Methods, Results and Interpretation for the
researchers to choose from. [See the report it
produces](https://ehrlinger.github.io/hvtiRtemplates/gallery/reports/ar.md)
on the gallery's synthetic study.

## Prerequisites

- **A study.** The job runs inside a study folder set up with
  `_study.yml`. [Start a new
  study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.html)
  shows how.
- **Packages:** `hvtiRutilities`. The job checks each floor when it
  starts, so an older library stops it at the top rather than partway
  through.

## Outline

These are the job's own sections, in order. The detail lives in the
template: the comments at each `EDIT:` marker say what to set and why,
and [Work a
job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change)
shows three ways to find them.

1.  **Question**: 1 choice marked `EDIT:`.
2.  **Item 1: Survival from the parametric fit**: 3 choices marked
    `EDIT:`.
3.  **Item 2: Parameter estimates**: 3 choices marked `EDIT:`.
4.  **About this run**

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

Generated from the template by hvtiRtemplates, 1.6.1 · built 2026-11-18.
The template holds the details; this sheet is its outline.
