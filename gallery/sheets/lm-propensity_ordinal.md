# lm-propensity_ordinal: Logistic model: ordinal propensity score

[← The template
gallery](https://ehrlinger.github.io/hvtiRtemplates/gallery/index.md)

# lm-propensity_ordinal: Logistic model: ordinal propensity score

Run sheet

## What it does

Proportional-odds propensity model for an ordered treatment. [See the
report it
produces](https://ehrlinger.github.io/hvtiRtemplates/gallery/reports/lm-propensity_ordinal.md)
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
- **Packages:** `hvtiRpropensity` (\>= 0.2.0), `hvtiRutilities`. The job
  checks each floor when it starts, so an older library stops it at the
  top rather than partway through.

## Outline

These are the job's own sections, in order. The detail lives in the
template: the comments at each `EDIT:` marker say what to set and why,
and [Work a
job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change)
shows three ways to find them.

1.  **The whole job**: 9 choices marked `EDIT:`; reads the study data;
    saves `lm-propensity_ordinal.rds`, which **lm-checkpred** can read.

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

- **lm-checkpred** can read what this job saves; its choices marked
  `EDIT:` name the file and its set. Add it with
  `add_job("lm.checkpred", subject = "<subject>", type = "<type>")`.

Generated from the template by hvtiRtemplates, 1.5.3 · built 2026-10-28.
The template holds the details; this sheet is its outline.
