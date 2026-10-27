# bd: Build

[← The template
gallery](https://ehrlinger.github.io/hvtiRtemplates/gallery/index.md)

# bd: Build

Run sheet

## What it does

Cuts a study's dataset from a master snapshot: cohort list, exclusions
with attrition and derived variables, then the working file and its
build record, registered as a dated version of the study dataset. [See
the report it
produces](https://ehrlinger.github.io/hvtiRtemplates/gallery/reports/bd.md)
on the gallery's synthetic study.

## Prerequisites

- **A study.** The job runs inside a study folder set up with
  `_study.yml`. [Start a new
  study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.html)
  shows how.
- **No dataset to read.** This job builds the study dataset rather than
  reading one; the choices marked `EDIT:` say what it starts from.
- **Packages:** `hvtiRutilities` (\>= 1.5.12). The job checks each floor
  when it starts, so an older library stops it at the top rather than
  partway through.

## Outline

These are the job's own sections, in order. The detail lives in the
template: the comments at each `EDIT:` marker say what to set and why,
and [Work a
job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change)
shows three ways to find them.

1.  **Above the first section**: 1 choice marked `EDIT:`.
2.  **Study choices**: 5 choices marked `EDIT:`.
3.  **Cohort**: 1 choice marked `EDIT:`.
4.  **Register**
5.  **Report**
    - **Who was excluded, and why**
    - **Columns**

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

Generated from the template by hvtiRtemplates, 1.5.2 · built 2026-10-27.
The template holds the details; this sheet is its outline.
