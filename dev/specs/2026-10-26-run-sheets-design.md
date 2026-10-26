# Run sheets: a "before you run" panel for every template

**Date:** 2026-10-26
**Status:** designed, approved in conversation 2026-10-26.
**Reads with:** `2026-10-22-run-job-design.md` (`hvti run`, `run_job()`, `guard_memory()`), the
working-read gate of PR #421 (a draft may read an unregistered build, a final render may not).
**Packages:** hvtiRtemplates only.

## 1. Why

On 2026-10-23 John asked for run books: guidance that ships with the templates and tells an analyst
how to run a job. That session proposed two layers. Layer 1 shipped in PR #407: every gallery row
links its `add_job()` call to the "Work a job" vignette ("Then run it"). Layer 2 was deferred until
the working-read gate settled. It is a short sheet per template that says what *this* template needs
before it runs.

The hand-written runbook for one study, `dev/TemporalHazard_runbook.md`, shows what goes wrong. Every
warning in it is real, and it described one study's jobs on one date. A sheet written by hand for each
of 44 templates would drift the same way. So the sheet is **generated from the template**, and a test
fails when the two disagree.

## 2. What a sheet says

A sheet has up to five lines. Choices, packages and run are always there; data and fit appear when
the template reads data or fits something. The wording below is for `rfs-fit`, and section 3 lists the
variants.

> **Before you run `rfs-fit`**
>
> - **10 choices to make.** Each is an `EDIT:` marker. The job renders as a draft until all of them are
>   worked. ▸ *(the first line of each marker, as the DRAFT banner shows it)*
> - **Packages:** randomForestSRC ≥ 3.7.0, ggRandomForests ≥ 4.0.0, hvtiPlotR ≥ 2.8.18, hvtiRutilities.
> - **Data:** a registered dataset (`DATASET`, `"built"` by default) or an analysis set. A draft may
>   read an unregistered build and is marked as a draft. A final render needs the build registered first,
>   with `hvtiRutilities::update_manifest()`.
> - **Fit:** cached by `cache_fit()`, so the next render reloads it. `REFIT` recomputes it.
> - **Run it:** `render_job(job)` for a draft, `render_job(job, final = TRUE)` for the final.

The gallery's render time is **not** on the sheet. It is already on the row, and a render on 800
synthetic rows says little about how long a fit on a real cohort takes.

## 3. Where each line comes from

| Line | Source in the template | Variants |
|---|---|---|
| Choices | the lines carrying the `EDIT:` token, found by `.edit_marker_lines()`. `.guard_edits()` uses the same helper, so the sheet and the DRAFT banner cannot disagree | none |
| Packages | `.template_packages()`, already used by `add_job()` and the preflight checks | a package with no floor is listed bare |
| Data | a literal top-level `DATASET <-` assignment | **`.read_handoff(path, role, cfg, rebuild)`**: "Reads a hand-off (*role*) from *rebuild*. Render that first, in this set; a final render refuses one saved from unregistered data." **`.read_bootstrap_artifact()`**: "Reads what its companion bootstrap runner writes; run the runner first." **`.job_setup(..., box_data = FALSE)`**, the template's own statement that it reads no registered dataset: "Builds the study dataset rather than reading one." `DATASET <- NULL` with no other read: no dataset line |
| Fit | `cache_fit()`, `guard_long_fit(why = )` and `guard_memory()` calls | no `cache_fit()`: no fit line. **guard**: "Refuses to start in an interactive session: *why*. Run it in the background." **memory**: "Checks the fit's memory against this session's limit before it starts." |
| Run it | whether `guard_long_fit()` is called | guarded: `hvti run <folder>/<job>.qmd`, or `run_job(job)` from R, with `--final` / `final = TRUE` for the final |

The `rebuild` text is quoted as the template wrote it ("the ac job", "the companion hm selection
runner"). It is free text, so the sheet does not try to resolve it to a template name.

A call is read only from **literal** arguments. When `why`, `role` or `rebuild` is not a string
literal, the sheet uses a generic phrase ("another job's hand-off") instead of guessing.

The rf templates gain `guard_long_fit()` on the confidence-bands branch. Their sheets switch to the
background command with no change here, because the sheet reads the guard rather than keeping a list
of which templates are long.

## 4. Architecture

```
inst/templates/*.qmd ──► R/run-sheet.R (internal, new)
                           .run_sheet(file)        the facts: markers, packages, data, fit
                           .run_sheet_lines(sheet) the wording; the only place it lives
                           .run_sheets(dir)        every template → named list
                                │
dev/gallery/gallery.R ──────────┘  writes <study>/run-sheets.json beside gallery-build.csv,
                                │  from the INSTALLED templates, the same ones it rendered
dev/gallery/package.py ─────────┘  attaches each sheet to its row in gallery-data.js and exits
                                   when a template on disk has none
dev/gallery/index.html             <details> "Before you run" under "Then run it"
```

- **Parsing.** Each R chunk of the `.qmd` (between a ```` ```{r ```` fence and the next ```` ``` ````)
  goes through `parse()`. A recursive walk then visits every call, including function bodies and
  default arguments: `vt-fit` reads its sid hand-off in a default argument. A function name matches
  bare, as `pkg::fn` or as `pkg:::fn`. Comments never reach the parser, so a commented-out call
  states nothing.
- **The marker helper is shared.** The `EDIT:` token (built, never written literally) and the 96-character
  cut move out of `.guard_edits()` into `.edit_marker_lines(src)`, and both call it. This is the
  one change to existing code, and its purpose is to keep the count from drifting.
- **The JSON carries the finished lines and the marker list.** The page's JavaScript only escapes text
  and turns backticks into `<code>`. All the wording stays in R, where testthat can see it.
- **Gallery only.** No new export, and no change to the vignette or the catalog. The sheet is built by
  an internal function, so adding a console `run_sheet()` later is a small step if one is wanted.

## 5. Testing

In `tests/testthat/test-run-sheet.R`:

1. **Every template on disk** produces a sheet with no error, and the sheet always has its choices,
   packages and run lines; the data and fit lines appear only when section 3 says so. This also
   catches a chunk the parser cannot read.
2. **It agrees with the existing readers.** The sheet's packages are `identical()` to
   `.template_packages(f)`. Its marker count equals a plain count of lines carrying the token.
3. **The parse walk agrees with a text scan, on the real templates.** Wherever a template's uncommented
   text contains `.read_handoff(`, `.read_bootstrap_artifact(`, `cache_fit(`, `guard_long_fit(` or
   `guard_memory(`, the sheet must report that fact. A walker that loses a call form fails on a
   shipped template.
4. **Fixture templates written to a temporary file**, one for each variant: a hand-off read in a default
   argument, a `:::` call, a `rebuild` that is not a literal, a guard with `why`, `box_data = FALSE` and
   `DATASET <- NULL`. Each fixture's wording is pinned with `expect_snapshot()`. Snapshots use fixtures,
   never real templates, so editing a template does not churn them.
5. **Mutation proof.** With the walker cut back to top-level calls, tests 3 and 4 must fail. The result
   is recorded in the pull request.
6. **The existing `.guard_edits()` tests stay green** once the marker helper is shared.
7. **The round trip.** `.run_sheets()` through `jsonlite` gives each template's `lines` and `markers`,
   which is the shape `package.py` reads.

`package.py` has no CI tests, so it fails loudly instead when a template has no sheet.

## 6. Rollout

Nothing here renders a job. The site shows the sheets only after the gallery is rebuilt on lri, against
an installed hvtiRtemplates that carries `.run_sheets()`:

```sh
Rscript dev/gallery/gallery.R <study>
python3 dev/gallery/package.py <study> pkgdown/assets/gallery
bash dev/gallery/publish.sh
```

Then rerun `pkgdown.yaml`. That is the release-day gallery rebuild AGENTS.md already prescribes, so it
needs no new step.
