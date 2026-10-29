# dc-stddiff: Descriptive: standardized differences

[← The template
gallery](https://ehrlinger.github.io/hvtiRtemplates/gallery/index.md)

# dc-stddiff: Descriptive: standardized differences

Run sheet

## What it does

The balance table: the standardized difference of each baseline variable
between two groups, unadjusted and, when the study has them, in the
matched set and under matching weights, with an optional permutation
reference. [See the report it
produces](https://ehrlinger.github.io/hvtiRtemplates/gallery/reports/dc-stddiff.md)
on the gallery's synthetic study.

## Prerequisites

- **A study.** The job runs inside a study folder set up with
  `_study.yml`. [Start a new
  study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.html)
  shows how.
- **The study's data.** `DATASET` names the registered dataset it reads
  (`"built"` unless you change it). A draft can read a build that is not
  registered yet, so you can start before the build is final, and the
  report then says it is a draft. A final render reads registered data
  only: register the build with `hvtiRutilities::update_manifest()`
  first.
- **Packages:** `hvtiRutilities`, `hvtiRpropensity` (\>= 0.2.0),
  `hvtiPlotR` (\>= 2.8.0), `ggplot2`. The job checks each floor when it
  starts, so an older library stops it at the top rather than partway
  through.

## Outline

These are the job's own sections, in order. The detail lives in the
template: the comments at each `EDIT:` marker say what to set and why,
and [Work a
job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change)
shows three ways to find them.

1.  **Above the first section**: 1 choice marked `EDIT:`.
2.  **Study choices**: 12 choices marked `EDIT:`.
3.  **Data**: reads the study data.
4.  **Groups compared**
5.  **Standardized differences**
6.  **Balance figure**
7.  **Permutation reference**

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

Generated from the template by hvtiRtemplates, 1.5.4 · built 2026-10-29.
The template holds the details; this sheet is its outline.
