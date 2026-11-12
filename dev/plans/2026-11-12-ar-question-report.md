# `ar` analysis report: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `ar` template: one research question, answered by numbered items drawn from finished jobs, each with Methods, Results and Interpretation slots the researchers choose from.

**Architecture:** Jobs record each citable figure, table or value by chunk label, with its file and sha256, plus a boilerplate Methods paragraph, in their provenance sidecar. The `ar` job reads those sidecars through `ar_item()` and `ar_value()` and re-runs nothing. Two console helpers, `ar_paste_methods()` and `ar_review()`, write the analyst-owned text and the review stamps into the `ar` file.

**Tech Stack:** R (>= 4.4.0), Quarto, knitr, testthat edition 3, digest, jsonlite, openssl (all already in Imports), hvtiRutilities (>= 1.5.20).

**Spec:** `dev/specs/2026-11-11-ar-question-report-design.md`. Read it before starting.

## Global Constraints

- Roxygen is **Rd markup, not markdown**: `\code{}`, `\strong{}`, `\emph{}`, `\itemize{}`, `\link{}`. Every export has `@return` and a runnable or `\donttest{}` example.
- Lines up to **135** characters (`.lintr`). Every other default linter is on.
- **No study identifiers** in templates, tests or fixtures. Synthetic data only.
- `devtools::document()` after any roxygen change; commit `man/` and `NAMESPACE` with the source.
- A pull request adds **`news/<branch>.md`** (branch `/` replaced by `-`) with its bullets and no heading. It does **not** touch `Version:` or `NEWS.md`.
- Never `git add -A`: failing testthat runs write `tests/testthat/_problems/`. Add files by name.
- A new template is `"status": "in-flight"` in `inst/extdata/templates.json` and has its **own file key** in `.lintr`.
- Every study-specific line in a template carries `EDIT:`. Boilerplate the template owns carries none, since an open marker makes every job of that template a draft.
- Prove each new branch by mutation: revert the code line, confirm the test goes red, restore.
- Local test runs: `_R_CHECK_LIMIT_CORES_=TRUE Rscript -e 'devtools::test(filter = "<name>")'`. Render tests install into a private library first (`R CMD INSTALL -l <lib> .`, then `R_LIBS=<lib>`), because concurrent sessions overwrite the shared install.

## Decisions this plan takes that the spec left open

These are written down so John can overturn them before Task 3:

1. **Spec 9.1:** `ar_item()`, `ar_value()`, `ar_paste_methods()` and `ar_review()` are all **exported**. `ar_item()` and `ar_value()` are called from study jobs, as `life_table()` is from `ac`.
2. **Spec 3, the item reference:** the item is named by the **chunk call** `ar_item("<job>#<label>")`, not by a heading attribute `{item=...}`. knitr cannot read a heading's attributes, and a chunk is needed anyway to show the exhibit. One `ar_item()` call opens each item; everything up to the next call belongs to it.
3. **Spec 9.3:** the pilot templates are **`ac` and `hz`**, the two in scope that nearly every survival question uses. Change them when the first two study questions are chosen.
4. **The published sidecar drops `.hvti_render_id` and `.hvti_source_sha256`** (`R/provenance.R`, `.provenance_post_render_locked()`). So this plan adds a public **`source_sha256`**, and the review stamp keys on the sidecar's **`rendered`** time plus the exhibit's digest, not on the render id the spec names.

## File map

| file | responsibility |
|---|---|
| `R/exhibits.R` (new) | `.record_exhibit()`, `.save_exhibit()`, `.methods_text()`, `.ar_extra()`: what a job records |
| `R/job-setup.R` | reset the exhibit state per run |
| `R/provenance.R` | add `.ar_extra()` to the payload `.embed_provenance()` builds |
| `inst/templates/20_distributions/hz.qmd`, `ac.qmd` | pilot exhibits and the `methods` chunk |
| `R/ar-resolve.R` (new) | `.ar_parse_id()`, `.ar_find_job()`, `.ar_read_sidecar()`, `.ar_resolve()`, `.ar_methods()`: from an item id to verified evidence |
| `R/ar-file.R` (new) | `.ar_parse()`, stamps, `ar_paste_methods()`, `ar_review()`: reading and writing the `ar` file |
| `R/ar-item.R` (new) | `ar_item()`, `ar_value()`, callouts and exhibit markdown: what a render shows |
| `inst/templates/50_documents/ar.qmd` (new) | the template |
| `tests/testthat/helper-ar.R` (new) | a synthetic study with a fake finished job, no render needed |
| `tests/testthat/test-exhibits.R`, `test-ar-resolve.R`, `test-ar-file.R`, `test-ar-item.R`, `test-ar-template.R` (new) | one per unit |

---

### Task 1: Jobs record exhibits and a Methods paragraph in their sidecar

**Files:**
- Create: `R/exhibits.R`
- Modify: `R/job-setup.R` (the reset block after `.run_state$identifiability <- NULL`)
- Modify: `R/provenance.R` (`.embed_provenance()`, after the check that forbids `source` and the `.hvti_*` names in `extra`)
- Create: `tests/testthat/helper-ar.R`
- Create: `tests/testthat/test-exhibits.R`

**Interfaces:**
- Produces:
  - `.record_exhibit(file, kind = c("figure", "table", "value"), label = knitr::opts_current$get("label"), root = .run_state$root)`. Returns the record invisibly, or `NULL` invisibly when `file` does not exist.
  - `.save_exhibit(x, kind = c("table", "value"), file, label = knitr::opts_current$get("label"))`. Writes `x` with `saveRDS()`, then records it.
  - `.methods_text(text)`. Records `list(text, sha256)` in `.run_state$methods`.
  - `.ar_extra(source_sha256)`. Returns `list(source_sha256, exhibits = <unnamed list of records>, methods)`, with `NULL` entries dropped.
  - An exhibit record is `list(label = chr, kind = chr, file = <path relative to study root, "/">, sha256 = chr)`.
  - The published sidecar gains top-level `source_sha256`, `exhibits` and `methods`.

- [ ] **Step 1: Write the test helper**

`tests/testthat/helper-ar.R`:

```r
# A fresh exhibit state for one test: what .job_setup() would leave, pointed at
# a temporary study root. Restores the package's run state afterwards.
local_exhibit_state <- function(root = withr::local_tempdir(.local_envir = env), env = parent.frame()) {
  state <- hvtiRtemplates:::.run_state
  saved <- mget(intersect(c("root", "exhibits", "methods"), ls(state, all.names = TRUE)), envir = state)
  assign("root", normalizePath(root, winslash = "/"), envir = state)
  assign("exhibits", list(), envir = state)
  assign("methods", NULL, envir = state)
  withr::defer({
    rm(list = intersect(c("root", "exhibits", "methods"), ls(state, all.names = TRUE)), envir = state)
    list2env(saved, envir = state)
  }, envir = env)
  invisible(get("root", envir = state))
}
```

- [ ] **Step 2: Write the failing tests**

`tests/testthat/test-exhibits.R`:

```r
# Exhibits: what a job offers an ar analysis report, recorded by chunk label
# with its file and digest. dev/specs/2026-11-11-ar-question-report-design.md, section 4.

test_that("an exhibit is recorded by label, kind, study-relative file and digest", {
  root <- local_exhibit_state()
  dir.create(file.path(root, "graphs", "dead-hz"), recursive = TRUE)
  png <- file.path(root, "graphs", "dead-hz", "hz-fit.png")
  writeBin(as.raw(1:10), png)
  rec <- hvtiRtemplates:::.record_exhibit(png, "figure", label = "fig-fit")
  expect_identical(rec$file, "graphs/dead-hz/hz-fit.png")
  expect_identical(rec$sha256, digest::digest(png, algo = "sha256", file = TRUE))
  expect_named(hvtiRtemplates:::.run_state$exhibits, "fig-fit")
})

test_that("a file that was not written records nothing", {
  root <- local_exhibit_state()
  expect_null(hvtiRtemplates:::.record_exhibit(file.path(root, "absent.png"), "figure", label = "fig-x"))
  expect_length(hvtiRtemplates:::.run_state$exhibits, 0L)
})

test_that("a label is required, well formed and used once", {
  root <- local_exhibit_state()
  f <- file.path(root, "a.png")
  writeBin(as.raw(1), f)
  expect_error(hvtiRtemplates:::.record_exhibit(f, "figure", label = NULL), "chunk label")
  expect_error(hvtiRtemplates:::.record_exhibit(f, "figure", label = "has space"), "chunk label")
  hvtiRtemplates:::.record_exhibit(f, "figure", label = "fig-a")
  expect_error(hvtiRtemplates:::.record_exhibit(f, "figure", label = "fig-a"), "twice")
})

test_that("an exhibit outside the study is refused", {
  local_exhibit_state()
  outside <- withr::local_tempfile(fileext = ".png")
  writeBin(as.raw(1), outside)
  expect_error(hvtiRtemplates:::.record_exhibit(outside, "figure", label = "fig-o"), "outside the study")
})

test_that("a table is a data frame and a value is a named list", {
  root <- local_exhibit_state()
  f <- file.path(root, "t.rds")
  expect_error(hvtiRtemplates:::.save_exhibit(matrix(1), "table", f, label = "tbl-m"), "data frame")
  expect_error(hvtiRtemplates:::.save_exhibit(list(1, 2), "value", f, label = "v"), "named list")
  hvtiRtemplates:::.save_exhibit(data.frame(a = 1), "table", f, label = "tbl-a")
  expect_identical(readRDS(f), data.frame(a = 1))
  expect_identical(hvtiRtemplates:::.run_state$exhibits[["tbl-a"]]$kind, "table")
})

test_that("the Methods paragraph is recorded with its digest", {
  local_exhibit_state()
  hvtiRtemplates:::.methods_text("Survival was estimated.")
  m <- hvtiRtemplates:::.run_state$methods
  expect_identical(m$text, "Survival was estimated.")
  expect_identical(m$sha256, digest::digest("Survival was estimated.", algo = "sha256", serialize = FALSE))
  expect_error(hvtiRtemplates:::.methods_text(""), "Methods paragraph")
})

test_that("the sidecar extra carries an unnamed exhibit array and drops what is empty", {
  root <- local_exhibit_state()
  expect_identical(hvtiRtemplates:::.ar_extra("abc"), list(source_sha256 = "abc"))
  f <- file.path(root, "a.png")
  writeBin(as.raw(1), f)
  hvtiRtemplates:::.record_exhibit(f, "figure", label = "fig-a")
  x <- hvtiRtemplates:::.ar_extra("abc")
  expect_null(names(x$exhibits))
  expect_identical(x$exhibits[[1]]$label, "fig-a")
})
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `Rscript -e 'devtools::test(filter = "exhibits")'`
Expected: FAIL, `object '.record_exhibit' not found`.

- [ ] **Step 4: Write `R/exhibits.R`**

```r
# Exhibits: the figures, tables and values a job offers to an `ar` analysis
# report, each recorded by its chunk label with its file and a digest, and the
# job's boilerplate Methods paragraph. .embed_provenance() writes both into the
# job's sidecar through .ar_extra(). The design is
# dev/specs/2026-11-11-ar-question-report-design.md, sections 4 and 5.

.exhibit_label_ok <- function(label) {
  is.character(label) && length(label) == 1L && !is.na(label) && grepl("^[A-Za-z0-9_-]+$", label)
}

.exhibit_relative <- function(file, root) {
  file <- normalizePath(file, winslash = "/", mustWork = TRUE)
  prefix <- paste0(normalizePath(root, winslash = "/", mustWork = TRUE), "/")
  if (!startsWith(file, prefix)) stop("Exhibit '", file, "' is outside the study.", call. = FALSE)
  substring(file, nchar(prefix) + 1L)
}

# A file the job did not write, a figure with SAVE_FIGURES off say, records
# nothing: the ar report then stops on the missing label and names it.
.record_exhibit <- function(file, kind = c("figure", "table", "value"), label = knitr::opts_current$get("label"),
                            root = .run_state$root) {
  kind <- match.arg(kind)
  if (!.exhibit_label_ok(label)) {
    stop("An exhibit needs a chunk label of letters, digits, '-' or '_'; got ",
         if (is.null(label)) "none" else encodeString(as.character(label)[1L], quote = "\""), ".", call. = FALSE)
  }
  if (is.null(root)) stop("An exhibit can be recorded only after the job's setup chunk has run.", call. = FALSE)
  if (!file.exists(file)) return(invisible(NULL))
  if (label %in% names(.run_state$exhibits)) {
    stop("Exhibit label '", label, "' is recorded twice in this run; give each exhibit its own label.", call. = FALSE)
  }
  rec <- list(label = label, kind = kind, file = .exhibit_relative(file, root),
              sha256 = digest::digest(file, algo = "sha256", file = TRUE))
  .run_state$exhibits[[label]] <- rec
  invisible(rec)
}

# Tables are saved unformatted, as data frames: the publication phase formats
# the ones researchers choose, and the report shows them as plain tables.
.save_exhibit <- function(x, kind = c("table", "value"), file, label = knitr::opts_current$get("label")) {
  kind <- match.arg(kind)
  if (identical(kind, "table") && !is.data.frame(x)) {
    stop("A table exhibit must be a data frame; format it in the report, not in the saved object.", call. = FALSE)
  }
  if (identical(kind, "value") && (!is.list(x) || is.null(names(x)) || any(!nzchar(names(x))))) {
    stop("A value exhibit must be a named list, so ar_value() can name a field.", call. = FALSE)
  }
  saveRDS(x, file)
  .record_exhibit(file, kind, label)
}

.methods_text <- function(text) {
  if (!is.character(text) || length(text) != 1L || is.na(text) || !nzchar(trimws(text))) {
    stop("A Methods paragraph must be one non-empty string.", call. = FALSE)
  }
  .run_state$methods <- list(text = text, sha256 = digest::digest(text, algo = "sha256", serialize = FALSE))
  invisible(text)
}

.ar_extra <- function(source_sha256) {
  exhibits <- .run_state$exhibits
  Filter(Negate(is.null), list(
    source_sha256 = source_sha256,
    exhibits = if (length(exhibits)) unname(exhibits),
    methods = .run_state$methods
  ))
}
```

- [ ] **Step 5: Reset the state per run in `R/job-setup.R`**

After the line `.run_state$identifiability <- NULL`, add:

```r
  # What this run offers an ar report, recorded as its chunks save it.
  .run_state$exhibits <- list()
  .run_state$methods <- NULL
  .run_state$root <- root
```

- [ ] **Step 6: Write it into the payload in `R/provenance.R`**

In `.embed_provenance()`, directly after the `stop("Template provenance extras may not replace the source or render identity.", ...)` check, add:

```r
  if (any(c("source_sha256", "exhibits", "methods") %in% names(extra))) {
    stop("Template provenance extras may not set source_sha256, exhibits or methods; .embed_provenance() records them.",
         call. = FALSE)
  }
  # Public, unlike .hvti_source_sha256, which post-render strips: an ar report
  # compares it with the job file to tell that the job was edited since.
  extra <- c(extra, .ar_extra(state$source_sha256[[source]]))
```

- [ ] **Step 7: Run the tests and confirm they pass**

Run: `Rscript -e 'devtools::test(filter = "exhibits|provenance|job-setup")'`
Expected: PASS, and no new failures in the provenance tests.

- [ ] **Step 8: Prove by mutation.** Delete the `if (label %in% names(.run_state$exhibits))` block, run `filter = "exhibits"`, confirm "used once" fails, then restore it.

- [ ] **Step 9: Commit**

```bash
git add R/exhibits.R R/job-setup.R R/provenance.R tests/testthat/helper-ar.R tests/testthat/test-exhibits.R
git commit -m "Jobs record exhibits and a Methods paragraph in their sidecar"
```

---

### Task 2: Pilot exhibits and boilerplate in `hz` and `ac`

**Files:**
- Modify: `inst/templates/20_distributions/hz.qmd` (chunks `tbl-estimates` and `fig-fit`, and a new `methods` chunk between `save` and `provenance`)
- Modify: `inst/templates/20_distributions/ac.qmd` (chunks `tbl-horizons` and `fig-km-survival`, and a new `methods` chunk directly before `provenance`)
- Modify: `tests/testthat/test-ac-template.R`
- Create: `tests/testthat/test-ar-pilot.R`

**Interfaces:**
- Consumes: `.record_exhibit()`, `.save_exhibit()` and `.methods_text()` from Task 1.
- Produces, for an `hz` job: exhibits `tbl-estimates` (table), `fig-fit` (figure) and `methods` (value: `n`, `events`, `phases`). For an `ac` job: `tbl-horizons` (table), `fig-km-survival` (figure) and `methods` (value: `n`, `events`).

- [ ] **Step 1: Write the failing `hz` test**

`tests/testthat/test-ar-pilot.R`:

```r
# The pilot templates for the ar report record their exhibits and their Methods
# paragraph. dev/specs/2026-11-11-ar-question-report-design.md, section 5.3.

test_that("hz records its estimates, its fit figure and its Methods paragraph", {
  skip_on_cran()
  skip_if_not_installed("TemporalHazard")
  env <- hz_fit_run()
  utils::capture.output(suppressWarnings(hazard_run(
    "hz", c("tbl-conservation-binding", "edit-estimates", "tbl-estimates", "estimates-warning", "fig-fit", "save",
            "methods"),
    env
  )))
  ex <- hvtiRtemplates:::.run_state$exhibits
  expect_setequal(names(ex), c("tbl-estimates", "fig-fit", "methods"))
  expect_identical(ex[["fig-fit"]]$kind, "figure")
  v <- readRDS(file.path(env$.root, ex[["methods"]]$file))
  expect_identical(v$n, nrow(env$resp))
  m <- hvtiRtemplates:::.run_state$methods$text
  expect_match(m, "multiphase hazard")
  expect_match(m, paste0(" ", nrow(env$resp), " patients"))
  expect_false(grepl("EDIT:", m))
})
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `Rscript -e 'devtools::test(filter = "ar-pilot")'`
Expected: FAIL, `chunk 'methods' found 0 times`.

- [ ] **Step 3: Edit `hz.qmd`**

In `tbl-estimates`, replace `knitr::kable(est, digits = 6)` with:

```r
# Saved as a data frame for an ar analysis report; the report formats it.
hvtiRtemplates:::.save_exhibit(as.data.frame(est), "table", set_path("documents", "tbl-estimates.rds"))
knitr::kable(est, digits = 6)
```

In `fig-fit`, directly after `save_figure(.fig, "hz-fit")`, add:

```r
hvtiRtemplates:::.record_exhibit(set_path("graphs", "hz-fit.png"), "figure")
```

After the `save` chunk's closing fence, before the `provenance` chunk, insert:

````markdown
```{r}
#| label: methods
# The paragraph an ar analysis report pastes into its Methods slot, filled from
# this job's own choices. A report whose pasted copy no longer matches it says so.
# Reword it here when the template's method changes, not in each study.
.n <- nrow(resp)
.events <- if ("status" %in% names(resp)) sum(resp$status == 1L, na.rm = TRUE) else NA_integer_
hvtiRtemplates:::.save_exhibit(list(n = .n, events = .events, phases = length(phases)), "value",
                               set_path("estimates", "hz-methods.rds"))
hvtiRtemplates:::.methods_text(sprintf(
  paste("The hazard of the event recorded in %s was modeled as a parametric multiphase hazard with %d phase%s",
        "(TemporalHazard %s), fitted by maximum likelihood to %d patients%s."),
  EVENT, length(phases), if (length(phases) == 1L) "" else "s",
  as.character(utils::packageVersion("TemporalHazard")), .n,
  if (is.na(.events)) "" else sprintf(" with %d events", .events)
))
```
````

- [ ] **Step 4: Run the `hz` test and confirm it passes**

Run: `Rscript -e 'devtools::test(filter = "ar-pilot")'`
Expected: PASS.

- [ ] **Step 5: Write the failing `ac` test**

Append to `tests/testthat/test-ac-template.R`, inside the `# nolint start` / `# nolint end` block that its helpers already use:

```r
test_that("ac records its horizons table, its survival figure and its Methods paragraph", {
  skip_ac()
  env <- ac_run(ac_data(), labels = c(ac_chunks, "methods"))
  ex <- hvtiRtemplates:::.run_state$exhibits
  expect_true(all(c("tbl-horizons", "fig-km-survival", "methods") %in% names(ex)))
  expect_s3_class(readRDS(file.path(env$.root, ex[["tbl-horizons"]]$file)), "data.frame")
  expect_match(hvtiRtemplates:::.run_state$methods$text, "Kaplan-Meier")
})
```

- [ ] **Step 6: Run it and confirm it fails**

Run: `Rscript -e 'devtools::test(filter = "ac-template")'`
Expected: FAIL, `chunk 'methods' found 0 times`.

- [ ] **Step 7: Edit `ac.qmd`**

Replace the body of `tbl-horizons` (the `knitr::kable(as_percent(...))` call) with:

```r
.horizons <- as_percent(hvtiRtemplates::life_table_at(d, TIME, EVENT, times = grid, labels = labs,
                                                      conf_level = CLEVEL))
# Saved as a data frame for an ar analysis report; the report formats it.
hvtiRtemplates:::.save_exhibit(as.data.frame(.horizons), "table", set_path("documents", "tbl-horizons.rds"))
knitr::kable(.horizons, row.names = FALSE, digits = 4)
```

In `fig-km-survival`, directly after `save_figure(.fig, "ac-survival", width = 6, height = 5)`, add:

```r
hvtiRtemplates:::.record_exhibit(set_path("graphs", "ac-survival.png"), "figure")
```

Directly before the `provenance` chunk, insert:

````markdown
```{r}
#| label: methods
# The paragraph an ar analysis report pastes into its Methods slot, filled from
# this job's own choices. A report whose pasted copy no longer matches it says so.
# Reword it here when the template's method changes, not in each study.
.n <- nrow(d)
.events <- sum(d[[EVENT]] == 1L, na.rm = TRUE)
hvtiRtemplates:::.save_exhibit(list(n = .n, events = .events), "value", set_path("estimates", "ac-methods.rds"))
hvtiRtemplates:::.methods_text(sprintf(
  "Survival was estimated by the Kaplan-Meier method, with %s%% confidence limits, from %d patients with %d events.",
  format(round(100 * CLEVEL, 1)), .n, .events
))
```
````

- [ ] **Step 8: Run both templates' full test files**

Run: `Rscript -e 'devtools::test(filter = "ac-template|ar-pilot|hz|hazard")'`
Expected: PASS. If a test asserts a template's chunk list or line count, update it to include `methods`; do not loosen it.

- [ ] **Step 9: Prove by mutation.** Remove the `.record_exhibit()` line from `fig-fit`, confirm the `hz` test fails on `setequal`, then restore it.

- [ ] **Step 10: Commit**

```bash
git add inst/templates/20_distributions/hz.qmd inst/templates/20_distributions/ac.qmd \
  tests/testthat/test-ar-pilot.R tests/testthat/test-ac-template.R
git commit -m "hz and ac record exhibits and a Methods paragraph for ar reports"
```

---

### Task 3: From an item id to verified evidence

**Files:**
- Create: `R/ar-resolve.R`
- Modify: `tests/testthat/helper-ar.R`
- Create: `tests/testthat/test-ar-resolve.R`

**Interfaces:**
- Consumes: the sidecar fields from Task 1 (`exhibits`, `methods`, `source_sha256`) and the existing ones (`run$status`, `run$open_markers`, `run$skipped_chunks`, `run$stopped_early`, `run$draft_reasons`, `rendered`, `r$version`, `packages`, `data`).
- Produces:
  - `.ar_parse_id(id)` → `list(id, job, label)`.
  - `.ar_resolve(id, root)` → `list(id, job, label, qmd, html, sidecar, exhibit, path, source_changed)`. It stops on every stop case in spec 6.2.
  - `.ar_methods(r)` → `list(text, sha256, floor)` for a resolved item `r`.

- [ ] **Step 1: Add a fake finished job to the helper**

Append to `tests/testthat/helper-ar.R`:

```r
# A study holding one finished job, written by hand instead of rendered, so the
# ar helpers can be tested in milliseconds. `run` and `methods` override the
# sidecar's; `exhibits` names what the job saved.
ar_fake_study <- function(env = parent.frame()) {
  root <- withr::local_tempdir("ar-study-", .local_envir = env)
  writeLines("study: synthetic", file.path(root, "_study.yml"))
  normalizePath(root, winslash = "/")
}

ar_fake_job <- function(root, job = "hz.dead.hz", folder = "20_distributions",
                        run = list(status = "final", open_markers = 0L, skipped_chunks = 0L, stopped_early = FALSE),
                        methods = list(text = "A hazard was modeled.", sha256 = NULL),
                        rendered = "2026-11-12T10:00:00Z") {
  dir.create(file.path(root, folder), showWarnings = FALSE)
  set <- file.path(root, "graphs", "dead-hz")
  dir.create(set, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(root, "documents", "dead-hz"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(root, "estimates", "dead-hz"), recursive = TRUE, showWarnings = FALSE)
  qmd <- file.path(root, folder, paste0(job, ".qmd"))
  writeLines(c("---", "title: fake", "---"), qmd)
  html <- sub("[.]qmd$", ".html", qmd)
  writeLines("<html></html>", html)
  png <- file.path(set, "hz-fit.png")
  grDevices::png(png, width = 100, height = 100)
  graphics::plot(1)
  grDevices::dev.off()
  saveRDS(data.frame(term = "mu", estimate = 0.1), file.path(root, "documents", "dead-hz", "tbl-estimates.rds"))
  saveRDS(list(n = 160L, events = 40L), file.path(root, "estimates", "dead-hz", "hz-methods.rds"))
  rec <- function(label, kind, rel) {
    list(label = label, kind = kind, file = rel, sha256 = digest::digest(file.path(root, rel), algo = "sha256", file = TRUE))
  }
  if (!is.null(methods) && is.null(methods$sha256)) {
    methods$sha256 <- digest::digest(methods$text, algo = "sha256", serialize = FALSE)
  }
  sidecar <- Filter(Negate(is.null), list(
    job = job, rendered = rendered, r = list(version = "4.6.1"),
    packages = list(list(package = "base", version = "4.6.1", source = "base"),
                    list(package = "TemporalHazard", version = "1.2.8", source = "standard")),
    data = list(list(path = "datasets/built.csv", role = "study", dataset = "built")),
    run = run, source_sha256 = digest::digest(qmd, algo = "sha256", file = TRUE),
    exhibits = list(rec("fig-fit", "figure", "graphs/dead-hz/hz-fit.png"),
                    rec("tbl-estimates", "table", "documents/dead-hz/tbl-estimates.rds"),
                    rec("methods", "value", "estimates/dead-hz/hz-methods.rds")),
    methods = methods
  ))
  jsonlite::write_json(sidecar, hvtiRutilities::provenance_path(html), auto_unbox = TRUE, null = "null")
  invisible(qmd)
}
```

- [ ] **Step 2: Write the failing tests**

`tests/testthat/test-ar-resolve.R`:

```r
# From an ar item id to verified evidence: every stop in spec section 6.2.

test_that("a well-formed id resolves to the exhibit, its file and its sidecar", {
  root <- ar_fake_study()
  ar_fake_job(root)
  r <- hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root)
  expect_identical(r$exhibit$kind, "figure")
  expect_true(file.exists(r$path))
  expect_false(r$source_changed)
})

test_that("a malformed id is refused with the expected form", {
  expect_error(hvtiRtemplates:::.ar_parse_id("hz.dead.hz"), "<job>#<label>")
  expect_error(hvtiRtemplates:::.ar_parse_id(c("a#b", "c#d")), "<job>#<label>")
})

test_that("a job that is absent, or has no sidecar, stops", {
  root <- ar_fake_study()
  expect_error(hvtiRtemplates:::.ar_resolve("hz.none.hz#fig-fit", root), "no job")
  qmd <- ar_fake_job(root)
  unlink(hvtiRutilities::provenance_path(sub("[.]qmd$", ".html", qmd)))
  expect_error(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root), "no provenance record")
})

test_that("a draft source stops, whether by an open marker or a runtime reason, with no partial render", {
  root <- ar_fake_study()
  ar_fake_job(root, run = list(status = "draft", open_markers = 2L, skipped_chunks = 0L, stopped_early = FALSE))
  expect_error(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root), "2 open EDIT: marker")
  ar_fake_job(root, run = list(status = "draft", open_markers = 0L, skipped_chunks = 0L, stopped_early = FALSE,
                               draft_reasons = list("the bootstrap pool is incomplete")))
  expect_error(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root), "bootstrap pool is incomplete")
})

test_that("a sidecar with no run status is not presumed final", {
  root <- ar_fake_study()
  ar_fake_job(root, run = NULL)
  expect_error(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root), "cannot be presumed final")
})

test_that("an unrecorded label stops and lists what the job recorded", {
  root <- ar_fake_study()
  ar_fake_job(root)
  expect_error(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-other", root), "fig-fit, tbl-estimates, methods")
})

test_that("a missing exhibit file stops", {
  root <- ar_fake_study()
  ar_fake_job(root)
  unlink(file.path(root, "graphs", "dead-hz", "hz-fit.png"))
  expect_error(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root), "is missing")
})

test_that("an exhibit overwritten after its sidecar was written stops on the digest", {
  root <- ar_fake_study()
  ar_fake_job(root)
  # As a re-render that wrote the figure and failed before publishing would leave it.
  writeBin(as.raw(1:4), file.path(root, "graphs", "dead-hz", "hz-fit.png"))
  expect_error(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root), "no longer holds the bytes")
})

test_that("a job file edited since its render is flagged, not stopped", {
  root <- ar_fake_study()
  qmd <- ar_fake_job(root)
  cat("# edited\n", file = qmd, append = TRUE)
  expect_true(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root)$source_changed)
})

test_that("Methods come from the sidecar, or from the floor when the template writes none", {
  root <- ar_fake_study()
  ar_fake_job(root)
  m <- hvtiRtemplates:::.ar_methods(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root))
  expect_false(m$floor)
  expect_identical(m$text, "A hazard was modeled.")
  ar_fake_job(root, methods = NULL)
  m <- hvtiRtemplates:::.ar_methods(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root))
  expect_true(m$floor)
  expect_match(m$text, "TemporalHazard 1.2.8")
  expect_false(grepl("base 4.6.1", m$text, fixed = TRUE))
})
```

- [ ] **Step 3: Run them and confirm they fail**

Run: `Rscript -e 'devtools::test(filter = "ar-resolve")'`
Expected: FAIL, `object '.ar_resolve' not found`.

- [ ] **Step 4: Write `R/ar-resolve.R`**

```r
# From an ar item id, "<job>#<label>", to evidence the report can show: the
# job's sidecar, the exhibit it recorded and the file, verified against the
# digest. Stops on everything that would let a draft or a stray file pass as
# finished evidence. dev/specs/2026-11-11-ar-question-report-design.md, 6.2.

.ar_parse_id <- function(id) {
  if (!is.character(id) || length(id) != 1L || is.na(id) || !grepl("^[A-Za-z0-9_.-]+#[A-Za-z0-9_-]+$", id)) {
    stop("An item is named '<job>#<label>', such as 'hz.dead.hz#fig-fit'; got ",
         encodeString(as.character(id)[1L], quote = "\""), ".", call. = FALSE)
  }
  parts <- strsplit(id, "#", fixed = TRUE)[[1L]]
  list(id = id, job = parts[[1L]], label = parts[[2L]])
}

# Jobs sit flat in the study's top-level folders, under either the numbered or
# the legacy bare layout, so one level of glob finds them.
.ar_find_job <- function(job, root) {
  hits <- Sys.glob(file.path(root, "*", paste0(job, ".qmd")))
  if (length(hits) == 0L) stop("There is no job '", job, ".qmd' in this study.", call. = FALSE)
  if (length(hits) > 1L) {
    stop("Job '", job, ".qmd' is in more than one folder: ", paste(hits, collapse = ", "), ".", call. = FALSE)
  }
  normalizePath(hits, winslash = "/")
}

.ar_read_sidecar <- function(qmd, job) {
  sidecar <- hvtiRutilities::provenance_path(sub("[.]qmd$", ".html", qmd))
  if (!file.exists(sidecar)) stop("Job '", job, "' has no provenance record; render it first.", call. = FALSE)
  jsonlite::read_json(sidecar, simplifyVector = FALSE)
}

.ar_draft_detail <- function(run) {
  c(if (isTRUE(run$open_markers > 0L)) paste(run$open_markers, "open EDIT: marker(s)"),
    if (isTRUE(run$skipped_chunks > 0L)) paste(run$skipped_chunks, "skipped chunk(s)"),
    if (isTRUE(run$stopped_early)) "a stop_here()",
    unlist(run$draft_reasons, use.names = FALSE))
}

.ar_resolve <- function(id, root) {
  item <- .ar_parse_id(id)
  qmd <- .ar_find_job(item$job, root)
  side <- .ar_read_sidecar(qmd, item$job)
  status <- side$run$status
  if (is.null(status)) {
    stop("Item '", id, "': job '", item$job, "' was rendered before runs recorded their status, so it cannot be ",
         "presumed final. Render it again with the current hvtiRtemplates.", call. = FALSE)
  }
  if (!identical(status, "final")) {
    stop("Item '", id, "': job '", item$job, "' last rendered as a draft (",
         paste(.ar_draft_detail(side$run), collapse = "; "),
         "). A draft is not evidence: finish the job and render it again.", call. = FALSE)
  }
  recs <- if (is.null(side$exhibits)) list() else side$exhibits
  labels <- vapply(recs, function(r) r$label, "")
  hit <- which(labels == item$label)
  if (length(hit) != 1L) {
    stop("Item '", id, "': job '", item$job, "' recorded no exhibit labeled '", item$label, "' (",
         if (length(labels)) paste("it recorded:", paste(labels, collapse = ", "))
         else "it recorded none; its template may not save exhibits yet, or SAVE_FIGURES may be off",
         ").", call. = FALSE)
  }
  rec <- recs[[hit]]
  path <- file.path(root, rec$file)
  if (!file.exists(path)) {
    stop("Item '", id, "': the file '", rec$file, "' its job recorded is missing. Render the job again.", call. = FALSE)
  }
  if (!identical(digest::digest(path, algo = "sha256", file = TRUE), rec$sha256)) {
    stop("Item '", id, "': '", rec$file, "' no longer holds the bytes its job's last completed render recorded. ",
         "A later render may have failed after writing it, or it was changed by hand. Render the job again.",
         call. = FALSE)
  }
  changed <- !is.null(side$source_sha256) &&
    !identical(digest::digest(qmd, algo = "sha256", file = TRUE), side$source_sha256)
  c(item, list(qmd = qmd, html = sub("[.]qmd$", ".html", qmd), sidecar = side, exhibit = rec,
               path = normalizePath(path, winslash = "/"), source_changed = changed))
}

# The template's paragraph, or, until its template writes one, a floor built
# from what the sidecar records: date, R, data and non-base packages.
.ar_methods <- function(r) {
  m <- r$sidecar$methods
  if (!is.null(m)) return(list(text = m$text, sha256 = m$sha256, floor = FALSE))
  pk <- Filter(function(p) !identical(p$source, "base"), r$sidecar$packages)
  pk <- vapply(pk, function(p) paste(p$package, p$version), "")
  ds <- unique(vapply(r$sidecar$data, function(x) if (is.null(x$dataset)) x$path else x$dataset, ""))
  text <- paste0("Job ", r$job, " was rendered on ", substr(r$sidecar$rendered, 1L, 10L), " with R ",
                 r$sidecar$r$version, if (length(ds)) paste0(", reading ", paste(ds, collapse = ", ")),
                 if (length(pk)) paste0(". Packages: ", paste(pk, collapse = ", ")), ".")
  list(text = text, sha256 = digest::digest(text, algo = "sha256", serialize = FALSE), floor = TRUE)
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `Rscript -e 'devtools::test(filter = "ar-resolve")'`
Expected: PASS.

- [ ] **Step 6: Prove by mutation.** Replace `!identical(status, "final")` with `FALSE`, confirm both draft tests fail, and restore. Remove the digest check, confirm "overwritten" fails, and restore.

- [ ] **Step 7: Commit**

```bash
git add R/ar-resolve.R tests/testthat/helper-ar.R tests/testthat/test-ar-resolve.R
git commit -m "ar: resolve an item id to verified, final evidence"
```

---

### Task 4: Read and write the `ar` file: `ar_paste_methods()` and `ar_review()`

**Files:**
- Create: `R/ar-file.R`
- Create: `tests/testthat/test-ar-file.R`

**Interfaces:**
- Consumes: `.ar_resolve(id, root)` and `.ar_methods(r)` from Task 3.
- Produces:
  - `.ar_parse(lines)` → a list with one entry per `ar_item("...")` call, each `list(id, index, call_line, open, close, stamp_line, stamp, empty)`. `open`, `close` and `stamp_line` are integer or `NA`, and `stamp` is a list or `NULL`.
  - The stamp line format: `<!-- ar-stamp {"item":..,"methods_sha256":..,"rendered":..,"exhibit_sha256":..} -->`, the first line inside the `::: methods` div.
  - `ar_paste_methods(path, root = NULL)` → the ids it pasted, invisibly.
  - `ar_review(path, item = NULL, root = NULL)` → the ids it stamped, invisibly.
  - `.ar_root(path)` → the study root above `path`.

- [ ] **Step 1: Write the failing tests**

`tests/testthat/test-ar-file.R`:

```r
# The ar file: its items, the pasted Methods text and the review stamps.
# dev/specs/2026-11-11-ar-question-report-design.md, sections 5.4 and 5.5.

ar_lines <- function(items = "hz.dead.hz#fig-fit", methods = list("")) {
  unlist(lapply(seq_along(items), function(i) c(
    paste0("## Item ", i), "", "```{r}", paste0('hvtiRtemplates::ar_item("', items[[i]], '")'), "```", "",
    "::: methods", methods[[i]], ":::", "", "::: results", ":::", ""
  )))
}

ar_report <- function(root, lines) {
  dir.create(file.path(root, "50_documents"), showWarnings = FALSE)
  path <- file.path(root, "50_documents", "ar.dead.question.qmd")
  writeLines(lines, path)
  path
}

test_that("items are found by their ar_item() call, with their methods div", {
  p <- hvtiRtemplates:::.ar_parse(ar_lines(c("a.b.c#x", "a.b.c#y")))
  expect_identical(vapply(p, `[[`, "", "id"), c("a.b.c#x", "a.b.c#y"))
  expect_true(p[[1]]$empty)
  expect_true(is.na(p[[1]]$stamp_line))
})

test_that("an item cited twice is refused", {
  expect_error(hvtiRtemplates:::.ar_parse(ar_lines(c("a.b.c#x", "a.b.c#x"), list("", ""))), "twice")
})

test_that("a methods div holding only a comment counts as empty, and prose does not", {
  expect_true(hvtiRtemplates:::.ar_parse(ar_lines(methods = list("<!-- run ar_paste_methods() -->")))[[1]]$empty)
  expect_false(hvtiRtemplates:::.ar_parse(ar_lines(methods = list("My own words.")))[[1]]$empty)
})

test_that("ar_paste_methods() fills an empty div with the stamp and the boilerplate", {
  root <- ar_fake_study()
  ar_fake_job(root)
  path <- ar_report(root, ar_lines())
  expect_identical(ar_paste_methods(path), "hz.dead.hz#fig-fit")
  p <- hvtiRtemplates:::.ar_parse(readLines(path))[[1]]
  expect_false(p$empty)
  expect_identical(p$stamp$rendered, "2026-11-12T10:00:00Z")
  expect_true(any(readLines(path) == "A hazard was modeled."))
})

test_that("ar_paste_methods() never touches a div that holds text, byte for byte", {
  root <- ar_fake_study()
  ar_fake_job(root)
  path <- ar_report(root, ar_lines(methods = list("My own words.")))
  before <- readBin(path, "raw", file.size(path))
  expect_identical(ar_paste_methods(path), character())
  expect_identical(readBin(path, "raw", file.size(path)), before)
})

test_that("ar_paste_methods() writes nothing when any item fails to resolve", {
  root <- ar_fake_study()
  ar_fake_job(root)
  path <- ar_report(root, ar_lines(c("hz.dead.hz#fig-fit", "hz.dead.hz#absent"), list("", "")))
  before <- readLines(path)
  expect_error(ar_paste_methods(path), "absent")
  expect_identical(readLines(path), before)
})

test_that("an item without a methods div is refused", {
  root <- ar_fake_study()
  ar_fake_job(root)
  path <- ar_report(root, c("```{r}", 'hvtiRtemplates::ar_item("hz.dead.hz#fig-fit")', "```"))
  expect_error(ar_paste_methods(path), "no ::: methods div")
})

test_that("ar_review() moves the stamp to the source's current run and keeps the analyst's text", {
  root <- ar_fake_study()
  ar_fake_job(root)
  path <- ar_report(root, ar_lines())
  ar_paste_methods(path)
  ar_fake_job(root, rendered = "2026-11-13T09:00:00Z")
  expect_identical(ar_review(path), "hz.dead.hz#fig-fit")
  p <- hvtiRtemplates:::.ar_parse(readLines(path))[[1]]
  expect_identical(p$stamp$rendered, "2026-11-13T09:00:00Z")
  expect_true(any(readLines(path) == "A hazard was modeled."))
})

test_that("ar_review() refuses an item never pasted", {
  root <- ar_fake_study()
  ar_fake_job(root)
  path <- ar_report(root, ar_lines())
  expect_error(ar_review(path), "ar_paste_methods\\(\\) first")
})
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `Rscript -e 'devtools::test(filter = "ar-file")'`
Expected: FAIL, `could not find function "ar_paste_methods"`.

- [ ] **Step 3: Write `R/ar-file.R`**

```r
# Reading and writing an ar job file: one item per ar_item("<job>#<label>")
# call, running to the next; its ::: methods div; and the review stamp, the
# first line inside that div. Run from the console, never during render: a
# render that edits its own source breaks the checksum provenance records.
# dev/specs/2026-11-11-ar-question-report-design.md, sections 5.4 and 5.5.

.ar_call_pattern <- '^\\s*(hvtiRtemplates::)?ar_item\\(\\s*"([^"]+)"'
.ar_stamp_pattern <- "^<!-- ar-stamp (\\{.*\\}) -->$"

.ar_parse <- function(lines) {
  calls <- grep(.ar_call_pattern, lines)
  ids <- sub(paste0(.ar_call_pattern, ".*$"), "\\2", lines[calls])
  dup <- anyDuplicated(ids)
  if (dup) stop("Item '", ids[[dup]], "' is cited twice in this report; cite each exhibit once.", call. = FALSE)
  ends <- c(calls[-1L] - 1L, length(lines))
  lapply(seq_along(calls), function(i) {
    region <- seq.int(calls[[i]], ends[[i]])
    open <- region[grepl("^:::+\\s*\\{?\\.?methods\\}?\\s*$", lines[region])][1L]
    close <- if (is.na(open)) NA_integer_ else region[region > open & grepl("^:::+\\s*$", lines[region])][1L]
    body <- if (is.na(open) || is.na(close)) integer() else seq_len(close - open - 1L) + open
    stamp_line <- body[grepl(.ar_stamp_pattern, lines[body])][1L]
    stamp <- if (is.na(stamp_line)) NULL else {
      jsonlite::fromJSON(sub(.ar_stamp_pattern, "\\1", lines[[stamp_line]]), simplifyVector = FALSE)
    }
    prose <- lines[setdiff(body, stamp_line)]
    list(id = ids[[i]], index = i, call_line = calls[[i]], open = open, close = close, stamp_line = stamp_line,
         stamp = stamp, empty = all(grepl("^\\s*$", prose) | grepl("^\\s*<!--.*-->\\s*$", prose)))
  })
}

.ar_stamp_line <- function(r) {
  paste0("<!-- ar-stamp ", jsonlite::toJSON(list(
    item = r$id, methods_sha256 = .ar_methods(r)$sha256,
    rendered = r$sidecar$rendered, exhibit_sha256 = r$exhibit$sha256
  ), auto_unbox = TRUE), " -->")
}

.ar_root <- function(path) normalizePath(.find_study_root(dirname(normalizePath(path, mustWork = TRUE))), winslash = "/")

.ar_write <- function(lines, path) {
  tmp <- tempfile(tmpdir = dirname(path), fileext = ".qmd")
  writeLines(lines, tmp)
  if (!file.rename(tmp, path)) {
    unlink(tmp)
    stop("Could not write '", path, "'.", call. = FALSE)
  }
}

.ar_need_div <- function(it) {
  if (is.na(it$open) || is.na(it$close)) {
    stop("Item '", it$id, "' has no ::: methods div; add one under its ar_item() chunk.", call. = FALSE)
  }
}

#' Paste each item's Methods boilerplate into an ar report
#'
#' @description Writes the Methods paragraph each cited job recorded into every
#'   \strong{empty} \code{::: methods} div of an \code{ar} analysis report, with a
#'   review stamp, so the analyst edits text that starts from the job's own
#'   choices. A div that already holds text is never touched.
#'
#' @details Run from the console, not from inside the render: a render that
#'   edits its own source would break the checksum its provenance records. Every
#'   item is resolved before anything is written, so an item that fails (a draft
#'   source, a missing exhibit) leaves the file exactly as it was.
#'
#' @param path Path to the \code{ar} job file.
#' @param root The study root. \code{NULL} finds it above \code{path}.
#' @return The ids of the items pasted, invisibly, in file order.
#' @seealso \code{\link{ar_review}}, \code{\link{ar_item}}
#' @examples
#' \donttest{
#' # ar_paste_methods("documents/ar.dead.question.qmd")
#' }
#' @export
ar_paste_methods <- function(path, root = NULL) {
  lines <- readLines(path, warn = FALSE)
  if (is.null(root)) root <- .ar_root(path)
  items <- .ar_parse(lines)
  if (!length(items)) stop("No ar_item() calls in '", path, "'.", call. = FALSE)
  plans <- lapply(items, function(it) {
    .ar_need_div(it)
    if (!it$empty) return(NULL)
    r <- .ar_resolve(it$id, root)
    list(it = it, insert = c(.ar_stamp_line(r), "", .ar_methods(r)$text))
  })
  plans <- Filter(Negate(is.null), plans)
  for (p in rev(plans)) {
    lines <- c(lines[seq_len(p$it$open)], p$insert, lines[p$it$close:length(lines)])
  }
  if (length(plans)) .ar_write(lines, path)
  invisible(vapply(plans, function(p) p$it$id, ""))
}

#' Mark ar report items as reviewed against their sources' current runs
#'
#' @description After rereading an item's methods, results and interpretation
#'   against a source job that has been rendered again, \code{ar_review()}
#'   moves that item's review stamp to the job's current run, which clears the
#'   report's callout. The analyst's text is not changed.
#'
#' @param path Path to the \code{ar} job file.
#' @param item Item ids to stamp, such as \code{"hz.dead.hz#fig-fit"}.
#'   \code{NULL} stamps every item.
#' @param root The study root. \code{NULL} finds it above \code{path}.
#' @return The ids of the items stamped, invisibly.
#' @seealso \code{\link{ar_paste_methods}}
#' @examples
#' \donttest{
#' # ar_review("documents/ar.dead.question.qmd", "hz.dead.hz#fig-fit")
#' }
#' @export
ar_review <- function(path, item = NULL, root = NULL) {
  lines <- readLines(path, warn = FALSE)
  if (is.null(root)) root <- .ar_root(path)
  items <- .ar_parse(lines)
  ids <- vapply(items, `[[`, "", "id")
  if (!is.null(item)) {
    unknown <- setdiff(item, ids)
    if (length(unknown)) stop("Not an item in this report: ", paste(unknown, collapse = ", "), ".", call. = FALSE)
    items <- items[ids %in% item]
  }
  for (it in items) {
    if (is.na(it$stamp_line)) stop("Item '", it$id, "' was never pasted; run ar_paste_methods() first.", call. = FALSE)
  }
  stamps <- lapply(items, function(it) .ar_stamp_line(.ar_resolve(it$id, root)))
  for (i in seq_along(items)) lines[[items[[i]]$stamp_line]] <- stamps[[i]]
  if (length(items)) .ar_write(lines, path)
  invisible(vapply(items, `[[`, "", "id"))
}
```

- [ ] **Step 4: Document and run the tests**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "ar-file")'`
Expected: PASS. `NAMESPACE` gains `export(ar_paste_methods)` and `export(ar_review)`.

`.find_study_root()` uses `hvtiRutilities::study_root()`, which looks for `_study.yml`. If the fake study's one-line `_study.yml` does not satisfy it, write it in `ar_fake_study()` with `hvtiRutilities::study_setup(root, study = "ar test", study_tracker_id = 1L, adopt = TRUE, cleanup = FALSE, renv = FALSE)`, as `hazard_study()` does.

- [ ] **Step 5: Prove by mutation.** Change `if (!it$empty) return(NULL)` to `if (FALSE) return(NULL)`, confirm "never touches" fails, and restore.

- [ ] **Step 6: Commit**

```bash
git add R/ar-file.R tests/testthat/test-ar-file.R NAMESPACE man/ar_paste_methods.Rd man/ar_review.Rd
git commit -m "ar: paste Methods boilerplate once and stamp reviewed items"
```

---

### Task 5: What a render shows: `ar_item()` and `ar_value()`

**Files:**
- Create: `R/ar-item.R`
- Create: `tests/testthat/test-ar-item.R`

**Interfaces:**
- Consumes: `.ar_resolve()`, `.ar_methods()`, `.ar_parse()` and `.ar_root()`.
- Produces:
  - `ar_item(id)` → a `knit_asis` object: the callouts, then the exhibit, then a link to the job's report.
  - `ar_value(id, field)` → the field's value.
  - `.ar_item_markdown(r, it, from)` → a character vector. It is factored out so tests need no knitr context.

- [ ] **Step 1: Write the failing tests**

`tests/testthat/test-ar-item.R`:

```r
# What an ar render shows for an item, and when it warns. Spec sections 6.1 and 6.2.

ar_item_md <- function(root, methods = list(""), ...) {
  path <- file.path(root, "50_documents", "ar.dead.question.qmd")
  dir.create(dirname(path), showWarnings = FALSE)
  writeLines(c("```{r}", 'hvtiRtemplates::ar_item("hz.dead.hz#fig-fit")', "```", "", "::: methods",
               methods[[1]], ":::"), path)
  list(path = path, md = function() {
    it <- hvtiRtemplates:::.ar_parse(readLines(path))[[1]]
    r <- hvtiRtemplates:::.ar_resolve(it$id, root)
    paste(hvtiRtemplates:::.ar_item_markdown(r, it, dirname(path)), collapse = "\n")
  })
}

test_that("a figure is embedded, numbered, downloadable and linked to its job", {
  root <- ar_fake_study()
  ar_fake_job(root)
  x <- ar_item_md(root)
  ar_paste_methods(x$path)
  md <- x$md()
  expect_match(md, "**Item 1**", fixed = TRUE)
  expect_match(md, "](../graphs/dead-hz/hz-fit.png)", fixed = TRUE)
  expect_match(md, "data:image/png;base64,", fixed = TRUE)
  expect_match(md, "(../20_distributions/hz.dead.hz.html)", fixed = TRUE)
  expect_false(grepl("callout", md))
})

test_that("an empty methods slot asks for ar_paste_methods()", {
  root <- ar_fake_study()
  ar_fake_job(root)
  expect_match(ar_item_md(root)$md(), "ar_paste_methods()", fixed = TRUE)
})

test_that("a source rendered again on changed data, Methods unchanged, raises the review callout until reviewed", {
  root <- ar_fake_study()
  ar_fake_job(root)
  x <- ar_item_md(root)
  ar_paste_methods(x$path)
  ar_fake_job(root, rendered = "2026-11-13T09:00:00Z")
  md <- x$md()
  expect_match(md, "rendered again since this item's text was reviewed")
  expect_false(grepl("Methods paragraph has changed", md))
  ar_review(x$path)
  expect_false(grepl("callout", x$md()))
})

test_that("changed boilerplate raises the drift callout", {
  root <- ar_fake_study()
  ar_fake_job(root)
  x <- ar_item_md(root)
  ar_paste_methods(x$path)
  ar_fake_job(root, methods = list(text = "A different method.", sha256 = NULL))
  expect_match(x$md(), "Methods paragraph has changed")
})

test_that("an edited source job and a template with no boilerplate each raise a callout", {
  root <- ar_fake_study()
  qmd <- ar_fake_job(root, methods = NULL)
  x <- ar_item_md(root)
  ar_paste_methods(x$path)
  cat("# edited\n", file = qmd, append = TRUE)
  md <- x$md()
  expect_match(md, "edited since its last render")
  expect_match(md, "writes no Methods paragraph yet")
})

test_that("a table renders as a table", {
  root <- ar_fake_study()
  ar_fake_job(root)
  r <- hvtiRtemplates:::.ar_resolve("hz.dead.hz#tbl-estimates", root)
  it <- list(id = r$id, index = 2L, empty = FALSE, stamp = NULL)
  md <- paste(hvtiRtemplates:::.ar_item_markdown(r, it, file.path(root, "50_documents")), collapse = "\n")
  expect_match(md, "|term |", fixed = TRUE)
})

test_that("ar_value() returns a field, and names the fields it has when one is misspelled", {
  root <- ar_fake_study()
  ar_fake_job(root)
  withr::local_dir(root)
  expect_identical(ar_value("hz.dead.hz#methods", "n"), 160L)
  expect_error(ar_value("hz.dead.hz#methods", "N"), "it has: n, events")
  expect_error(ar_value("hz.dead.hz#fig-fit", "n"), "not a saved value")
})
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `Rscript -e 'devtools::test(filter = "ar-item")'`
Expected: FAIL, `object '.ar_item_markdown' not found`.

- [ ] **Step 3: Write `R/ar-item.R`**

```r
# What an ar render shows for one item: the callouts that say what to check,
# the exhibit and a link to the job's full report. Nothing is re-run.
# dev/specs/2026-11-11-ar-question-report-design.md, sections 6.1 and 6.2.

.ar_relative <- function(path, from) {
  p <- strsplit(normalizePath(path, winslash = "/"), "/", fixed = TRUE)[[1L]]
  f <- strsplit(normalizePath(from, winslash = "/"), "/", fixed = TRUE)[[1L]]
  n <- 0L
  while (n < min(length(p), length(f)) && identical(p[[n + 1L]], f[[n + 1L]])) n <- n + 1L
  paste(c(rep("..", length(f) - n), p[-seq_len(n)]), collapse = "/")
}

.ar_callout <- function(text) paste0("::: {.callout-warning}\n", text, "\n:::\n")

.ar_callouts <- function(r, it) {
  m <- .ar_methods(r)
  s <- it$stamp
  notes <- c(
    if (isTRUE(r$source_changed)) {
      sprintf("The source job `%s` has been edited since its last render. Render it again before relying on this item.",
              r$job)
    },
    if (m$floor) {
      sprintf(paste("The `%s` job's template writes no Methods paragraph yet, so the Methods draft names the software,",
                    "versions and data only."), r$job)
    },
    if (isTRUE(it$empty)) "The Methods slot is empty. Run `hvtiRtemplates::ar_paste_methods()` on this file from the console.",
    if (!is.null(s) && !identical(s$methods_sha256, m$sha256)) {
      "The source job's Methods paragraph has changed since it was pasted here. Compare and update it, then run `ar_review()`."
    },
    if (!is.null(s) && (!identical(s$rendered, r$sidecar$rendered) || !identical(s$exhibit_sha256, r$exhibit$sha256))) {
      paste("The source job has been rendered again since this item's text was reviewed. Reread its methods, results",
            "and interpretation, then run `hvtiRtemplates::ar_review()`.")
    }
  )
  vapply(notes, .ar_callout, "", USE.NAMES = FALSE)
}

# A figure is embedded by Quarto's embed-resources; the download link carries
# the PNG itself, so it still works in the one HTML file researchers receive.
.ar_exhibit_body <- function(r, from) {
  switch(r$exhibit$kind,
    figure = {
      rel <- .ar_relative(r$path, from)
      png <- openssl::base64_encode(readBin(r$path, "raw", file.size(r$path)))
      c(sprintf("![](%s)", rel), "",
        sprintf('<a href="data:image/png;base64,%s" download="%s">Download the figure (PNG)</a>', png, basename(rel)))
    },
    table = knitr::kable(readRDS(r$path), format = "pipe", row.names = FALSE),
    value = sprintf("Values saved for the text: %s.", paste0("`", names(readRDS(r$path)), "`", collapse = ", "))
  )
}

.ar_item_markdown <- function(r, it, from) {
  c(.ar_callouts(r, it), sprintf("**Item %d** · `%s`", it$index, r$id), "", .ar_exhibit_body(r, from), "",
    sprintf("[The full report of `%s`, in the study folder](%s)", r$job, .ar_relative(r$html, from)), "")
}

.ar_input <- function() {
  input <- knitr::current_input(dir = TRUE)
  if (is.null(input)) stop("ar_item() shows an item while an ar report renders.", call. = FALSE)
  input
}

#' Show one item of an ar analysis report
#'
#' @description Called once per item in an \code{ar} job. Finds the exhibit a
#'   finished job recorded under \code{id}, checks that the job last rendered as
#'   final and that the file still holds the bytes it recorded, and shows the
#'   exhibit with a link to the job's report. Callouts above it say what to
#'   check: a job edited since its render, Methods boilerplate that changed, or
#'   text written against an earlier run.
#'
#' @param id The item, \code{"<job>#<label>"}: the source job's file name
#'   without \code{.qmd}, and the chunk label it saved the exhibit under.
#' @return A \code{knit_asis} object holding the item's Markdown.
#' @seealso \code{\link{ar_value}}, \code{\link{ar_paste_methods}}, \code{\link{ar_review}}
#' @examples
#' \donttest{
#' # In an ar job's chunk:
#' # hvtiRtemplates::ar_item("hz.dead.hz#fig-fit")
#' }
#' @export
ar_item <- function(id) {
  input <- .ar_input()
  root <- .ar_root(input)
  items <- .ar_parse(readLines(input, warn = FALSE))
  it <- items[vapply(items, `[[`, "", "id") == id]
  if (length(it) != 1L) stop("ar_item() takes its id as a literal string, so ar_paste_methods() can read it.", call. = FALSE)
  r <- .ar_resolve(id, root)
  knitr::asis_output(paste(.ar_item_markdown(r, it[[1L]], dirname(input)), collapse = "\n"))
}

#' Quote a saved value in an ar analysis report
#'
#' @description Reads one field of a value a finished job saved for its report,
#'   so a number in the Results text comes from the fit and goes stale with it,
#'   rather than being retyped. The source run must be final and its file
#'   unchanged, as for \code{\link{ar_item}}.
#'
#' @param id The value's item id, \code{"<job>#<label>"}.
#' @param field The field to return.
#' @return The field's value.
#' @examples
#' \donttest{
#' # Inline in an ar job: `r hvtiRtemplates::ar_value("hz.dead.hz#methods", "n")` patients
#' }
#' @export
ar_value <- function(id, field) {
  input <- knitr::current_input(dir = TRUE)
  r <- .ar_resolve(id, .ar_root(if (is.null(input)) file.path(getwd(), ".") else input))
  if (!identical(r$exhibit$kind, "value")) {
    stop("Item '", id, "' is a ", r$exhibit$kind, ", not a saved value; ar_value() reads values only.", call. = FALSE)
  }
  x <- readRDS(r$path)
  if (!is.character(field) || length(field) != 1L || !field %in% names(x)) {
    stop("Item '", id, "' has no field ", encodeString(as.character(field)[1L], quote = "'"), "; it has: ",
         paste(names(x), collapse = ", "), ".", call. = FALSE)
  }
  x[[field]]
}
```

- [ ] **Step 4: Document and run the tests**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "ar-item|ar-file|ar-resolve")'`
Expected: PASS.

- [ ] **Step 5: Prove by mutation.** Drop the `rendered` comparison from the review callout, confirm "changed data, Methods unchanged" fails, and restore.

- [ ] **Step 6: Commit**

```bash
git add R/ar-item.R tests/testthat/test-ar-item.R NAMESPACE man/ar_item.Rd man/ar_value.Rd
git commit -m "ar: show an item with its callouts, and quote saved values"
```

---

### Task 6: The `ar` template, its ledger row and an end-to-end render

**Files:**
- Create: `inst/templates/50_documents/ar.qmd`
- Modify: `inst/extdata/templates.json` (a new `templates` row)
- Modify: `.lintr` (a file key)
- Modify: `inst/templates/README.md` (a template-table row, and the "What is not here yet" list if it names `ar`)
- Create: `tests/testthat/test-ar-template.R`
- Create: `news/<branch>.md`

**Interfaces:**
- Consumes: everything above. `add_job("ar", subject, type)` places the job under `documents/` through `hvtiRutilities::study_dir()`, with no code change, because the taxonomy already has the row.

- [ ] **Step 1: Write the failing test**

`tests/testthat/test-ar-template.R`:

```r
# The ar template scaffolds, and an ar job renders end to end against a
# finished hz job. Spec section 7.

test_that("ar scaffolds into documents with one SUBJECT and one TYPE line", {
  root <- hazard_study()
  job <- suppressMessages(add_job("ar", "dead", "question", dir = root))
  expect_match(job, "/(50_)?documents/ar\\.dead\\.question\\.qmd$")
  src <- readLines(job)
  expect_length(grep("^SUBJECT\\s+<- ", src), 1L)
  expect_length(grep("^TYPE\\s+<- ", src), 1L)
  expect_gte(length(grep("EDIT:", src)), 2L)
})

test_that("an ar job renders against a finished hz job", {
  skip_on_cran()
  skip_if_not_installed("TemporalHazard")
  skip_if(Sys.which("quarto") == "", "quarto is not installed")
  root <- hazard_study()
  hz <- suppressMessages(add_job("hz", "dead", "hz", dir = root))
  # Stand in for a finished job by removing the marker word only. Truncating the
  # line at the marker would leave a one-line HTML comment unclosed.
  writeLines(gsub("EDIT:", "", readLines(hz), fixed = TRUE), hz)
  render_job(hz)
  ar <- suppressMessages(add_job("ar", "dead", "question", dir = root))
  a <- gsub("hz.dead_pa.hz", "hz.dead.hz", readLines(ar), fixed = TRUE)
  writeLines(gsub("EDIT:", "", a, fixed = TRUE), ar)
  ar_paste_methods(ar)
  render_job(ar)
  html <- readLines(sub("[.]qmd$", ".html", ar), warn = FALSE)
  expect_true(any(grepl("Item 1", html, fixed = TRUE)))
  expect_false(any(grepl("callout-warning", html, fixed = TRUE)))
})
```

⚠️ The render test removes `EDIT:` markers bluntly, as a stand-in for a finished job. Before relying on it, run the hz job's actual edits from `dev/gallery/family-hazard.R` (`hazard_rows`, `hazard_counts`, `hazard_hz_choices`, applied with `set_choices()` from `dev/demo/demo-study.R`) instead if the blunt removal leaves `hz` unable to fit. The test proves the integration. It does not need to prove `hz`.

- [ ] **Step 2: Run it and confirm it fails**

Run: `Rscript -e 'devtools::test(filter = "ar-template")'`
Expected: FAIL. `add_job()` finds no `ar` template.

- [ ] **Step 3: Write `inst/templates/50_documents/ar.qmd`**

````markdown
---
title: "Analysis report"
format:
  html:
    embed-resources: true
    toc: true
    toc-location: left
    code-fold: true
execute:
  warning: false
---

<!--
An ar job answers ONE research question from jobs that have already run. It
re-runs nothing: each item shows a figure, table or value a finished job saved,
checked against the bytes that job recorded. The report goes to the researchers,
who choose which items are published; the publication formatting comes after
their choice.

Workflow:
  1. Render the source jobs until each is final.
  2. Name each item below as "<job>#<label>": the job's file name without .qmd,
     and the chunk label it saved under. The job's report shows the labels.
  3. From the console: hvtiRtemplates::ar_paste_methods("<this file>").
  4. Write each item's results and interpretation, then render.
  5. When a source job is rendered again, reread the items it feeds and run
     hvtiRtemplates::ar_review("<this file>").
-->

```{r}
#| label: setup
SUBJECT <- "dead_pa"
TYPE    <- "question"
.in <- knitr::current_input(dir = TRUE)
.provenance_artifacts <- list()
suppressPackageStartupMessages(library(hvtiRutilities))
.job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE, envir = environment())
.root <- .job$root
set_path <- .job$set_path
.provenance_data <- list()
.job$notice
```

## Question

```{r}
#| label: edit-question
#| results: asis
# EDIT: paste the research question from the protocol, word for word. The
# report is judged against this sentence, so do not paraphrase it.
QUESTION <- "Does the early hazard of death differ from the late hazard?"
cat("> ", QUESTION, "\n", sep = "")
```

## Item 1: Survival from the parametric fit

```{r}
#| label: item-1
# EDIT: name the exhibit as "<job>#<label>".
hvtiRtemplates::ar_item("hz.dead_pa.hz#fig-fit")
```

::: methods
<!-- ar_paste_methods() writes the source job's paragraph here. Edit it freely. -->
:::

::: results
<!-- EDIT: what the exhibit shows, with its numbers. Quote a saved value with
an inline r expression calling hvtiRtemplates::ar_value("<job>#<label>", "<field>"),
such as ar_value("hz.dead_pa.hz#methods", "n"), so the number follows the fit. -->
:::

::: interpretation
<!-- EDIT: how this bears on the question above. -->
:::

## Item 2: Parameter estimates

```{r}
#| label: item-2
# EDIT: name the exhibit as "<job>#<label>".
hvtiRtemplates::ar_item("hz.dead_pa.hz#tbl-estimates")
```

::: methods
<!-- ar_paste_methods() writes the source job's paragraph here. Edit it freely. -->
:::

::: results
<!-- EDIT: what the exhibit shows, with its numbers. -->
:::

::: interpretation
<!-- EDIT: how this bears on the question above. -->
:::

## About this run

```{r}
#| label: provenance
#| echo: false
#| results: asis
cat(hvtiRtemplates:::.embed_provenance(
  .in,
  data = .provenance_data,
  run = .job$run,
  artifacts = .provenance_artifacts,
  extra = list(subject = SUBJECT, type = TYPE, question = QUESTION)
))
```
````

⚠️ **Never write an inline `` `r ...` `` expression inside an HTML comment in this template.** knitr evaluates inline code before Markdown is parsed, so a comment does not hide it, and an example `ar_value()` call would run on every render.

Before you write it, compare the `setup` chunk with `inst/templates/20_distributions/hz.qmd` lines 57 to 112. Copy that chunk's exact body (its version-floor check and its `.job_setup()` call signature), keep `SUBJECT`, `TYPE` and `library(hvtiRutilities)`, and drop the hazard-only lines. The block above is the shape; the `hz` chunk is the authority on the call.

- [ ] **Step 4: Add the ledger row**

Add to `templates` in `inst/extdata/templates.json`, beside the other in-flight rows:

```json
{
  "prefix": "ar",
  "qualifier": null,
  "name": "Analysis report",
  "description": "One research question answered from finished jobs: numbered figures, tables and values, each with Methods, Results and Interpretation for the researchers to choose from.",
  "folder": "documents",
  "family": "documents",
  "kind": "job",
  "status": "in-flight",
  "batch": null,
  "sas_breadth": null,
  "r_exemplars": null,
  "r_jobs": null,
  "upstream": [],
  "downstream": [],
  "workflows": [],
  "blocked_on": null,
  "spec": "dev/specs/2026-11-11-ar-question-report-design.md",
  "note": "Released for review. Becomes shipped once two study questions have used it.",
  "sas_breadth_jobs": null,
  "disposition": "scaffold",
  "uses": []
}
```

Copy any field the `vt-fit` row has that this one lacks, with its null or empty value. Then run `python3 .github/scripts/check-roadmap-counts.py` and fix whatever it reports. If `family: "documents"` is not an accepted value, use the value it lists.

- [ ] **Step 5: Add the `.lintr` file key**, after the `vt-explain.qmd` entry:

```r
    "inst/templates/50_documents/ar.qmd" = list(
      object_name_linter = Inf,
      commented_code_linter = Inf,
      object_usage_linter = Inf
    ),
```

- [ ] **Step 6: Add the README row** in `inst/templates/README.md`, in the template table's style:

```markdown
| `50_documents/ar.qmd` | analysis report: one research question answered from finished jobs, as numbered items with Methods, Results and Interpretation for researchers to choose from (in flight) | `50_documents/` or `documents/` |
```

- [ ] **Step 7: Write the news fragment** `news/<branch>.md`:

```markdown
* New in-flight template `ar`, an analysis report for one research question.
  Each item shows a figure, table or value a finished job saved, checked
  against the bytes that job recorded, with Methods, Results and Interpretation
  for the researchers to choose from. `ar_item()`, `ar_value()`,
  `ar_paste_methods()` and `ar_review()` are new exports.
* `hz` and `ac` now record their exhibits and a Methods paragraph for `ar`
  reports. Jobs rendered before this record none; render them again to cite
  them.
```

- [ ] **Step 8: Run the tests, lint and the full check**

Run: `R CMD INSTALL -l "$TMPDIR/arlib" . && R_LIBS="$TMPDIR/arlib" NOT_CRAN=true Rscript -e 'devtools::test(filter = "ar-|exhibits|ac-template|add-job|roadmap|taxonomy")'`
Expected: PASS, `SKIP 0` with Quarto present.

Run: `Rscript -e 'lintr::lint_package()'`
Expected: no lints.

Run: `Rscript -e 'devtools::check()'`
Expected: 0 errors, 0 warnings, 0 notes.

- [ ] **Step 9: Commit**

```bash
git add inst/templates/50_documents/ar.qmd inst/extdata/templates.json .lintr inst/templates/README.md \
  tests/testthat/test-ar-template.R news/<branch>.md
git commit -m "ar: the analysis report template, in flight"
```

---

### Task 7: Gallery entry

**Files:**
- Modify: `dev/gallery/gallery.R` (`gallery_job()`)
- Modify: `dev/gallery/family-hazard.R` (a new `ar` job after `hp`)

**Interfaces:**
- Consumes: the hazard family's `hz` and `ac` jobs, subject `"dead"`, type `"hz"`.

- [ ] **Step 1: Give jobs a hook that runs after their choices.** `prepare()` runs before `set_choices()`, and `ar_paste_methods()` must read the item ids the choices write. In `gallery_job()`, replace the last line, `set_choices(job, spec$choices %||% list())`, with:

```r
  job <- set_choices(job, spec$choices %||% list())
  if (!is.null(spec$finish)) spec$finish(root, job)
  job
```

Confirm first that `set_choices()` (in `dev/demo/demo-study.R`) returns the job path. If it returns something else, keep `job` from `add_job()` and pass that.

- [ ] **Step 2: Add the job** to the hazard family's `jobs` list, after `hp`:

```r
    ar = list(
      subject = "dead", type = "question",
      choices = list(
        "^QUESTION <- " = "QUESTION <- \"Does the early hazard of death differ from the late hazard?\"",
        "^hvtiRtemplates::ar_item\\(\"hz.dead_pa.hz#fig-fit\"\\)$" = "hvtiRtemplates::ar_item(\"hz.dead.hz#fig-fit\")",
        "^hvtiRtemplates::ar_item\\(\"hz.dead_pa.hz#tbl-estimates\"\\)$" =
          "hvtiRtemplates::ar_item(\"hz.dead.hz#tbl-estimates\")"
      ),
      finish = function(root, job) hvtiRtemplates::ar_paste_methods(job)
    ),
```

- [ ] **Step 3: Build the gallery** in a temp directory and read the `ar` page:

Run: `d=$(mktemp -d) && Rscript dev/gallery/gallery.R "$d"`
Expected: the `ar` row reports a rendered page. Open it. The two items show the figure and the table, the Methods slots hold the `hz` paragraph, and the only callouts are the ones the unwritten Results text explains.

- [ ] **Step 4: Commit**

```bash
git add dev/gallery/gallery.R dev/gallery/family-hazard.R
git commit -m "Gallery: an ar report over the hazard family"
```

---

## Before opening the pull request

- [ ] Run `/code-review` locally, and say in the PR body that it stood in for Copilot if the reviews command reads `quota=true`.
- [ ] Read the `testthat` summary lines in CI, not the check marks: `gh run view <id> --log | grep -E "SKIP [0-9]+ \| PASS"`.
- [ ] The Windows sweep is not a PR gate. `.ar_relative()` and `Sys.glob()` paths are exercised only there, so dispatch `R-CMD-check.yaml` once before merge.
