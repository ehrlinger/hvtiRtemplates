# `dt` folds into `bd`: the checks run inside the build

**Date:** 2026-10-29
**Status:** design, decided by John Ehrlinger on 2026-10-29 after the stat programmer meeting
that day. Implementation follows in its own pull request.
**Supersedes:** section 7 of `2026-10-27-dt-datacheck-design.md` ("Where the checks live"), which
decided that `dt` ships as its own template. Sections 3 to 6 and 8 of that note still describe
the checks themselves, and this note refers to them rather than repeating them.
**Reads with:** `2026-10-02-bd-build-job-design.md`; `inst/templates/00_datasets/bd.qmd` and
`inst/templates/00_datasets/dt.qmd` as they stand at hvtiRtemplates 1.5.4.
**Packages:** hvtiRtemplates only. The helpers the checks call, `proc_print()` (hvtiRutilities
1.5.17) and `compare_built()` (hvtiRdatabuild 0.3.3), are released and unchanged.

This note is self-contained. It assumes no memory of the session that produced it.

⚠️ No study, variable value or patient identifier appears here.

## 1. Why the decision changed

The 2026-10-27 note set a rule: put the checks in `bd` if at least 80% of the legacy SAS `dt`
jobs read nothing but `bd`'s output. The census found 50%, so `dt` shipped separately in 1.5.4.

At the 2026-10-29 stat programmer meeting, two things came up that the census could not see:

- **The stat programmers do not run a separate check job.** Beth checks inside her build, and
  Moses does not use `dt` either.
- **Most of a `dt` job is not used.** John's scan found that about 80% of the template's lines
  are used in no build.

The census measured what the old jobs read, while the meeting reported how the people writing
builds now actually work. The second is what a template has to fit, so the checks move into `bd`.

The meeting also raised ownership: Linda has resisted statisticians editing her build. Folding the
checks in fits that concern. The checks become part of the programmer's own build job, written
by the person who writes the build, and no statistician edits it.

## 2. Decisions

Three decisions, made by John on 2026-10-29:

1. **All four of `dt`'s check sections move into `bd`:** what this rebuild changed, cross-tabs,
   follow-up, and the named checks.
2. **The standalone `dt` template is removed.** It shipped as `in-flight`, which carries no
   support promise, on the morning of the same day.
3. **The checks sit above Register and only report.** No finding blocks registration. (Refined
   the same day after review, in section 4: an error in a check does stop the render, and a
   registering render must match the build a draft reviewed.)
   `REGISTER` stays `FALSE` by default: the author reads the draft's checks, then sets
   `REGISTER <- TRUE` and renders again. That is the SAS loop as the stat programmers run it now.

## 3. The layout of `bd.qmd`

```
setup -> Study choices -> check-choices -> read-master
Cohort:   cohort -> derive -> write-built
Checks:   rebuild -> crosstabs -> followup -> tbl-checks      (new)
Register -> Report -> about-run
```

- **Study choices** gains `dt`'s `CROSSTABS`, `EVENT`, `FOLLOWUP`, `CHECKS` and `PRINT_COLS`,
  each under its `EDIT:` marker and carrying the comment it had in `dt`. `bd` already has `ID`,
  `KEY` and `DATASET_ID`, which `dt` copied from it, so the checks take `bd`'s own.
- **The checks read the data frame in memory.** `write-built` has just written it, so nothing
  reads the `.rds` back, and `dt`'s `read-working` chunk and its "bd has not written the working
  file" stop are both dropped.
- **What this rebuild changed** compares the cut against the version registered now, joined on
  `KEY` through `hvtiRdatabuild::compare_built()`, as `dt` does. On a study's first build nothing
  is registered, and the section says so and compares nothing. A comparison build, one whose
  `DATASET_ID` is not the study's dataset, is compared against the study's dataset and the
  report says so, as `dt` does.
- **`check-choices`** validates the new choices with the stops `dt` used, each naming its step
  and the file and never a data value.
- **`setup`** gains `dt`'s version floors: hvtiRutilities 1.5.17 for `proc_print()` and
  hvtiRdatabuild 0.3.3 for `compare_built()`.

## 4. Contract

- **The report holds counts only.** The rows behind a named check, and the patients on one side
  of a rebuild, go to the console through `proc_print()` on `stderr()`, which knitr does not
  capture. That fits `bd` as it is: its report already shows no code, because its `EXCLUDE` rules
  may name patients.
- **A check never writes,** and no finding changes what Register does.
- **Cross-tab levels are values, so a cross-tab column is screened.** A cross-tab prints its
  levels in the report. `check-choices` refuses a `CROSSTABS` column that is `ID`, a column of
  `KEY` or a column of `JOIN_BY`. The `crosstabs` chunk takes a column only if it reads as a category, an
  allow-list: logical, factor, whole numbers or text; at most 20 distinct non-missing values; not a different value
  on every row once there are more than five; and no text that reads as a date. Every stop names the column and
  never a value. The screen is what keeps "counts only" true; the comment above
  `CROSSTABS` says so.
- **A finding never blocks registration; an error does.** A finding is a count: rows matching a
  check, a column that differs, a suspicious follow-up interval. A check that cannot run (a column
  it names is missing, a condition does not evaluate, the comparison fails) is a broken job, and it
  stops the render with `.bd_stop()`, as a bad `EXCLUDE` rule does. A build whose checks did not
  run is never registered.
- **The build registered is the build reviewed.** A render with `REGISTER <- FALSE` writes
  `datasets/<DATASET_ID>.reviewed.yml` beside the working file, holding the `built_sha256` of the
  bytes it wrote. A render with `REGISTER <- TRUE` re-cuts the master, and before registering it
  compares its bytes' hash with that file. If they differ, or no draft has been rendered, it stops
  in `register` before registering anything and says to render with `REGISTER <- FALSE` and review
  that build. A registering render never writes `.reviewed.yml`, so repeating it cannot approve
  bytes nobody reviewed. This closes the gap where a changed snapshot (with `VERIFY_MASTER <-
  FALSE`), a changed cohort list or a nondeterministic derivation registers data the author never
  saw. Like the build record, `.reviewed.yml` holds no key and no data value.
- **A changed `KEY` is a finding.** When the version registered now lacks a column of `KEY`, as when a study
  moves to repeated measures, the rebuild section says the key changed and compares nothing, as on a first build,
  and registration proceeds. Any other failure of the comparison still stops the render. (John, 2026-10-29, after
  the branch's final review.)
- **A partial render never reviews and never registers.** A `skip` or `stop_here()` above `register` would leave
  checks unrun, so a partial draft writes no `.reviewed.yml` and a partial registering render stops.
- `bd` stays `in-flight`. The stat programmers' line-by-line review, still open, now covers the
  Checks section too, so the checks reach review with the rest of the build rather than after it.

## 5. Removing `dt`

In the implementation pull request:

- delete `inst/templates/00_datasets/dt.qmd`;
- remove its row in `inst/extdata/templates.json`, its `.lintr` key, its gallery job in
  `dev/gallery/family-00-datasets.R`, and its entry in `inst/templates/README.md`;
- move its tests to `bd`: `helper-dt.R`, `test-dt-template.R` and `test-dt-e2e.R` become `bd`
  tests. Every privacy guard comes across and is proved again by mutation: rows on `stderr()` and
  not stdout, no row in the rendered HTML, a condition's warning or message muffled out of the
  report;
- **keep `dt`'s row in `hvti_taxonomy()`.** `job_census()` still counts the legacy SAS `dt` jobs,
  as the `dp` row stayed for the jobs named `dp.*`;
- leave `dt`'s texts in `inst/extdata/template-history.rds`; they are history, and nothing reads
  them once the template is gone;
- add one news fragment saying that `dt` is folded into `bd` and that a job scaffolded from the
  1.5.4 `dt` should move its choices into the study's `bd` job.

`dt` is not listed under `renamed` in `templates.json`. An alias would scaffold a `bd` job when
someone asks for `dt`, and `dt` and `bd` are not the same job.

## 6. The cost, accepted

Changing a check means re-rendering the build, so the master is read and the cohort cut again.
`skip` and `stop_here()` leave out chunks below a point, never above it, so the read cannot be
skipped. A check-only re-render with `VERIFY <- FALSE` avoids rehashing the snapshot, which is
the expensive part on a large master. If timing on the real master shows that is not enough,
revisit it then, with numbers.

## 7. Testing, at implementation

- The `dt` tests, ported as section 5 says, run against `bd`'s chunks.
- One end-to-end `bd` render on a synthetic master: the Checks section appears above Register,
  the report holds counts and no row, and a first build says nothing is registered.
- The gallery's `bd` job sets the choices the `dt` job set (`ID <- "patient_id"`, cross-tab of
  `dead` by `female`), and `gallery_missing()` no longer expects a `dt` job.
- `check-roadmap-counts.py` passes with the `dt` row gone from the ledger.

## 8. Review of this design, 2026-10-29

John's review of PR #454 raised four findings, each settled by John the same day:

1. Cross-tab levels reach the report, so "counts only" did not hold for an identifying or
   free-text column. Settled by the screen in section 4. `dt` as released in 1.5.4 had the same gap.
2. The second render re-cuts the master, so the registered bytes were not bound to the reviewed
   ones. Settled by `.reviewed.yml` in section 4.
3. A check error stopped the render, against the wording "blocks nothing". Settled by keeping the
   stop and saying so: errors stop, findings never.
4. Removing the catalog row left the generated roadmap stale and `check-roadmap-counts.py` red.
   Settled in the plan: Task 3 regenerates the roadmap with `roadmap_render.py`.

The branch's final review then found that a cross-tab of a date column, a `skip` on a check chunk and a changed
`KEY` each broke a promise above. The first two are closed by the screen and the partial-render rule; the third
was settled by John as a finding, not an error.

A `/code-review` of the branch found two more ways through the screen, a second identifier in a small cohort and a
date stored as text. John chose an allow-list over a longer block-list (2026-10-29): a block-list had been passed
twice, and an allow-list refuses whatever it has not named. A date stored as SAS day numbers, with ties and at most
20 values, still reads as whole numbers; that gap is accepted and named here.

## 9. Open

1. Whether `bd` should also take a second input to compare against, such as an earlier dated
   release or a `vars` output. This was open item 1 of the 2026-10-27 note, and it carries over.

## 10. Out of scope

The meeting's other items: the `dc-eda` variable list, folding `gfup` into the EDA, composite
uniqueness keys, and the render errors. The SAS workflow is being retired and stays as it is.
