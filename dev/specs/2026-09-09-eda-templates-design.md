# EDA templates: descriptive checking, data-checking graphics, goodness of follow-up

**Date:** 2026-09-09
**Status:** design. Sections 8.1 and 8.2 are both ANSWERED, 2026-09-09. A new
prerequisite fell out of 8.2 and is section 8.3, which blocks the catalog
change and also blocks `dp-variable` in batch 3.
**Supersedes nothing.** Schedules rows that
`2026-08-29-template-conversion-roadmap.md` placed in batches 3 and 4, both of
which that document marks provisional. Answers the first open question in
`2026-09-02-dp-dc-decomposition-design.md` section 10 only partially, and
inherits the rest.

## 1. Why now

The biostats fellows training session (Teams, 2026-09-09) named the
exploratory-data-analysis jobs as the material fellows should be taught first,
before actuarial or hazard work. Ashley Lowry, at 54:12: "cover the templates
that we have for these types of jobs, all the EDA stuff, that's relative
specifically to R. So the postage stamps, some correlation plots, trend..."

None of those templates exists in this package. Most of the engines do, but not
the ones the first draft of this document claimed.

## 2. Read `replaced_by` before reading any package

Every `dc` and `dp` row in the catalog carries `disposition: "thin"` and a
populated `replaced_by` list naming the functions its template would be thin
over. That is a machine-readable answer to "what is the engine for this row",
and it is authoritative in a way that reading sibling `NAMESPACE` files is not.

The first draft of this document was written from package exports and got two
of six rows wrong. The list below is copied from the catalog.

| row | folder | `replaced_by` |
|---|---|---|
| `dc-general` | descriptive | `hvtiRutilities::proc_contents`, `proc_means` |
| `dc-tables` | descriptive | `hvtiRtables::hv_tbl_summary`, `hv_man_table`, `hv_man_table_save` |
| `dc-gfup` | descriptive | `hvtiRutilities::proc_means` |
| `dp-trends` | graphs | `hvtiPlotR::hv_trends` |
| `dp-gfup` | graphs | `hvtiPlotR::hv_followup` |
| `dp-variable` | distributions | `hvtiPlotR::hv_trends`, `hv_ordinal` |

## 3. What was asked for, and what it maps to

Six items were named. Five map onto existing catalog rows. **One does not**,
which is the finding that changed this design.

| asked for | row | jobs | engine | missing |
|---|---|---|---|---|
| `dc.general` | `dc-general` | 759 | `hvtiRutilities::proc_contents()`, `proc_means()` | template; warranted, see section 8.1 |
| Tables, and correlation plots | `dc-tables` | 551 | `hvtiRtables::hv_tbl_summary()` | template, plus two functions |
| Goodness of follow-up, summary | `dc-gfup` | 389 | `hvtiRutilities::proc_means()` | template |
| Trend plots | `dp-trends` | 80 | `hvtiPlotR::hv_trends()` | template |
| Goodness of follow-up, graph | `dp-gfup` | 48 | `hvtiPlotR::hv_followup()` | template |
| Postage stamps | **no row** | unmeasured | none | a row, a decision, and a template |

`dc.general` is spelled as the fellows' list spells it. The row key is
`dc-general` and the SAS job is `dc.general.*`; all three name one thing.

### 3.1 Correlation plots are a `dc-tables` job

"Correlation plots" has no roadmap row, no taxonomy prefix, and no chapter in
`hvtiGraphics`. The corpus places them. The exemplar is
`/descriptive/dc.tables.ods_preoplabs_a1c.sas`, preserved in
`~/Documents/macro.library/CorrTable.sas`, whose header reads "to obtain
pairwise correlations between preop lab values and A1c within A1c groups". Its
computation is one call:

```sas
proc corr data=built nosimple spearman pearson fisher(biasadj=no alpha=.32) plots=matrix;
  ods output SpearmanCorr=corrs FisherSpearmanCorr=corrcis
             PearsonCorr=corrp  FisherPearsonCorr=corrcip;
```

Two artifacts: a **scatter-plot matrix** (`plots=matrix`) and a **table of
pairwise coefficients with Fisher confidence intervals**. The job is filed
under `/descriptive/` and named `dc.tables.*`, so correlation work is a variant
inside `dc-tables`, recorded there as an `EDIT:` path rather than a seventh row.

⚠️ `~/Documents/macro.library/CorrTable.sas` is two unrelated programs
concatenated. The first is `%STStable`, an STS observed-versus-expected table;
the correlation program is the second, below it. The filename describes neither.
Read past the first header before concluding what that file is.

⚠️ **`pool_collinear_pairs()` in `hvtiRutilities` is not this function.** It
prunes bootstrap selection pools at a 0.99 threshold. It answers "which pair is
so collinear that one must go", not "what is the correlation structure here",
and reusing it would silently discard everything below the threshold, which is
the part an author is looking at.

### 3.2 `dc-tables`, not `dc-general`, is the `hv_tbl_summary()` row

`hvtiRtables` 1.0.0 ships `hv_tbl_summary()`, written to the `%summarytable`
SAS macro interface the biostats team already knows: `groups` is the macro's
`LIST=`, doing double duty as display order and section headers; `continuous`,
`binary` and `categorical` are `CON1=`, `CAT1=` and `CAT2=`; `compare` adds the
trailing comparison column as `"pvalue"`, `"smd"` or `"both"`.
`R/hv-sas-glossary.R` encodes the compute, shape and save stages explicitly.
`%summarytable` descends from Amanda Artis (2020), modifying Rocio Lopez's
`%summtable` (2013), modifying Ryan Lennon's `%summary` (Mayo, 2009).

⚠️ **That engine backs `dc-tables`, and the first draft of this document
attached it to `dc-general`.** The catalog note on `dc-general` is explicit
about the difference: "Base procs only (contents/means/freq), **no package
dependency, which is what separates it from `tables`**." `dc-general` is a
base-R QC job. Any design that gives it a `gtsummary` dependency has collapsed
the one distinction the two rows exist to draw.

⚠️ **`corr` in `hvtiRtables` means CORR the group**, Cardiovascular Outcomes,
Registries and Research, and never correlation. `hv-sas-glossary.R` keys every
stage on `corr` versus `jtcvs` as the two manuscript destinations. A grep for
correlation machinery there returns nothing but false positives. This is why
the new functions in section 6 are named `hv_correlation_*` in full.

### 3.3 Postage stamps have no row, and `dp` spans three folders

This is the finding that stops the batch being scheduled today.

`2026-09-02-dp-dc-decomposition-design.md` section 7 records that **`dp` spans
three folders while the ledger records `folder: graphs`**: `distributions/dp`
is the 237-study per-variable job, `graphs/dp` is trends, spaghetti, procs and
gfup, and `descriptive/` carries six live `dp` templates, named there as
`DescriptiveSummary`, `EDA_barplots_scatterplots`, `descriptive.figures`,
`gfup` and two variants. That design's section 9 enacted rows for `graphs/dp`
and `distributions/dp`. **It enacted none for `descriptive/dp`**, and the six
templates in that folder are therefore unrepresented in the catalog.

The postage stamp is one of those six. The exemplar is
`~/Documents/template/descriptive/templates/tp.dp.DescriptiveSummary.qmd`,
which is already a Quarto file with a `format:` block, an
`## ===== EDIT HERE BEFORE RUNNING =====` block that is the direct ancestor of
`EDIT:` markers, a matching `## ---- DO NOT EDIT THIS SECTION ----`, and at
line 195:

```r
# postage stamp plot grid size
ncol=4
nrow=4
```

It is parameterised by dataset, not by variable: `dta_filename`,
`pref_time_var`, `pref_color_var`, `stratify_by`, `examine_cont_feature`, and
the grid dimensions. One small panel per **variable**, across the whole
dataset.

⚠️ **It is not `dp-variable`.** That row is `distributions/dp`, is
parameterised by variable rather than by dataset, and its `replaced_by` is
`hv_trends` and `hv_ordinal`. Its own note records the measurement: 666 of
1,271 job rows (52%) carry only the variable and no second field. A whole-
dataset EDA grid is a different job, and filing it there would repeat the
`dp`-is-one-thing error that the decomposition design exists to correct.

⚠️ **No faceting constructor exists.** `hvtiGraphics` `postagestamp.qmd:27`
says "hvtiPlotR 2.7.10 has no postage-stamp or faceting constructor, so we
build this" from `ggplot2::facet_wrap()` and `theme_hv_manuscript()`. Confirmed
still true at hvtiPlotR 2.7.13. `hv_eda()` classifies one variable's
measurement scale and plots one panel; it does not arrange a grid.

⚠️ **Two different pictures are called a postage stamp.** `postagestamp.qmd`
facets one plot **by subgroup or era**. `tp.dp.DescriptiveSummary.qmd` tiles
one panel **per variable**. The fellows' list means the second: it sits beside
correlation and trend plots as a data-checking sweep over a new build. A design
that ports the first has built the wrong thing.

## 4. Ledger changes

⚠️ **None yet.** The first draft of this document prescribed moving three `dc`
rows to batch 3 and adding a note to `dc-tables`. That is held until section 8
is answered, because the justification for the move was "four of six are wiring
jobs" and that count did not survive section 2.

When the move is made, the catalog is `inst/extdata/jobs.json` in
`ehrlinger/hvtiR`, resolved through `HVTI_JOBS` or a sibling checkout. Nothing
in this repo is the authority, and editing the copy that used to live here does
nothing. Re-render from this repo afterwards:

```sh
python3 dev/specs/artifacts/roadmap_render.py
```

⚠️ **`batch` is an integer, and must stay one.** The obvious spelling of a
pulled-forward batch is `"3a"`. It crashes the renderer. `roadmap_render.py`
derives each family's label by sorting the set of batch values it contains
(line 177) and sorts rows on `r["batch"] or 0` (line 196), so a `plots` family
holding both `3` and `"3a"`, which is what moving three of five `dp` rows
produces, raises `TypeError: '<' not supported between instances of 'str' and
'int'`. Every value in the catalog today is an integer or `null`, so no string
batch has ever been exercised. Batch 5 is a free integer slot but sorts after
4, saying this work happens later, which is the opposite of the intent.

## 5. Sequencing

Provisional, and contingent on section 8.

| wave | templates | blocked on |
|---|---|---|
| 1 | `dp-trends`, `dp-gfup` | nothing |
| 2 | `dc-general`, `dc-gfup` | nothing |
| 3 | `dc-tables` | the two correlation functions |
| 4 | `dp-postage` | section 8.3, then a decision on the grid helper |

Wave 1 first because both rows are genuinely thin over shipped `hvtiPlotR`
functions, and because a trend plot is the thing a fellow can read on a slide.
Postage stamps move to the back despite being named first, which is the cost of
their having no row.

## 6. New functions

Split by artifact type: a plot goes to the plotting package, a table to the
tables package. The correlation job produces one of each, so it costs a
cross-package pair. Accepted, because the alternative puts a manuscript-output
package in the business of drawing EDA scatter matrices, or puts
confidence-interval statistics in a plotting package.

**These are specced by their owning repositories, not here.** This document
records the dependency and the shape the templates need.

| function | package | shape |
|---|---|---|
| `hvtiPlotR::hv_correlation_matrix()` | hvtiPlotR | scatter-plot matrix, mirroring `plots=matrix`. Returns an `hv_data`-classed object with a `sample_*_data()` companion, per that package's convention. |
| `hvtiRtables::hv_correlation_table()` | hvtiRtables | Spearman and Pearson coefficients with Fisher confidence intervals, mirroring `ods output SpearmanCorr` / `FisherSpearmanCorr` / `PearsonCorr` / `FisherPearsonCorr`. Must support stratification: the exemplar computes overall and within `a1c_grp`. |

Names are spelled out rather than abbreviated to `hv_corr_*` because of the
CORR collision in section 3.2.

⚠️ **`hv_followup_table()` was proposed in the first draft and is withdrawn.**
`dc-gfup`'s `replaced_by` is `hvtiRutilities::proc_means`, so the summary it
needs may already exist. Read that function against
`~/Documents/template/descriptive/templates/tp.dc.gfup.sas` before proposing a
new one.

## 7. Per-template obligations in this repo

Each template carries, without exception:

- Its own **file key** in `.lintr`, never a directory key. A directory key
  excludes every linter on that path wholesale and silently.
- Exactly one `^ENDPOINT\s+<- ` line and one `^TYPE\s+<- ` line. `new_job()`
  substitutes both and hard-stops if either is missing, duplicated or moved.
- Its own `format:` block, not inherited from a project `_quarto.yml`.
- `EDIT:` markers on every study-specific line, with comments saying why a
  choice matters rather than only what to type.
- No study identifiers. `test-new-job.R` asserts no template matches
  `/studies/`, a study name, or a built-dataset filename.
- A row in `inst/templates/README.md`.
- A `NEWS.md` entry under `# hvtiRtemplates (unreleased)`, added if absent. No
  `Version:` bump in the template PR itself.
- The catalog row flipped to `shipped`, re-rendered.

Filenames, all qualified, because `dp` and `dc` are wholly-qualified prefixes:

```
inst/templates/40_graphs/dp-trends.qmd
inst/templates/40_graphs/dp-gfup.qmd
inst/templates/10_descriptive/dc-general.qmd
inst/templates/10_descriptive/dc-tables.qmd
inst/templates/10_descriptive/dc-gfup.qmd
```

⚠️ `10_descriptive/` does not exist yet; this batch creates it. The digits are
assigned, not derived, and 10 is already the assigned decade for `descriptive`.

Jobs scaffold into the **bare** taxonomy folder, `graphs/` and `descriptive/`,
carrying the qualifier as a fourth field: `new_job("dp", "dead_pa", "hz",
qualifier = "trends")` writes `graphs/dead_pa-hz-dp-trends.qmd`.

## 8. Open questions, blocking the ledger change

**8.1 Does `dc-general` deserve a template at all? ANSWERED: yes.**

`2026-09-02-dp-dc-decomposition-design.md` section 10 raised this and could not
answer it: "759 studies and base procs only, so it is either the most valuable
template here or too trivial to be worth one. The counts cannot say; reading
two study exemplars can, **and the share was not mounted when this was
written**." The share is mounted now. Two exemplars were read on 2026-09-09,
chosen to be as unlike each other as the corpus allows:

| | exemplar A | exemplar B |
|---|---|---|
| study | `cardiac/general/dm_a1c` | `thoracic/lung/complications/po_afib` |
| cohort | CCF 1999 to 2010, n=10,999 | CCF Jan 1998 to Aug 2002, n=99 |
| lines | 360 | 177 |

Different specialty, different decade, different author, two orders of
magnitude apart in cohort size. **Both carry the same four-section skeleton,
down to the spaced-capital banner comments**, which is not a shape two authors
arrive at independently:

```
*                    O V E R A L L   S T A T I S T I C S                       ;
  proc contents data=built;
  proc means data=built n nmiss mean std min max sum;

*                    C O N T I N G E N C Y   T A B L E S                       ;
*             F O R   C A T E G O R I C A L  V A R I A B L E S                 ;
  proc freq data=built; tables <grouped list> ; run;

*                C U M U L A T I V E   D I S T R I B U T I O N S               ;
*                 F O R   C O N T I N U O U S  V A R I A B L E S               ;
  proc univariate data=built; id ccfid; var <grouped list> ; run;

*              P A I R - W I S E   C O R R E L A T I O N S                     ;
  proc corr nosimple rank data=built; var ; run;
```

Four further findings, each of which shapes the template:

1. **The variable lists are grouped by a stable comment taxonomy**, and it is
   the same taxonomy in both: `/* Demography */`, `/* Cardiac Comorbidity */`,
   `/* Non-cardiac Comorbidity */`, `/* Procedure */`, `/* Time-related
   Outcomes */`. That is the shape of `hv_tbl_summary()`'s `groups` argument.
   `dc-general`'s **engine** is base procs, but its **variable-grouping
   structure** is the same one `dc-tables` uses, which is what makes the pair
   coherent rather than redundant.
2. **Sections are wrapped in `%macro name; ... %mend;` and called at the
   bottom** (`%freq; %cdfs;`), the SAS idiom for toggling a section on and off.
   That is the direct ancestor of `EDIT:` markers and of the commented
   scaffolding `commented_code_linter` is excluded for.
3. **Exemplar B's `%macro corr` has an empty `var` list.** A section was copied
   in and never filled. A skeleton that arrives unfilled is copied, not
   written, which is the strongest available evidence that a template already
   exists in practice and is simply not in this package.
4. **Roughly two thirds of exemplar A is study-specific ad-hoc work sitting
   above the skeleton**, and none of it generalises. The template should
   scaffold the four sections and leave a marked, empty region for that work
   rather than attempt to anticipate it.

⚠️ **`id ccfid` is a patient identifier and must not be a default.** Both
exemplars label extreme observations with `ccfid` so an author can look a case
up, which is a real need. Exemplar A goes further: it prints `ccfid` for
outlier ranges and exports two identified `.xlsx` files to the study root. The
template carries this as an `EDIT:` with the reason stated, never switched on,
and ships no export step at all.

⚠️ **This also revises section 3.1.** Pairwise correlation is a section of the
`dc.general` skeleton, `proc corr nosimple rank`, as well as a `dc.tables` job.
The two are different: `dc-general`'s is a bare coefficient sweep, while the
`dc-tables` exemplar adds `spearman pearson fisher(biasadj=no) plots=matrix`
with ODS output. The fellows asked for correlation **plots**, so the
`dc-tables` assignment stands, and `dc-general`'s template needs the plain
section as a fourth banner.

**8.2 Where do postage stamps go? ANSWERED: a new `descriptive/dp` qualifier.**

Decided by the maintainer, 2026-09-09. The job is `dp`-named in the corpus and
sits in `descriptive/`, so it is filed as what it is rather than folded into
`dc`.

⚠️ **The cost stated in the first draft of this section was wrong, and the real
one is worse.** That draft said "the row's `folder` field cannot express a
prefix that spans three folders". It can: `folder` is a per-row field, and
`dp-variable` already carries `folder: distributions` while its four siblings
carry `graphs`. The catalog needs nothing new. The constraint is one layer up,
and it is section 8.3.

**8.3 `hvti_taxonomy()` cannot express a prefix that spans folders, and a test
enforces that. NEW, blocking.**

`hvti_taxonomy()` is a prefix-to-folder map with exactly one row per prefix:
`dp` maps to `graphs`, full stop. `test-taxonomy.R:59` checks every template on
disk against it:

```r
test_that("a template sits in the folder its prefix is filed under", {
  tl <- template_list()
  tx <- hvti_taxonomy()
  expect_equal(tl$folder, tx$folder[match(tl$prefix, tx$prefix)])
})
```

`template_list()` derives `folder` from the directory, so a
`10_descriptive/dp-variable.qmd` yields `descriptive` against the taxonomy's
`graphs` and the suite fails. A `descriptive/dp` template cannot ship until
this is resolved.

⚠️ **`dp-variable` hits this first, and it is already scheduled.** It is a
batch 3 row carrying `folder: distributions`, so shipping it into
`20_distributions/dp-variable.qmd` fails the same assertion. The catalog is
scheduling a row the test suite will reject, and nothing surfaces that until
someone writes the template. This is not a cost of the present batch; the
present batch is what found it.

`new_job()` is unaffected: `out_dir <- file.path(dir, row$folder[[1L]])` takes
`folder` from `template_list()`, which is directory-derived, so scaffolding
routes a `descriptive/dp` job into `descriptive/` correctly today.

Two ways to resolve it:

1. **Make the test consult the catalog row's folder**, falling back to the
   taxonomy when a template has no row. The catalog is already the finer
   authority and already carries the per-row answer; the taxonomy stays the
   coarse cross-check for undecomposed prefixes. No `hvtiRutilities` change, no
   schema change, one test rewritten. **Recommended.**
2. **Give `hvti_taxonomy()` several rows per prefix.** Truer to the corpus and
   far riskier: every consumer that does `match(prefix, tx$prefix)` silently
   takes the first row, which is precisely the failure class `AGENTS.md`
   records for `template_path()`'s ambiguity, where selecting with `match()`
   returned the first row and said nothing about the rest. Changing a shared
   map so that a one-to-one lookup quietly becomes one-to-many, in a package
   eleven repositories import, would seed that bug everywhere at once.

Option 1 is a change in this repository; option 2 is a cross-repo PR against
`hvtiRutilities` plus an audit of every `hvti_taxonomy()` caller. The
recommendation is 1, and the decision has not been taken.

## 9. The second-exemplar gate

`AGENTS.md` requires two studies to have exercised a shape before a template is
added. Every row with a measured count clears it by a wide margin, the smallest
being `dp-gfup` at 48 jobs. Postage stamps are unmeasured, because the job type
has no row to count; the six legacy templates in `descriptive/` are evidence of
use but are not a study count.

## 10. Definition of done

Per template, and per `AGENTS.md`:

- `devtools::test()` passes.
- `devtools::check()` is 0 errors, 0 warnings, 0 notes.
- `devtools::document()` run, with `man/` and `NAMESPACE` committed alongside.
- The template renders.
- `check-roadmap-counts.py` passes, which it will not until the catalog row is
  flipped and re-rendered. It is the only one of the three `spec-counts.yaml`
  checks that reads the catalog: `check-spec-counts.py` is hard-scoped to the
  macro-allocation spec and its map, and `check-flow-counts.py` checks the job
  flow diagrams against the taxonomy. Neither is affected by this batch, so a
  failure in either is not a symptom of a missing catalog flip.

⚠️ `check-manual.yaml` does not run on `pull_request`. It is push-to-`main`,
release and dispatch only. No template here is expected to touch Rd markup, but
if one does, build the PDF manual locally before merging.

⚠️ **Copilot review credits are available again, measured 2026-09-09.**
`AGENTS.md` records them as exhausted until October, confirmed 2026-09-03. PR
#95 drew a substantive review the same day this was written. Treat the
`AGENTS.md` paragraph as stale and re-measure rather than assuming either way:

```sh
gh api --paginate repos/ehrlinger/hvtiRtemplates/pulls/<n>/reviews \
  --jq '[.[] | select(.user.login | startswith("copilot"))] | last | .body'
```

A body containing "quota limit" means the credits are gone. Running
`/code-review` locally before opening a PR remains the rule regardless, since
Copilot reads only the diff: on PR #95 it returned two presentation nits and
caught none of the three engine-mapping defects corrected in this revision,
because those live in a catalog it never opened.

## 11. Out of scope

- `dp-procs`, `dp-spaghetti`, `dp-variable`, `dc-dead`, `lg`, `rg`. Not asked
  for.
- The `dc-stddiff` member, which the catalog assigns to `hvtiRutilities` with
  `disposition: build`, not here.
- The three-folder `dp` ledger defect in general. This document records it
  where it blocks a decision and does not attempt to fix it.
- Multi-file templates. Every row here is a single-file job, so the runner
  gap that blocks `bh` and `hm` does not apply.
