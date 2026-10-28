# vp-fit: VarPro: fit

[← The template
gallery](https://ehrlinger.github.io/hvtiRtemplates/gallery/index.md)

# vp-fit: VarPro: fit

Run sheet

## What it does

A VarPro variable screen that says which variables were tested, judges
selection against permuted noise of the same kind, and checks the
selection across subsamples. [See the report it
produces](https://ehrlinger.github.io/hvtiRtemplates/gallery/reports/vp-fit.md)
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
2.  **Study choices**: 12 choices marked `EDIT:`.
3.  **Cohort**: reads the study data.
4.  **Noise**
5.  **Fit**: fits and caches its results, so a later render reloads them
    (`REFIT <- TRUE` recomputes them).
6.  **Coverage**
7.  **Stability**: fits and caches its results, so a later render
    reloads them (`REFIT <- TRUE` recomputes them).
8.  **Reading the result**: saves `vp.rds`, which **vp-explain** and
    **vp-individual** read and **vt-fit** can read.

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

- **vp-explain** reads what this job saves (`vp.rds`). Add it to the
  same set, with this job's `subject` and `type`, because that shared
  pair is how it finds the file:
  `add_job("vp.explain", subject = "<subject>", type = "<type>")`.
- **vp-individual** reads what this job saves (`vp.rds`). Add it to the
  same set, with this job's `subject` and `type`, because that shared
  pair is how it finds the file:
  `add_job("vp.individual", subject = "<subject>", type = "<type>")`.
- **vt-fit** can read what this job saves; its choices marked `EDIT:`
  name the file and its set. Add it with
  `add_job("vt.fit", subject = "<subject>", type = "<type>")`.

Generated from the template by hvtiRtemplates, 1.5.3 · built 2026-10-28.
The template holds the details; this sheet is its outline.
