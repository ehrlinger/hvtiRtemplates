# rhf-explain: Random hazard forest: explain

[← The template
gallery](https://ehrlinger.github.io/hvtiRtemplates/gallery/index.md)

# rhf-explain: Random hazard forest: explain

Run sheet

## What it does

Explains a saved hazard forest: AUC over follow-up, predicted hazard
curves and VarPro importance over time. It never grows a forest. [See
the report it
produces](https://ehrlinger.github.io/hvtiRtemplates/gallery/reports/rhf-explain.md)
on the gallery's synthetic study.

## Prerequisites

- **A study.** The job runs inside a study folder set up with
  `_study.yml`. [Start a new
  study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.html)
  shows how.
- **The job it reads from.** Render **rhf-fit** first, in this same set:
  the same `subject` and `type` as this job, which is how it finds what
  that job saved (`rhf.rds`). For a final render, render it final too: a
  final render refuses a hand-off saved from unregistered data.
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
2.  **Study choices**: 6 choices marked `EDIT:`.
3.  **The forest**: reads what **rhf-fit** saved (`rhf.rds`).
4.  **Discrimination over follow-up**: fits and caches its results, so a
    later render reloads them (`REFIT <- TRUE` recomputes them).
5.  **Hazard curves**
6.  **Importance**: a long fit (the VarPro cache walks every rule of
    every tree at study size) that will not start in an interactive
    session, so the job runs in the background; fits and caches its
    results, so a later render reloads them (`REFIT <- TRUE` recomputes
    them).

## Run it

**Run it in the background.** The fit is long (the VarPro cache walks
every rule of every tree at study size), and a fit run in the console
dies with the session. From a terminal in the study,
`hvti run 30_analyses/rhf.explain.<subject>.<type>.qmd` (`analyses/` in
an older study whose folders carry no number) checks the job, then
renders it in the background on the R the study's `renv.lock` records;
add `--final` for the final render. From R, `run_job(job)` does the
same. `hvti status` follows it and `hvti cancel` stops it. Once the fit
is cached, its chunks run interactively and load it.

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
