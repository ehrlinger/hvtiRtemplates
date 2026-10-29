# bl: Bootstrap logistic

[← The template
gallery](https://ehrlinger.github.io/hvtiRtemplates/gallery/index.md)

# bl: Bootstrap logistic

Run sheet

## What it does

Bootstrap variable-selection screen over a logistic model. [See the
report it
produces](https://ehrlinger.github.io/hvtiRtemplates/gallery/reports/bl.md)
on the gallery's synthetic study.

## Prerequisites

- **A study.** The job runs inside a study folder set up with
  `_study.yml`. [Start a new
  study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.html)
  shows how.
- **The study's data.** Its choices name the registered dataset it
  reads. A draft can read a build that is not registered yet, so you can
  start before the build is final, and the report then says it is a
  draft. A final render reads registered data only: register the build
  with `hvtiRutilities::update_manifest()` first.
- **Its bootstrap runner, run first.** The screen runs in a companion
  script, `bl.<subject>.<type>.runner.R`, which `add_job()` writes
  beside the job. This job reports on what the runner saved.
- **Packages:** `hvtiRbootstrap` (\>= 0.9.3), `hvtiRutilities`,
  `ggplot2`. The job checks each floor when it starts, so an older
  library stops it at the top rather than partway through.

## Outline

These are the job's own sections, in order. The detail lives in the
template: the comments at each `EDIT:` marker say what to set and why,
and [Work a
job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change)
shows three ways to find them.

1.  **Above the first section**: 1 choice marked `EDIT:`.
2.  **Study choices**: 5 choices marked `EDIT:`.
3.  **The screen**
    - **The runner**: reads what the bootstrap runner saved.
4.  **Provenance**
5.  **Candidates that were never screened**
6.  **Did the screen actually run?**
7.  **What a selection frequency is, and what it is not**
8.  **Concepts**: 1 choice marked `EDIT:`.
9.  **Correlation clusters**: 2 choices marked `EDIT:`; reads the study
    data.
10. **Figure**
11. **Save**

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
