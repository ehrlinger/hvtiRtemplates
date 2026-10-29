# hm: Hazard model

[← The template
gallery](https://ehrlinger.github.io/hvtiRtemplates/gallery/index.md)

# hm: Hazard model

Run sheet

## What it does

Multivariable risk-factor model built on the shape parameters the hz job
fitted. [See the report it
produces](https://ehrlinger.github.io/hvtiRtemplates/gallery/reports/hm.md)
on the gallery's synthetic study.

## Prerequisites

- **A study.** The job runs inside a study folder set up with
  `_study.yml`. [Start a new
  study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.html)
  shows how.
- **The job it reads from.** Render **hz** first, in this same set: the
  same `subject` and `type` as this job, which is how it finds what that
  job saved (`hz.rds`). For a final render, render it final too: a final
  render refuses a hand-off saved from unregistered data.
- **Optional: the companion hm selection runner.** It writes
  `hm-selection.rds`. This job reads it when it is there, and runs
  without it otherwise.
- **Packages:** `TemporalHazard`, `hvtiRutilities`, `numDeriv`,
  `hvtiPlotR`. The job checks each floor when it starts, so an older
  library stops it at the top rather than partway through.

## Outline

These are the job's own sections, in order. The detail lives in the
template: the comments at each `EDIT:` marker say what to set and why,
and [Work a
job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change)
shows three ways to find them.

1.  **Above the first section**: 1 choice marked `EDIT:`.
2.  **Study choices**: 4 choices marked `EDIT:`.
3.  **Cohort**: reads what **hz** saved (`hz.rds`).
4.  **Covariates**: 1 choice marked `EDIT:`.
    - **What these columns are, before they become covariates**
5.  **Phases**
6.  **Fitting**
    - **Two stages, and why it is not one**: 2 choices marked `EDIT:`.
7.  **Estimates**
8.  **Selection**: reads `hm-selection.rds`, which the companion hm
    selection runner writes, when it is there.
9.  **Calibration**
10. **Save**: saves `hm.rds`, which **hs-score** and **hs-setup** read
    and **hs-concordance** can read.

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

- **hs-score** reads what this job saves (`hm.rds`). Add it to the same
  set, with this job's `subject` and `type`, because that shared pair is
  how it finds the file:
  `add_job("hs.score", subject = "<subject>", type = "<type>")`.
- **hs-setup** reads what this job saves (`hm.rds`). Add it to the same
  set, with this job's `subject` and `type`, because that shared pair is
  how it finds the file:
  `add_job("hs.setup", subject = "<subject>", type = "<type>")`.
- **hs-concordance** can read what this job saves; its choices marked
  `EDIT:` name the file and its set. Add it with
  `add_job("hs.concordance", subject = "<subject>", type = "<type>")`.

Generated from the template by hvtiRtemplates, 1.5.4 · built 2026-10-29.
The template holds the details; this sheet is its outline.
