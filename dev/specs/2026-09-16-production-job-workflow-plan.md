# Production Job Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A biostatistician goes from an adopted study to a rendered job with three calls (`migrate_job()` or `open_job()`, then `render_job()`), creating no support file and setting no path or environment variable by hand.

**Architecture:** Templates find the study root through `_study.yml` via `hvtiRutilities::study_root()`, started from the rendered file's directory. Two thin exported wrappers, `open_job()` over `add_job()` and `render_job()` over `quarto::quarto_render()`, carry the ceremony. `migrate_job()` on #120 infers its template from the SAS filename and falls back to a plain scaffold where no converter exists.

**Tech Stack:** R, roxygen2 (Rd markup, not markdown), testthat 3e, Quarto, `hvtiRutilities`.

Spec: [`2026-09-16-production-job-workflow-design.md`](2026-09-16-production-job-workflow-design.md).

## Global Constraints

- Versions are three digits. No bump in a feature PR: entries go under `# hvtiRtemplates (unreleased)` (or `# hvtiRutilities (unreleased)`) in `NEWS.md`; the bump is a separate commit by the maintainer's call. Patch digit only.
- Never push to `main`. One branch and PR per delivery row in spec §7. Merge `origin/main`, not local `main`.
- Roxygen is Rd markup: `\code{}`, `\strong{}`, `\link{}`. No backticks in roxygen.
- Lines up to 135 characters (`.lintr`). `lintr::lint_package()` must be clean.
- No new `Imports`. `quarto` is already in `Suggests`; `withr` is NOT, so restore state with `on.exit()` or `tryCatch(finally =)`.
- `hvtiRutilities (>= 1.1.12)` already provides `study_root()`; do not raise the floor in PR 2.
- Templates carry no study identifiers. Tests use temporary studies, never `/studies`.
- A template must keep exactly one `^ENDPOINT\s+<- ` and one `^TYPE\s+<- ` line.
- No template may contain the edit-marker token as a quoted literal (see `test-templates.R`, "no template writes the edit marker token literally").
- Every new test is proven by mutation: revert the change it guards and confirm it fails.
- Definition of done per PR: `devtools::document()` committed, `devtools::test()` passes, `devtools::check()` 0/0/0, `/code-review` run locally and stated in the PR body.

---

## PR 1: hvtiRutilities writes an R project

Repository: `~/Documents/GitHub/hvtiRutilities`. Branch: `feat/study-setup-rproj` from `origin/main`.

### Task 1: `study_setup()` writes `<basename>.Rproj`

**Files:**
- Modify: `R/study_setup.R` (after the `.renvignore` write, before `study_status(root)`)
- Modify: `R/study_setup.R` roxygen `@details` for `study_setup()`
- Test: `tests/testthat/test-study_setup.R`
- Modify: `NEWS.md`

**Interfaces:**
- Consumes: existing `.study_write_lines_if_missing(lines, path)`.
- Produces: after `study_setup(root, ...)`, `list.files(root, "[.]Rproj$")` has length >= 1. Later PRs rely only on this.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-study_setup.R`:

```r
test_that("study_setup writes an R project named for the study directory", {
  root <- file.path(tempfile("rproj-"), "bio_example")
  on.exit(unlink(dirname(root), recursive = TRUE), add = TRUE)
  suppressMessages(study_setup(root, study = "Rproj test", study_tracker_id = 1L))

  proj <- file.path(root, "bio_example.Rproj")
  expect_true(file.exists(proj))
  expect_identical(readLines(proj, n = 1L), "Version: 1.0")
})

test_that("study_setup leaves an existing R project alone", {
  root <- tempfile("rproj-existing-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  suppressMessages(study_setup(root, study = "Rproj adopt", study_tracker_id = 2L))
  unlink(list.files(root, "[.]Rproj$", full.names = TRUE))
  writeLines("Version: 1.0\n\nRestoreWorkspace: Yes", file.path(root, "mine.Rproj"))

  suppressMessages(study_setup(root, study = "Rproj adopt", study_tracker_id = 2L, adopt = TRUE))

  expect_identical(list.files(root, "[.]Rproj$"), "mine.Rproj")
  expect_identical(readLines(file.path(root, "mine.Rproj"))[[3L]], "RestoreWorkspace: Yes")
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'devtools::test(filter = "study_setup")'`
Expected: the first test FAILS (`file.exists(proj)` is FALSE). The second PASSES now, because nothing writes a project yet, and must still pass after Step 3; it guards against a second project being written beside an author's own.

- [ ] **Step 3: Implement**

In `R/study_setup.R`, immediately before `study_status(root)`:

```r
  # An R project beside _study.yml means opening the project, here::here()
  # and study_root() all name the same directory. An existing project, of
  # any name, is the author's and is left alone.
  if (!length(list.files(root, pattern = "[.]Rproj$"))) {
    .study_write_lines_if_missing(
      c("Version: 1.0", "", "RestoreWorkspace: No", "SaveWorkspace: No",
        "AlwaysSaveHistory: No", "", "EnableCodeIndexing: Yes",
        "Encoding: UTF-8"),
      file.path(root, paste0(basename(root), ".Rproj"))
    )
  }
```

Add to the `study_setup()` roxygen `@details`:

```r
#' When the root holds no \code{.Rproj} file, one named for the root
#' directory is written, so that opening the project and
#' \code{\link{study_root}} agree on the study root. An existing project is
#' left unchanged.
```

- [ ] **Step 4: Run to verify pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "study_setup")'`
Expected: PASS. Then mutate: delete the `if` block, rerun, confirm the first test fails; restore.

- [ ] **Step 5: NEWS, check, commit**

Add under `# hvtiRutilities (unreleased)` at the top of `NEWS.md` (create the heading if absent):

```markdown
* `study_setup()` writes `<study>.Rproj` when the root has no R project, so
  opening the project, `here::here()` and `study_root()` name the same
  directory. An existing project is left alone.
```

Run: `Rscript -e 'devtools::check()'` → 0 errors, 0 warnings, 0 notes.

```bash
git add R/study_setup.R man/study_setup.Rd tests/testthat/test-study_setup.R NEWS.md
git commit -m "feat: study_setup() writes an R project beside _study.yml"
```

Open the PR against `main`; body states `/code-review` stood in for the bot.

---

## PR 2: hvtiRtemplates root lookup, `open_job()`, `render_job()`

Repository: this one. Branch: `feat/production-job-workflow` from `origin/main`.

### Task 2: Templates find the root through `_study.yml`

**Files:**
- Modify: the `.root` block in all 13 files under `inst/templates/*/` (listed by `template_list()$file`)
- Test: `tests/testthat/test-templates.R`

**Interfaces:**
- Produces: every template's `setup` chunk defines `.root` as the absolute study root; nothing else in the templates changes.

Every template holds this exact six-line block (comment lines above it vary and stay):

```r
.root <- if (file.exists("_quarto.yml")) "." else ".."
if (!file.exists(file.path(.root, "_quarto.yml"))) {
  stop("Neither . nor .. contains _quarto.yml, so the project root cannot be ",
       "resolved. Render this from the project root or from the job directory.",
       call. = FALSE)
}
```

It becomes:

```r
.in <- knitr::current_input(dir = TRUE)
.root <- hvtiRutilities::study_root(if (is.null(.in)) getwd() else dirname(.in))
```

`knitr::current_input()` is `NULL` when a chunk is run interactively, where RStudio's working directory is the document's directory, hence the `getwd()` fallback. The comment above each block ("This file runs either from the directory it was scaffolded into or from the project root...") is replaced by:

```r
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
```

The `format:` comment in each YAML header that mentions `_quarto.yml` is unrelated and stays.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-templates.R`:

```r
test_that("no template resolves its root from _quarto.yml", {
  tl <- template_list()
  skip_if(nrow(tl) == 0L, "no templates installed")
  for (f in tl$file) {
    src <- readLines(f, warn = FALSE)
    expect_false(any(grepl("file.exists(\"_quarto.yml\")", src, fixed = TRUE)), info = basename(f))
    expect_true(any(grepl("hvtiRutilities::study_root(", src, fixed = TRUE)), info = basename(f))
  }
})

test_that("every template's root resolves to the study from any depth", {
  # Runs each template's own root lines with knitr::current_input() mocked to
  # a job file two levels below the study, then with it NULL (interactive
  # chunk execution) from a working directory inside the study.
  skip_if_not_installed("knitr")
  tl <- template_list()
  skip_if(nrow(tl) == 0L, "no templates installed")

  root <- tempfile("root-lookup-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  suppressMessages(hvtiRutilities::study_setup(root, study = "Root lookup", study_tracker_id = 1L))
  root <- normalizePath(root)
  deep <- file.path(root, "30_analyses", "sub")
  dir.create(deep, recursive = TRUE)
  job <- file.path(deep, "job.qmd")

  root_code <- function(f) {
    src <- readLines(f, warn = FALSE)
    i <- grep("^\\.in <- knitr::current_input", src)
    src[c(i, i + 1L)]
  }
  input <- job
  local_mocked_bindings(current_input = function(...) input, .package = "knitr")
  for (f in tl$file) {
    code <- root_code(f)
    expect_length(code, 2L)
    env <- new.env()
    input <- job
    eval(parse(text = code), envir = env)
    expect_identical(normalizePath(env$.root), root, info = basename(f))

    input <- NULL
    old <- setwd(deep)
    tryCatch(eval(parse(text = code), envir = env), finally = setwd(old))
    expect_identical(normalizePath(env$.root), root, info = paste(basename(f), "interactive"))
  }
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-templates.R")'`
Expected: both new tests FAIL (the pattern is present; `root_code()` finds no `.in` line).

- [ ] **Step 3: Replace the block in all 13 templates**

Run this once from the repo root; it refuses to write a file whose block does not match exactly:

```bash
Rscript -e '
old <- c(
  ".root <- if (file.exists(\"_quarto.yml\")) \".\" else \"..\"",
  "if (!file.exists(file.path(.root, \"_quarto.yml\"))) {",
  "  stop(\"Neither . nor .. contains _quarto.yml, so the project root cannot be \",",
  "       \"resolved. Render this from the project root or from the job directory.\",",
  "       call. = FALSE)",
  "}")
new <- c(".in <- knitr::current_input(dir = TRUE)",
         ".root <- hvtiRutilities::study_root(if (is.null(.in)) getwd() else dirname(.in))")
for (f in Sys.glob("inst/templates/*/*.qmd")) {
  x <- readLines(f, warn = FALSE)
  i <- which(x == old[1])
  stopifnot(length(i) == 1L, identical(x[i:(i + 5L)], old))
  x <- c(x[seq_len(i - 1L)], new, x[(i + 6L):length(x)])
  writeLines(x, f)
  cat("updated", f, "\n")
}'
```

Expected: 13 `updated` lines. Then, in each file, replace the "This file runs either from the directory it was scaffolded into or from the project root..." comment lines directly above `.in <-` with the three-line comment given above, by hand, and read each diff.

- [ ] **Step 4: Run to verify pass**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-templates.R"); testthat::test_file("tests/testthat/test-add-job.R"); testthat::test_file("tests/testthat/test-template-data-routes.R")'`
Expected: PASS. Mutate one template back to the old block and confirm both new tests name it; restore.

- [ ] **Step 5: Verify under a real render (decides the line)**

Run a server-shaped render from outside the study, using `ac` (no optional packages needed past `setup`):

```bash
Rscript -e '
root <- tempfile("render-probe-"); hvtiRutilities::study_setup(root, study = "Probe", study_tracker_id = 1L)
job <- hvtiRtemplates::add_job("ac", "probe", "eda", dir = root)
txt <- readLines(job); i <- grep("^\\.root <- ", txt)
writeLines(c(txt[1:i], "cat(\"ROOT=\", .root, \"\\n\"); knitr::knit_exit()", txt[(i + 1):length(txt)]), job)
setwd(tempdir()); quarto::quarto_render(job, execute_dir = dirname(job), quiet = FALSE)'
```

Expected: the log prints `ROOT= <root>` (normalized path of `root`). If it errors in `study_root()`, record the value of `knitr::current_input(dir = TRUE)` from the log, replace the two-line lookup in all templates with one that works, and update spec §4.1 before continuing.

- [ ] **Step 6: Lint and commit**

Run: `Rscript -e 'lintr::lint_package()'` → no lints.

```bash
git add inst/templates tests/testthat/test-templates.R
git commit -m "feat: templates find the study root through _study.yml"
```

### Task 3: `open_job()`

**Files:**
- Create: `R/open-job.R`
- Test: `tests/testthat/test-open-job.R`

**Interfaces:**
- Consumes: `add_job(prefix, endpoint, type, dir, qualifier)`; internal `.select_template(template_list(), prefix, qualifier)`; `hvtiRutilities::study_root()`, `hvtiRutilities::study_dir()`.
- Produces: `open_job(prefix, endpoint, type, qualifier = NULL, dir = ".")` returning the job path invisibly; internal `.open_in_editor(path)` returning `invisible(path)`, reused by Task 7.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-open-job.R`:

```r
new_study <- function(pattern) {
  root <- tempfile(pattern)
  suppressMessages(hvtiRutilities::study_setup(root, study = "Open job test", study_tracker_id = 1L))
  normalizePath(root)
}

test_that("open_job creates a missing job under the study root found from a subdirectory", {
  root <- new_study("openjob-new-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)

  out <- open_job("ac", "dead", "eda", dir = file.path(root, "20_distributions"))

  expect_identical(out, file.path(root, "20_distributions", "dead-eda-ac.qmd"))
  expect_true(file.exists(out))
})

test_that("open_job opens an existing job without changing it", {
  root <- new_study("openjob-existing-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  first <- open_job("ac", "dead", "eda", dir = root)
  writeLines("worked on", first)

  expect_message(again <- open_job("ac", "dead", "eda", dir = root), "already exists")

  expect_identical(again, first)
  expect_identical(readLines(first), "worked on")
})

test_that("open_job refuses an ambiguous prefix", {
  root <- new_study("openjob-ambiguous-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  expect_error(open_job("dc", "dead", "eda", dir = root), "open_job\\(\\):")
})

test_that("open_job outside a study names study_setup", {
  dir <- tempfile("openjob-nostudy-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  expect_error(open_job("ac", "dead", "eda", dir = dir), "_study.yml")
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-open-job.R")'`
Expected: FAIL, `could not find function "open_job"`.

- [ ] **Step 3: Implement**

Create `R/open-job.R`:

```r
#' Open a job, creating it from its template if needed
#'
#' @description
#' Finds the study root from \code{dir}, creates the job with
#' \code{\link{add_job}} when it does not exist, and opens it in the editor.
#' An existing job is opened as it stands, never overwritten.
#'
#' @details
#' The study root is the nearest directory at or above \code{dir} holding
#' \code{_study.yml}, so this can be called from anywhere inside a study.
#' Naming, prefix and qualifier rules are those of \code{\link{add_job}}.
#' The editor is opened only in an interactive session.
#'
#' @inheritParams add_job
#' @param dir Character. Any directory inside the study. Defaults to the
#'   working directory.
#'
#' @return The path to the job file, invisibly.
#'
#' @seealso \code{\link{add_job}}, \code{\link{render_job}}
#' @examples
#' root <- file.path(tempdir(), "open-job-example")
#' hvtiRutilities::study_setup(root, study = "Example", study_tracker_id = 1L)
#' open_job("ac", "dead", "eda", dir = root)
#' unlink(root, recursive = TRUE)
#' @export
open_job <- function(prefix, endpoint, type, qualifier = NULL, dir = ".") {
  root <- hvtiRutilities::study_root(dir)
  row <- tryCatch(
    .select_template(template_list(), prefix, qualifier),
    error = function(e) stop("open_job(): ", conditionMessage(e), call. = FALSE)
  )
  .check_field("endpoint", endpoint)
  .check_field("type", type)
  stem <- paste0(endpoint, "-", type, "-", prefix,
                 if (!is.na(row$qualifier[[1L]])) paste0("-", row$qualifier[[1L]]) else "")
  out <- file.path(hvtiRutilities::study_dir(row$folder[[1L]], root = root), paste0(stem, ".qmd"))
  if (file.exists(out)) {
    message("open_job(): '", out, "' already exists; opening it unchanged.")
  } else {
    out <- add_job(prefix, endpoint, type, dir = root, qualifier = qualifier)
  }
  .open_in_editor(out)
}

# utils::file.edit() opens the RStudio source pane when RStudio is running and
# the configured editor otherwise, with no dependency on rstudioapi.
.open_in_editor <- function(path) {
  if (interactive()) utils::file.edit(path)
  invisible(path)
}
```

- [ ] **Step 4: Run to verify pass**

Run: `Rscript -e 'devtools::document(); devtools::load_all(); testthat::test_file("tests/testthat/test-open-job.R")'`
Expected: PASS. Mutate: drop the `file.exists(out)` branch; the "existing" test must fail. Restore.

- [ ] **Step 5: Commit**

```bash
git add R/open-job.R man/open_job.Rd NAMESPACE tests/testthat/test-open-job.R
git commit -m "feat: open_job() finds the study root and opens or creates a job"
```

### Task 4: `render_job()`

**Files:**
- Create: `R/render-job.R`
- Test: `tests/testthat/test-render-job.R`

**Interfaces:**
- Consumes: `quarto::quarto_render(input, execute_dir, quiet)` (Suggests).
- Produces: `render_job(path, final = FALSE, quiet = FALSE)` returning `path` invisibly.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-render-job.R`. The render itself is mocked; what is under test is the environment the render sees and its restoration.

```r
test_that("render_job drafts by default and sets strict only for a final render", {
  skip_if_not_installed("quarto")
  job <- tempfile(fileext = ".qmd")
  writeLines("x", job)
  on.exit(unlink(job), add = TRUE)
  seen <- list()
  local_mocked_bindings(
    quarto_render = function(input, execute_dir, ...) {
      seen[[length(seen) + 1L]] <<- list(strict = Sys.getenv("HVTI_TEMPLATE_STRICT", NA), dir = execute_dir)
    },
    .package = "quarto"
  )
  old <- Sys.getenv("HVTI_TEMPLATE_STRICT", unset = NA)
  Sys.setenv(HVTI_TEMPLATE_STRICT = "0")
  on.exit(if (is.na(old)) Sys.unsetenv("HVTI_TEMPLATE_STRICT") else Sys.setenv(HVTI_TEMPLATE_STRICT = old), add = TRUE)

  render_job(job)
  render_job(job, final = TRUE)

  expect_identical(seen[[1L]]$strict, "0")
  expect_identical(seen[[2L]]$strict, "1")
  expect_identical(seen[[2L]]$dir, dirname(normalizePath(job, winslash = "/")))
  expect_identical(Sys.getenv("HVTI_TEMPLATE_STRICT"), "0")
})

test_that("render_job restores the environment when the render fails", {
  skip_if_not_installed("quarto")
  job <- tempfile(fileext = ".qmd")
  writeLines("x", job)
  on.exit(unlink(job), add = TRUE)
  local_mocked_bindings(quarto_render = function(...) stop("unresolved EDIT markers"), .package = "quarto")
  old <- Sys.getenv("HVTI_TEMPLATE_STRICT", unset = NA)
  Sys.unsetenv("HVTI_TEMPLATE_STRICT")
  on.exit(if (is.na(old)) Sys.unsetenv("HVTI_TEMPLATE_STRICT") else Sys.setenv(HVTI_TEMPLATE_STRICT = old), add = TRUE)

  expect_error(render_job(job, final = TRUE), "unresolved")
  expect_true(is.na(Sys.getenv("HVTI_TEMPLATE_STRICT", unset = NA)))
})

test_that("render_job rejects a missing file and a non-logical final", {
  expect_error(render_job(tempfile(fileext = ".qmd")), "render_job\\(\\):")
  job <- tempfile(fileext = ".qmd")
  writeLines("x", job)
  on.exit(unlink(job), add = TRUE)
  expect_error(render_job(job, final = "yes"), "render_job\\(\\):")
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-render-job.R")'`
Expected: FAIL, `could not find function "render_job"`.

- [ ] **Step 3: Implement**

Create `R/render-job.R`:

```r
#' Render a job
#'
#' @description
#' Renders a job from its own directory. By default the render is a draft:
#' open \code{EDIT:} markers appear in the report's DRAFT banner. With
#' \code{final = TRUE} an unfinished job stops instead, as the render of an
#' accepted result should.
#'
#' @details
#' \code{final = TRUE} sets \code{HVTI_TEMPLATE_STRICT} to \code{1} for this
#' render only and restores its previous value afterwards, including after an
#' error. The job's own edit guard decides whether it is finished; this
#' function does not search for markers itself, so it cannot disagree with a
#' render started from the editor or from Quarto.
#'
#' @param path Character. Path to a job \code{.qmd} file.
#' @param final Logical. \code{TRUE} for the accepted result.
#' @param quiet Logical. Passed to \code{quarto::quarto_render()}.
#'
#' @return \code{path}, invisibly.
#'
#' @seealso \code{\link{open_job}}
#' @export
render_job <- function(path, final = FALSE, quiet = FALSE) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path)) {
    stop("render_job(): `path` must be an existing job file.", call. = FALSE)
  }
  if (!is.logical(final) || length(final) != 1L || is.na(final)) {
    stop("render_job(): `final` must be TRUE or FALSE.", call. = FALSE)
  }
  if (!requireNamespace("quarto", quietly = TRUE)) {
    stop("render_job(): the quarto package is required; install.packages(\"quarto\").", call. = FALSE)
  }
  path <- normalizePath(path, winslash = "/")
  if (final) {
    old <- Sys.getenv("HVTI_TEMPLATE_STRICT", unset = NA)
    on.exit(if (is.na(old)) Sys.unsetenv("HVTI_TEMPLATE_STRICT") else Sys.setenv(HVTI_TEMPLATE_STRICT = old),
            add = TRUE)
    Sys.setenv(HVTI_TEMPLATE_STRICT = "1")
  }
  quarto::quarto_render(path, execute_dir = dirname(path), quiet = quiet)
  invisible(path)
}
```

- [ ] **Step 4: Run to verify pass**

Run: `Rscript -e 'devtools::document(); devtools::load_all(); testthat::test_file("tests/testthat/test-render-job.R")'`
Expected: PASS. Mutate: remove the `on.exit()` line; the failure test must go red. Restore.

- [ ] **Step 5: Commit**

```bash
git add R/render-job.R man/render_job.Rd NAMESPACE tests/testthat/test-render-job.R
git commit -m "feat: render_job() renders a draft or, with final = TRUE, a strict result"
```

### Task 5: Documentation, NEWS and the PR 2 gate

**Files:**
- Modify: `AGENTS.md` (opening export list: "Five exports across three source files" becomes "Seven exports across five source files", adding `open_job()` and `render_job()`)
- Modify: `inst/templates/README.md` (any instruction to create `_quarto.yml` or to render from the root or job directory is replaced by "render with `render_job()`, the Render button, or `quarto render`; the root is found through `_study.yml`")
- Modify: `vignettes/sas-to-r-descriptive.qmd` (any `add_job(..., dir = root)` + `quarto_render()` sequence becomes `open_job()` + `render_job()`)
- Modify: `NEWS.md`
- Modify: `.github/workflows/R-CMD-check.yaml` only if a new test reads the job catalog (none in this plan does)

- [ ] **Step 1: Find every stale instruction**

Run: `grep -rn "_quarto.yml\|quarto_render\|HVTI_TEMPLATE_DRAFT\|dir = root" README.md inst/templates/README.md vignettes AGENTS.md`
Expected: a list; each hit that describes root resolution, the draft variable, or the render sequence is rewritten as above. Hits about the `format:` block stay.

- [ ] **Step 2: NEWS**

Under `# hvtiRtemplates (unreleased)`:

```markdown
* **Templates find the study root through `_study.yml`.** Each template called
  `hvtiRutilities::study_root()` in place of looking for `_quarto.yml` in `.`
  or `..`, so a study needs no `_quarto.yml`, and a job renders the same from
  the Render button, `quarto render` or `render_job()`, at any depth. A study
  must have been adopted with `hvtiRutilities::study_setup()`.
* `open_job()` finds the study root from any directory inside it, creates the
  job with `add_job()` if it is missing, and opens it in the editor. An
  existing job is opened unchanged.
* `render_job()` renders a job from its own directory: a draft by default,
  and with `final = TRUE` a render that stops on an unfinished job.
```

- [ ] **Step 3: Full gate**

Run: `Rscript -e 'devtools::document(); devtools::test(); devtools::check()'`
Expected: tests PASS, check 0/0/0. Run `lintr::lint_package()`: clean. Run `python3 dev/specs/artifacts/check-spec-counts.py`, `check-flow-counts.py`, `check-roadmap-counts.py`: all exit 0.

- [ ] **Step 4: Commit, review, PR**

```bash
git add AGENTS.md inst/templates/README.md vignettes NEWS.md
git commit -m "docs: teach open_job() and render_job() and the _study.yml root"
```

Run `/code-review` locally; fix findings. Push, open the PR against `main`, state in the body that the local review ran. After CI, read every step's `SKIP n | PASS n` line.

---

## PR 3: `migrate_job()` on #120

Worktree: `/private/tmp/hvtiRtemplates-legacy-migration`, branch `codex/legacy-study-template-migration`. Precondition: PR 2 merged.

### Task 6: Bring #120 up to date with `main`

**Files:** the 14 conflicted files (`DESCRIPTION`, `NAMESPACE`, `NEWS.md`, `R/add-job.R`, `README.md`, `inst/templates/10_descriptive/dc-gfup.qmd`, `dc-tables.qmd`, `dp-postage.qmd`, `inst/templates/40_graphs/dp-trends.qmd`, `inst/templates/README.md`, `man/add_job.Rd`, `tests/testthat/test-add-job.R`, `test-template-data-routes.R`, `test-templates.R`).

- [ ] **Step 1: Merge**

```bash
cd /private/tmp/hvtiRtemplates-legacy-migration && git fetch origin && git merge origin/main
```

- [ ] **Step 2: Resolve by rule**

- Templates: take `main`'s setup chunk (the `_study.yml` root, #119's edit guard, `DATASET`) and keep the branch's `# MIGRATE-BEGIN:` / `# MIGRATE-END:` region markers and their contents.
- `NAMESPACE`, `man/`: take either side, then regenerate with `devtools::document()`.
- `DESCRIPTION`: keep `main`'s `Version:`; union the `Imports`/`Suggests` (the branch adds `digest`).
- `NEWS.md`: one `# hvtiRtemplates (unreleased)` heading holding both sides' entries.
- Tests: keep both sides' tests; where they assert the same thing differently, `main` wins.

- [ ] **Step 3: Verify and commit**

Run: `Rscript -e 'devtools::document(); devtools::test()'`
Expected: PASS. Then `grep -rn "HVTI_TEMPLATE_DRAFT\|_quarto.yml\")" R inst vignettes tests` returns nothing.

```bash
git add -A && git commit -m "merge: bring the migration branch up to date with main"
```

### Task 7: Infer the template, find the root and the evidence

**Files:**
- Modify: `R/migrate-job.R` (`migrate_job()` signature and head; new `.infer_template()`, `.default_evidence()`)
- Test: `tests/testthat/test-migrate-job.R` (existing file on the branch; add tests)

**Interfaces:**
- Consumes: `.select_template()`, `.check_field()`, `.check_scalar_string()`, `.open_in_editor()` (Task 3), `hvtiRutilities::study_root()`.
- Produces: `migrate_job(source, endpoint, type, prefix = NULL, qualifier = NULL, lst = NULL, log = NULL, reference = NULL, dir = NULL)`; `.infer_template(source, prefix, qualifier)` returning `list(prefix = chr, qualifier = chr or NULL)`; `.default_evidence(source, suffix)` returning a path or `NULL`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/testthat/test-migrate-job.R`:

```r
test_that(".infer_template reads prefix and qualifier from a corpus job name", {
  expect_identical(.infer_template("x/dc.tables.ods.sas", NULL, NULL), list(prefix = "dc", qualifier = "tables"))
  expect_identical(.infer_template("x/ac.dead.sas", NULL, NULL), list(prefix = "ac", qualifier = NULL))
  expect_identical(.infer_template("x/odd_name.sas", "dp", "trends"), list(prefix = "dp", qualifier = "trends"))
})

test_that(".infer_template refuses a qualified prefix it cannot resolve", {
  expect_error(.infer_template("x/dc.custom.sas", NULL, NULL), "tables")
  expect_error(.infer_template("x/oddname.sas", NULL, NULL), "prefix")
})

test_that(".default_evidence finds a same-stem listing and log", {
  d <- tempfile("evidence-")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  src <- file.path(d, "dc.tables.ods.sas")
  file.create(src, file.path(d, "dc.tables.ods.lst"))
  expect_identical(.default_evidence(src, "lst"), file.path(d, "dc.tables.ods.lst"))
  expect_null(.default_evidence(src, "log"))
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-migrate-job.R")'`
Expected: FAIL, `could not find function ".infer_template"`.

- [ ] **Step 3: Implement**

In `R/migrate-job.R`, add:

```r
# A corpus job is <prefix>.<variable>[.<more>].sas. For a prefix with
# qualified templates the second field must name one of them; otherwise the
# choice is the author's, and guessing is the defect add_job() refuses.
.infer_template <- function(source, prefix, qualifier) {
  if (!is.null(prefix)) return(list(prefix = prefix, qualifier = qualifier))
  fields <- strsplit(basename(source), ".", fixed = TRUE)[[1L]]
  tl <- template_list()
  if (length(fields) < 3L || !fields[[1L]] %in% tl$prefix) {
    stop("migrate_job(): cannot read a template prefix from '", basename(source),
         "'; pass `prefix` (and `qualifier`).", call. = FALSE)
  }
  prefix <- fields[[1L]]
  quals <- tl$qualifier[tl$prefix == prefix]
  if (all(is.na(quals))) return(list(prefix = prefix, qualifier = NULL))
  if (fields[[2L]] %in% quals) return(list(prefix = prefix, qualifier = fields[[2L]]))
  stop("migrate_job(): '", basename(source), "' does not name a ", prefix, " template; pass `qualifier` as one of: ",
       paste(sort(quals), collapse = ", "), ".", call. = FALSE)
}

.default_evidence <- function(source, suffix) {
  path <- sub("[.][^.]+$", paste0(".", suffix), source)
  if (file.exists(path)) path else NULL
}
```

Replace the head of `migrate_job()` up to and including `adapter <- .migration_adapter(prefix, qualifier)` with:

```r
migrate_job <- function(source, endpoint, type, prefix = NULL, qualifier = NULL,
                        lst = NULL, log = NULL, reference = NULL, dir = NULL) {
  .check_field("endpoint", endpoint)
  .check_field("type", type)
  .check_scalar_string("source", source)
  if (!file.exists(source)) stop("migrate_job(): source not found: ", source, call. = FALSE)
  source <- normalizePath(source, winslash = "/")
  if (!is.null(prefix)) .check_field("prefix", prefix)
  if (!is.null(qualifier)) .check_field("qualifier", qualifier)
  root <- if (is.null(dir)) hvtiRutilities::study_root(dirname(source)) else hvtiRutilities::study_root(dir)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  for (arg in c("lst", "log")) {
    given <- get(arg)
    if (!is.null(given)) {
      .check_scalar_string(arg, given)
      if (!file.exists(given)) stop("migrate_job(): `", arg, "` not found: ", given, call. = FALSE)
    }
  }
  if (is.null(lst)) lst <- .default_evidence(source, "lst")
  if (is.null(log)) log <- .default_evidence(source, "log")
  if (!is.null(reference) && (!is.character(reference) || !length(reference) ||
                                anyNA(reference) || any(!nzchar(reference)))) {
    stop("migrate_job(): `reference` must contain existing file paths.", call. = FALSE)
  }
  tpl <- .infer_template(source, prefix, qualifier)
  prefix <- tpl$prefix
  qualifier <- tpl$qualifier
  paths <- c(source = source, lst = lst, log = log, reference = reference)
  paths <- vapply(paths, .migration_path, character(1L), root = root)
  row <- tryCatch(
    .select_template(template_list(), prefix, qualifier),
    error = function(e) stop("migrate_job(): ", conditionMessage(e), call. = FALSE)
  )
  adapter <- .migration_adapter(prefix, qualifier)
```

Update the roxygen `@param` entries: `prefix`, `qualifier` ("read from the SAS filename when \code{NULL}"), `lst`, `log` ("defaults to the same-named file beside \code{source} when present"), `dir` ("any directory in the study; defaults to the directory of \code{source}").

- [ ] **Step 4: Run to verify pass**

Run: `Rscript -e 'devtools::document(); devtools::load_all(); testthat::test_file("tests/testthat/test-migrate-job.R")'`
Expected: new tests PASS. Existing tests that passed `prefix`, `dir = root`, `lst`, `log` explicitly still PASS; any that relied on `dir = "."` defaulting to the working directory are updated to pass `dir` or to run inside a `study_setup()` study.

- [ ] **Step 5: Commit**

```bash
git add R/migrate-job.R man/migrate_job.Rd tests/testthat/test-migrate-job.R
git commit -m "feat: migrate_job() reads its template, root and evidence from the SAS job"
```

### Task 8: One path for templates without a converter

**Files:**
- Modify: `R/migrate-job.R` (`.migration_adapter()`, `.migration_finish()`, `.migration_report()`)
- Test: `tests/testthat/test-migrate-job.R`

**Interfaces:**
- Consumes: Task 7's `migrate_job()`; `.open_in_editor()`.
- Produces: `.migration_adapter(prefix, qualifier)` returns `.migrate_no_converter` for an unregistered key; `.migration_report(evidence, result, template, version, converter = TRUE)`.

- [ ] **Step 1: Write the failing test**

```r
test_that("migrate_job scaffolds a template with no converter and says so", {
  root <- tempfile("migrate-noconv-")
  suppressMessages(hvtiRutilities::study_setup(root, study = "No converter", study_tracker_id = 1L))
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  src <- file.path(root, "20_distributions", "ac.dead.sas")
  writeLines(c("proc lifetest data=built;", "run;"), src)

  out <- migrate_job(src, "dead", "eda")

  expect_identical(basename(out), "dead-eda-ac.qmd")
  tpl <- readLines(template_path("ac"), warn = FALSE)
  tok <- paste0("ED", "IT", ":")
  expect_identical(sum(grepl(tok, readLines(out), fixed = TRUE)), sum(grepl(tok, tpl, fixed = TRUE)))
  report <- readLines(sub("[.]qmd$", "-migration.md", out))
  expect_true(any(grepl("No converter: every choice is manual", report, fixed = TRUE)))
  expect_identical(readLines(src), c("proc lifetest data=built;", "run;"))
})
```

- [ ] **Step 2: Run to verify failure**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-migrate-job.R")'`
Expected: FAIL, "migration is not supported for ac".

- [ ] **Step 3: Implement**

Replace `.migration_adapter()`:

```r
.migration_adapter <- function(prefix, qualifier = NULL) {
  key <- .migration_key(prefix, qualifier)
  registry <- .migration_adapters()
  if (!key %in% names(registry)) return(.migrate_no_converter)
  get(registry[[key]], envir = asNamespace("hvtiRtemplates"), mode = "function", inherits = FALSE)
}

# A template without a converter still migrates: the scaffold keeps every
# EDIT: marker, and the evidence travels with the job for the manual port.
.migrate_no_converter <- function(evidence, lines) {
  none <- data.frame(item = character(), detail = character())
  list(regions = character(), translated = none, unresolved = none, ignored = none, converter = FALSE)
}
```

In `.migration_finish()`, change the report call to:

```r
  report <- .migration_report(evidence, result, template$name, converter = !isFALSE(result$converter))
```

and its last line to `.open_in_editor(template$out)`.

In `.migration_report()`, add `converter = TRUE` as the last parameter and, in the returned vector, directly after the `paste0("Template: hvtiRtemplates ", ...)` line and its `""`, insert:

```r
    if (!converter) c("**No converter: every choice is manual.** This template has no migration adapter yet; ",
                      "the job is the plain scaffold and the evidence below is for porting by hand.", "") else character(),
```

- [ ] **Step 4: Run to verify pass**

Run: `Rscript -e 'devtools::load_all(); devtools::test()'`
Expected: PASS, including every existing converter test. Mutate: make `.migration_adapter()` stop again; the new test fails. Restore.

- [ ] **Step 5: Commit**

```bash
git add R/migrate-job.R tests/testthat/test-migrate-job.R
git commit -m "feat: migrate_job() scaffolds templates that have no converter yet"
```

### Task 9: Vignette, NEWS and the PR 3 gate

**Files:**
- Modify: `vignettes/legacy-study-migration.qmd`
- Modify: `tests/testthat/test-vignette-migration.R` (only where it asserts the old call shapes)
- Modify: `NEWS.md`

- [ ] **Step 1: Rewrite the calls in the vignette**

Every `migrate_job(..., prefix = , qualifier = , lst = , log = , dir = root)` becomes the inferred form, for example:

```r
migrate_job(file.path(root, "descriptive", "dc.tables.sas"), "cohort", "eda",
            reference = file.path(root, "documents", "general.rtf"))
```

Every `quarto::quarto_render()` becomes `render_job(job)` for a draft and `render_job(job, final = TRUE)` for the accepted result. Delete any step creating `_quarto.yml`. Add one short section, "A job with no converter", showing `migrate_job()` on an `ac.<variable>.sas` file and the report's "No converter" line.

- [ ] **Step 2: NEWS**

Edit the branch's existing `migrate_job()` entry under `# hvtiRtemplates (unreleased)` so it says: the template is read from the SAS filename (`prefix`/`qualifier` override), the root from `_study.yml` above the source, the listing and log from same-named files beside it (`lst`/`log` override), and a template without a converter is scaffolded with every marker kept and a report saying so.

- [ ] **Step 3: Full gate**

Run: `Rscript -e 'devtools::document(); devtools::test(); devtools::check()'` → 0/0/0; `lintr::lint_package()` clean; the three `check-*-counts.py` scripts exit 0.

- [ ] **Step 4: Commit, review, mark ready**

```bash
git add vignettes tests NEWS.md
git commit -m "docs: teach migrate_job() as the single SAS-to-R path"
```

Run `/code-review` locally, paying attention to the patient-level withholding paths, which this PR has not yet had reviewed. Push, update the #120 body (remove the "not reviewed" and "conflicts" warnings, state the local review), then `gh pr ready 120`. Read every CI step's `SKIP n | PASS n` line.

---

## Maintainer step (not an agent task)

Before using PR 2's templates in production, remove the test jobs already scaffolded into production studies.
