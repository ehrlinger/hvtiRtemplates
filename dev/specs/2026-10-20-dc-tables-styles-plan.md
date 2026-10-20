# Table styles, Phase 5: `dc-tables` adopts the table styles

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** `dc-tables`' report keeps hvtiRtables' `"report"` style, with the Variable column on
screen, and its Word export takes the `"manuscript"` style, with the layout, the caption and the
section fill as study choices; `migrate_job()` chooses the layout a `%desc_tab` job needs. This is
design D7 of hvtiRtables' `dev/specs/2026-10-17-table-styles-design.md` and the Phase 5 row of
its roadmap, `dev/specs/2026-10-17-table-styles-plan.md`.

**Architecture:** One summary table, `tbl`, is drawn twice in the template. `tbl-table` draws it
in the report style and shows it, as today. A new unnumbered `word-file` chunk draws it in the
manuscript style from three new study choices, `MANUSCRIPT_LAYOUT`, `MANUSCRIPT_CAPTION` and
`MANUSCRIPT_FILL`, saves it under its caption and checks the `.docx` with the manuscript style's
merged-cell rule; a new `tbl-word` chunk shows that saved table in the report.
`MANUSCRIPT_LAYOUT` sits inside the `dc-tables-config` migration region, because the migrator
must choose it (the compare layout cannot draw `%desc_tab`'s mean ± SD beside its
percentiles); the caption and the fill sit outside it and keep their `EDIT:` markers through a
migration.

**Tech Stack:** R (>= 4.4), hvtiRtables 1.0.8 (tag `v1.0.8`, `a0aa324`), gtsummary 2.5.1,
flextable 0.10.0, officer 0.7.6, xml2, testthat 3, Quarto CLI 1.10.18 (R package `quarto` 1.5.1),
hvtiRutilities 1.5.5, hvtiRpropensity 0.2.1, hvtiPlotR 2.8.14.

## Global Constraints

- Work on branch `feat/dc-tables-styles`, cut from `origin/main` (merge `origin/main`, never a
  local `main`, which concurrent sessions leave stale). Never push to `main`; open a PR and let
  John merge.
- **Patch digits only, and no `Version:` change in this feature PR.** The change ships
  (`inst/templates/`, `R/`, `DESCRIPTION`), so it adds `news/feat-dc-tables-styles.md`, the
  bullet exactly as it will read in `NEWS.md`, no heading. The bump, and
  `python3 .github/scripts/news.py collect`, are John's at release.
- **Floor:** `hvtiRtables (>= 1.0.8)` in `DESCRIPTION` Suggests AND in the template's setup
  guard, in the same commit: `test-templates.R`'s "DESCRIPTION's Suggests bounds match what the
  templates enforce" fails when they disagree.
- **Red first, and by mutation, for every new branch of code.** Run each new test before the
  code and see it fail for the stated reason; after the code, revert each mutation in the
  Task 4 table and see a test go red. A test that stays green under a mutation is not a test.
- **Stage files by name.** Never `git add -A` or `git add .`: a failing testthat run writes
  `tests/testthat/_problems/`, and a render leaves `.html`, `.docx` and `_files/` behind.
- **Render tests run against a private library**, never the default one, which concurrent
  sessions overwrite: `R CMD INSTALL -l <lib>` hvtiRtables `v1.0.8` (from a `git archive` of the
  tag) and this branch, then `R_LIBS=<lib>` for every test and render command. Quarto renders
  use the INSTALLED hvtiRtemplates, so reinstall the branch into `<lib>` after every template
  edit before a render test means anything.
- **Gates (AGENTS.md):** `R_LIBS=<lib> NOT_CRAN=true Rscript -e 'devtools::test()'`: FAIL 0,
  WARN 0 apart from the known `test-rf-templates.R` warnings (local runs only; CI expects WARN 0),
  and `SKIP 0` on macOS (CI: `SKIP 0` macOS and Ubuntu, `SKIP 3` Windows, read from
  `gh run view <id> --log | grep -E "SKIP [0-9]+ \| PASS"`, every leg). `devtools::check()` from
  a clean `git archive` export, manual and vignettes built: 0 errors, 0 warnings, 0 notes, apart
  from CRAN's "New submission" NOTE when the incoming checks run. `lintr::lint_package()`: 0
  lints, against the branch installed in `<lib>`. `python3 dev/specs/artifacts/check-spec-counts.py`,
  `check-flow-counts.py` and `check-roadmap-counts.py` all exit 0. The `news-fragment` job sees
  the fragment.
- **Lines are 135 columns** (`.lintr`), in the template's chunks and tests too. Roxygen is Rd
  markup; this plan changes no roxygen.
- **Template rules:** every study-specific line is marked `EDIT:`; a chunk holding a marker is
  labeled `edit-`; the setup chunk stays the single `setup` chunk; the template keeps its own
  `format:` block; no template text names a study, a study's data file or a manuscript; a chunk
  that calls a table function shows a numbered table (`tbl-` label and `tbl-cap`, no `caption =`)
  or says `# unnumbered: <reason>` (`test-template-numbering.R`). No `.lintr` change: no
  template file is added.
- **No PHI.** Synthetic data only. The migration report masks SAS title text (`"[string]"`), so
  no title text is copied into a job or a report.
- Run `/code-review` locally before opening the PR, and again after any later substantive push,
  and say in the PR body that it stood in for Copilot. AGENTS.md records the Copilot quota as
  exhausted since 2026-10-12 apart from three days; measure it with the reviews command there
  rather than assuming either way.
- US spelling. No em-dashes anywhere (a hook blocks them, even in grep patterns; use
  `\x{2014}` with `grep -P`).

## Checked 2026-10-20 against live state

- hvtiRtemplates `origin/main` is `17f1b42` (#365). Open PRs: #366 (draft, background jobs) and
  #367 (boostmtree install line); neither touches `dc-tables`, `R/migrate-dc-tables.R` or
  `R/upgrade-job.R`.
- hvtiRtables `origin/main` is `a0aa324`, tagged `v1.0.8`, Version 1.0.8. It carries Phases 1
  to 4. `hv_man_table(tbl, font, font_size, digits, style = "report", layout = "compare", ...)`;
  `hv_table_style(name = c("report", "manuscript"), fill = "#CAEDFB")`;
  `hv_man_table_save(ft, file, footnotes, abbreviations, caption = NULL, ...)`, which REQUIRES
  `caption` for a manuscript table; `hv_man_table_display(ft, footnotes, abbreviations)`;
  `hv_check_docx(path, style = NULL)`.
- **The `dc-tables` suite on `main` passes against hvtiRtables 1.0.8 unchanged** (helpers,
  render and migrate files, `NOT_CRAN=true`, private library). Phase 5 is therefore not a fix:
  today's template already runs on 1.0.8 and saves a report-style `.docx`, without the Variable
  column (hvtiRtables #82).
- The `dc-tables`, `dc-summary` and migrator work since 1.4.1 is unreleased: its fragments
  (`feat-dc-tables-summary-shape.md`, `feat-dc-tables-display-notes.md`,
  `feat-migrate-dc-tables-desc-tab.md`, `fix-migrate-dc-tables-overall-pair.md`) are in `news/`.
  This PR's fragment joins them under the next version.

## What the probe verified

A prototype of this plan, applied to a `git archive` of `17f1b42` and installed with
hvtiRtables `v1.0.8` into a scratch private library, was rendered through Quarto in scratch
studies built as `test-dc-tables-render.R` builds its study (60 synthetic patients, `grp` 0/1).
All of the following were measured, not inferred:

| case | saved `.docx` | `hv_check_docx()` | HTML report |
|---|---|---|---|
| `BY = "grp"`, `COMPARE = "pvalue"`, `STDDIFF`, `MEAN_SD = "age"`, `MANUSCRIPT_FILL = "#A5C9EB"`, layout `"compare"` | caption `Table 1. Patient characteristics` as the first paragraph; header row 1 `Characteristic \| n* \| Overall (N = 60) \| grp† \| P† \| Std. Diff. (%)`, row 2 `0 (N = 30) \| 1 (N = 30)`; section rows spanned and shaded `A5C9EB`; no Variable column; notes `*Patients with non-missing data.`, `†Values are No. (%) or median [15th, 85th percentiles]; P values from ...`, `‡Fisher exact test.`, `¶Mean±SD.`, `Key: NYHA, ...`; US Letter landscape (15840 x 12240 twips); no font name or size set in the table | `style = "manuscript"`: 0; `NULL`: 0; `"report"`: 4 (merged rows 1 to 3 and a section row) | both tables: the report table with its Variable column and `Number of non-missing values.`; the Word table with `Patients with non-missing data.`; Fisher note and key present; no `\|\|\|` sentinel |
| same, `CONTINUOUS_STAT = "both"`, layout `"describe"` | header row 1 `Characteristic \| Overall (N = 60) \| 0 (N = 30) \| 1 (N = 30) \| P†`, row 2 an `n*`, a `No. (%) or Mean±SD†` and a `Median [15th, 85th percentiles]` column under each group; fill `CAEDFB` | manuscript 0, NULL 0 | as above |
| same, `"both"`, layout `"compare"` | render stops in `word-file`: "The compare layout shows one statistic per group, and continuous_stat = "both" shows two. Build the table with continuous_stat = "median" or "mean"; layout = "describe" or the report style draws "both"." | none written | none |
| a new job: `BY <- NULL`, template defaults | header `Characteristic \| n* \| All patients (N = 60)†`; US Letter portrait | manuscript 0 | both tables |
| a draft: every `EDIT:` marker left in place, `HVTI_TEMPLATE_STRICT` unset | renders; `.docx` as in the row above | manuscript 0 | rendered (banners not inspected) |

Also measured:

- **`hv_check_docx(style = "manuscript")` applies the same rule as `style = NULL`.** Its strict
  mode is only `merged == "none"`, the report style. Passing `"manuscript"` therefore changes no
  finding today; it names the rule the file was written under, and follows hvtiRtables if a
  style ever gains a rule of its own. No mutation can tell the two apart, so the contract test in
  `test-templates.R` asserts the call's text instead (Task 2).
- **hvtiRtables validates the three new choices itself**, with messages that say what to do:
  `fill = "blue"` stops with "`fill` must be one color written "#RRGGBB""; `layout = "side"`
  with "`layout` must be "compare" or "describe""; `caption = NULL`, `NA` or `""` with "A
  manuscript table needs `caption` ..." or "`caption` must be a single non-empty string". The
  template adds no validation of its own.
- **`upgrade_job()` on a job written from today's template** (with `CONTINUOUS_STAT <- "both"`
  and `SHOW_VARIABLE <- FALSE` set) carried both choices, added `MANUSCRIPT_LAYOUT <- "compare"`,
  `MANUSCRIPT_CAPTION` and `MANUSCRIPT_FILL` with their `EDIT:` markers, and listed the three
  under "## New" in `<job>-upgrade.md`. Rendering that upgraded job stops at the compare
  layout's message above until `MANUSCRIPT_LAYOUT <- "describe"` is set (decision 4).
- **The existing tests went red against `main`'s code, and green on the prototype.** With this
  plan's tests on `main`: `FAIL 12 | PASS 109` in `test-migrate-dc-tables.R`. On the prototype:
  `FAIL 0 | WARN 0 | SKIP 0 | PASS 141` there, and `FAIL 0 | WARN 0 | SKIP 0 | PASS 2347` over
  `dc-tables|vignette-migration|^templates$|template-numbering|template-catalog|upgrade-job`.
  Each mutation in Task 4's table turned a test red (measured: M1 to M6).
- `lintr::lint_package()` on the prototype: 0 lints, once `tests/testthat/_problems/` was
  deleted. The mutation runs had written six files there, and `lint_package()` lints them (six
  lints on the first run). No line of the prototype exceeds 135 columns. The three count
  scripts exit 0 on it (36 templates on disk, unchanged).
- **The full suite was not completed in the probe:** the background run was stopped by the
  session's time limit partway through the rf templates. Task 4 step 2 runs it.
- **An unrelated hvtiRtables defect, found by the probe:** a global object named `sd` makes
  `hv_tbl_summary()` fail with gtsummary's "Error in the argument `statistic` ... Value must be
  a named list of functions" whenever mean ± SD is shown (`continuous_stat = "mean"`, `"both"`,
  or any `mean_sd`), in 1.0.7 and 1.0.8 alike. A study whose `R/` defines `sd` would break
  `dc-tables`. Out of scope here; raise it in hvtiRtables.
- **Not verified:** the HTML was read as text, not looked at in a browser (the browser pane could
  not open the scratch file). Task 4 step 6 looks at it.

## Decisions this plan takes

Each has a default and its reason. The PR lists them for John.

1. **The new choices are `MANUSCRIPT_LAYOUT`, `MANUSCRIPT_CAPTION` and `MANUSCRIPT_FILL`.** The
   roadmap row said `MANUSCRIPT_STYLE`, but the Word table's style is fixed (manuscript); what a
   study chooses is hvtiRtables' `layout =`, so the choice takes that name. Defaults:
   `MANUSCRIPT_LAYOUT <- "compare"`, hvtiRtables' default and the shape of a Table 1 that
   compares groups; `MANUSCRIPT_FILL <- "#CAEDFB"`, the house default (design question 6).
2. **The caption has a default value AND an `EDIT:` marker** (confirmed by John, 2026-10-20):
   `MANUSCRIPT_CAPTION <- "Table 1. Patient characteristics"`. `hv_man_table_save()` refuses a
   manuscript table without one, so a `NULL` default would stop every draft render, the demo
   study and the gallery, which resolve markers and keep defaults. The marker makes a final
   render refuse the job until someone has read the caption. The caption is not filled from the
   SAS `title` statements: the migration report masks title text on purpose, and points instead
   at `MANUSCRIPT_CAPTION` (Task 1).
3. **`MANUSCRIPT_LAYOUT` is inside the `dc-tables-config` migration region; the caption and the
   fill are outside it.** The region is replaced whole by the migrator, so a choice inside it
   must be written by the migrator or it vanishes from a migrated job. The layout has to be
   chosen there (decision 5). The caption and the fill have nothing in the SAS source to choose
   them from, so they stay template defaults with their markers.
4. **Jobs scaffolded before this change keep working and are not touched.** They run on
   hvtiRtables 1.0.8 (measured: the `main` suite passes) and keep saving a report-style `.docx`
   with the Variable column dropped. `upgrade_job()` is not changed: it already carries a job's
   choices and adds the three new ones with their markers (probed). A migrated job with
   `CONTINUOUS_STAT <- "both"` that is upgraded gets `MANUSCRIPT_LAYOUT <- "compare"` and its
   render stops with hvtiRtables' message naming `layout = "describe"`. **No template guard
   rewords that message**: the comment beside `MANUSCRIPT_LAYOUT` says "describe" is the layout
   that draws "both", the upgrade report lists the choice as new, and a guard is a branch to
   keep in step with hvtiRtables' own rule. Say if you want the guard; it is four lines.
5. **The migrator maps `%desc_tab` to a layout by the statistics it printed:** `"describe"` when
   it writes `CONTINUOUS_STAT <- "both"` (every `%desc_tab` job with a continuous variable), since
   the compare layout refuses two statistics per group; `"compare"` otherwise, by group or
   overall. A table with no `by=` and no continuous variable takes `"compare"`: the design's
   no-grouping shape (section 5.1, `Characteristic | n* | All patients (N = n)`) is what the
   compare layout draws (probed), and nothing is side by side. **Amended 2026-10-20, after
   implementation:** an earlier wording said every table with no `by=` takes `"compare"`. A
   continuous one does not: `%desc_tab` printed both statistics, the migrator writes
   `CONTINUOUS_STAT <- "both"`, and against hvtiRtables 1.0.8 `"describe"` is the only layout
   that draws it, so the rule above governs and the job gets `"describe"`. A job whose source logic blocks
   the mapping gets the template default, `"compare"`, as every other choice falls back to it
   there.
6. **The report also shows the Word table** (`tbl-word`, "The table as saved to Word, in the
   manuscript style"). The 2026-10-16 meeting asked that the HTML and the Word table be the same
   table (dc-summary design, section 5a, item 3), and #352 met that by showing the saved table.
   With the two styles that no longer holds, so the report shows both: the working table with
   its Variable column, and the table a reader of the `.docx` sees. The cost is the table twice
   on the page. Dropping `tbl-word` leaves `word-file` as it is.
7. **The report table keeps the report style's own fill,** `#CAEDFB`, not `MANUSCRIPT_FILL`.
   The fill is a journal's choice, and the report goes to no journal.
8. **The gallery rebuild follows, on the release day of the hvtiRtemplates version that ships
   this** (AGENTS.md, "Release ordering"), not in this PR. hvtiRtables 1.0.8's notation and
   Letter pages have already changed every `dc-tables` output; one rebuild after this release
   covers both. The meeting's item 9 (the gallery shows no saved `.docx`) is not addressed here.
9. **No version change in this PR.** At release it is a patch bump under the house rule. It
   changes the `.docx` of every new and upgraded `dc-tables` job, which you may judge worth a
   minor; that is your call, not this plan's.

## File structure

| file | change | task |
|---|---|---|
| `R/migrate-dc-tables.R` | choose and write `MANUSCRIPT_LAYOUT`; record it in the report; the title row names `MANUSCRIPT_CAPTION` | 1 |
| `inst/templates/10_descriptive/dc-tables.qmd` | `MANUSCRIPT_LAYOUT` in the config region (1); floor, prose, `MANUSCRIPT_CAPTION`, `MANUSCRIPT_FILL`, `SHOW_VARIABLE` wording, the `word-file` and `tbl-word` chunks (2) | 1, 2 |
| `tests/testthat/test-migrate-dc-tables.R` | layout mapping tests; the manuscript-table test; the chunk renamed in two tests | 1, 2 |
| `DESCRIPTION` | `hvtiRtables (>= 1.0.8)` in Suggests | 2 |
| `tests/testthat/test-dc-tables-render.R` | floor; assertions on both tables and the saved `.docx` | 2 |
| `tests/testthat/test-templates.R` | the `dc-tables` contract names the manuscript calls | 2 |
| `tests/testthat/test-vignette-migration.R` | the migrated-fixture render skips below hvtiRtables 1.0.8 | 2 |
| `inst/extdata/templates.json` | `hvtiRtables::hv_table_style` in `dc-tables`' `uses` | 2 |
| `vignettes/sas-to-r-descriptive.qmd` | one paragraph on the two styles and the layout | 3 |
| `news/feat-dc-tables-styles.md` | the fragment | 3 |

No change to `R/upgrade-job.R`, `inst/templates/README.md` (its `dc-tables` row, "CORR Word
tables and optional correlations", stays true), `.lintr`, `_pkgdown.yml` or `man/`.

---

### Task 0: Re-measure, branch, and build the private library

**Files:** none.

- [ ] **Step 1: Re-measure the live state.** Re-run each line of "Checked 2026-10-20" above:
  `git fetch origin && git log --oneline -1 origin/main`, `gh pr list --state open`, and in
  hvtiRtables `git fetch && git log --oneline -1 origin/main && git describe --tags origin/main`.
  If `origin/main` touched `dc-tables.qmd`, `R/migrate-dc-tables.R` or its tests, or hvtiRtables
  has moved past 1.0.8, stop and re-read before going on.

- [ ] **Step 2: Branch.**

```bash
cd ~/Documents/GitHub/hvtiRtemplates
git fetch origin
git worktree add ../hvtiRtemplates-dc-styles -b feat/dc-tables-styles origin/main
```

- [ ] **Step 3: Build the private library** (the scratch directory is the session's).

```bash
LIB=<scratch>/lib; SRC=<scratch>/src; mkdir -p "$LIB" "$SRC"
(cd ~/Documents/GitHub/hvtiRtables && git archive v1.0.8 --prefix=hvtiRtables/ | tar -x -C "$SRC")
R CMD INSTALL -l "$LIB" "$SRC/hvtiRtables"
R CMD INSTALL -l "$LIB" ~/Documents/GitHub/hvtiRtemplates-dc-styles
R_LIBS="$LIB" Rscript -e 'cat(format(packageVersion("hvtiRtables")), format(packageVersion("hvtiRtemplates")), "\n")'
```

Expected: `1.0.8 1.4.1`.

- [ ] **Step 4: Baseline.** From the worktree:

```bash
R_LIBS="$LIB" NOT_CRAN=true Rscript -e 'devtools::test(filter = "dc-tables", reporter = "check")'
```

Expected: `FAIL 0 | WARN 0 | SKIP 0`. Record the PASS count for the PR.

---

### Task 1: The migrator chooses the Word table's layout

**Files:**
- Modify: `R/migrate-dc-tables.R:156` (the title row's reason), `:218-220` (after the
  `COMPARE` record), `:243-244` (the blocked-source reset), `:264` (the config lines)
- Modify: `inst/templates/10_descriptive/dc-tables.qmd:151-152` (the config region's end)
- Test: `tests/testthat/test-migrate-dc-tables.R`

**Interfaces:**
- Consumes: `.migrate_dc_tables(evidence, template)` as on `main`; the `tables_config()`,
  `tables_region()` and `tables_migrate()` helpers in `test-migrate-dc-tables.R`.
- Produces: every migrated job's `dc-tables-config` region ends with
  `MANUSCRIPT_LAYOUT <- "describe"` or `MANUSCRIPT_LAYOUT <- "compare"`; the report's Translated
  section gains a row `MANUSCRIPT_LAYOUT: <layout>`; a title row's reason reads
  `Review title against MANUSCRIPT_CAPTION, the Word table's caption.` The template's region
  carries `MANUSCRIPT_LAYOUT <- "compare"`, which Task 2 reads.

- [ ] **Step 1: Write the failing tests.** Append to `tests/testthat/test-migrate-dc-tables.R`:

```r
# ---- the Word table's layout --------------------------------------------------

test_that("a migrated job lays its Word table out by what %desc_tab printed", {
  # Mean +/- SD beside the percentiles is two statistics per group, which only
  # the describe layout draws; hv_man_table() refuses it in the compare layout.
  both <- tables_config("%desc_tab(vartype=continuous,input=built,by=treatment,varlist=/* Demography */ age);")
  expect_identical(both$env$CONTINUOUS_STAT, "both")
  expect_identical(both$env$MANUSCRIPT_LAYOUT, "describe")
  expect_true(any(grepl("MANUSCRIPT_LAYOUT: describe", both$translated, fixed = TRUE)))
  # One statistic per variable, by group or overall: the compare layout.
  by_group <- tables_config("%desc_tab(vartype=category,input=built,by=treatment,varlist=/* Demography */ female);")
  expect_identical(by_group$env$MANUSCRIPT_LAYOUT, "compare")
  expect_true(any(grepl("MANUSCRIPT_LAYOUT: compare", by_group$translated, fixed = TRUE)))
  overall <- tables_config("%desc_tab(vartype=category,input=built,by=,varlist=/* Demography */ female);")
  expect_identical(overall$env$MANUSCRIPT_LAYOUT, "compare")
})
```

In "dc-tables blocks local DATA-step filters and transformed measurements", after
`expect_identical(env$CONTINUOUS_STAT, "median")`, add:

```r
  expect_identical(env$MANUSCRIPT_LAYOUT, "compare")
```

In "the overall and by-group calls of tp.dc.tables.ods.sas migrate to one table", after
`expect_identical(env$CONTINUOUS_STAT, "both")`, add:

```r
  expect_identical(env$MANUSCRIPT_LAYOUT, "describe")
```

In "dc-tables retains complete title statements and their starting lines", change the reason
the test selects on:

```r
  titles <- result$unresolved[result$unresolved$reason == "Review title against MANUSCRIPT_CAPTION, the Word table's caption.", ]
```

- [ ] **Step 2: Run them and see them fail.**

```bash
R_LIBS="$LIB" NOT_CRAN=true Rscript -e 'devtools::test(filter = "migrate-dc-tables", reporter = "check")'
```

Expected: FAIL in the four tests above: `MANUSCRIPT_LAYOUT` is `NULL` in every migrated region,
no Translated row names it, and the title test selects no rows (`titles$line` is
`integer(0)`).

- [ ] **Step 3: Write the code.** In `R/migrate-dc-tables.R`, change the title row's reason
(line 156):

```r
                                           "Review title against MANUSCRIPT_CAPTION, the Word table's caption."))
```

After the `COMPARE: ...; CONTINUOUS_STAT: ...` record (line 220), add:

```r
  # The Word table's layout. The compare layout draws one statistic per group,
  # so %desc_tab's mean +/- SD beside its percentiles needs the describe layout.
  layout <- if (identical(continuous_stat, "both")) "describe" else "compare"
  layout_reason <- if (identical(layout, "describe")) {
    "CONTINUOUS_STAT is both, which only the describe layout draws in the Word table."
  } else {
    "One statistic per variable: the compare layout, one n column beside the groups."
  }
  translated <- rbind(translated, record(calls[[1L]]$start, paste0("MANUSCRIPT_LAYOUT: ", layout), layout_reason))
```

The record is added before the blocked-source block on purpose: that block moves every
Translated row to Unresolved as a candidate, this one included. In that block, after
`percentiles <- c(15, 85)`, add the reset, so the job falls back to the template default as
every other choice there does:

```r
    layout <- "compare"
```

In `config`, after `'WORD_FILE <- "dc-tables.docx"',` add:

```r
    paste0("MANUSCRIPT_LAYOUT <- ", quote_r(layout)),
```

Leave the two `# EDIT:` lines the config ends with unchanged:
`tests/testthat/fixtures-migration/dc-tables/review-markers.txt` declares
`# EDIT: confirm comparison, summaries, percentiles, abbreviations and Word filename.` by its
exact text, and `render_all_migration_fixtures()` stops if it is not found. The new line is
covered by `# EDIT: review SAS presentation choices in the migration report.`, and the report
row says why the layout was chosen.

In `inst/templates/10_descriptive/dc-tables.qmd`, end the config region with the choice and
explain it just below the region, where the migrator does not overwrite the comment:

```r
WORD_FILE <- "dc-tables.docx"  # EDIT: choose the Word filename within this set
MANUSCRIPT_LAYOUT <- "compare" # EDIT: choose the Word table's layout
# MIGRATE-END: dc-tables-config
# The Word table is drawn in the manuscript style. MANUSCRIPT_LAYOUT, above,
# says what the table does: "compare" puts one n column beside the groups it
# compares; "describe" puts a count beside each group, for cohorts or repeated
# measures shown side by side. "describe" is also the layout that draws
# CONTINUOUS_STAT "both": "compare" has one statistic column per group.
```

- [ ] **Step 4: Run the tests and see them pass.**

```bash
R_LIBS="$LIB" NOT_CRAN=true Rscript -e \
  'devtools::test(filter = "migrate-dc-tables|^templates$|template-numbering", reporter = "check")'
```

Expected: `FAIL 0 | WARN 0 | SKIP 0`. The template does not read `MANUSCRIPT_LAYOUT` yet, so the
migrated-document test still saves today's report-style table and passes.

- [ ] **Step 5: Commit.**

```bash
git add R/migrate-dc-tables.R inst/templates/10_descriptive/dc-tables.qmd tests/testthat/test-migrate-dc-tables.R
git commit -m "feat(migrate_job): a migrated dc-tables job chooses its Word table's layout"
```

---

### Task 2: The Word export takes the manuscript style

**Files:**
- Modify: `inst/templates/10_descriptive/dc-tables.qmd:26-33` (prose), `:52-55` (floor),
  after the Task 1 comment (two choices), `:173-175` (`SHOW_VARIABLE`), `:359-415` (the table
  chunk, split)
- Modify: `DESCRIPTION:59`
- Modify: `inst/extdata/templates.json:1468` (`dc-tables`' `uses`)
- Test: `tests/testthat/test-migrate-dc-tables.R`, `tests/testthat/test-dc-tables-render.R`,
  `tests/testthat/test-templates.R`, `tests/testthat/test-vignette-migration.R`

**Interfaces:**
- Consumes: `MANUSCRIPT_LAYOUT` from Task 1; hvtiRtables 1.0.8's `hv_table_style()`,
  `hv_man_table(style =, layout =)`, `hv_man_table_save(caption =)`,
  `hv_man_table_display()`, `hv_check_docx(style =)`.
- Produces: in a rendered job, `ft` (the report-style flextable, `hv_style$name == "report"`,
  with an `hv_variable` column when `SHOW_VARIABLE`), `word_ft` (the manuscript-style
  flextable, no `hv_variable` column), `word_path` (the saved `.docx`), and `check` (its
  findings, zero rows). Chunks: `tbl-table` (shows `ft`), `word-file` (unnumbered; builds
  `word_ft`, saves, checks), `tbl-word` (shows `word_ft`).

- [ ] **Step 1: Write the failing tests.** Append to `tests/testthat/test-migrate-dc-tables.R`,
after the Task 1 test:

```r
test_that("the Word table is drawn in the manuscript style, under the study's caption, fill and layout", {
  skip_on_cran()
  root <- migration_study_fixture("dc-tables")
  template <- template_path("dc", "tables")
  env <- new.env()
  env$.root <- root
  env$SUBJECT <- "cohort"
  env$TYPE <- "eda"
  env$study_dir <- hvtiRutilities::study_dir
  env$d <- hvtiRutilities::read_built(hvtiRutilities::study_config(root))
  env$GROUPS <- list(Demography = c("age", "female", "race_grp"), Procedure = "repair")
  env$BY <- "treatment"
  env$CONTINUOUS <- "age"
  env$BINARY <- c("female", "repair")
  env$CATEGORICAL <- "race_grp"
  env$COMPARE <- "pvalue"
  env$CONTINUOUS_STAT <- "median"
  env$PERCENTILES <- c(15, 85)
  env$ABBREVIATIONS <- character(0)
  env$WORD_FILE <- "dc-tables.docx"
  env$OVERRIDES <- list()
  env$MEAN_SD <- env$ORDINAL <- character(0)
  env$STDDIFF <- FALSE
  env$GROUP_1 <- NULL
  env$SHOW_VARIABLE <- TRUE
  env$MANUSCRIPT_LAYOUT <- "compare"
  env$MANUSCRIPT_CAPTION <- "Table 2. Operative details"
  env$MANUSCRIPT_FILL <- "#A5C9EB"
  eval(tables_chunk(template, "helpers"), env)
  invisible(eval(tables_chunk(template, "tbl-table"), env))
  invisible(eval(tables_chunk(template, "word-file"), env))
  word <- file.path(root, "documents", "cohort-eda", "dc-tables.docx")
  # The report keeps the Variable column; the Word table never has it.
  expect_true("hv_variable" %in% env$ft$col_keys)
  expect_false("hv_variable" %in% env$word_ft$col_keys)
  expect_identical(attr(env$ft, "hv_style")$name, "report")
  expect_identical(attr(env$word_ft, "hv_style")$name, "manuscript")
  expect_identical(nrow(hvtiRtables::hv_check_docx(word, style = "manuscript")), 0L)
  doc <- officer::docx_summary(officer::read_docx(word))
  expect_identical(doc$text[doc$content_type == "paragraph"][[1L]], "Table 2. Operative details")
  cells <- doc[doc$content_type == "table cell", ]
  expect_identical(cells$text[cells$row_id == 1L][1:2], c("Characteristic", "n*"))
  expect_false(any(cells$text == "Variable"))
  xml <- xml2::read_xml(unzip(word, "word/document.xml", exdir = withr::local_tempdir()))
  fills <- xml2::xml_attr(xml2::xml_find_all(xml, "//w:tc/w:tcPr/w:shd", xml2::xml_ns(xml)), "fill")
  expect_true("A5C9EB" %in% fills)
  expect_false("CAEDFB" %in% fills)
  # The describe layout draws both statistics, with a count beside each group.
  env$CONTINUOUS_STAT <- "both"
  env$MANUSCRIPT_LAYOUT <- "describe"
  invisible(eval(tables_chunk(template, "tbl-table"), env))
  invisible(eval(tables_chunk(template, "word-file"), env))
  cells <- officer::docx_summary(officer::read_docx(word))
  cells <- cells[cells$content_type == "table cell" & cells$row_id == 2L, ]
  expect_gt(sum(cells$text == "n*"), 1L)
  expect_identical(nrow(hvtiRtables::hv_check_docx(word, style = "manuscript")), 0L)
  # A manuscript table is never saved without its caption.
  env$MANUSCRIPT_CAPTION <- NULL
  expect_error(eval(tables_chunk(template, "word-file"), env), "needs `caption`", fixed = TRUE)
})
```

In "migrated dc-tables writes an editable structurally clean document in the logical documents
folder", give the two choices outside the region their template defaults, and run the new
chunk:

```r
  env$SHOW_VARIABLE <- TRUE
  env$MANUSCRIPT_CAPTION <- "Table 1. Patient characteristics"
  env$MANUSCRIPT_FILL <- "#CAEDFB"
```

```r
  invisible(eval(tables_chunk(out, "tbl-table"), env))
  invisible(eval(tables_chunk(out, "word-file"), env))
  word <- file.path(root, "documents", "cohort-eda", "dc-tables.docx")
```

and the WORD_FILE escape at its end now stops in `word-file`:

```r
  env$WORD_FILE <- "../escape.docx"
  invisible(eval(tables_chunk(out, "tbl-table"), env))
  expect_error(invisible(eval(tables_chunk(out, "word-file"), env)), "plain .docx filename", fixed = TRUE)
```

This test now saves a describe-layout table, since the fixture migrates to
`CONTINUOUS_STAT <- "both"` and, after Task 1, `MANUSCRIPT_LAYOUT <- "describe"`; its
`hv_check_docx(word)` assertion stays as it is.

In "dc-tables stops on actual CORR structural findings", the `check <-` line moves:

```r
  code <- tables_chunk(template_path("dc", "tables"), "word-file")
```

In `tests/testthat/test-dc-tables-render.R`, update the header comment and the skip, and assert
both tables and the saved file:

```r
# dc-tables end to end with the %summarytable shape: %stddiff's difference
# beside the p-value, mean +/- SD for named variables, the report's table in the
# report style, and the Word table in the manuscript style shown beneath it.
```

```r
  skip_if(utils::packageVersion("hvtiRtables") < "1.0.8", "needs hvtiRtables >= 1.0.8")
```

```r
  expect_match(html, "New York Heart Association", fixed = TRUE)
  # Both tables are in the report: the report style's count note, and the Word
  # table's, which the manuscript style words differently.
  expect_match(html, "Number of non-missing values.", fixed = TRUE)
  expect_match(html, "Patients with non-missing data.", fixed = TRUE)
  docx <- list.files(hvtiRutilities::study_dir("documents", root), pattern = "[.]docx$",
                     recursive = TRUE, full.names = TRUE)
  expect_length(docx, 1L)
  expect_identical(nrow(hvtiRtables::hv_check_docx(docx, style = "manuscript")), 0L)
  doc <- officer::docx_summary(officer::read_docx(docx))
  expect_identical(doc$text[doc$content_type == "paragraph"][[1L]], "Table 1. Patient characteristics")
```

In `tests/testthat/test-templates.R`, "dc-tables carries the registered-data and checked Word
pipeline contract", extend the required calls. This is what holds `style = "manuscript"` on the
check, which no behavioral test can (it is the default rule today):

```r
    "hvtiRtables::hv_man_table_save(", "hvtiRtables::hv_check_docx(",
    'hvtiRtables::hv_table_style("manuscript", fill = MANUSCRIPT_FILL)', "layout = MANUSCRIPT_LAYOUT",
    "caption = MANUSCRIPT_CAPTION", 'hv_check_docx(word_path, style = "manuscript")',
```

In `tests/testthat/test-vignette-migration.R`, "the final migration verifier returns four
lasting rendered fixtures" renders the migrated `dc-tables` job, which now refuses below
1.0.8, so it must skip there rather than fail:

```r
  skip_if_not_installed("hvtiRtables", "1.0.8")
```

- [ ] **Step 2: Run them and see them fail.** Reinstall first, since the render tests read the
installed template:

```bash
R CMD INSTALL -l "$LIB" .
R_LIBS="$LIB" NOT_CRAN=true Rscript -e 'devtools::test(filter = "dc-tables|^templates$", reporter = "check")'
```

Expected: FAIL. `tables_chunk(..., "word-file")` finds no chunk (the new test, the migrated
document test, the structural-findings test); the render test finds no
`Patients with non-missing data.` and no caption paragraph; the contract test finds none of the
four new calls.

- [ ] **Step 3: Write the template.** In `inst/templates/10_descriptive/dc-tables.qmd`:

The prose under the title, from "The default is ..." (Phase 1's notation, and the two styles):

```markdown
The default is median [15th, 85th percentiles].
`%desc_tab` wrote the categorical and continuous tables as two
RTF files; `hv_tbl_summary()` writes one table with both. It describes; with
`BY` set it separates the groups into columns. `COMPARE` chooses whether to
test them; a p-value here is a prompt for an analysis, not a result.
The report shows the table in the report style, with each variable's column
name beside its label. The Word file holds the same table in the manuscript
style, under its caption, as a journal receives it.
```

The floor in the setup chunk:

```r
if (utils::packageVersion("hvtiRtables") < "1.0.8") {
  stop("This job needs hvtiRtables >= 1.0.8 for hv_table_style() and the manuscript Word table; ",
       utils::packageVersion("hvtiRtables"), " is installed.", call. = FALSE)
}
```

The two choices, directly after the comment Task 1 placed below the region:

```r
# EDIT: the Word table's caption, written in bold above it. A manuscript
# table must carry one, so the title is never typed into Word by hand.
MANUSCRIPT_CAPTION <- "Table 1. Patient characteristics"
# EDIT: the shading of the Word table's section rows, one color "#RRGGBB".
# Journals differ here; "#CAEDFB" is the house default.
MANUSCRIPT_FILL <- "#CAEDFB"
```

`SHOW_VARIABLE` becomes report-only (hvtiRtables drops the column from every saved `.docx`
since #82, and the manuscript style never draws it):

```r
# EDIT: FALSE drops the Variable column, the column name beside each label,
# from the report. The Word table never carries it, whatever this says.
SHOW_VARIABLE <- TRUE
```

The `tbl-table` caption loses "as written to the Word file":

```r
#| tbl-cap: "Summary statistics for the study cohort"
```

and the chunk ends at the report table; everything from the `WORD_FILE` check down moves into
two new chunks. Replace from the comment above `ft <- hvtiRtables::hv_man_table(tbl)` to the end
of the chunk, its closing fence included, with:

````markdown
# The report's table, in the report style. hv_man_table_display() adds the
# header marks, notes and abbreviation key the Word table carries, from the
# saver's own code.
ft <- hvtiRtables::hv_man_table(tbl)
hvtiRtables::hv_man_table_display(ft, abbreviations = ABBREVIATIONS)
```

```{r}
#| label: word-file
# unnumbered: writes the Word file; the table below shows what it holds
# The same summary, drawn for the manuscript. MANUSCRIPT_CAPTION is written into
# the .docx above the table; this report numbers its own tables.
word_ft <- hvtiRtables::hv_man_table(
  tbl, style = hvtiRtables::hv_table_style("manuscript", fill = MANUSCRIPT_FILL),
  layout = MANUSCRIPT_LAYOUT
)
if (length(WORD_FILE) != 1L || is.na(WORD_FILE) ||
      !grepl("^[A-Za-z0-9_][A-Za-z0-9_.-]*[.]docx$", WORD_FILE)) {
  stop("WORD_FILE must be a plain .docx filename within this set.", call. = FALSE)
}
word_path <- file.path(study_dir("documents", .root), paste0(SUBJECT, "-", TYPE), WORD_FILE)
dir.create(dirname(word_path), recursive = TRUE, showWarnings = FALSE)
hvtiRtables::hv_man_table_save(word_ft, word_path, abbreviations = ABBREVIATIONS, caption = MANUSCRIPT_CAPTION)
# The manuscript style merges its header and section rows, and nothing else.
check <- hvtiRtables::hv_check_docx(word_path, style = "manuscript")
if (nrow(check)) stop("Word output failed the CORR structural check", call. = FALSE)
```

```{r}
#| label: tbl-word
#| tbl-cap: "The table as saved to Word, in the manuscript style"
hvtiRtables::hv_man_table_display(word_ft, abbreviations = ABBREVIATIONS)
```
````

Why the split is three chunks: `test-template-numbering.R` refuses `caption =` in a chunk that
shows a table (a report caption belongs in `tbl-cap`), and the `.docx` caption has to be passed
to the saver. The save therefore lives in an `# unnumbered:` chunk and the display in its own
numbered one. `check` stays the last assignment before the `stop()` so the structural-findings
test can run the chunk from there with only `word_path` set; a literal `"manuscript"`, not the
style object, keeps that true.

In `DESCRIPTION` Suggests:

```
    hvtiRtables (>= 1.0.8),
```

In `inst/extdata/templates.json`, `dc-tables`' `uses`, after `"hvtiRtables::hv_man_table_display",`:

```json
        "hvtiRtables::hv_table_style",
```

- [ ] **Step 4: Run the tests and see them pass.** Reinstall, then:

```bash
R CMD INSTALL -l "$LIB" .
R_LIBS="$LIB" NOT_CRAN=true Rscript -e 'devtools::test(filter = "dc-tables|vignette-migration|^templates$|template-numbering|template-catalog|upgrade-job", reporter = "check")'
```

Expected: `FAIL 0 | WARN 0 | SKIP 0` (the prototype read `PASS 2347`).

- [ ] **Step 5: Lint the changed files.**

```bash
R_LIBS="$LIB" Rscript -e 'for (f in c("inst/templates/10_descriptive/dc-tables.qmd", "R/migrate-dc-tables.R",
  "tests/testthat/test-migrate-dc-tables.R", "tests/testthat/test-dc-tables-render.R")) print(lintr::lint(f))'
awk 'length > 135 {print FILENAME": "FNR}' inst/templates/10_descriptive/dc-tables.qmd R/migrate-dc-tables.R tests/testthat/test-*dc-tables*.R
```

Expected: no lints, no line printed.

- [ ] **Step 6: Commit.**

```bash
git add inst/templates/10_descriptive/dc-tables.qmd DESCRIPTION inst/extdata/templates.json \
  tests/testthat/test-migrate-dc-tables.R tests/testthat/test-dc-tables-render.R \
  tests/testthat/test-templates.R tests/testthat/test-vignette-migration.R
git commit -m "feat(dc-tables): the Word table takes the manuscript style; the report keeps the report style"
```

---

### Task 3: The vignette and the news fragment

**Files:**
- Modify: `vignettes/sas-to-r-descriptive.qmd:208` (after "`migrate_job()` writes these choices
  and lists the differences in its report.")
- Create: `news/feat-dc-tables-styles.md`

**Interfaces:** none; prose only.

- [ ] **Step 1: The vignette.** After the sentence named above, add:

```markdown
The report shows the table in the report style, with each variable's column
name; the Word file holds it in the manuscript style, under `MANUSCRIPT_CAPTION`
and shaded in `MANUSCRIPT_FILL`. A migrated job that shows both statistics gets
`MANUSCRIPT_LAYOUT <- "describe"`, the manuscript layout that draws them.
```

The vignette's executable chunk calls `hv_tbl_summary()` only and needs no change.

- [ ] **Step 2: The fragment,** `news/feat-dc-tables-styles.md`, exactly:

```markdown
* `dc-tables` saves its Word table in hvtiRtables' manuscript style: a full
  grid, a two-row header with the grouping spanning its levels, shaded section
  rows that span the table, the notes below it, and a caption above it. Three
  study choices set it: `MANUSCRIPT_LAYOUT` (`"compare"`, one `n` column beside
  the groups, or `"describe"`, a count beside each group), `MANUSCRIPT_CAPTION`
  and `MANUSCRIPT_FILL`. The report keeps the report style, with the Variable
  column, and shows the Word table beneath it. `SHOW_VARIABLE` now applies to
  the report only. `migrate_job()` writes `MANUSCRIPT_LAYOUT <- "describe"` for
  a `%desc_tab` job that printed mean ± SD beside the percentiles, which the
  compare layout cannot draw. Needs hvtiRtables 1.0.8. A job scaffolded before
  this keeps working and keeps its report-style Word table; `upgrade_job()`
  adds the three choices, each with its `EDIT:` marker.
```

- [ ] **Step 3: Render the vignette and run the vignette tests.**

```bash
R_LIBS="$LIB" Rscript -e 'quarto::quarto_render("vignettes/sas-to-r-descriptive.qmd", quiet = TRUE)'
R_LIBS="$LIB" NOT_CRAN=true Rscript -e 'devtools::test(filter = "vignette", reporter = "check")'
git status --short
```

Expected: the render succeeds, `FAIL 0`; delete the rendered `.html` and `_files/` it leaves
(they are not committed).

- [ ] **Step 4: Commit.**

```bash
git add vignettes/sas-to-r-descriptive.qmd news/feat-dc-tables-styles.md
git commit -m "docs(dc-tables): the two table styles in the descriptive guide; news fragment"
```

---

### Task 4: Gates, mutations and review

**Files:** none changed unless a gate fails.

- [ ] **Step 1: Mutations.** Apply each, reinstall when the template changes, run
`R_LIBS="$LIB" NOT_CRAN=true Rscript -e 'devtools::test(filter = "migrate-dc-tables", reporter = "check")'`,
record the result, and revert. Each was red on the prototype (FAIL count in brackets).

| # | mutation | expected red |
|---|---|---|
| M1 | `hv_table_style("manuscript", fill = MANUSCRIPT_FILL)` to `hv_table_style("manuscript")` | the manuscript-table test, fill assertions [2] |
| M2 | `layout = MANUSCRIPT_LAYOUT` to `layout = "compare"` | the migrated-document test and the describe half of the manuscript-table test [2] |
| M3 | `hv_man_table_save(word_ft,` to `hv_man_table_save(ft,` | the manuscript-table test: header, Variable, fill [5] |
| M4 | delete the blocked-source `layout <- "compare"` | the DATA-step test [1] |
| M5 | `if (identical(continuous_stat, "both")) "describe" else "compare"` to `"compare"` | the layout test, the overall-pair test, the migrated-document test [4] |
| M6 | delete `paste0("MANUSCRIPT_LAYOUT <- ", quote_r(layout)),` | the layout, DATA-step, overall-pair and migrated-document tests [6] |

Removing `style = "manuscript"` from `hv_check_docx()` is caught by the contract test in
`test-templates.R`, not by behavior (see "What the probe verified").

- [ ] **Step 2: The full suite.**

```bash
R CMD INSTALL -l "$LIB" .
R_LIBS="$LIB" NOT_CRAN=true Rscript -e 'devtools::test()' 2>&1 | tee <scratch>/full.log | tail -5
```

Expected: FAIL 0, SKIP 0; WARN only the known `test-rf-templates.R` warnings. Report the PASS
count beside Task 0's baseline.

- [ ] **Step 3: Check, from a clean export.**

```bash
EXP=<scratch>/export; rm -rf "$EXP"; mkdir -p "$EXP"
git archive HEAD --prefix=hvtiRtemplates/ | tar -x -C "$EXP"
cd "$EXP" && R_LIBS="$LIB" R CMD build hvtiRtemplates && R_LIBS="$LIB" NOT_CRAN=true R CMD check --as-cran hvtiRtemplates_*.tar.gz
```

Expected: `Status: OK`, or only CRAN's "New submission" NOTE. Read the per-step timings; the
new test carries `skip_on_cran()`, so the CRAN-mode check time does not move.

- [ ] **Step 4: Lint and the count scripts.** Delete `tests/testthat/_problems/` first: the
mutation runs of step 1 write files there, and `lint_package()` lints them (measured).

```bash
rm -rf tests/testthat/_problems
R_LIBS="$LIB" Rscript -e 'print(length(lintr::lint_package()))'
python3 dev/specs/artifacts/check-spec-counts.py && python3 dev/specs/artifacts/check-flow-counts.py && python3 dev/specs/artifacts/check-roadmap-counts.py
```

Expected: `0`, and all three scripts exit 0 (this phase adds no template, so the roadmap count,
36 on disk, does not move).

- [ ] **Step 5: The no-study and no-dash scans.**

```bash
grep -nP '\x{2014}' inst/templates/10_descriptive/dc-tables.qmd R/migrate-dc-tables.R news/feat-dc-tables-styles.md \
  vignettes/sas-to-r-descriptive.qmd tests/testthat/test-migrate-dc-tables.R tests/testthat/test-dc-tables-render.R
R_LIBS="$LIB" NOT_CRAN=true Rscript -e 'devtools::test(filter = "add-job", reporter = "check")'
```

Expected: no grep output; `test-add-job.R` (no `/studies/`, study name or built-dataset filename
in any template) passes.

- [ ] **Step 6: Look at the report.** Render a job as `test-dc-tables-render.R` does, open the
`.html` in a browser, light and dark, and confirm the report table (shaded section rows, the
Variable column) and the Word table beneath it (grid, spanned header, notes) read as two
tables. Open the `.docx` in Word: caption above, notes below, Letter landscape for a by-group
table with a P column.

- [ ] **Step 7: `/code-review`, then the PR.** Run `/code-review` on the branch. Open the PR
against `main` (never stacked), list "Decisions this plan takes" for John, quote each gate's
summary line (the full suite's `[ FAIL | WARN | SKIP | PASS ]`, the check status, the lint
count), and say that the local review stood in for Copilot. After it opens, measure the Copilot
review with AGENTS.md's timeline and reviews commands rather than assuming the quota.

## Self-review

- **Spec coverage.** D7 and the Phase 5 row: report in `"report"` with the Variable column
  (Task 2, `tbl-table`, asserted by `hv_variable` in `ft`); Word export in `"manuscript"`
  (Task 2, `word-file`); layout and fill as study choices with markers (Tasks 1 and 2);
  caption required (Task 2, default plus marker, decision 2); `SHOW_VARIABLE` report-only
  (Task 2, comment; behavior is hvtiRtables'); floor in Suggests and the setup guard (Task 2);
  the migrator's layout (Task 1, decision 5) and its markers (decision 3);
  `hv_check_docx(style = "manuscript")` (Task 2, contract test). Gallery: decision 8. Version:
  decision 9.
- **No placeholders.** Every code step carries the code; every run step its command and
  expected result. `<scratch>` and `$LIB` are the session's scratch directory and private
  library, set in Task 0.
- **Names are consistent across tasks:** `MANUSCRIPT_LAYOUT`, `MANUSCRIPT_CAPTION`,
  `MANUSCRIPT_FILL`; chunks `tbl-table`, `word-file`, `tbl-word`; objects `ft`, `word_ft`,
  `word_path`, `check`; migrator locals `layout`, `layout_reason`.
