# dc-general job template (hvtiRtemplates + hvtiR) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `dc-general` job template in hvtiRtemplates and flip its
catalog row to `shipped` in hvtiR.

**Architecture:** One self-contained Quarto file,
`inst/templates/10_descriptive/dc-general.qmd`, whose setup contract is copied
verbatim from `dc-gfup.qmd`. All computation lives in a single `derive` chunk
that the tests extract and evaluate without rendering; the report chunks only
print what `derive` produced. The catalog flip is a separate hvtiR pull request,
released as `v1.1.13`, which the hvtiRtemplates pull request then pins.

**Tech Stack:** Quarto, knitr, base R (`table()`, `quantile()`, `cor()`),
hvtiRutilities 1.1.12 (`proc_contents()`, `proc_means()`, `study_setup()`,
`register_data()`, `study_dir()`), testthat, lintr, Python 3 for the roadmap
guards.

**Spec:** `dev/specs/2026-09-16-dc-general-template-design.md`.

## Global Constraints

- Engine: `hvtiRutilities::proc_contents()` and `proc_means()`, and base R. **No new package dependency, no `DESCRIPTION` change.**
- `ENDPOINT <- "cohort"`, `TYPE <- "eda"`, exactly once each (the copied `set` chunk).
- `ID_COL <- NULL` by default. `ccfid` is a patient identifier and is **never a default**; no export step of any kind.
- Quantiles use `quantile(type = 2)`, which is SAS `QNTLDEF=5`.
- Correlations: Pearson, pairwise complete, distinct pairs, sorted by descending `abs(r)`.
- The `derive` chunk must contain no line that is exactly three backticks: the tests find its end by the first such line.
- Lint: this repo's `.lintr` (line length 135, all other defaults enforced). Indentation and braces are ON for templates.
- `NEWS.md` entry under the existing `# hvtiRtemplates (unreleased)` heading; **no `Version:` bump** in the template pull request.
- hvtiR names a version **at most once a day**. `1.1.12` was named 2026-09-16, so `1.1.13` is 2026-09-17 at the earliest.
- **Never push to `main`** in either repo. Branch, pull request, the maintainer merges.
- No em-dashes in prose written by an agent (a hook enforces this).
- Commit trailer: `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

## Where the work happens

| repo | worktree | branch |
|---|---|---|
| hvtiRtemplates | `~/Documents/GitHub/hvtiRtemplates-dc-general` | `spec/dc-general-template` (spec and plan already committed) |
| hvtiR | `~/Documents/GitHub/hvtiR` | `chore/catalog-ship-dc-general` (Task 3 creates it) |

All hvtiRtemplates commands below run from its worktree root.

## File map

| file | task | responsibility |
|---|---|---|
| `inst/templates/10_descriptive/dc-general.qmd` | 1, 2 | the template |
| `tests/testthat/test-dc-general-derive.R` | 1 | behaviour of the `derive` chunk |
| `tests/testthat/test-template-data-routes.R` | 2 | add the new template to the whole-cohort route test |
| `.lintr` | 2 | file key for the new template |
| `inst/templates/README.md` | 2 | template row and qualified-template list |
| `NEWS.md` (hvtiRtemplates) | 2, 4 | release note |
| hvtiR `tests/testthat/test-jobs.R` | 3 | pin the shipped row |
| hvtiR `inst/extdata/jobs.json` | 3 | `dc-general` status |
| hvtiR `NEWS.md` | 3 | release note |
| `.github/workflows/R-CMD-check.yaml`, `.github/workflows/spec-counts.yaml` | 4 | catalog pin |

---

### Task 1: The template's computation, test first

**Files:**
- Create: `tests/testthat/test-dc-general-derive.R`
- Create: `inst/templates/10_descriptive/dc-general.qmd` (header, copied boilerplate, `spec` and `derive` chunks)

**Interfaces:**
- Consumes: `inst/templates/10_descriptive/dc-gfup.qmd` (lines from the `setup` chunk through the `data` chunk, verbatim).
- Produces, in the `derive` chunk's environment (Task 2 prints these):
  - `PROBS`: numeric, `c(0, 0.01, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99, 1)`.
  - `freqs`: `list(<group> = list(<var> = data.frame(level = chr, n = int, percent = num)))`, missing shown as level `"(missing)"`.
  - `cdfs`: `list(<group> = list(<var> = list(summary = data.frame(n = int, nmiss = int), quantiles = data.frame(percent = num, value = num), extremes = data.frame(end = chr, value = num[, <ID_COL>]))))`.
  - `corrs`: `data.frame(var1 = chr, var2 = chr, r = num, n = int)`, zero rows when fewer than two distinct `CORR_VARS`.
- Settings the chunk reads: `d`, `CATEGORICAL`, `CONTINUOUS`, `CORR_VARS`, `ID_COL`.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-dc-general-derive.R`:

```r
template <- system.file(
  "templates", "10_descriptive", "dc-general.qmd",
  package = "hvtiRtemplates"
)
if (!nzchar(template)) {
  template <- testthat::test_path(
    "..", "..", "inst", "templates", "10_descriptive", "dc-general.qmd"
  )
}
template_lines <- readLines(template, warn = FALSE)
derive_label <- grep("^#\\| label: derive$", template_lines)
derive_end <- derive_label + which(template_lines[-seq_len(derive_label)] == "```")[[1L]]
derive_code <- parse(text = template_lines[(derive_label + 1L):(derive_end - 1L)])

synthetic <- function() {
  data.frame(
    ccfid = 1001:1012,
    female = c(0, 1, 1, 0, NA, 1, 0, 0, 1, 1, 0, 1),
    age = c(61, 45, 70, 58, NA, 66, 52, 80, 39, 74, 69, 55),
    creat = c(1.1, 0.9, 1.4, 2.2, 1.0, NA, 0.8, 3.1, 1.2, 1.0, 1.7, 0.95),
    nyha = c("I", "II", "III", "II", "I", "IV", "II", "III", "I", "II", "II", "I")
  )
}

run_derive <- function(d = synthetic(),
                       categorical = list(Demography = c("female", "nyha")),
                       continuous = list(Demography = "age", Labs = "creat"),
                       corr_vars = c("age", "creat"),
                       id_col = NULL) {
  env <- list2env(
    list(
      d = d, CATEGORICAL = categorical, CONTINUOUS = continuous,
      CORR_VARS = corr_vars, ID_COL = id_col
    ),
    parent = baseenv()
  )
  eval(derive_code, envir = env)
  env
}

test_that("extreme values carry no identifier unless ID_COL is set", {
  off <- run_derive()
  extremes <- off$cdfs$Demography$age$extremes
  expect_named(extremes, c("end", "value"))
  expect_identical(extremes$end, rep(c("lowest", "highest"), each = 5L))
  expect_identical(extremes$value, c(39, 45, 52, 55, 58, 80, 74, 70, 69, 66))
  every_name <- unlist(lapply(off$cdfs, function(g) lapply(g, function(v) lapply(v, names))))
  expect_false("ccfid" %in% every_name)

  on <- run_derive(id_col = "ccfid")
  expect_named(on$cdfs$Demography$age$extremes, c("end", "value", "ccfid"))
  expect_identical(on$cdfs$Demography$age$extremes$ccfid[[1L]], 1009L)
})

test_that("an unknown column stops and names every one", {
  expect_error(
    run_derive(
      categorical = list(Demography = c("female", "nope")),
      corr_vars = c("age", "zilch")
    ),
    "Unknown column\\(s\\): nope, zilch"
  )
})

test_that("a non-numeric continuous column stops", {
  expect_error(
    run_derive(continuous = list(Demography = c("age", "nyha"))),
    "Not numeric.*: nyha"
  )
})

test_that("contingency tables show missing values as their own level", {
  female <- run_derive()$freqs$Demography$female
  expect_identical(female$level, c("0", "1", "(missing)"))
  expect_identical(female$n, c(5L, 6L, 1L))
})

test_that("correlations list each distinct pair once, strongest first", {
  d <- synthetic()
  d$noise <- c(5, 1, 4, 2, 3, 6, 2, 5, 1, 4, 3, 6)
  corrs <- run_derive(d = d, corr_vars = c("age", "creat", "noise", "age"))$corrs

  expect_identical(nrow(corrs), 3L)
  expect_false(any(corrs$var1 == corrs$var2))
  expect_identical(anyDuplicated(paste(pmin(corrs$var1, corrs$var2), pmax(corrs$var1, corrs$var2))), 0L)
  expect_identical(order(-abs(corrs$r)), seq_len(nrow(corrs)))

  age_creat <- corrs[corrs$var1 == "age" & corrs$var2 == "creat", ]
  ok <- stats::complete.cases(d$age, d$creat)
  expect_equal(age_creat$r, stats::cor(d$age[ok], d$creat[ok]))
  expect_identical(age_creat$n, 10L)
})

test_that("quantiles follow SAS QNTLDEF=5", {
  creat <- run_derive()$cdfs$Labs$creat
  x <- synthetic()$creat
  expect_equal(creat$quantiles$percent, c(0, 1, 5, 10, 25, 50, 75, 90, 95, 99, 100))
  expect_equal(
    creat$quantiles$value,
    unname(stats::quantile(x, creat$quantiles$percent / 100, type = 2, na.rm = TRUE))
  )
  expect_identical(creat$summary$n, 11L)
  expect_identical(creat$summary$nmiss, 1L)
})

test_that("an empty CORR_VARS skips the sweep without error", {
  corrs <- run_derive(corr_vars = character())$corrs
  expect_identical(nrow(corrs), 0L)
  expect_named(corrs, c("var1", "var2", "r", "n"))
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "dc-general-derive")'`
Expected: an error that `inst/templates/10_descriptive/dc-general.qmd` cannot be opened (the file does not exist yet).

- [ ] **Step 3: Create the template header**

````bash
cat > inst/templates/10_descriptive/dc-general.qmd <<'EOF'
---
title: "General descriptive checks"
format:
  html:
    theme: cosmo
    toc: true
    toc-depth: 3
    code-fold: true
    df-print: default
    embed-resources: true
---

<!-- EDIT: name the job this replaces (descriptive/dc.general). -->

Replaces `descriptive/dc.general`.

A `dc-general` job is the first look at a built cohort, before any table or
model: what the data contain, how each categorical variable breaks down, how
each continuous variable is distributed, and which variables move together. It
uses base procedures only. The formatted manuscript table is a `dc-tables` job.
EOF
````

- [ ] **Step 4: Append the setup contract, verbatim from `dc-gfup.qmd`**

````bash
R --no-save --quiet <<'EOF'
src <- readLines("inst/templates/10_descriptive/dc-gfup.qmd")
setup_label <- grep("^#\\| label: setup$", src)
data_label <- grep("^#\\| label: data$", src)
stopifnot(length(setup_label) == 1L, length(data_label) == 1L,
          src[setup_label - 1L] == "```{r}")
data_close <- data_label + which(src[-seq_len(data_label)] == "```")[[1L]]
cat(c("", src[(setup_label - 1L):data_close]),
    file = "inst/templates/10_descriptive/dc-general.qmd", sep = "\n", append = TRUE)
EOF
grep -c "label: setup\|label: edit-guard\|label: set$\|label: data" inst/templates/10_descriptive/dc-general.qmd
````

Expected: `4`.

- [ ] **Step 5: Append the `spec` and `derive` chunks**

````bash
cat >> inst/templates/10_descriptive/dc-general.qmd <<'EOF'

```{r}
#| label: spec
# EDIT: categorical variables, grouped. Each name is a section heading, in this
# order. Carry the /* Demography */ banners across from the SAS %macro freq
# tables list. Missing values are tabulated as their own level (missprint).
CATEGORICAL <- list(
  Demography = c("female")
)
# EDIT: continuous variables, grouped the same way (the SAS %macro cdfs var
# list).
CONTINUOUS <- list(
  Demography = c("age")
)
# EDIT: variables for the pairwise correlation sweep (SAS proc corr nosimple
# rank). Defaults to every continuous variable; character() skips the section.
CORR_VARS <- unlist(CONTINUOUS, use.names = FALSE)
# EDIT: leave NULL. A column name (the SAS job used id ccfid) labels the extreme
# values with it, which puts patient identifiers in the report: a report
# rendered that way must not be circulated.
ID_COL <- NULL
```

```{r}
#| label: derive
PROBS <- c(0, 0.01, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99, 1)
cat_vars <- unlist(CATEGORICAL, use.names = FALSE)
con_vars <- unlist(CONTINUOUS, use.names = FALSE)
unknown <- setdiff(unique(c(cat_vars, con_vars, CORR_VARS, ID_COL)), names(d))
if (length(unknown)) {
  stop("Unknown column(s): ", paste(unknown, collapse = ", "), call. = FALSE)
}
numeric_vars <- unique(c(con_vars, CORR_VARS))
not_numeric <- numeric_vars[!vapply(numeric_vars, function(v) is.numeric(d[[v]]), logical(1))]
if (length(not_numeric)) {
  stop("Not numeric, so not summarised as continuous or correlated: ",
       paste(not_numeric, collapse = ", "), call. = FALSE)
}

freqs <- lapply(CATEGORICAL, function(vars) {
  stats::setNames(lapply(vars, function(v) {
    tab <- table(d[[v]], useNA = "ifany")
    data.frame(
      level = ifelse(is.na(names(tab)), "(missing)", names(tab)),
      n = as.integer(tab),
      percent = round(100 * as.integer(tab) / sum(tab), 1)
    )
  }), vars)
})

cdfs <- lapply(CONTINUOUS, function(vars) {
  stats::setNames(lapply(vars, function(v) {
    x <- d[[v]]
    seen <- which(!is.na(x))
    lowest <- seen[order(x[seen])][seq_len(min(5L, length(seen)))]
    highest <- seen[order(-x[seen])][seq_len(min(5L, length(seen)))]
    extremes <- data.frame(
      end = rep(c("lowest", "highest"), c(length(lowest), length(highest))),
      value = x[c(lowest, highest)]
    )
    if (!is.null(ID_COL)) extremes[[ID_COL]] <- d[[ID_COL]][c(lowest, highest)]
    list(
      summary = data.frame(n = length(seen), nmiss = sum(is.na(x))),
      quantiles = data.frame(
        percent = 100 * PROBS,
        value = if (length(seen)) stats::quantile(x[seen], PROBS, type = 2, names = FALSE) else NA_real_
      ),
      extremes = extremes
    )
  }), vars)
})

corr_vars <- unique(CORR_VARS)
corrs <- data.frame(var1 = character(), var2 = character(), r = numeric(), n = integer())
if (length(corr_vars) >= 2L) {
  pairs <- utils::combn(corr_vars, 2L)
  pair_stats <- apply(pairs, 2L, function(p) {
    ok <- stats::complete.cases(d[[p[[1L]]]], d[[p[[2L]]]])
    r <- if (sum(ok) >= 2L) stats::cor(d[[p[[1L]]]][ok], d[[p[[2L]]]][ok]) else NA_real_
    c(r = r, n = sum(ok))
  })
  corrs <- data.frame(
    var1 = pairs[1L, ], var2 = pairs[2L, ],
    r = pair_stats["r", ], n = as.integer(pair_stats["n", ])
  )
  corrs <- corrs[order(-abs(corrs$r)), , drop = FALSE]
  rownames(corrs) <- NULL
}
```
EOF
````

- [ ] **Step 6: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "dc-general-derive")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 22 ]` (the PASS count is the number of expectations; any FAIL or WARN is a stop).

- [ ] **Step 7: Commit**

```bash
git add inst/templates/10_descriptive/dc-general.qmd tests/testthat/test-dc-general-derive.R
git commit -m "feat: dc-general derive chunk and its tests" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Report sections, registration and the render gate

**Files:**
- Modify: `inst/templates/10_descriptive/dc-general.qmd` (append the report sections)
- Modify: `.lintr` (new file key after the `dc-gfup.qmd` key)
- Modify: `inst/templates/README.md` (row after the `dc-gfup` row; qualified-template list)
- Modify: `tests/testthat/test-template-data-routes.R` (template vector)
- Modify: `NEWS.md` (entry under `# hvtiRtemplates (unreleased)`)

**Interfaces:**
- Consumes: `freqs`, `cdfs`, `corrs` from Task 1's `derive` chunk; `d` from the copied `data` chunk.
- Produces: the finished template, resolvable as `hvtiRtemplates::add_job("dc", "cohort", "eda", qualifier = "general")`.

- [ ] **Step 1: Add the template to the whole-cohort route test**

In `tests/testthat/test-template-data-routes.R`, replace

```r
  templates <- file.path(template_dir, c(
    "dc-tables.qmd", "dc-gfup.qmd", "dp-postage.qmd"
  ))
```

with

```r
  templates <- file.path(template_dir, c(
    "dc-general.qmd", "dc-tables.qmd", "dc-gfup.qmd", "dp-postage.qmd"
  ))
```

Run: `Rscript -e 'devtools::test(filter = "template-data-routes")'`
Expected: PASS. The `data` chunk was copied verbatim in Task 1, so this passes immediately; that is the evidence the copy is faithful. If it fails, the Task 1 Step 4 splice is wrong: fix that, not the test.

- [ ] **Step 2: Append the report sections**

````bash
cat >> inst/templates/10_descriptive/dc-general.qmd <<'EOF'

## Other investigations

<!-- EDIT: study-specific checks go here, above the standard sections (the SAS
job's O T H E R   I N V E S T I G A T I O N S banner). Delete this marker when
there are none. -->

## Overall statistics

```{r}
#| label: overall
proc_contents(d)
proc_means(d, stats = c("n", "nmiss", "mean", "std", "min", "max", "sum"))
```

## Contingency tables for categorical variables

```{r}
#| label: freqs
#| results: asis
for (group in names(freqs)) {
  cat("\n### ", group, "\n\n", sep = "")
  for (v in names(freqs[[group]])) {
    cat(knitr::kable(freqs[[group]][[v]], caption = v), sep = "\n")
    cat("\n")
  }
}
```

## Cumulative distributions for continuous variables

```{r}
#| label: cdfs
#| results: asis
for (group in names(cdfs)) {
  cat("\n### ", group, "\n\n", sep = "")
  for (v in names(cdfs[[group]])) {
    cdf <- cdfs[[group]][[v]]
    cat("\n#### ", v, "\n\n", sep = "")
    cat(knitr::kable(cdf$summary), sep = "\n")
    cat("\n")
    cat(knitr::kable(cdf$quantiles, caption = "Quantiles (SAS QNTLDEF=5)"), sep = "\n")
    cat("\n")
    cat(knitr::kable(cdf$extremes, caption = "Five lowest and five highest values"), sep = "\n")
    cat("\n")
  }
}
```

## Pair-wise correlations

```{r}
#| label: corrs
#| results: asis
if (nrow(corrs)) {
  cat(knitr::kable(corrs, digits = 3, row.names = FALSE,
                   caption = "Pearson, pairwise complete, strongest first"), sep = "\n")
} else {
  cat("No correlation sweep: `CORR_VARS` names fewer than two variables.\n")
}
```

`proc_means()` skips non-numeric columns. Quantiles are SAS `QNTLDEF=5`, the
`proc univariate` default. The SAS job printed `ccfid` beside every extreme
value so an author could look the patient up; this job prints the values alone
unless `ID_COL` is set in the spec chunk.
EOF
````

- [ ] **Step 3: Register the lint file key**

In `.lintr`, replace

```
    "inst/templates/10_descriptive/dc-gfup.qmd" = list(
      object_name_linter = Inf,
      commented_code_linter = Inf,
      object_usage_linter = Inf
    ),
```

with

```
    "inst/templates/10_descriptive/dc-gfup.qmd" = list(
      object_name_linter = Inf,
      commented_code_linter = Inf,
      object_usage_linter = Inf
    ),
    "inst/templates/10_descriptive/dc-general.qmd" = list(
      object_name_linter = Inf,
      commented_code_linter = Inf,
      object_usage_linter = Inf
    ),
```

- [ ] **Step 4: Register the README row**

In `inst/templates/README.md`, after the line

```
| `10_descriptive/dc-gfup.qmd` | goodness-of-follow-up tables | `10_descriptive/` or `descriptive/` |
```

insert

```
| `10_descriptive/dc-general.qmd` | general descriptive checks (base procedures) | `10_descriptive/` or `descriptive/` |
```

and replace

```
qualified templates are `dc-tables`, `dc-gfup`, `dp-trends` and `dp-postage`;
```

with

```
qualified templates are `dc-general`, `dc-tables`, `dc-gfup`, `dp-trends` and `dp-postage`;
```

- [ ] **Step 5: Add the NEWS entry**

In `NEWS.md`, directly under `# hvtiRtemplates (unreleased)` and its blank line, insert:

```markdown
* **The `dc-general` job template ships**, replacing `descriptive/dc.general`:
  overall statistics through `hvtiRutilities::proc_contents()` and
  `proc_means()`, then base-R contingency tables, cumulative distributions
  (SAS `QNTLDEF=5` quantiles and the five lowest and highest values) and a
  Pearson pairwise-correlation sweep. `ID_COL` is off by default, so no
  patient identifier reaches the report unless a study author sets it.

```

- [ ] **Step 6: Run the full suite, lint and the identifier guard**

Run: `Rscript -e 'devtools::document(); devtools::test()'`
Expected: `FAIL 0`. `test-add-job.R` ("every template is free of study identifiers") and `test-taxonomy.R` pass with the new file present. `git status` shows no change under `man/` or `NAMESPACE`.

Run: `Rscript -e 'print(lintr::lint_package())'`
Expected: no lints.

Run: `bash tools/check-no-site-identifiers.sh`
Expected: `PASS: no site identifiers in tracked files`, exit 0.

- [ ] **Step 7: Render gate**

Install the branch, then build a scratch study with synthetic data (no study data, no identifiers):

````bash
Rscript -e 'devtools::install(quick = TRUE, upgrade = "never")'
R --no-save --quiet <<'EOF'
root <- file.path(tempdir(), "dc-general-gate")
unlink(root, recursive = TRUE)
suppressMessages(hvtiRutilities::study_setup(root, study = "Gate", study_tracker_id = 1L))
i <- seq_len(200)
built <- data.frame(
  ccfid = i,
  female = rep(0:1, length.out = 200),
  nyha = rep(c("I", "II", "III", "IV", NA), length.out = 200),
  age = 30 + (i * 7) %% 55,
  creat = 0.6 + (i %% 23) / 10,
  dead = rep(c(0L, 0L, 1L), length.out = 200),
  iv_dead = i / 40
)
utils::write.csv(built, file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"), row.names = FALSE)
suppressWarnings(suppressMessages(hvtiRutilities::register_data(
  root, built = "built.csv", event = "dead", time = "iv_dead"
)))
writeLines("project:\n  type: default", file.path(root, "_quarto.yml"))
job <- hvtiRtemplates::add_job("dc", "cohort", "eda", dir = root, qualifier = "general")

src <- readLines(job)
src <- sub('ANALYSIS_SET <- "eda"', "ANALYSIS_SET <- NULL", src, fixed = TRUE)
src <- sub('Demography = c("female")', 'Demography = c("female", "nyha")', src, fixed = TRUE)
src <- sub('Demography = c("age")', 'Demography = "age", Labs = "creat"', src, fixed = TRUE)
src <- gsub("EDIT:", "Resolved:", src, fixed = TRUE)
writeLines(src, job)

stopifnot(system2("quarto", c("render", shQuote(job))) == 0L)
html <- sub("[.]qmd$", ".html", job)
txt <- paste(readLines(html, warn = FALSE), collapse = "\n")
for (h in c("Overall statistics", "Contingency tables", "Cumulative distributions",
            "Pair-wise correlations", "(missing)", "Five lowest and five highest")) {
  stopifnot(grepl(h, txt, fixed = TRUE))
}
# Not grepl("DRAFT"): code-fold embeds the edit-guard source, which contains that word.
stopifnot(!grepl('class="callout[^"]*callout-important', txt))
cat("render gate: PASS\n", job, "\n")
unlink(root, recursive = TRUE)
EOF
````

Expected: `render gate: PASS`. A failure names the missing section; fix the template, not the gate.

Then confirm the edit guard still bites on an unresolved job: repeat the script without the `gsub("EDIT:", ...)` line and expect `quarto render` to fail with "unresolved EDIT: marker(s) remain in this job".

- [ ] **Step 8: Run the package check**

Run: `Rscript -e 'devtools::check(cran = FALSE)'`
Expected: `0 errors | 0 warnings | 0 notes`.

- [ ] **Step 9: Commit and open the pull request**

```bash
git add inst/templates/10_descriptive/dc-general.qmd .lintr inst/templates/README.md tests/testthat/test-template-data-routes.R NEWS.md
git commit -m "feat: dc-general job template" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git push -u origin spec/dc-general-template
gh pr create -R ehrlinger/hvtiRtemplates --title "Ship the dc-general template" --body "$(cat <<'EOF'
## Summary
- add `dc-general`: base-procedure descriptive checks replacing `descriptive/dc.general`
- spec `dev/specs/2026-09-16-dc-general-template-design.md` and plan `dev/specs/2026-09-16-dc-general-template-plan.md`
- `ID_COL` off by default; no export step

## Verification
- `devtools::test()`: record the count
- `lintr::lint_package()`: clean
- `devtools::check(cran = FALSE)`: 0 errors, 0 warnings, 0 notes
- render gate on a synthetic study: PASS

⚠️ `spec-counts` stays red until the catalog pin moves to hvtiR `v1.1.13` (Task 4). It is not a required check, so GitHub shows this PR mergeable while red: do not merge before the pin commit.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Replace "record the count" with the real `devtools::test()` total before creating the PR.

---

### Task 3: hvtiR catalog flip

**Files:**
- Modify: `tests/testthat/test-jobs.R` (new test after "the descriptive EDA wave stays shipped on its released engines")
- Modify: `inst/extdata/jobs.json` (the `dc-general` row's `status`)
- Modify: `NEWS.md` (entry under `# hvtiR (unreleased)`)

**Interfaces:**
- Consumes: `read_jobs()` (internal to hvtiR, already used by `test-jobs.R`).
- Produces: a merged hvtiR `main` whose `dc-general` row is `shipped`, ready for Task 4 to name and tag.

All commands in this task run from `~/Documents/GitHub/hvtiR`.

- [ ] **Step 1: Branch from the live main**

```bash
git fetch origin && git checkout -b chore/catalog-ship-dc-general origin/main
```

- [ ] **Step 2: Write the failing test**

In `tests/testthat/test-jobs.R`, insert directly after the closing `})` of `test_that("the descriptive EDA wave stays shipped on its released engines", {`:

```r

test_that("dc-general stays shipped on base procedures", {
  raw <- read_jobs()
  hit <- Filter(function(x) {
    identical(x$prefix, "dc") && identical(x$qualifier, "general")
  }, raw)
  expect_length(hit, 1L)
  general <- hit[[1L]]

  expect_identical(general$status, "shipped")
  expect_identical(general$destination, "hvtiRtemplates")
  expect_setequal(
    unlist(general$replaced_by),
    c("hvtiRutilities::proc_contents", "hvtiRutilities::proc_means")
  )
})
```

- [ ] **Step 3: Run it to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "jobs")'`
Expected: 1 FAIL, `general$status` is `"queued"`, not `"shipped"`.

- [ ] **Step 4: Flip the row without reformatting the file**

````bash
python3 - <<'EOF'
import json, pathlib, re
p = pathlib.Path("inst/extdata/jobs.json")
s = p.read_text()
rows = list(re.finditer(r'\{[^{}]*"prefix": "dc",[^{}]*"qualifier": "general",[^{}]*\}', s))
assert len(rows) == 1, f"expected one dc-general row, found {len(rows)}"
block = rows[0].group(0)
assert block.count('"status": "queued"') == 1, "dc-general is not queued"
s = s[:rows[0].start()] + block.replace('"status": "queued"', '"status": "shipped"') + s[rows[0].end():]
json.loads(s)
p.write_text(s)
EOF
git diff --stat
````

Expected: `inst/extdata/jobs.json | 2 +-` (one line changed).

- [ ] **Step 5: Run the test to verify it passes, then the full suite**

Run: `Rscript -e 'devtools::test()'`
Expected: `FAIL 0`; network-only skips are acceptable and must be reported by count.

- [ ] **Step 6: Add the NEWS entry**

In `NEWS.md`, directly under `# hvtiR (unreleased)` and its blank line, insert:

```markdown
* **The catalog marks `dc-general` shipped**, over
  `hvtiRutilities::proc_contents()` and `proc_means()`, with base R for the
  contingency tables, cumulative distributions and correlations.

```

- [ ] **Step 7: Lint, check, commit and open the pull request**

Run: `Rscript -e 'print(lintr::lint_package()); devtools::check(cran = FALSE)'`
Expected: no lints; `0 errors | 0 warnings | 0 notes`.

```bash
git add tests/testthat/test-jobs.R inst/extdata/jobs.json NEWS.md
git commit -m "feat: ship the dc-general catalog row" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git push -u origin chore/catalog-ship-dc-general
gh pr create -R ehrlinger/hvtiR --title "Ship the dc-general catalog row" --body "$(cat <<'EOF'
## Summary
- mark `dc-general` shipped on `hvtiRutilities::proc_contents()` and `proc_means()`
- pin the row in `test-jobs.R`

Companion implementation: ehrlinger/hvtiRtemplates PR from Task 2 (link it).

## Verification
- `devtools::test()`: record the count and skips
- `lintr::lint_package()`: clean
- `devtools::check(cran = FALSE)`: 0 errors, 0 warnings, 0 notes

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Replace the placeholders in the body with the real counts and link before creating the PR.

---

### Task 4: Release sequencing (gated on the maintainer)

**Files:**
- hvtiR: `DESCRIPTION` (`Version`, `Date`), `NEWS.md` (DCF `Version:` line and the unreleased heading)
- hvtiRtemplates: `.github/workflows/R-CMD-check.yaml`, `.github/workflows/spec-counts.yaml`, `NEWS.md`, `dev/specs/2026-08-29-template-conversion-roadmap.md` (re-rendered)

**Interfaces:**
- Consumes: Task 3 merged by the maintainer; Task 2's open PR.
- Produces: hvtiR tag `v1.1.13`; the hvtiRtemplates PR green and mergeable.

- [ ] **Step 1: Wait for the gate.** Do not start before **both** hold: the hvtiR PR from Task 3 is merged, and the date is **2026-09-17 or later**. Check with `gh pr view <number> -R ehrlinger/hvtiR --json state` and `date +%F`.

- [ ] **Step 2: Name hvtiR 1.1.13** (from `~/Documents/GitHub/hvtiR`)

```bash
git fetch origin && git checkout -b chore/bump-1.1.13 origin/main
sed -i '' 's/^Version: 1\.1\.12$/Version: 1.1.13/' DESCRIPTION NEWS.md
sed -i '' "s/^Date: .*/Date: $(date +%F)/" DESCRIPTION
sed -i '' 's/^# hvtiR (unreleased)$/# hvtiR 1.1.13/' NEWS.md
git diff
```

Expected diff: exactly `Version:` in `DESCRIPTION` and `NEWS.md`, `Date:` in `DESCRIPTION`, and the heading in `NEWS.md`. Then `Rscript -e 'devtools::test()'` (FAIL 0), commit `chore: name 1.1.13` with the trailer, push, and open the PR. The maintainer merges.

- [ ] **Step 3: Tag.** After the bump PR merges, and only when the maintainer asks for it:

```bash
git fetch origin && git tag -a v1.1.13 origin/main -m "hvtiR 1.1.13" && git push origin v1.1.13
```

- [ ] **Step 4: Move the hvtiRtemplates pins** (from the hvtiRtemplates worktree)

```bash
sed -i '' 's/ref: v1\.1\.11$/ref: v1.1.13/' .github/workflows/R-CMD-check.yaml .github/workflows/spec-counts.yaml
grep -n "ref: v1\.1\." .github/workflows/R-CMD-check.yaml .github/workflows/spec-counts.yaml
```

Expected: both lines read `ref: v1.1.13`.

- [ ] **Step 5: Re-render the roadmap against the tagged catalog, and measure the count**

```bash
mkdir -p "$TMPDIR/hvtiR-v1.1.13"
git -C ~/Documents/GitHub/hvtiR show v1.1.13:inst/extdata/jobs.json > "$TMPDIR/hvtiR-v1.1.13/jobs.json"
export HVTI_JOBS="$TMPDIR/hvtiR-v1.1.13/jobs.json"
python3 dev/specs/artifacts/roadmap_render.py
python3 dev/specs/artifacts/check-roadmap-counts.py; echo "exit=$?"
python3 tools/check_pin_currency.py; echo "exit=$?"
git diff --stat
```

Expected: both checks `exit=0`. Read the on-disk template count from the re-rendered roadmap; do **not** carry forward the 13 of 44 recorded in `NEWS.md` for #113, because hvtiR#79 and #81 refreshed catalog data since.

- [ ] **Step 6: Record the pin in NEWS, commit, push**

Append to the `dc-general` bullet added in Task 2 Step 5, before its trailing blank line:

```markdown
  The job-catalog pin advances to `hvtiR` `v1.1.13` in both workflows, and the
  roadmap is re-rendered: N templates are in scope and M are on disk.
```

with N and M replaced by the numbers measured in Step 5.

```bash
git add .github/workflows/R-CMD-check.yaml .github/workflows/spec-counts.yaml NEWS.md dev/specs/2026-08-29-template-conversion-roadmap.md
git commit -m "ci: advance catalog pin to v1.1.13" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git push
```

Expected: every check on the hvtiRtemplates PR green, `spec-counts` included. The maintainer merges.

- [ ] **Step 7: Vault.** Update `~/Documents/ObsidianVault/Claude/Tasks/EDA template batch follow-ups.md`: stamp the Wave 2 line `✅ RESOLVED <date>` with both PR links and the tag, and commit to the vault's `main` with `GIT_DIR=~/Documents/GitHub/obsidian.git GIT_WORK_TREE=~/Documents/ObsidianVault`.

---

## Out of scope (from the spec)

- The SAS "confidence intervals for categories" section.
- Any `.xlsx` or identified export.
- `proc_freq()`, `proc_univariate()`, `proc_corr()` in hvtiRutilities.
- `dp-gfup`.
