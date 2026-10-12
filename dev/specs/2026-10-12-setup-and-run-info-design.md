# One setup chunk, and what every report says about its run: design, 2026-10-12

**Status** Design, decided with the maintainer on 2026-10-12. Not implemented.
**Scope** All 34 shipped templates, plus new internals in `R/`. It ships in 1.3.1.

## 1. The problem

**Every template opens with four chunks before its study choices:** `setup`,
`guard-edits`, `guard-partial` and `set`. A rendered report therefore starts with
four "Code" folds before it says anything.
- `guard-edits` is about 30 lines copied verbatim into all 34 templates, so a
  change to it is 34 edits.
- `set` carries about 20 lines that check the file name and build `set_path()`.

**A report says little about the run that produced it.**
- The provenance JSON embedded in every report records the data versions and
  lineage, but a reader cannot see it.
- `tbl-data` shows the rows read, but not when the dataset was registered, nor
  whether a newer file is waiting.
- Nothing visible says when the report was rendered, whether it is final, which
  template produced it or who ran it.

## 2. Decisions

1. **One setup chunk.** The four chunks become one, labeled `setup`, that calls an
   internal `.job_setup()`. It is kept separate from other changes so the report
   shows one "Code" fold.
2. **Run information appears twice.**
   - A one-line box under the title, so a reader sees at a glance what the
     numbers come from.
   - A full "About this run" table at the end of the report.
3. **Included:** the run, the job, the dataset, upstream lineage, the seed and
   renv, and **who rendered it and on which machine**.
   - The maintainer chose to include user and host, knowing they identify a
     person and that reports are shared.
   - Package versions are not shown. hvtiRtemplates' own version is: it is part
     of the job.
4. **Both changes ship together.** Both rewrite the top of all 34 templates.

## 3. The setup chunk

```r
#| label: setup
#| results: asis
SUBJECT <- "cohort"
TYPE    <- "eda"
suppressPackageStartupMessages(library(hvtiRutilities))
.job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE, envir = environment())
.root <- .job$root
set_path <- .job$set_path
.provenance_data <- list()
```

**What stays in the template, and why:**
- the `SUBJECT` and `TYPE` lines, which `add_job()` rewrites, so they must stay
  exactly one `^SUBJECT\s+<- ` and one `^TYPE\s+<- ` line;
- `library()`, because a package function should not attach packages;
- the assignments from `.job`, so an author can see where `.root` and `set_path`
  come from.

**`.job_setup(subject, type, envir)` does what the four chunks did, in their
order:**
1. Finds the study root from `knitr::current_input()`, or the working directory.
2. Sources the study's `R/*.R` into `envir`, which is the only place it writes.
3. Runs the edit-marker guard: the DRAFT callout in a draft, a stop in a final
   render.
4. Runs `.guard_partial()`.
5. Checks the file name against `SUBJECT` and `TYPE`.
6. Starts the run record: the start time, and the run facts known at the top.
7. Prints the top box (section 4).
8. Returns `list(root, set_path, run)`.

The edit-marker guard moves into the package as `.guard_edits()`, unchanged in
behavior and messages.

**Jobs already in studies keep their four chunks and keep working.** Every
internal they call (`.find_study_root`, `.guard_partial`, `.job_name_fields`)
stays.

**Tests** that run the `set` chunk by name (about 81 references) are served by
one change to the test helpers, which maps `set` to `setup`. They are not edited
one by one.

## 4. Run information

**The top box** is one line, as a callout under the title:

> Rendered 2026-10-12 14:03 by jdoe on host · **final** · data `built`
> `built_20261009.parquet`, registered 2026-10-09 · hvtiRtemplates 1.3.1

In a draft, it reads **draft** and gives the count of open markers and skipped
chunks, so it points at the DRAFT banner the guard already prints.

**The end table, "About this run",** is drawn in the existing `provenance`
chunk, before the JSON is embedded:

| group | fields |
|---|---|
| Run | render start and end (time zone stated), duration, final or draft (open markers, skipped chunks), user, host |
| Job | job file name, template (prefix and qualifier from the name), subject and type, hvtiRtemplates version |
| Dataset, for each dataset read | registered name, dated version file, registration (extract) date, source file, rows and patients read, the `WHERE` filter, the short sha256 (12 characters), manifest status (current, or a newer file waiting) |
| Upstream | for each handoff read (`hp`, `hm`, `hs-*`, `lp-mirror`, `lm-checkpred`, `bh`...): the job it came from, when that job rendered, and its dataset version |
| Reproducibility | the seed, when the job sets `SEED`; renv: active or not, and the sha256 of `renv.lock` (12 characters) when there is one |

- **Every value comes from what the job already records:** `read_job_data()`'s
  record, the manifest entry (`extract_date`, `parquet`), the handoff lineage and
  `.provenance_data`. The new values are the start time, the duration, user,
  host, the seed and renv.
- **The same facts go into the embedded provenance JSON,** under `run`, so they
  are machine-readable too.
- **No patient identifier and no data value appears.** The table holds names,
  dates, counts and hashes.

## 5. Placement in the report

- The box is printed by the setup chunk, so it sits right under the title.
- The table is the last section, headed "About this run", unnumbered, so it does
  not shift any template's figure or table numbering. A test checks the
  numbering is unchanged.

## 6. Tests

All fixtures synthetic. Each test fails with its code reverted.

1. **Equivalence.** `.job_setup()` matches the old four chunks:
   - the same root;
   - the study's `R/` sourced into `envir`;
   - the DRAFT callout and the strict stop for open markers;
   - the partial-render list;
   - a name mismatch stops with the same message;
   - `set_path()` creates `<kind>/<subject>-<type>/`.
2. **Template contract.** Every template has exactly one chunk before "Study
   choices", labeled `setup`, and exactly one `SUBJECT` and one `TYPE` line;
   `add_job()` still substitutes them.
3. **Top box.** It shows the render date, final or draft, the dataset version and
   registration date, and the hvtiRtemplates version.
4. **End table.** It holds every field in the table, for a plain job and for a
   downstream job with an upstream handoff.
5. **renv and seed.** Present when set, absent otherwise. The renv hash is the
   lockfile's.
6. **No identifiers.** The rendered report carries no fixture identifier, using
   the scan `lp-mirror` uses (drop `data:` URIs, whole tokens).
7. **Old jobs.** A job with the old four-chunk header still renders.

## 7. Not in this design

- package versions;
- recording who scaffolded a job, or with which hvtiRtemplates version;
- changing what the provenance JSON already holds, beyond adding `run`.
