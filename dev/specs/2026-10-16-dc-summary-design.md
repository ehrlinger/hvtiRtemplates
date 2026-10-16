# `dc-summary`: the summary table before and after adjustment

**Date:** 2026-10-16
**Status:** decided 2026-10-16, see section 7: `dc-tables` is extended rather than a new
template added. Section 2 is read from the SAS source. Section 5a records the meeting, which
reframed the request.
**Reads with:** `2026-09-16-standardized-difference-design.md` (`dc-stddiff`, which already
owns the standardized differences); `2026-09-09-eda-templates-design.md` (`hv_tbl_summary()`
as the `%summarytable` port); `2026-09-02-dp-dc-decomposition-design.md` (the `dc` qualifiers).
**Packages:** hvtiRtables (`hv_tbl_summary()`, the Word writers), hvtiRpropensity (the matched
set and the matching weight, as `dc-stddiff` uses them), hvtiRtemplates (the template).

This note is self-contained. It assumes no memory of the session that produced it.

⚠️ No study, variable value or patient identifier appears here. The exemplar's header names its
study; that is left out on purpose, and the template must not carry it either.

## 1. The question

A study comparing two groups after propensity adjustment reports one baseline table three
times: as observed, in the matched pairs, and under matching weights. Each version gives the
per-group summaries, a p-value and the standardized difference. Readers compare the three to
see that the adjustment balanced the groups.

`dc-tables` draws one of those tables and has no weight. `dc-stddiff` draws the standardized
differences in all three populations and has no per-group summaries. Nothing draws the full
table in all three.

## 2. The exemplar

`~/Documents/template/descriptive/templates/tp.dc.stddiff.summarytable.sas`, 314 lines,
dated 2026-04-01. The 2026-08-22 job-flow census records it as reading `built`, running `%vars`
and writing nothing; that last field is wrong, see step 5.

1. Reads `built`, runs `%vars(match=1, matchds=..., propen=1, propends=...)`, so the match
   indicator and the matching weight arrive as columns from other jobs (J2 and J3 in the
   bd/vars design).
2. Builds formats and one derived categorical (a race group from four indicators), with a
   `proc freq` check that the indicators do not overlap. That is a `vars` action (V1), not
   this job's.
3. Checks the adjustment: `proc means` of the weight sum by group, and `proc freq` of group by
   match, with the counts pasted back as comments.
4. Calls `%summarytable` three times on the same variable lists:

   | run | `SUBSET=` | `WEIGHT=` | `PROPENMT=` | `F1=` |
   |---|---|---|---|---|
   | unadjusted | none | none | 0 | default |
   | matched | `match` | none | 1 | default |
   | matching weights | none | the weight column | 0 | `__WCountf.` (weighted counts) |

   All three set `CLASS=` a 0/1 group, `TOTALCOL=0`, `PVALUES=1`, `NCOL=2` (N per group),
   `ASD=1`, `SORTBY=_list` with an explicit `LIST=`, landscape, and an RTF file each. Under the
   weight, the comment says p-values for continuous and ordinal variables come from a
   bootstrap.
5. Joins the unadjusted and matched standardized differences by variable name, keeps four
   variables, sorts by the difference and **saves the result to the study library**. That is the
   one output another job could read.

Two siblings have the same shape. `tp.dc.stddiffci.sumtbl.sas` runs the same three tables with
permutation intervals on the difference (`NPERM=1000`). `tp.dc.table1.mtch_mtwt.sas` does the
same with the older `%std_dif` macro. The catalog already folds `stddiffci` into `dc-stddiff`.

## 3. Mapping `%summarytable` onto `hv_tbl_summary()`

hvtiRtables 1.0.5. `hv_tbl_summary(data, by, groups, continuous, binary, categorical, compare,
percentiles, overall, continuous_stat, normal)`.

| `%summarytable` | R | status |
|---|---|---|
| `DATA=`, `SUBSET=` | `DATASET`, `WHERE`; the matched panel filters on `MATCH` | covered |
| `CLASS=` (0/1) | `by`, two levels | covered |
| `CON1=` Gaussian, mean (SD) | `continuous` + `normal` | covered |
| `CON3=`, `PP=` median [P1, P2] | `continuous`, `percentiles = c(15, 85)` | covered |
| `CON2=` median (min, max) | folded into `continuous`, so it shows median [P15, P85]; one percentile pair per table | **gap** |
| `CAT1=` binary | `binary` | covered |
| `CAT2=` all levels | `categorical` | covered |
| `ORD1=` ordinal, all levels | `categorical`; documented as dropping the ordinal distinction | covered for display |
| `PVALUES=` | `compare = "pvalue"` | covered, unweighted only |
| `ASD=` | `compare = "smd"`, but see below: **not the same number** | **gap** |
| `TOTALCOL=` | `overall` | covered |
| `NCOL=2`, N per group | not an argument; `gtsummary::add_n()` on the returned object is the likely route | **check** |
| `SORTBY=_list`, `LIST=` | `GROUPS` sections in `dc-tables` | covered |
| `WEIGHT=` | **no weight argument anywhere in hvtiRtables** | **gap** |
| `PROPENMT=1` | `WHERE` on the match indicator; nothing else, see below | covered |
| `RTFFILE=` | Word, through the `hv_man_table_save()` route `dc-tables` uses | covered |

### What `%summarytable` does, read 2026-10-16

From `~/Documents/macro.library/summarytable.sas`, 4,097 lines, last modified by Artis in 2021.

- **`PROPENMT=1` changes nothing about the summaries or the tests.** It only routes the
  standardized difference to `%stddiff(..., SUBSET=)` and names the output `stddiff_propen`.
  The matched panel is the ordinary table on the matched rows, with unpaired tests. No paired
  test is run, so none is needed in R to reproduce it.
- **The standardized difference comes from `%stddiff`, the 2019 macro, not from a generic
  formula.** It splits variables as `GAUSSIAN=` (CON1) and `NONG_ORD=` (CON2, CON3 and ORD1),
  and prints it as a percentage ("Standardized Difference (%)"). `hv_tbl_summary()` computes
  its column with `gtsummary::add_difference(~ "smd")`, which treats every continuous variable
  alike and reports a proportion. The two will disagree for non-Gaussian and ordinal
  variables. `hvtiRpropensity::ps_stddiff()` (0.2.1) is the port of `%stddiff` that
  `dc-stddiff` already uses, with the same four buckets and a `weight_col`, so it is the
  number to show.
- **Under `WEIGHT=`**, counts and percentages come from `proc freq` with a `weight` statement,
  and means, SDs and percentiles from `proc univariate` with `VARDEF=WDF`. P-values for every
  variable come from `%mw_var`, a bootstrap with `RESAMPL=1000` and **`SEED=-1`, so they
  change on every run**. Exact tests are switched off under a weight.
  `hvtiRpropensity::ps_mw_var(data, treatment_col, outcomes, weight_col, n_rep, seed)` is the
  port, and it takes a seed.

So the weighted panel needs three things, and two already exist: the weighted difference
(`ps_stddiff(weight_col =)`) and the weighted p-value (`ps_mw_var()`, seeded). What is missing
is **weighted summaries in hvtiRtables**: weighted n (%), mean ± SD and percentiles, in the
same table object `hv_tbl_summary()` returns. `gtsummary::tbl_svysummary()` over a
`survey::svydesign(weights = )` is the obvious engine; whether its weighted percentiles and
SDs match `VARDEF=WDF` has to be measured, not assumed.

The difference column needs work in all three panels, not only the weighted one, because the
unadjusted `%summarytable` difference is also `%stddiff`'s.

## 4. Options

1. **A new `dc-summary` template**: three panels from one set of variable lists, each a
   `hv_tbl_summary()` call, written to one Word file.
2. **A `PANELS` choice on `dc-tables`**: the same, without a new qualifier.
3. **Per-group summaries added to `dc-stddiff`**, which already handles `MATCH` and `WEIGHT`.

The request is option 1. Options 2 and 3 are listed because each reuses a template that already
has half the job, and the meeting should rule them out on purpose rather than by default.

## 5. Gates this must pass

- **Two studies.** Three legacy templates share the shape, but the rule counts studies. The
  corpus census counts by the second name field, so `dc.stddiff.summarytable` jobs sit inside
  `dc-stddiff`'s 59 and are not counted on their own. A census on the server answers it.
- **Catalog.** `dc` is fully qualified, so a `(dc, summary)` row is allowed. The `stddiffci`
  fold into `dc-stddiff` must be revisited if `dc-summary` takes the summary-table half.
- **Name.** `dc-summary` is a working name, kept on 2026-10-16 and open to change once the
  meeting transcript is read. Beside `tables` and `general` it must say what separates them,
  in the catalog note and in `template_list()`. `balance` is taken in effect: `dc-stddiff`'s
  catalog description reads "The balance table" and its default `TYPE` is `"balance"`.
  `adjusted` and `table1` were the alternatives considered.

## 5a. What the 2026-10-16 meeting asked for

Read from the "Umbrella project status review" transcript (2026-10-16, about 44 to 50 minutes in,
with the table critique from 26 to 31 and 1:03 to 1:16). Speaker labels in that transcript are
unreliable: one conference-room device carries several voices.

**The request was not the three-panel table.** Matching and weighting were never mentioned. What
was asked for is the `%summarytable` *shape*: one call, continuous and categorical variables
together in ordered sections, by group, with p-values and the standardized difference in the
same table. The team said it had stopped running separate tables and standardized-difference
jobs and runs the summary macro instead, and that a standardized difference is never shown on
its own: it always sits beside the means and frequencies. One table, one function with every
option, was the stated preference. It was described in the meeting as a mix between `dc-tables`
and `dc-stddiff`, which is accurate. The objection to `dc-stddiff` was that the summary macro
treats nominal variables differently; section 3 shows the R difference column has the same
problem (`gtsummary`'s SMD is not `%stddiff`'s).

So the exemplar in section 2 is one *use* of the shape, run three times for an adjusted study.
The shape itself is `dc-tables` plus `%stddiff`'s difference. That makes option 2 of section 4,
extending `hv_tbl_summary()` and `dc-tables`, the closest fit to what was asked, and it turns
the weighted panel into a later addition rather than the blocker.

**Critique of `dc-tables` and `hv_tbl_summary()` raised in the same meeting**, all of which a
`dc-summary` would inherit:

1. A column with the variable's name, with an argument to drop it, so the report and the
   manuscript come from one regenerated table and nobody edits a table by hand.
2. The count of non-missing values as its own column, not stacked lines under each variable.
   The header wording that a manuscript reviewer accepted was "number of non-missing data
   available". A percent missing was asked about and not wanted.
3. The rendered HTML and the saved Word table should be the same table. Today the HTML stacks
   lines and the saved `.docx` splits them into manuscript columns.
4. Categorical tests should switch to Fisher's exact automatically when expected cell counts
   are small, as `%summarytable`'s `CUTEXACT=` did. Today chi-square is swapped by hand.
5. Continuous tests stay nonparametric for every variable (Wilcoxon, or Kruskal-Wallis for
   three or more groups). Nobody wanted the normal/non-normal test split.
6. But the *display* must be chosen per variable: mean ± SD for some continuous variables and
   median [P15, P85] for skewed ones, in the same manuscript table. `normal` in
   `hv_tbl_summary()` couples mean ± SD to ANOVA today; the request is display without the test.
7. In a report, `continuous_stat = "both"` should put N, mean ± SD and median side by side as
   columns per group, blank for categorical rows, not stack them as sub-rows.
8. P-value, standardized difference or both, as `compare` already offers.
9. The gallery shows no saved `.docx` table, which is the artifact the team judges.

## 6. Open questions for the meeting

After the transcript: 2 leans to option 2 (one function with every option); 3 is one table;
1, 4, 5 and 7 were not raised, so the weighted panel, the saved differences, the matched-panel
tests and the permutation intervals are out of a first version; 6 was not raised, and median
[P15, P85] is the default.

## 7. Decision, 2026-10-16

**Option 2. No separate `dc-summary` template: `hv_tbl_summary()` and `dc-tables` are extended
instead.** The weighted panel is parked; hvtiRtables#76 is a draft that records its design.

The work is in hvtiRtables first, then `dc-tables`:

1. A standardized difference faithful to `%stddiff`. hvtiRtables takes no dependency on
   hvtiRpropensity (tier 1 against tier 2), so it gains a seam that joins a caller-supplied
   per-variable column, and `dc-tables` calls `hvtiRpropensity::ps_stddiff()` and passes the
   result in. `compare = "smd"` keeps gtsummary's generic SMD and says so in its help.
2. Fisher's exact chosen automatically by `%summarytable`'s `CUTEXACT=` rule.
3. Mean ± SD or median chosen per variable for display, with one nonparametric test for all.
4. The non-missing count as its own column, and `"both"` as side-by-side columns in a report.
5. A variable-name column, with an argument to drop it.

`dc-tables` then maps its study choices onto `ps_stddiff()`'s buckets as `%summarytable` did:
the mean ± SD variables are `gaussian`; the other continuous variables, and ordinal ones, are
`nong_ord`. That needs a way to name ordinal variables in `dc-tables`, which today folds them
into `CATEGORICAL`.

1. Is the weighted panel required? If so, hvtiRtables needs weighted summaries first.
   Weighted p-values will be seeded in R, so they will not reproduce a SAS run digit for
   digit; SAS's were unseeded and never reproduced themselves either.
2. Which of options 1 to 3?
3. One Word file with three panels, three files, or one table with three column groups?
4. Does the job save the joined standardized differences, as step 5 does, and who reads them?
5. Do p-values stay in the matched and weighted panels? SAS runs unpaired tests on matched
   pairs; keep that for parity, or change it?
6. Is median (min, max) still wanted, or does median [15, 85] cover it?
7. Are permutation intervals on the difference (the `stddiffci` sibling) part of this job?
