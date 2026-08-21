# Template Set Layout — Stage 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `hvtiRtemplates` scaffold jobs into the study layout settled in
`specs/2026-08-21-template-set-layout-design.md` — taxonomy folder, flat authored
files, `<endpoint>-<type>-<NN.MM>-<prefix>.qmd`.

**Architecture:** The template's own filename becomes the authoritative source of
its ordinal and prefix, and its directory the source of its folder. Everything
`template_list()` reports is read off the filesystem; `hvti_taxonomy()` is demoted
from a lookup table that `template_list()` joins against to a cross-check that a
test enforces. `new_job()` composes the four scaffolded fields from the template's
two plus the caller's two.

**Tech Stack:** R package, roxygen2 (Rd markup, **not** markdown), testthat
edition 3, lintr, Quarto templates under `inst/templates/`.

## Global Constraints

- **Line length is 135**, not 80 (`.lintr`). Every other default linter is on.
- **Roxygen is Rd markup.** `DESCRIPTION` has no `Roxygen: list(markdown = TRUE)`.
  Use `\code{}`, `\strong{}`, `\emph{}`, `\itemize{}`, `\link{}` — backticks land
  literally in the `.Rd`.
- **A new/moved template needs its own `.lintr` key, and the key must be the FILE.**
  A directory key silently disables every linter on that path.
- **Templates carry no study identifiers** — no `/studies/`, no study name, no
  built-dataset filename. Enforced by `test-new-job.R`.
- **Version is three digits.** Bump the patch digit only: `1.0.2 → 1.0.3`. Never a
  `.9000` suffix or fourth digit.
- **`NEWS.md` uses plain `# hvtiRtemplates X.Y.Z` headings** — no `Version:` line.
- **Never push to `main`.** Work on `spec/template-set-layout`; the maintainer merges.
- **Definition of done:** `devtools::test()` passes, `devtools::check()` is 0/0/0,
  `devtools::document()` run with `man/` and `NAMESPACE` committed, and
  `lintr::lint_package()` clean.

## File Structure

| file | responsibility after this plan |
|---|---|
| `R/templates.R` | discovery: `.template_fields()` parses a template name; `template_list()` reads the tree; `template_path()` resolves a prefix |
| `R/new-job.R` | composition: turn a template plus `(endpoint, type)` into a written job file |
| `R/taxonomy.R` | **unchanged** — no longer joined against, only cross-checked |
| `inst/templates/distributions/03.01-ac.qmd` | the template, relocated and gaining `ENDPOINT`/`TYPE` |
| `tests/testthat/test-templates.R` | parser and discovery tests |
| `tests/testthat/test-new-job.R` | scaffolding tests |
| `tests/testthat/test-taxonomy.R` | the ordinal-vs-taxonomy cross-check |

`R/taxonomy.R` is deliberately untouched. All four §9 open items — the `hs`
misfiling, the missing `estimates` row, the `folder` column conflation, and whether
this warrants a minor — are the maintainer's calls and are **out of scope**.

---

### Task 1: `.template_fields()` — parse a template filename

Replaces `.prefix_of()`. That function splits on `.` and guesses (drop a leading
`tp.`, reject a first field longer than five characters) because legacy names were
unstructured. The new name is fully structured, and a split-based parser cannot
work on it anyway: `.` is now both a field separator *inside* the ordinal and the
extension separator.

**Files:**
- Modify: `R/templates.R:57-65` (replace `.prefix_of()`)
- Test: `tests/testthat/test-templates.R:21-32` (replace the `.prefix_of()` test)

**Interfaces:**
- Consumes: nothing.
- Produces: `.template_fields(name)` — takes `character(1)`, returns a one-row
  `data.frame` with `ordinal` (`character`, e.g. `"03.01"`) and `prefix`
  (`character`, e.g. `"ac"`). Both `NA_character_` when the name does not match.

- [ ] **Step 1: Write the failing test**

Replace the whole `test_that(".prefix_of() derives a prefix ...")` block at the end
of `tests/testthat/test-templates.R` with:

```r
test_that(".template_fields() parses a structured template name", {
  # A template is named "<NN>.<MM>-<prefix>.qmd". The name is parsed by pattern
  # rather than by splitting on separators, because `.` is both a field
  # separator inside the ordinal and the extension separator -- a split cannot
  # tell the two apart.
  expect_equal(hvtiRtemplates:::.template_fields("03.01-ac.qmd")$ordinal, "03.01")
  expect_equal(hvtiRtemplates:::.template_fields("03.01-ac.qmd")$prefix, "ac")
  expect_equal(hvtiRtemplates:::.template_fields("04.19-rfs.qmd")$prefix, "rfs")
})

test_that(".template_fields() returns NA for a name it cannot parse", {
  # NA rather than an error: template_list() reports what is on disk, and a
  # stray file should not stop it. The unclassified-prefix test in
  # test-taxonomy.R is what turns an unparsed name into a build failure.
  expect_true(is.na(hvtiRtemplates:::.template_fields("ac.qmd")$prefix))
  expect_true(is.na(hvtiRtemplates:::.template_fields("README.md")$prefix))
})

test_that(".template_fields() rejects an unpadded ordinal", {
  # The zero-padding is what makes `ls` sort a set in run order past nine
  # entries. Accepting "3.1" here would let an unsortable name into the tree
  # silently, so the parser is where the padding rule is enforced.
  expect_true(is.na(hvtiRtemplates:::.template_fields("3.1-ac.qmd")$ordinal))
  expect_true(is.na(hvtiRtemplates:::.template_fields("03.1-ac.qmd")$ordinal))
})
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test-templates.R")'
```

Expected: FAIL — `could not find function ".template_fields"`.

- [ ] **Step 3: Write the implementation**

In `R/templates.R`, delete the `.prefix_of()` function and its comment block
entirely, and put this in its place:

```r
# Parse a template file name into its fields.
#
# A template is named `<NN>.<MM>-<prefix>.qmd` -- "03.01-ac.qmd". The name is
# fully structured, so it is matched by pattern rather than split on separators:
# `.` is a field separator inside the ordinal AND the extension separator, and a
# split-based parser cannot tell the two apart. This replaces `.prefix_of()`,
# whose heuristics (drop a leading "tp.", reject a first field over five
# characters) existed only because legacy names were unstructured.
#
# The two digits either side of the dot are required. The zero-padding is what
# makes a flat folder sort into run order past nine entries, so an unpadded name
# is rejected here rather than allowed to sort wrongly later.
#
# Returns `ordinal` and `prefix` as NA for a name that does not match, rather
# than erroring: `template_list()` reports what is on disk, and a stray file
# should not stop it. `test-taxonomy.R` is what turns an unclassified prefix
# into a build failure.
.template_fields <- function(name) {
  m <- regmatches(name, regexec("^(\\d{2}[.]\\d{2})-(.+)[.]qmd$", name))[[1L]]
  if (length(m) != 3L) {
    return(data.frame(ordinal = NA_character_, prefix = NA_character_,
                      stringsAsFactors = FALSE))
  }
  data.frame(ordinal = m[[2L]], prefix = m[[3L]], stringsAsFactors = FALSE)
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test-templates.R")'
```

Expected: the three `.template_fields()` tests PASS. Other tests in the file
still fail — `template_list()` still calls `.prefix_of()`. That is expected and
Task 2 fixes it.

- [ ] **Step 5: Commit**

```bash
git add R/templates.R tests/testthat/test-templates.R
git commit -m "refactor: parse template names by pattern, not by splitting on dots"
```

---

### Task 2: Relocate the template and read its fields off the tree

The move and the `template_list()` change must land together: relocating the file
breaks the non-recursive glob, and making the glob recursive with no file to find
proves nothing.

`folder` stops being a taxonomy lookup and becomes the directory the template sits
in. That is the point — the filesystem, not a table, says where a template lives.

**Files:**
- Move: `inst/templates/ac.qmd` → `inst/templates/distributions/03.01-ac.qmd`
- Modify: `R/templates.R` (`template_list()`, `template_path()`)
- Modify: `.lintr` (the exclusions key)
- Test: `tests/testthat/test-templates.R`

**Interfaces:**
- Consumes: `.template_fields(name)` from Task 1.
- Produces: `template_list()` returning a `data.frame` with columns
  `name`, `prefix`, `ordinal`, `folder`, `file` (all `character`); and
  `template_path(prefix)` returning `character(1)`. Task 3 uses all five columns.

- [ ] **Step 1: Move the file and update `.lintr`**

```bash
mkdir -p inst/templates/distributions
git mv inst/templates/ac.qmd inst/templates/distributions/03.01-ac.qmd
```

In `.lintr`, change the exclusions key — the path only, nothing else in the file:

```
exclusions: list(
    "inst/templates/distributions/03.01-ac.qmd" = list(
      object_name_linter = Inf,
      commented_code_linter = Inf,
      object_usage_linter = Inf
    )
  )
```

- [ ] **Step 2: Write the failing test**

Replace the first two `test_that()` blocks at the top of
`tests/testthat/test-templates.R` with:

```r
test_that("template_list() has the expected shape", {
  tl <- template_list()
  expect_s3_class(tl, "data.frame")
  expect_named(tl, c("name", "prefix", "ordinal", "folder", "file"))
})

test_that("template_list() finds templates in taxonomy subfolders", {
  # Templates live one level down, under the taxonomy folder they scaffold into,
  # so the glob must recurse. A non-recursive glob would report zero templates
  # and every downstream test would pass vacuously.
  tl <- template_list()
  expect_true("ac" %in% tl$prefix)
  i <- match("ac", tl$prefix)
  expect_equal(tl$folder[[i]], "distributions")
  expect_equal(tl$ordinal[[i]], "03.01")
  expect_equal(tl$name[[i]], "03.01-ac")
})

test_that("template_list() reads folder from the directory, not the taxonomy", {
  # The filesystem is the authority on where a template lives. Joining through
  # hvti_taxonomy() instead would report the folder the prefix is *filed* under
  # even when the file sits somewhere else -- hiding exactly the mistake the
  # cross-check in test-taxonomy.R exists to catch.
  tl <- template_list()
  expect_equal(tl$folder, basename(dirname(tl$file)))
})

test_that("every listed template exists and every template file is listed", {
  tl <- template_list()
  dir <- system.file("templates", package = "hvtiRtemplates")
  skip_if(dir == "", "templates not installed")
  on_disk <- list.files(dir, pattern = "[.]qmd$", recursive = TRUE)
  expect_setequal(tl$file, file.path(dir, on_disk))
  expect_true(all(file.exists(tl$file)))
})

test_that("template_path() resolves a prefix", {
  expect_true(file.exists(template_path("ac")))
  expect_error(template_path("zz"), "unknown template")
})
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test-templates.R")'
```

Expected: FAIL — `template_list()` still calls the deleted `.prefix_of()`, and has
no `ordinal` column.

- [ ] **Step 4: Write the implementation**

In `R/templates.R`, replace the body of `template_list()` and its `@return` line,
and replace `template_path()` entirely:

```r
#' List the supported R job templates
#'
#' These templates are supported: they render, they are tested, and they are
#' the intended starting point for a new analysis job.
#'
#' A template is named \code{<NN.MM>-<prefix>.qmd} and lives in the taxonomy
#' folder it scaffolds into, so \code{folder} and \code{ordinal} are read from
#' the tree rather than looked up. \code{\link{hvti_taxonomy}} is a cross-check
#' on that, enforced by the test suite, not a source for it.
#'
#' @return A data frame with columns \code{name}, \code{prefix}, \code{ordinal},
#'   \code{folder} and \code{file}.
#' @export
#' @examples
#' template_list()
template_list <- function() {
  dir <- system.file("templates", package = "hvtiRtemplates")
  files <- if (nzchar(dir)) {
    list.files(dir, pattern = "[.]qmd$", full.names = TRUE, recursive = TRUE)
  } else {
    character(0)
  }
  fields <- do.call(rbind, lapply(basename(files), .template_fields))
  if (is.null(fields)) {
    fields <- data.frame(ordinal = character(0), prefix = character(0),
                         stringsAsFactors = FALSE)
  }

  data.frame(
    name    = sub("[.]qmd$", "", basename(files)),
    prefix  = fields$prefix,
    ordinal = fields$ordinal,
    folder  = basename(dirname(files)),
    file    = files,
    stringsAsFactors = FALSE
  )
}

#' Path to a supported template
#'
#' @param prefix Analysis prefix, e.g. \code{"ac"}. See \code{\link{template_list}}.
#' @return The full path, as \code{character(1)}.
#' @export
#' @examples
#' try(template_path("ac"))
template_path <- function(prefix) {
  tl <- template_list()
  i <- match(prefix, tl$prefix)
  if (is.na(i)) {
    stop("unknown template: ", prefix,
         if (nrow(tl)) paste0(". Available: ", paste(stats::na.omit(tl$prefix), collapse = ", "))
         else ". No templates are installed yet.",
         call. = FALSE)
  }
  tl$file[[i]]
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test-templates.R")'
```

Expected: PASS.

- [ ] **Step 6: Confirm the lint exclusion still binds after the move**

```bash
Rscript -e 'print(lintr::lint_package())'
```

Expected: no output (zero lints). If `object_name_linter` or
`commented_code_linter` findings appear for the template, the `.lintr` path in
Step 1 is wrong — fix the path, do **not** widen the key to a directory.

- [ ] **Step 7: Commit**

```bash
git add R/templates.R .lintr tests/testthat/test-templates.R inst/templates
git commit -m "feat: templates live in their taxonomy folder, named <NN.MM>-<prefix>"
```

---

### Task 3: `new_job()` writes the scaffolded four-field name

**Files:**
- Modify: `R/new-job.R` (whole function and its roxygen)
- Test: `tests/testthat/test-new-job.R:16-28` and the overwrite test at `:30-35`

**Interfaces:**
- Consumes: `template_list()` columns `prefix`, `ordinal`, `folder`, `file` from Task 2.
- Produces: `new_job(prefix, endpoint, type, dir = ".")` returning the written path
  invisibly as `character(1)`.

- [ ] **Step 1: Write the failing test**

Replace the `new_job` tests in `tests/testthat/test-new-job.R` — the three blocks
from `test_that("new_job writes a file and returns its path"` through
`test_that("new_job refuses to overwrite an existing job"` — with:

```r
test_that("new_job writes into the taxonomy folder with all four fields", {
  dir <- tempfile("newjob-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  out <- new_job("ac", "dead_pa", "hz", dir = dir)
  expect_true(file.exists(out))
  expect_equal(out, file.path(dir, "distributions", "dead_pa-hz-03.01-ac.qmd"))
})

test_that("new_job distinguishes two analysis types over one endpoint", {
  # This is the collision the type field exists to prevent. A death-hazard set
  # and a death-RFS set share the same Kaplan-Meier upstream, so keyed on
  # endpoint alone both would be `dead_pa-03.01-ac.qmd` -- two sets, one file.
  dir <- tempfile("newjob-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  a <- new_job("ac", "dead_pa", "hz", dir = dir)
  b <- new_job("ac", "dead_pa", "rfs", dir = dir)
  expect_false(a == b)
  expect_true(all(file.exists(c(a, b))))
})

test_that("new_job refuses an unknown prefix, naming the valid ones", {
  dir <- tempfile("newjob-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  expect_error(new_job("zz", "dead_pa", "hz", dir = dir), "ac")
})

test_that("new_job refuses to overwrite an existing job", {
  # A job file accumulates a study's edits; silently replacing one discards them.
  dir <- tempfile("newjob-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  new_job("ac", "dead_pa", "hz", dir = dir)
  expect_error(new_job("ac", "dead_pa", "hz", dir = dir), "already exists")
})
```

Then update the two remaining `new_job(...)` calls further down the file — in the
`"new_job errors when the copy fails"` test — from `new_job("ac", "dead", dir = dir)`
to `new_job("ac", "dead_pa", "hz", dir = dir)`.

- [ ] **Step 2: Run the test to verify it fails**

```bash
Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test-new-job.R")'
```

Expected: FAIL — `unused argument` or a path under `qmd/` rather than
`distributions/`.

- [ ] **Step 3: Write the implementation**

Replace `R/new-job.R` in full:

```r
#' Scaffold a new analysis job from a template
#'
#' @description
#' Copies a supported job template into the taxonomy folder it belongs to,
#' named \code{<endpoint>-<type>-<NN.MM>-<prefix>.qmd}. Refuses to overwrite an
#' existing job: a job file accumulates a study's edits, and silently replacing
#' one would discard them.
#'
#' @details
#' A job is identified by four fields. Two come from the template — its
#' \code{ordinal} and \code{prefix} — and two from the caller. The pair
#' \code{(endpoint, type)} names the \strong{set} the job belongs to, and both
#' are required: one endpoint is analysed by several methods, and the jobs those
#' chains share would otherwise collide. A death-hazard set and a death
#' random-forest-survival set both begin from the same life table, so keyed on
#' the endpoint alone both would be written to one filename.
#'
#' @param prefix Job type: one of the prefixes reported by
#'   \code{\link{template_list}}.
#' @param endpoint The endpoint this job analyses, e.g. \code{"dead_pa"}.
#' @param type The analysis type the job's set belongs to, e.g. \code{"hz"}.
#' @param dir The study root to write into. The taxonomy folder beneath it is
#'   created if it does not exist.
#'
#' @return The path written, invisibly. Errors if the copy fails, so the
#'   returned path always names a file that exists.
#'
#' @seealso \code{\link{template_list}}, \code{\link{template_path}}
#'
#' @export
#'
#' @examples
#' d <- file.path(tempdir(), "new-job-example")
#' new_job("ac", "dead_pa", "hz", dir = d)
#' list.files(d, recursive = TRUE)
#' unlink(d, recursive = TRUE)
new_job <- function(prefix, endpoint, type, dir = ".") {
  tl <- template_list()
  valid <- sort(unique(stats::na.omit(tl$prefix)))
  if (!prefix %in% valid) {
    stop("new_job(): unknown prefix '", prefix, "'. Valid prefixes: ",
         paste(valid, collapse = ", "), call. = FALSE)
  }
  i <- match(prefix, tl$prefix)

  out_dir <- file.path(dir, tl$folder[[i]])
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  out <- file.path(out_dir, paste0(endpoint, "-", type, "-",
                                   tl$ordinal[[i]], "-", prefix, ".qmd"))

  if (file.exists(out)) {
    stop("new_job(): '", out, "' already exists; refusing to overwrite.",
         call. = FALSE)
  }
  if (!file.copy(tl$file[[i]], out, overwrite = FALSE)) {
    stop("new_job(): failed to write '", out, "'.", call. = FALSE)
  }
  invisible(out)
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test-new-job.R")'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/new-job.R tests/testthat/test-new-job.R
git commit -m "feat: new_job() writes <endpoint>-<type>-<NN.MM>-<prefix> into its taxonomy folder"
```

---

### Task 4: The template declares its set

`ac.qmd` currently writes nothing — it renders tables only. So there are no
existing output paths to reroute. What this task adds is the *idiom*: the two
markers that name the set, and a helper that resolves an artifact path from them,
with a commented example of use. The commented example is the template showing its
user what to uncomment, which is why `commented_code_linter` is excluded for this
file.

**Files:**
- Modify: `inst/templates/distributions/03.01-ac.qmd` (after the `setup` chunk, before `## Cohort`)
- Test: `tests/testthat/test-new-job.R` (append)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing other code calls. The template's `set_path(kind, file)` is
  local to the scaffolded job.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-new-job.R`:

```r
test_that("the ac template declares its set and resolves artifact paths from it", {
  # The markers are the interface. A job still holding the template's placeholder
  # values has not been finished, and a template that computes artifact paths
  # from anything but them would need a path edited by hand -- the mistake the
  # EDIT markers exist to prevent.
  txt <- readLines(template_path("ac"), warn = FALSE)
  expect_true(any(grepl("^ENDPOINT <- ", txt)))
  expect_true(any(grepl("^TYPE\\s+<- ", txt)))
  expect_true(any(grepl("set_path <- function\\(kind, file\\)", txt)))
  expect_true(any(grepl("paste0\\(ENDPOINT, \"-\", TYPE\\)", txt)))
})
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test-new-job.R")'
```

Expected: FAIL on all four `expect_true` assertions.

- [ ] **Step 3: Write the implementation**

In `inst/templates/distributions/03.01-ac.qmd`, immediately after the closing
` ``` ` of the `setup` chunk and before the `## Cohort` heading, insert:

````markdown
<!-- EDIT: the two values below. They name the SET this job belongs to, and
     every artifact path in the document is computed from them, so no output
     path below needs editing.

     A set is keyed on (endpoint, analysis type), not on the endpoint alone.
     One endpoint is analysed by several methods — parametric hazard, random
     forest survival, competing risks — and those chains share their upstream.
     Two sets keyed on `dead_pa` alone would write their life tables to the
     same file. Both values must match the corresponding fields in this file's
     own name. -->

```{r}
#| label: set
ENDPOINT <- "dead_pa"
TYPE     <- "hz"

# Resolve a path inside this set's artifact directory. `kind` is the artifact
# folder -- "estimates" for serialized results, "graphs" for figures. The set
# directory sits one layer under the kind and never two, which is the whole
# layout rule.
#
# Created on first use rather than up front, so a job that writes nothing leaves
# no empty directories behind.
set_path <- function(kind, file) {
  d <- file.path(.root, kind, paste0(ENDPOINT, "-", TYPE))
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  file.path(d, file)
}

# EDIT: uncomment to persist a result for a downstream job in this set. An `hz`
# fit or an `hp` figure reads what `ac` leaves here, and reads it by set, so a
# job that persists nothing cannot be chained from.
#
# saveRDS(fit, set_path("estimates", "ac.rds"))
```
````

- [ ] **Step 4: Run the test to verify it passes**

```bash
Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test-new-job.R")'
```

Expected: PASS. The study-identifier test in the same file must also still
pass — `dead_pa` is an endpoint name, not a study name, so it is not one of the
forbidden patterns (`/studies/`, `preserve_root`, `lv_function`,
`built.sas7bdat`). If it fails, the inserted text names a study; remove the name.

- [ ] **Step 5: Verify the template still lints and still renders**

```bash
Rscript -e 'print(lintr::lint_package())'
```

Expected: no output.

```bash
quarto render inst/templates/distributions/03.01-ac.qmd --to html 2>&1 | tail -20
```

Expected: the render fails at the `setup` chunk with the deliberate
"Neither . nor .. contains _quarto.yml" error. That is the template's own root
guard firing correctly outside a study project — it is a **pass**, not a
regression. A failure *before* that point, or a different error, is a real defect.
Clean up any `.html` the attempt leaves behind.

- [ ] **Step 6: Commit**

```bash
git add inst/templates/distributions/03.01-ac.qmd tests/testthat/test-new-job.R
git commit -m "feat: ac template declares its set and computes artifact paths from it"
```

---

### Task 5: Cross-check the ordinals against the taxonomy

§5 of the spec makes the template filename the single authority for the ordinal
and demotes `hvti_taxonomy()` to a cross-check. This task is that cross-check.
With one template most of it is near-vacuous; it becomes load-bearing the moment
a second arrives, which is the same reasoning already recorded in this file for
the folder test.

**Files:**
- Test: `tests/testthat/test-taxonomy.R` (append)

**Interfaces:**
- Consumes: `template_list()` columns `ordinal`, `folder`, `prefix` from Task 2.
- Produces: nothing.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-taxonomy.R`:

```r
test_that("a template's ordinal major identifies the folder it sits in", {
  # The major is derived from the taxonomy's own folder order rather than from a
  # table written out here. A second copy of that mapping would be a second
  # thing to keep in step, which is the drift hvti_taxonomy() exists to prevent.
  tl <- template_list()
  skip_if(nrow(tl) == 0, "no templates installed")
  order_of <- unique(hvti_taxonomy()$folder)
  expect_equal(substr(tl$ordinal, 1L, 2L),
               sprintf("%02d", match(tl$folder, order_of)))
})

test_that("a template sits in the folder its prefix is filed under", {
  # template_list() reads `folder` from the directory, so this is a real check
  # and not a tautology: it catches a template filed somewhere the taxonomy does
  # not put its prefix.
  tl <- template_list()
  skip_if(nrow(tl) == 0, "no templates installed")
  tx <- hvti_taxonomy()
  expect_equal(tl$folder, tx$folder[match(tl$prefix, tx$prefix)])
})

test_that("within a folder, ordinal minors follow taxonomy row order", {
  # Deliberately per-folder rather than global. Global row order does not work:
  # `rfsrc`, `rfc`, `rfs` and `nb` are `analyses` rows that sit AFTER the
  # `documents` row `ar`, so an `rfs` template (major 04) would compare as later
  # than an `ar` template (major 06) on row order while being earlier on
  # ordinal. The majors already carry the between-folder ordering; only the
  # within-folder ordering is left for this check.
  tl <- template_list()
  skip_if(nrow(tl) == 0, "no templates installed")
  tx <- hvti_taxonomy()
  for (f in unique(tl$folder)) {
    k <- tl$folder == f
    expect_equal(order(tl$ordinal[k]),
                 order(match(tl$prefix[k], tx$prefix)),
                 info = paste("minors out of taxonomy order in", f))
  }
})
```

- [ ] **Step 2: Run the test**

```bash
Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test-taxonomy.R")'
```

Expected: PASS. These assert the state Tasks 1–3 already established, so they
pass on first run — that is correct, not a sign the test is empty. To confirm the
first one bites, temporarily rename the template to `04.01-ac.qmd`, re-run, see it
fail, then rename it back:

```bash
git mv inst/templates/distributions/03.01-ac.qmd inst/templates/distributions/04.01-ac.qmd
Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test-taxonomy.R")'
git mv inst/templates/distributions/04.01-ac.qmd inst/templates/distributions/03.01-ac.qmd
```

Expected mid-sequence: FAIL on "ordinal major identifies the folder".

- [ ] **Step 3: Commit**

```bash
git add tests/testthat/test-taxonomy.R
git commit -m "test: cross-check template ordinals against the taxonomy"
```

---

### Task 6: Documentation, version, and the full gate

**Files:**
- Modify: `inst/templates/README.md`
- Modify: `NEWS.md` (new section at the top)
- Modify: `DESCRIPTION:4-5` (`Version`, `Date`)
- Regenerate: `man/`, `NAMESPACE`

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces: nothing.

- [ ] **Step 1: Rewrite the layout section of `inst/templates/README.md`**

Replace the "## What is here" section — the heading and the table under it —
with:

```markdown
## What is here

| template | job type | scaffolds into |
|---|---|---|
| `distributions/03.01-ac.qmd` | actuarial life tables | `distributions/` |

A template is named `<NN.MM>-<prefix>.qmd` and lives in the taxonomy folder it
scaffolds into. The name is the authority: `template_list()` reads the ordinal
and prefix from it and the folder from the directory, and the test suite checks
both against `hvti_taxonomy()`.

## Where a scaffolded job lands

`new_job("ac", "dead_pa", "hz")` writes
`distributions/dead_pa-hz-03.01-ac.qmd`. Four fields, `-` separated, with `.`
reserved for inside the ordinal: **endpoint, type, ordinal, prefix**.

The layout rule is one sentence, and it holds in every folder:

> **Authored files sit flat. Generated artifacts sit under `<endpoint>-<type>/`.**

```
<study_root>/
├── distributions/  dead_pa-hz-03.01-ac.qmd   dead_pa-rfs-03.01-ac.qmd
├── estimates/                                dead_pa-hz/ac.rds
└── graphs/         dead_pa-hz-05.01-hp.qmd   dead_pa-hz/hp-fig1.png
```

**A set is keyed on `(endpoint, analysis type)`, not on the endpoint alone.**
One endpoint is analysed by several methods, and those chains share their
upstream — a death-hazard set and a death random-forest-survival set both begin
from the same life table. Keyed on the endpoint alone, both would be written to
`dead_pa-03.01-ac.qmd`. The cost of carrying the type on every job is that the
shared upstream runs once per set rather than once per endpoint; the benefit is
that a set is self-contained and uniformly named.

The full design, including what was rejected and why, is in
`specs/2026-08-21-template-set-layout-design.md`.
```

- [ ] **Step 2: Add the `NEWS.md` entry**

Insert at the very top of `NEWS.md`, above `# hvtiRtemplates 1.0.2`:

```markdown
# hvtiRtemplates 1.0.3

## Breaking changes

- `new_job()` now takes `endpoint` and `type` in place of `basename`, and `dir`
  defaults to the study root rather than `"qmd"`. It writes
  `<folder>/<endpoint>-<type>-<NN.MM>-<prefix>.qmd` — into the taxonomy folder
  the template belongs to, not a flat `qmd/`. The `type` is required because a
  set is keyed on `(endpoint, analysis type)`: one endpoint is analysed by
  several methods and those chains share their upstream, so keyed on the
  endpoint alone two sets would write to one filename.
- `template_path()`'s argument is renamed `name` to `prefix`, which is what it
  always matched on.
- `template_list()` gains an `ordinal` column, and reports `folder` from the
  directory a template sits in rather than by looking its prefix up in
  `hvti_taxonomy()`.

## Improvements

- Templates are named `<NN.MM>-<prefix>.qmd` and live in the taxonomy folder
  they scaffold into. The name is parsed by pattern rather than by splitting on
  dots, which the old `.prefix_of()` heuristic could not do once the ordinal
  contained one.
- The `ac` template declares its set with `ENDPOINT` and `TYPE` markers and
  resolves artifact paths from them, so a scaffolded job needs no output path
  edited by hand.
- New tests cross-check every template's ordinal against `hvti_taxonomy()` —
  the major against the folder it sits in, and the minors against row order
  within that folder.
```

- [ ] **Step 3: Bump `DESCRIPTION`**

Set line 4 to `Version: 1.0.3` and line 5 to `Date: 2026-08-21`.

- [ ] **Step 4: Regenerate documentation**

```bash
Rscript -e 'devtools::document()'
```

Expected: `man/new_job.Rd`, `man/template_list.Rd` and `man/template_path.Rd`
rewritten. `NAMESPACE` should be unchanged — no exports were added or removed.
Confirm with `git diff --stat NAMESPACE`; any change there means a roxygen
`@export` was lost.

- [ ] **Step 5: Run the full gate**

```bash
Rscript -e 'devtools::test()'
```

Expected: all tests PASS, 0 failures, 0 warnings, 0 skips other than the
OS-conditional ones already in `test-new-job.R`.

```bash
Rscript -e 'print(lintr::lint_package())'
```

Expected: no output.

```bash
Rscript -e 'devtools::check()'
```

Expected: **0 errors, 0 warnings, 0 notes.** Anything else must be fixed before
committing, not explained away.

- [ ] **Step 6: Commit**

```bash
git add inst/templates/README.md NEWS.md DESCRIPTION man NAMESPACE
git commit -m "docs: document the template set layout; bump to 1.0.3"
```

- [ ] **Step 7: Open the pull request**

```bash
git push -u origin spec/template-set-layout
```

```bash
gh pr create --title "Template set layout: scaffold jobs into their taxonomy folder" --body "$(cat <<'BODY'
Implements stage 1 of `specs/2026-08-21-template-set-layout-design.md`.

`new_job("ac", "dead_pa", "hz")` now writes
`distributions/dead_pa-hz-03.01-ac.qmd` rather than `qmd/ac.dead_pa.qmd`. The
template's own filename is the authority for its ordinal and prefix, its
directory for its folder, and `hvti_taxonomy()` is demoted from a lookup table
to a cross-check the test suite enforces.

A set is keyed on `(endpoint, analysis type)` rather than the endpoint alone,
because one endpoint is analysed by several methods and those chains share their
upstream — keyed on `dead_pa` alone, a hazard set and an RFS set would write
their shared life table to one filename.

**Breaking:** `new_job()`'s signature, its output path, and `template_path()`'s
argument name. Version bumped `1.0.2 -> 1.0.3`; the spec notes this is
minor-shaped and that the call is the maintainer's.

**Deferred:** `new_job_set()`, until `hz` and `hp` templates exist.

**Not addressed** — the four open items in §9 of the spec, all taxonomy or
versioning calls for the maintainer: the `hs` misfiling, `estimates/` being
absent from the taxonomy, the `folder` column conflating type with kind, and
whether this warrants a minor.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)"
```

---

## Out of scope

Do not do these as part of this plan. Each is recorded in §9 of the spec as the
maintainer's call:

- Editing `hvti_taxonomy()` for the `hs` misfiling.
- Adding an `estimates` row to the taxonomy.
- Splitting the `folder` column into type and kind.
- Rolling the minor version digit.
- Building `new_job_set()`.
- Implementing §5.2's package-side parity convention in any other repository.
