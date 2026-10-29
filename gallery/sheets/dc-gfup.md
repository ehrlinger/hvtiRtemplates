# dc-gfup: Descriptive: follow-up

[← The template
gallery](https://ehrlinger.github.io/hvtiRtemplates/gallery/index.md)

# dc-gfup: Descriptive: follow-up

Run sheet

## What it does

Checks follow-up before any time-related analysis: counts for the
cohort, the event and censored subsets, and the missing, negative and
zero intervals, then the goodness-of-follow-up figure, each patient's
follow-up against operation year under the diagonal the close date
allows. [See the report it
produces](https://ehrlinger.github.io/hvtiRtemplates/gallery/reports/dc-gfup.md)
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
- **Packages:** `hvtiRutilities` (\>= 1.4.5), `hvtiPlotR` (\>= 2.8.18),
  `ggplot2`. The job checks each floor when it starts, so an older
  library stops it at the top rather than partway through.

## Outline

These are the job's own sections, in order. The detail lives in the
template: the comments at each `EDIT:` marker say what to set and why,
and [Work a
job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change)
shows three ways to find them.

1.  **Above the first section**: 1 choice marked `EDIT:`.
2.  **Study choices**: 16 choices marked `EDIT:`.
3.  **Data**: reads the study data.
4.  **Follow-up checks**
5.  **Operation years and the close date**
6.  **Potential follow-up**
7.  **Goodness of follow-up**
8.  **Event-coding consistency**

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
