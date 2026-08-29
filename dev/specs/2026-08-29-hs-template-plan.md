# `06.02-hs.qmd` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `inst/templates/graphs/06.02-hs.qmd`, the template that turns a
multivariable hazard model into patient-level predictions and compares them
against expected population survival.

**Architecture:** One Quarto template, structurally a sibling of the shipped
`04.01-hm.qmd`. It reads `estimates/hm.rds`, predicts per patient at
study-chosen horizons via `predict.hazard()`, derives expected survival via
`hvtiRlifetables::us_matched()`, and writes `estimates/hs.rds` for downstream
plotting jobs.

**Tech Stack:** Quarto, R, `TemporalHazard`, `hvtiRutilities`,
`hvtiRlifetables`, testthat edition 3.

**Design spec:** `dev/specs/2026-08-29-hs-template-design.md`. **Read it first.**
This plan implements it and decides nothing it left open.

## Global Constraints

- **Never push to `main`.** Branch, open a PR **against `main`** — not stacked,
  or the Copilot review never fires — and let the maintainer merge.
- **The prerequisite has already landed.** `hvtiRutilities` 1.1.6 moved `hs`
  from `analyses` to `graphs`, immediately after `hp`. Verify before starting:
  `Rscript -e 'hvtiRutilities::hvti_taxonomy()'` must show `hs` under `graphs`,
  and the graphs order must be `hp → hs → mp → …`. If it does not, **stop** —
  `DESCRIPTION` needs `hvtiRutilities (>= 1.1.6)` and the installed copy needs
  upgrading. Everything in this plan depends on it.
- **The file is `inst/templates/graphs/06.02-hs.qmd`.** Folder and ordinal are
  both asserted by `tests/testthat/test-taxonomy.R`; neither is a free choice.
- **A new template needs its own key in `.lintr`, and the key must be the
  FILE.** A directory key silently disables every linter on that path.
- **Templates carry no study identifiers.** `test-new-job.R` greps every
  template for `/studies/|preserve_root|lv_function|built[.]sas7bdat`.
- **Exactly one `^ENDPOINT\s+<- ` line and one `^TYPE\s+<- ` line.** `new_job()`
  substitutes both and hard-stops if either is missing, duplicated or moved.
- **Every study-specific line is marked `EDIT:`**, and the comment says *why the
  choice matters*, not merely what to type.
- **Lines are 135 characters here, not 80.**
- **Roxygen is Rd markup, not markdown** — no roxygen in this plan, but do not
  "fix" any you pass.
- **Straight three-digit version, patch digit only.** `DESCRIPTION` `Version` +
  `Date` and a matching plain `# hvtiRtemplates X.Y.Z` heading in `NEWS.md` —
  **no `Version:` line**.

## What cannot be verified here, and how it is verified instead

⚠️ **This template cannot be rendered in this repository, and no step in this
plan pretends otherwise.** Rendering needs a study project — a `_quarto.yml`, an
`R/` directory, a built dataset, and an `estimates/<set>/hm.rds` produced by a
real `hm` run. None exists here, and fabricating one would be a fixture that
proves the fixture works.

What CI and this plan actually check:

| property | checked by |
|---|---|
| the name parses; prefix, ordinal and folder agree with the taxonomy | `test-templates.R`, `test-taxonomy.R` — **automatically, for any new template** |
| `new_job()` can scaffold it and substitute both markers | `test-new-job.R` |
| no study identifiers | `test-new-job.R` |
| style | `lintr::lint_package()`, given the `.lintr` key |
| the R is syntactically valid | Task 1 Step 6, by parsing the chunks |

**A render against a real study is a manual acceptance step, named in Task 4
Step 5 and not claimable by CI.** Say so in the PR rather than implying the
suite covered it.

## File Structure

| file | responsibility |
|---|---|
| `inst/templates/graphs/06.02-hs.qmd` | the template — the whole deliverable |
| `.lintr` | its per-file linter exclusions |
| `inst/templates/README.md` | its row in the supported-templates table |
| `dev/specs/artifacts/2026-08-29-template-roadmap.json` | ledger row → `graphs` / `06.02` / `shipped` |
| `DESCRIPTION`, `NEWS.md` | the patch release |

---

### Task 1: Skeleton, guards and the `hm` read

**Files:**
- Create: `inst/templates/graphs/06.02-hs.qmd`
- Modify: `.lintr`

**Interfaces:**
- Consumes: `estimates/hm.rds`, written by `inst/templates/analyses/04.01-hm.qmd`'s
  `save` chunk as `list(reported, stage1, stage2, covariates, audit, deciles)`.
  `reported` is the `hazard` model object.
- Produces: for Tasks 2 and 3 — `.root` (character), `set_path(kind, file)`,
  `ENDPOINT`, `TYPE`, `hm_art` (the loaded list), `fit <- hm_art$reported`,
  and `d` (the cohort data frame).

- [ ] **Step 1: Confirm the prerequisite landed**

```bash
Rscript -e 'tx <- hvtiRutilities::hvti_taxonomy(); stopifnot(tx$folder[which(tx$prefix=="hs")] == "graphs"); cat("graphs order:", paste(tx$prefix[tx$folder=="graphs" & !is.na(tx$prefix)], collapse=" -> "), "\n")'
```

Expected: `graphs order: hp -> hs -> mp -> lp -> np -> dp -> fp -> gp -> cp -> ce -> rp`

If this errors or `hs` is not second, **stop and report**. Nothing below works.

- [ ] **Step 2: Copy the shared skeleton from the `hm` template**

Create `inst/templates/graphs/06.02-hs.qmd` by copying
`inst/templates/analyses/04.01-hm.qmd` **lines 1 through 184** — the YAML
`format:` block, the `setup` chunk, the `edit-guard` chunk, the set-declaration
comment, the `set` chunk with `ENDPOINT`/`TYPE`, the filename-agreement guard,
and `set_path()`.

**Copy it, do not paraphrase it.** Those chunks encode defects that were paid
for: the built-token `.tok <- paste0("ED", "IT", ":")` (a literal would match
its own source line and fire on every render), the `HVTI_TEMPLATE_DRAFT`
value check (`nzchar()` alone would treat `0` as ON), and the
filename-vs-declaration guard. Re-typing them loses the comments that say why.

Then make exactly these changes to the copy:

1. **Title** — `title: "Multivariable hazard model"` becomes
   `title: "Patient-level predictions and expected survival"`.
2. **The prose block after the YAML** (`hm`'s `<!-- EDIT: name the SAS job … -->`
   through the paragraph ending `lives in \`parity/\``) is replaced wholesale by
   the block in Step 3.
3. **The `setup` chunk's library calls** gain `hvtiRlifetables`:

```r
suppressPackageStartupMessages({
  library(TemporalHazard)
  library(hvtiRutilities)
  library(hvtiRlifetables)
})
```

4. **Leave `ENDPOINT <- "dead_pa"` and `TYPE <- "hz"` exactly as they are.**
   They are placeholders `new_job()` overwrites, and `test-new-job.R` asserts
   the substituted values match the scaffolded filename. Changing them here
   breaks that test.

- [ ] **Step 3: Write the opening prose**

Replace the block described in Step 2 item 2 with:

```markdown
<!-- EDIT: name the SAS job this replaces, and say which horizons it reported
     and against which expected-survival comparison. -->

Replaces `graphs/<job>.sas`: describe its prediction step here — which horizons
it reported, and what it compared them against.

An `hs` job turns the risk-factor model an `hm` job fitted into **predictions
for individual patients**, and sets those against the survival the general
population would have had. The model is not refitted here; it is read.

**This job is filed under `graphs/`, which reads oddly for something named
"setup".** That placement follows the corpus rather than the name: all ten
`tp.hs.*` templates in the SAS library, and ten of the eleven R `hs` jobs across
the study tree, sit in `graphs/`. An `hs` job computes what the plotting jobs
beside it consume — the `setup` / `uses_setup` pairing the corpus uses
throughout. The reasoning is in
`hvtiRtemplates:dev/specs/2026-08-29-hs-template-design.md`.

Validation metrics — C-index, Brier score — are **not** here. The corpus files
them under `hs`, but the only R implementation is a loose script on a shared
drive with no package and no version, and no supported template depends on an
unpackaged file. They arrive once it has a home.
```

- [ ] **Step 4: Add the cohort and `hm` read**

Append, after the `set` chunk:

```markdown
## Cohort and model

<!-- EDIT: choose the cohort shape, exactly as the `hm` job did.

     The rows this job predicts for MUST be the rows the model was fitted on,
     or the predictions describe a cohort the model never saw. That failure is
     silent: `predict()` returns a number for any row you hand it, whatever
     cohort it came from. -->

```{r}
#| label: cohort
d <- read_built()
assert_cohort(d)
```

```{r}
#| label: model
# The model, not a refit. `hm.rds` is written by the hm job in this same set,
# so a prediction can never be filed against a different set than the model it
# came from.
hm_art <- readRDS(set_path("estimates", "hm.rds"))
fit    <- hm_art$reported

# The covariates the model was actually fitted on. Taken from the artifact
# rather than re-declared here: a re-declared list drifts from the model the
# moment the hm job's screen changes, and `predict()` would then either error
# on a missing column or -- worse -- silently use a stale set.
COVARIATES <- hm_art$covariates
stopifnot(is.character(COVARIATES), length(COVARIATES) > 0L)
missing_cols <- setdiff(COVARIATES, names(d))
if (length(missing_cols)) {
  stop("The model was fitted on covariate(s) absent from this cohort: ",
       paste(missing_cols, collapse = ", "),
       ". The cohort here is not the cohort hm was fitted on.", call. = FALSE)
}
```
````

⚠️ The fenced block above contains a nested ```` ```{r} ```` fence. When you
write the file, the chunk fences are ordinary Quarto chunks — the outer fence in
this plan is only for display.

- [ ] **Step 5: Add the `.lintr` key**

In `.lintr`, inside `exclusions: list(`, add an entry keyed on the **file**,
matching the four already there:

```r
    "inst/templates/graphs/06.02-hs.qmd" = list(
      object_name_linter = Inf,
      commented_code_linter = Inf,
      object_usage_linter = Inf
    ),
```

Place it after the `06.01-hp.qmd` entry. All three exclusions are needed for the
same reasons the siblings need them: `SCREAMING_CASE` edit constants,
instructional commented scaffolding, and calls into packages deliberately absent
from `DESCRIPTION`.

- [ ] **Step 6: Verify structure, and that the R parses**

```bash
Rscript -e '
tl <- hvtiRtemplates::template_list()
print(tl[tl$prefix == "hs", c("name", "prefix", "ordinal", "folder")])
' 2>&1
```

Expected: one row — `06.02-hs`, prefix `hs`, ordinal `06.02`, folder `graphs`.

```bash
grep -cE "^ENDPOINT[[:space:]]+<- " inst/templates/graphs/06.02-hs.qmd
grep -cE "^TYPE[[:space:]]+<- " inst/templates/graphs/06.02-hs.qmd
```

POSIX classes rather than `\s`. Both GNU and BSD `grep` do accept `\s` as an
extension — verified, it returns `1` on macOS against the `hm` template — but
`[[:space:]]` is the form POSIX actually defines, and these two commands decide
whether `new_job()` can scaffold the file at all. A check that silently returns
`0` on some runner's `grep` reads as "the marker is missing" and sends the
implementer to fix a template that was already correct.

Expected: `1` and `1`. Any other number and `new_job()` cannot scaffold the file
at all.

Parse every R chunk, which is the strongest syntax check available without a
study project:

```bash
Rscript -e '
src <- readLines("inst/templates/graphs/06.02-hs.qmd", warn = FALSE)
starts <- grep("^```\\\\{r", src); ends <- grep("^```$", src)
n <- 0
for (s in starts) {
  e <- ends[ends > s][1]
  code <- src[(s + 1):(e - 1)]
  code <- code[!grepl("^#\\\\|", code)]
  parse(text = paste(code, collapse = "\n"))
  n <- n + 1
}
cat("parsed", n, "chunks cleanly\n")'
```

Expected: `parsed 5 chunks cleanly` (setup, edit-guard, set, cohort, model).

- [ ] **Step 7: Run the suite and lint**

```bash
Rscript -e 'devtools::test()'
```

Expected: `FAIL 0 | WARN 0 | SKIP 0 | PASS 89`. The template tests are
data-driven over `template_list()`, so the new file is picked up with no test
changes. **A drop in the pass count means a test started skipping — investigate,
do not accept it.**

```bash
Rscript -e 'lintr::lint_package()'
```

Expected: no output. If lints appear for the new file, the `.lintr` key is
wrong — fix the key, do not reformat the template to dodge it.

- [ ] **Step 8: Commit**

```bash
git add inst/templates/graphs/06.02-hs.qmd .lintr
git commit -m "feat(hs): scaffold the 06.02-hs template with its guards"
```

---

### Task 2: Patient-level predictions

**Files:**
- Modify: `inst/templates/graphs/06.02-hs.qmd`

**Interfaces:**
- Consumes: `fit`, `d`, `COVARIATES`, `set_path()` from Task 1.
- Produces: for Task 3 — `TIME` (character, the follow-up column name),
  `HORIZONS` (numeric), `pred` (data frame with columns `id`, `horizon`, `fit`,
  `se.fit`, `lower`, `upper`).

⚠️ A fitted `hazard` object has slots `call`, `call_env`, `spec`, `data`, `fit`,
`legacy_args`, `engine`. **There is no `formula` slot**, and `spec` carries only
`dist`, `control`, `time_windows`, `phases`. Do not introspect the time variable
off the fit — declare it.

- [ ] **Step 1: Add the horizons declaration**

Append:

```markdown
## Predictions

<!-- EDIT: the follow-up time column, and the horizons this job reports.

     TIME must be the SAME column the hm job fitted on. It is re-declared here
     rather than read from `hm.rds`, because that artifact does not carry it --
     so the two CAN drift, and the guard below is what catches it. If you change
     one, change both.

     The horizons are in TIME's own units.

     These are reporting choices, not statistical ones, and they must match the
     job being replaced -- a nomogram at 5 years and a table at 10 answer
     different questions. The corpus uses 30-day, 5-year and 10-year most
     often. The units are whatever `hz` fitted in: if that job worked in years,
     30 days is 30/365.25, not 30. Getting this wrong produces a plausible
     number at the wrong time, which is the failure mode with no symptom. -->

```{r}
#| label: horizons
TIME     <- "iu_dead"
HORIZONS <- c(1, 5, 10)

# A `hazard` object carries `call`, `call_env`, `spec`, `data`, `fit`,
# `legacy_args` and `engine` -- there is NO `formula` slot, and `spec` holds
# only dist/control/time_windows/phases. The formula is recoverable from
# `fit$call` only when the model was built through the formula interface;
# `hazard()` also accepts time=/status=, in which case it is not there at all.
# So the time column is declared above rather than introspected.
if (!TIME %in% names(fit$data)) {
  stop("TIME is \"", TIME, "\", which is not a column of the data the model was ",
       "fitted on. It must name the same follow-up column the hm job used.",
       call. = FALSE)
}

# The model cannot extrapolate past the follow-up it was fitted on, and
# `predict()` will not say so -- it returns a number for any time you give it.
# Beyond the last observed time that number is the fitted parametric form
# running on, not an estimate the data supports.
.max_obs <- max(fit$data[[TIME]], na.rm = TRUE)
if (any(HORIZONS > .max_obs)) {
  stop("HORIZONS contains ", paste(HORIZONS[HORIZONS > .max_obs], collapse = ", "),
       ", beyond the last observed time (", signif(.max_obs, 4),
       "). Shorten the horizon or say in the text why extrapolation is defensible.",
       call. = FALSE)
}
```
````

- [ ] **Step 2: Add the prediction chunk**

```markdown
`predict()` needs one row per (patient, horizon): the covariates identify the
patient and a `time` column names the horizon.

```{r}
#| label: predict
# One row per patient per horizon. Built explicitly rather than by looping
# `predict()` per horizon, so every prediction comes from ONE call and cannot
# drift between horizons.
nd <- do.call(rbind, lapply(HORIZONS, function(h) {
  x <- d[, COVARIATES, drop = FALSE]
  x$time <- h
  x$.id  <- seq_len(nrow(d))
  x$.horizon <- h
  x
}))

p <- predict(fit, newdata = nd[, c(COVARIATES, "time")], type = "survival",
             se.fit = TRUE, level = 0.95)

pred <- data.frame(id = nd$.id, horizon = nd$.horizon,
                   fit = p$fit, se.fit = p$se.fit,
                   lower = p$lower, upper = p$upper)

# Survival is a probability. A value outside [0, 1] means the delta-method
# interval was built on the wrong scale, not that a patient is 103% alive.
stopifnot(all(pred$fit >= 0 & pred$fit <= 1, na.rm = TRUE))
knitr::kable(
  do.call(rbind, lapply(split(pred, pred$horizon), function(g)
    data.frame(horizon = g$horizon[[1]], n = nrow(g),
               median = stats::median(g$fit, na.rm = TRUE),
               min = min(g$fit, na.rm = TRUE), max = max(g$fit, na.rm = TRUE)))),
  row.names = FALSE, digits = 4,
  caption = "Predicted survival by horizon, across the cohort")
```
````

- [ ] **Step 3: Verify it parses and the suite still passes**

```bash
Rscript -e '
src <- readLines("inst/templates/graphs/06.02-hs.qmd", warn = FALSE)
starts <- grep("^```\\\\{r", src); ends <- grep("^```$", src)
for (s in starts) { e <- ends[ends > s][1]; code <- src[(s+1):(e-1)]
  parse(text = paste(code[!grepl("^#\\\\|", code)], collapse = "\n")) }
cat("parsed", length(starts), "chunks cleanly\n")'
Rscript -e 'devtools::test()' 2>&1 | tail -2
```

Expected: `parsed 7 chunks cleanly`, then `FAIL 0 | ... | PASS 89`.

- [ ] **Step 4: Commit**

```bash
git add inst/templates/graphs/06.02-hs.qmd
git commit -m "feat(hs): predict patient-level survival at the reported horizons"
```

---

### Task 3: Expected survival, and the save

**Files:**
- Modify: `inst/templates/graphs/06.02-hs.qmd`

**Interfaces:**
- Consumes: `d`, `pred`, `HORIZONS`, `set_path()` from Tasks 1-2.
- Produces: `estimates/hs.rds` — `list(pred, expected, obs_vs_exp, horizons, covariates, vintage)`.
  `expected` is `us_matched()`'s data frame, with columns `id`, `time`,
  `agesurv`, `smatched`, `hmatched`. **There is no `survival` column** — use
  `smatched`.

- [ ] **Step 1: Add the expected-survival chunk, with the vintage marker**

```markdown
## Expected population survival

<!-- EDIT: the columns naming each patient's age, sex and race, and the life
     table vintage.

     `vintage` HAS NO DEFAULT HERE, ON PURPOSE. The SAS macro `%usmatchd` took
     no vintage argument, so every `hs.uslife` job silently inherited the macro
     default AS OF ITS RUN DATE -- and that default moved twice, table84 ->
     table2008 -> table2023, with no signal at either move. The vintages are
     structurally different fits, not perturbations, so a wrong one is wrong by
     orders of magnitude. A parity check on one such job could not read the
     vintage off it at all and had to RECOVER it, by fitting all three and
     seeing which landed at machine precision. A job that does not state its
     vintage cannot be reproduced.

     `us_lifetable_vintages()` lists the valid values AND what each one's
     non-white stratum actually means -- which is not what its code says.
     Under `table2023`, stratum `"b"` is a risk-weighted average of Black,
     Asian, American Indian and Hispanic death rates, NOT Black, despite the
     code and despite the macro's own comment. Name strata by meaning in your
     prose, never by the letter code. -->

```{r}
#| label: expected
AGE_COL  <- "age"
MALE_COL <- "male"
OTHER_COL <- "other"
VINTAGE  <- NULL

if (is.null(VINTAGE)) {
  # us_lifetable_vintages() returns a DATA FRAME -- vintage, n_strata,
  # nonwhite_code, nonwhite_meaning, added -- not a character vector. The
  # `$vintage` is deliberate; pasting the frame prints column-wise nonsense.
  stop("VINTAGE is unset. Choose one of: ",
       paste(us_lifetable_vintages()$vintage, collapse = ", "),
       " -- and record WHY in the text above. There is no safe default; see the ",
       "comment on this chunk.", call. = FALSE)
}

# Read this before choosing, and print it in the report:
knitr::kable(us_lifetable_vintages(), row.names = FALSE,
             caption = "Life table vintages, and what each one's non-white stratum means")

expected <- us_matched(
  age = d[[AGE_COL]], male = d[[MALE_COL]], other = d[[OTHER_COL]],
  times = HORIZONS, id = seq_len(nrow(d)),
  vintage = VINTAGE, table = "sexrace", scale = "years", individual = TRUE
)
```
````

- [ ] **Step 2: Add the observed-versus-expected comparison**

```markdown
```{r}
#| label: obs-vs-exp
# The cohort average at each horizon, which is what gets overlaid on an
# actuarial curve. Derived here rather than called, because hvtiRlifetables
# has no aggregate yet -- see hvtiRlifetables#16, which this derivation is the
# specification for. When that lands, this chunk becomes one call and the
# result must not change.
#
# The mean is taken over SURVIVAL, not over cumulative hazard. The two differ,
# and mixing them across studies is exactly the drift that issue exists to
# prevent -- so if you change it, say so in the text.
# `smatched` is the matched SURVIVAL column. us_matched() returns
# id / time / agesurv / smatched / hmatched -- there is no column called
# `survival`, and `agesurv` is the age-matched baseline rather than the
# sex/race-matched answer. Taking the wrong one is a plausible number for a
# different question.
exp_avg <- vapply(split(expected$smatched, expected$time), mean, numeric(1),
                  na.rm = TRUE)
obs_avg <- vapply(split(pred$fit, pred$horizon), mean, numeric(1), na.rm = TRUE)

stopifnot(identical(names(exp_avg), names(obs_avg)))
obs_vs_exp <- data.frame(
  horizon  = as.numeric(names(obs_avg)),
  observed = unname(obs_avg),
  expected = unname(exp_avg)
)
obs_vs_exp$ratio <- obs_vs_exp$observed / obs_vs_exp$expected

knitr::kable(obs_vs_exp, row.names = FALSE, digits = 4,
             caption = "Model-predicted vs age/sex/race-matched population survival")
```

A ratio below 1 says the cohort does worse than the matched general population
at that horizon. It is a comparison, not a test — no interval is attached,
because the expected curve carries no sampling error of its own here.
````

- [ ] **Step 3: Add the save chunk**

```markdown
## Save

```{r}
#| label: save
# Read by the plotting jobs in this set. `vintage` travels WITH the estimates
# rather than being recorded only in prose: an expected curve whose vintage has
# to be recovered later is the defect this template's vintage marker exists to
# prevent, and it would be reintroduced here by omitting it.
saveRDS(list(pred = pred, expected = expected, obs_vs_exp = obs_vs_exp,
             horizons = HORIZONS, covariates = COVARIATES, vintage = VINTAGE),
        set_path("estimates", "hs.rds"))
```
````

- [ ] **Step 4: Verify**

```bash
Rscript -e '
src <- readLines("inst/templates/graphs/06.02-hs.qmd", warn = FALSE)
starts <- grep("^```\\\\{r", src); ends <- grep("^```$", src)
for (s in starts) { e <- ends[ends > s][1]; code <- src[(s+1):(e-1)]
  parse(text = paste(code[!grepl("^#\\\\|", code)], collapse = "\n")) }
cat("parsed", length(starts), "chunks cleanly\n")'
Rscript -e 'devtools::test()' 2>&1 | tail -2
Rscript -e 'lintr::lint_package()' 2>&1 | tail -2
```

Expected: `parsed 10 chunks cleanly`; `FAIL 0 | ... | PASS 89`; no lints.

Confirm the markers are present and countable:

```bash
grep -c "EDIT:" inst/templates/graphs/06.02-hs.qmd
```

Expected: **`4`** — the opening prose (Task 1 Step 3), the cohort (Task 1
Step 4), horizons and TIME (Task 2 Step 1), and the vintage (Task 3 Step 1).

⚠️ **CORRECTED 2026-08-29, before execution.** An earlier draft of this step
predicted `6` and attributed markers to "the save" and "the copied skeleton's
set-declaration comment". Neither carries one. The skeleton's only `EDIT:` is
in the opening prose block at `04.01-hm.qmd:22`, which Task 1 Step 2 **replaces
wholesale**, so the copy contributes zero. Chasing the wrong number would send
an implementer hunting markers that do not exist, or adding spurious ones to
reach it.

**A count of 0 means the template ships as if it were finished, which is
issue #27 all over again.**

- [ ] **Step 5: Commit**

```bash
git add inst/templates/graphs/06.02-hs.qmd
git commit -m "feat(hs): compare predictions against matched population survival"
```

---

### Task 4: README, ledger, release, and the manual acceptance

**Files:**
- Modify: `inst/templates/README.md`
- Modify: `dev/specs/artifacts/2026-08-29-template-roadmap.json`
- Modify: `DESCRIPTION`, `NEWS.md`

**Interfaces:**
- Consumes: the template from Tasks 1-3.
- Produces: a PR against `main`.

- [ ] **Step 1: Add the README row**

In `inst/templates/README.md`'s "What is here" table, after the
`graphs/06.01-hp.qmd` row:

```markdown
| `graphs/06.02-hs.qmd` | patient-level predictions and expected survival | `graphs/` |
```

Then, in the "What is not here yet, and why" section, delete `hs` from the
per-prefix R-job count table if it appears there — it is no longer pending.

- [ ] **Step 2: Update the ledger**

In `dev/specs/artifacts/2026-08-29-template-roadmap.json`, the `hs` record:

```json
  "folder": "graphs",
  "status": "shipped",
  "ordinal": "06.02",
  "spec": "dev/specs/2026-08-29-hs-template-design.md",
```

⚠️ `folder` **and** `ordinal` must change together. `check-roadmap-counts.py`
verifies the ordinal's major against the folder (`graphs` → `06`) and that a
`shipped` row has a file on disk at
`inst/templates/<folder>/<ordinal>-<prefix>.qmd`. Changing one without the other
fails the guard, which is what it is for.

Run it:

```bash
python3 dev/specs/artifacts/check-roadmap-counts.py
```

Expected: `Ledger agrees with disk: 45 prefixes, 5 on disk.` — five, not four:
`ac`, `hz`, `hm`, `hp` and now `hs`.

- [ ] **Step 3: Regenerate the roadmap document**

```bash
python3 dev/specs/artifacts/roadmap_render.py
python3 dev/specs/artifacts/check-roadmap-counts.py
```

Expected: `rendered 45 prefixes into 2026-08-29-template-conversion-roadmap.md`,
then the guard passes. The hazard-chain workflow view should now read `5/5`.

**Do not hand-edit the roadmap document's tables** — they are generated, and the
guard byte-compares them.

- [ ] **Step 4: Version and NEWS**

`DESCRIPTION`: raise the patch digit and set `Date` to today. Check what `main`
is on first — the roadmap work took `1.0.11`:

```bash
git show origin/main:DESCRIPTION | grep -E "^Version"
```

Use the next patch above whatever that prints. `NEWS.md`, at the top, plain
heading, **no `Version:` line**:

```markdown
# hvtiRtemplates 1.0.12

* Added `graphs/06.02-hs.qmd`, the patient-level prediction template. It reads
  the model an `hm` job fitted, predicts survival per patient at the horizons a
  study reports, and sets those against age/sex/race-matched population survival
  from `hvtiRlifetables`. Its `vintage` marker has no default on purpose: the
  SAS macro it replaces inherited a default that moved twice with no signal, and
  a job that does not state its vintage cannot be reproduced. Design in
  `dev/specs/2026-08-29-hs-template-design.md`.
```

- [ ] **Step 5: The full gate, and the manual acceptance**

```bash
python3 dev/specs/artifacts/check-spec-counts.py && python3 dev/specs/artifacts/check-flow-counts.py && python3 dev/specs/artifacts/check-roadmap-counts.py
Rscript -e 'lintr::lint_package()'
Rscript -e 'devtools::test()'
Rscript -e 'devtools::check()'
```

Expected: three guard success lines; no lints; `PASS 89`; `0 errors | 0 warnings
| 0 notes`.

⚠️ **Then state plainly, in the PR body, that the template has NOT been
rendered.** It cannot be here — see "What cannot be verified" above. Scaffolding
it into a real study with an existing `hm.rds` and rendering it is the
acceptance step, and it is the maintainer's to run. Do not describe the suite as
having covered it.

- [ ] **Step 6: Commit, push, PR**

```bash
git add inst/templates/README.md dev/specs/artifacts/2026-08-29-template-roadmap.json dev/specs/2026-08-29-template-conversion-roadmap.md DESCRIPTION NEWS.md
git commit -m "chore: ship 06.02-hs, ledger row and patch bump"
git push -u origin feat/hs-template
```

Open the PR **against `main`**, unstacked. Then confirm scope:

```bash
gh api repos/ehrlinger/hvtiRtemplates/compare/main...feat/hs-template --jq '{ahead:.ahead_by, files:[.files[].filename]}'
```

Expected: only the files this plan names. Unrelated commits mean you branched
off the wrong base — rebase with
`git rebase --onto origin/main <wrong-base-sha> feat/hs-template` rather than
opening the PR anyway.

---

## Self-review notes

**Spec coverage.** §3 placement → Task 1 Steps 1-2, Task 4 Step 2. §4 interface
→ Task 1 Step 4, Task 3 Step 3. §5.1 predictions → Task 2. §5.2 expected
survival → Task 3 Steps 1-2. §6 the vintage marker → Task 3 Step 1. §7 the
`hvtiRlifetables` demand signal → Task 3 Step 2's comment, which names
issue #16 and states the property that must not change when it lands. §9
definition of done → Task 4.

**Deliberately not implemented**, per spec §8: validation metrics (C-index,
Brier), and a model-consuming `hp` variant.

**The known sharp edge.** Nothing here renders the template. Task 1 Step 6's
chunk-parsing is the strongest available substitute and it is a syntax check,
not a behaviour check — the `predict()` call, the `us_matched()` call and the
`hm.rds` shape assumption are all unexercised until someone runs it against a
real study. Task 4 Step 5 says so, and the PR must too.
