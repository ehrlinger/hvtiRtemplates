# rhf-fit: Random hazard forest: fit

[← The template
gallery](https://ehrlinger.github.io/hvtiRtemplates/gallery/index.md)

# rhf-fit: Random hazard forest: fit

Run sheet

## What it does

Grows a random hazard forest on counting-process rows with time-varying
predictors: checks the rows, tunes the tree size and saves the forest.
[See the report it
produces](https://ehrlinger.github.io/hvtiRtemplates/gallery/reports/rhf-fit.md)
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
- **Packages:** `randomForestRHF` (\>= 2.1.0), `ggRandomForests` (\>=
  4.0.0), `hvtiRutilities`, `hvtiPlotR` (\>= 2.8.18). The job checks
  each floor when it starts, so an older library stops it at the top
  rather than partway through.
- **The `hvti` command.** A long job starts from a terminal with
  `hvti run`; `install_hvti()` puts the command on your PATH, once.

## Outline

These are the job's own sections, in order. The detail lives in the
template: the comments at each `EDIT:` marker say what to set and why,
and [Work a
job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change)
shows three ways to find them.

1.  **Above the first section**: 1 choice marked `EDIT:`.
2.  **Study choices**: 11 choices marked `EDIT:`.
3.  **Cohort**: reads the study data.
4.  **Cleanup before the fit**
5.  **Forest**: a long fit (a hazard forest on every interval of
    follow-up takes hours at study size) that will not start in an
    interactive session, so the job runs in the background; a long fit
    (the tree-size search grows a forest at each size it tries) that
    will not start in an interactive session, so the job runs in the
    background; fits and caches its results, so a later render reloads
    them (`REFIT <- TRUE` recomputes them).
6.  **Does the forest work?**: saves `rhf.rds`, which **rhf-explain**
    reads.

## Run it

**Run it in the background.** The fit is long (a hazard forest on every
interval of follow-up takes hours at study size), and a fit run in the
console dies with the session. From a terminal in the study,
`hvti run 30_analyses/rhf.fit.<subject>.<type>.qmd` (`analyses/` in an
older study whose folders carry no number) checks the job, then renders
it in the background on the R the study's `renv.lock` records; add
`--final` for the final render. From R, `run_job(job)` does the same.
`hvti status` follows it and `hvti cancel` stops it. Once the fit is
cached, its chunks run interactively and load it.

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

- **rhf-explain** reads what this job saves (`rhf.rds`). Add it to the
  same set, with this job's `subject` and `type`, because that shared
  pair is how it finds the file:
  `add_job("rhf.explain", subject = "<subject>", type = "<type>")`.

Generated from the template by hvtiRtemplates, 1.5.2 · built 2026-10-27.
The template holds the details; this sheet is its outline.
