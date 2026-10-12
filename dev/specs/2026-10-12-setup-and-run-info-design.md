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
2. **The render date goes in the YAML title metadata,** and the rest of the run
   information appears twice.
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

**The render date goes in the YAML header,** added to every template's own
front matter:

```yaml
date: now
date-format: "YYYY-MM-DD HH:mm"
```

Quarto evaluates `now` at render, so the date appears in the standard title block
with no code. (This design first said it also lands in the HTML `dcterms.date`
meta tag; Quarto 1.10.18 puts it in the title block only, measured while building
it.) Templates carry their own `format:` block by rule, so the
two lines go in each template, not a shared `_quarto.yml`. Jobs already in
studies do not gain them, and gain neither the box nor the end table: an old
four-chunk header never calls `.job_setup()`, so it starts no run record, and its
provenance carries no `run`. (This design first promised those jobs the end table.
Its compatibility test already expects none.)

**The top box** is one line, as a callout under the title. It holds what Quarto
cannot know:

> **final** · data `built` `built_20261009.parquet`, registered 2026-10-09 ·
> rendered by jdoe on host · hvtiRtemplates 1.3.1

In a draft, it reads **draft** and gives the count of open markers and skipped
chunks, so it points at the DRAFT banner the guard already prints.

- **The box names data only when it can be resolved with certainty.** The box is
  printed before the data are read, so it reads the job's own file: a literal
  `ANALYSIS_SET <- "x"` names the analysis set (and the time it was written, when
  its sidecar says), else a literal `DATASET <- "x"` or `'x'` names the dataset
  (and its version file and registration date, when the manifest has them). If the
  value is `NULL`, inherited from an upstream handoff, computed or not declared, the
  box says "data: see About this run" and never guesses the study dataset, `built`.
  The end table is the record of what was read. `bd`, which builds a dataset and
  reads none, leaves the data clause out.
- **The box cannot take back "final".** It is printed first, and a report can turn
  out to be a draft after that: a `stop_here()` that the source scan could not see
  and that runs, a scale not chosen in `lg`, an incomplete bootstrap pool, a figure
  not drawn. Each calls one internal hook, `.run_mark_draft(reason)`. The run facts
  are reconciled when they are emitted: status `draft`, `stopped_early` for a stop,
  and `draft_reasons`; the end table's status reads draft and a callout above the
  table, "This run ended as a draft", names each reason. A final render (strict)
  still refuses a runtime `stop_here()`, so a final report cannot be truncated by
  one.

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
- **The upstream render time is recorded, never inferred.** A handoff bundle's
  lineage holds no producer timestamp of its own, and a file's modification time
  changes on a copy or a touch. So a job that saves a bundle records `rendered_at`
  in the bundle's lineage, the start of its own render from the run record, as ISO
  8601 with a time zone. The end table shows it, or "not recorded" for a bundle
  saved before this change. The file's modification time is never used.
- **The same facts go into the embedded provenance JSON,** under `run`, so they
  are machine-readable too.
- **No patient identifier and no data value appears.** The table holds names,
  dates, counts and hashes.
- **User and host can be overridden** with the environment variables
  `HVTI_RUN_USER` and `HVTI_RUN_HOST`, read before `Sys.info()`; an empty value
  is ignored. The gallery build sets both to `gallery`, because the gallery is
  published and must not carry a real username. Environment variables, not an
  option, because Quarto renders in a child process.

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
3. **Date and top box.** Every template's YAML has `date: now` and a `date-format`,
   and the rendered title block shows the date. The box shows final or draft, the
   dataset version and registration date, user and host, and the hvtiRtemplates
   version.
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
