# nb-boostmtree_explain: Boosting: boostmtree explain

[← The template
gallery](https://ehrlinger.github.io/hvtiRtemplates/gallery/index.md)

# nb-boostmtree_explain: Boosting: boostmtree explain

Run sheet

## What it does

Explains a saved boostmtree fit: importance pooled over repeated runs
against shadow covariates, partial effects over time and patient
trajectories. It never fits. [See the report it
produces](https://ehrlinger.github.io/hvtiRtemplates/gallery/reports/nb-boostmtree_explain.md)
on the gallery's synthetic study.

## Prerequisites

- **A study.** The job runs inside a study folder set up with
  `_study.yml`. [Start a new
  study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.html)
  shows how.
- **The job it reads from.** Render **nb-boostmtree_fit** first, in this
  same set: the same `subject` and `type` as this job, which is how it
  finds what that job saved (`nb-boostmtree_fit.rds`). For a final
  render, render it final too: a final render refuses a hand-off saved
  from unregistered data.
- **Packages:** `boostmtree` (\>= 2.0.13), `ggBoostedTrees` (\>=
  0.10.2), `hvtiRutilities`. The job checks each floor when it starts,
  so an older library stops it at the top rather than partway through.
- **A background run.** A long job starts from the study's R console
  with `hvtiRtemplates::run_job()`, which checks it first and renders it
  in a process that outlives the session.

## Outline

These are the job's own sections, in order. The detail lives in the
template: the comments at each `EDIT:` marker say what to set and why,
and [Work a
job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change)
shows three ways to find them.

1.  **Above the first section**: 1 choice marked `EDIT:`.
2.  **Study choices**: 5 choices marked `EDIT:`.
3.  **The fit**: reads what **nb-boostmtree_fit** saved
    (`nb-boostmtree_fit.rds`).
4.  **Importance**: a long fit (repeated boostmtree importance takes
    hours at study size) that will not start in an interactive session,
    from the Render button or from a terminal, so the job runs in the
    background; checks the fit's memory need against this session's
    limit before it starts; fits and caches its results, so a later
    render reloads them (`REFIT <- TRUE` recomputes them).
5.  **Partial effects**: a long fit (the partial effects predict over
    every patient at each grid value) that will not start in an
    interactive session, from the Render button or from a terminal, so
    the job runs in the background; checks the fit's memory need against
    this session's limit before it starts; fits and caches its results,
    so a later render reloads them (`REFIT <- TRUE` recomputes them).
6.  **Trajectories**

## Run it

**Run it in the background.** The fit is long (repeated boostmtree
importance takes hours at study size), and a fit run chunk by chunk dies
with the session. From the study's R console,
`hvtiRtemplates::run_job("30_analyses/nb.boostmtree_explain.<subject>.<type>.qmd")`
(`analyses/` in an older study whose folders carry no number) checks the
job, then renders it in a background process that outlives the session;
add `final = TRUE` for the final render. `hvtiRtemplates::job_status()`
and `hvtiRtemplates::cancel_job()`, given the same path, follow it and
stop it. Once the fit is cached, its chunks run interactively and load
it.

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

Generated from the template by hvtiRtemplates, 1.6.3 · built 2026-11-25.
The template holds the details; this sheet is its outline.
