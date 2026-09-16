# Standardized differences, their reference intervals, and matching-weight variance

**Date:** 2026-09-16
**Status:** design, not started. No code in any package yet.
**Supersedes:** the owner named for `dc-stddiff` in
`2026-09-02-dp-dc-decomposition-design.md` §5,
`2026-09-09-eda-templates-design.md` §11, and
`2026-08-29-template-conversion-roadmap.md` (propensity-matching workflow).
The macro choice made there stands; the owner does not.

**What "owner" changes, and where it is recorded.** Two authorities name an
owner, and this repo keeps them apart on purpose
(`artifacts/2026-09-09-macro-component-scan.py`):

| question | source of truth | today | after this spec |
|---|---|---|---|
| which package owes the R function and the `dc-stddiff` job route | hvtiR's job catalog (`jobs.json`, `destination` / `replaced_by`) | `hvtiRutilities`, `build` | `hvtiRpropensity`, `build` |
| which package owns the SAS macro's domain | `artifacts/2026-08-14-macro-allocation.json` | `stddiff.sas` to `hvtiRutilities` | `hvtiRpropensity`, for `stddiff.sas`, `stddiffci.sas` and `mw_var.sas` |

Neither is edited by hand in this pull request. The catalog row changes in
hvtiR; the allocation map is generated, guarded by `check-spec-counts.py`, and
changes when the scan's owner table is next regenerated. Until both land, the
two sources disagree with this spec, and this spec is the later decision.

## 1. Decisions taken 2026-09-16

- **`hvtiRpropensity` owns standardized differences**, not `hvtiRutilities`.
  Its matching, scoring and weighting paths (`ps_match()`, `ps_logistic()` via
  `ps_score.R`, `ps_weight()`) already compute them internally (§3), and those
  objects are the thing a balance check is about. `ps_nominal()` does not: its
  only diagnostic table is `group_counts`.
- **`%mw_var` is in scope**, as its own function, not as an option on the
  standardized difference. It estimates the variance of a treatment effect, not
  balance.
- **Three-way matching is examined here** (§7) and gated, not built.

Still the maintainer's call, listed in §10: function names, whether the
reference interval reuses `hvtiRbootstrap`, and which template prefix `%mw_var`
scaffolds under.

## 2. The SAS being ported

All four live in `~/Documents/macro.library`.

| macro | provenance | what it computes |
|---|---|---|
| `stddiff.sas` | Artis 2019 to 2020, from Dongsheng Yang (CCF, 2012) | Standardized difference, group 1 minus group 0, for Gaussian, non-Gaussian/ordinal, binary and categorical variables, with an optional weight and `SUBSET=` where-clause. Saves a dataset (`OUT=est.stddiff`) |
| `stddiffci.sas` | Artis 2020, corrected 2021 | Calls `%stddiff` once on the observed groups and `NPERM` times on permuted groups, then takes the 2.5, 16, 50, 84 and 97.5 percentiles per variable |
| `wt_mtch_boot_sd.sas` (`%mw_var`) | Rajeswaran 2014, after Li and Greene 2013 | Bootstrap of the matching-weighted difference in group means. Reports SD, the same five percentiles (`PCTLDEF=1`), z and p |
| `std_dif_4groups.sas` (`%std_df4g`) | 2012 | Four-group difference: (max group mean minus min group mean) over the root of the average of the four group variances. Continuous and binary only |

The formulas in `stddiff.sas`, read 2026-09-16:

| type | formula | line |
|---|---|---|
| Gaussian | `(mean1 - mean0) / sqrt((var1 + var0) / 2)` | 168 |
| non-Gaussian, ordinal | the same, on `PROC RANK` ranks of the pooled sample | 180 to 235 |
| binary | `(p1 - p0) / sqrt((p1(1-p1) + p0(1-p0)) / 2)` | 352 |
| categorical, k > 2 levels | Mahalanobis form, `sqrt(t' S^-1 t)`, defined below (Yang and Dalton 2012) | 395 to 602 |
| one-level variable | 0 | 278 |

**The categorical quantities, as the macro builds them.** For a variable with
`L` observed levels, `K = L - 1`:

1. `PROC FREQ ... table var * group`, with `weight &WEIGHT` when given, gives
   column percents per group. Levels absent from a group get proportion 0.
2. Rows are sorted by `group, level`, and **the last level of each group is
   dropped** (`if last.group then delete`). The reference level is therefore
   the highest level in sort order, not the first.
3. `t` and `c` are the K remaining proportions in group 1 and group 0.
   `t - c` is the difference vector.
4. `S` is K by K: diagonal `0.5 * (t_i(1 - t_i) + c_i(1 - c_i))`, off-diagonal
   `-0.5 * (t_i t_j + c_i c_j)`.
5. `S` is inverted by `PROC ORTHOREG` against identity columns with
   `singular = 1E-16`, and the result is `sqrt((t - c)' S^-1 (t - c))`.

Weighting enters only through the proportions in step 1. The R port uses
`solve()` on the same `S`; parity at 4 decimals is the check that the two
inversions agree.

**Weighted continuous and ordinal variances** come from `PROC MEANS` with a
`WEIGHT` statement (lines 146, 212), which SAS documents as
`sum(w_i (x_i - xbar_w)^2) / (n - 1)`. Ordinal ranks come from `PROC RANK` on
the pooled sample, **unweighted**, with the default `ties = mean` (`ties=low`
is commented out); only the rank means and variances are weighted.

⚠️ **The output label reads `"Standardized Difference (%)"` (line 637), and no
multiplication by 100 was found in the file.** Either the label is wrong or the
scaling happens somewhere a grep for `*100` did not reach. Settle it against a
real `est.stddiff` before fixing the R output's units.

⚠️ **`stddiffci` is a PERMUTATION reference distribution, not a bootstrap
confidence interval**, whatever its header calls it. The loop feeds `%stddiff`
groups named `f<group>_<i>` (and, weighted, weights `<weight>_<i>`) that the
macro does not create: the calling job must already have written `NPERM`
permuted group columns, and, for matching weights, re-derived weights under
each permutation. So the percentiles describe what the standardized difference
looks like when group membership carries no information, and the macro's
behaviour depends on a data step that is not in it. The R port must do the
permutation itself, and must take the weight re-derivation as a function
argument rather than assume columns exist.

⚠️ **`%mw_var` holds the weights fixed across replicates.** It resamples rows
within `strata &GROUP`, and the treatment group is its **only** stratum: the
macro has no strata argument of its own. It recomputes only the weighted means, never the
propensity model or the weights. That is what production SAS did and what a
parity port must reproduce, but it ignores the uncertainty in the estimated
weights. Port it faithfully, and document the limitation in the roxygen rather
than silently "fixing" it and breaking parity.

## 3. What the R family has today

| where | what | gap against `%stddiff` |
|---|---|---|
| `hvtiRpropensity` `.calc_smd()` / `.smd_table()` (`R/utils.R`, internal) | Unweighted SMD for `ps_match` before/after and `ps_score` | Numeric only; defaults to every numeric column; no ordinal ranks, no categorical |
| `hvtiRpropensity` `.calc_smd_weighted()` (`R/ps-weight.R`, internal) | Weighted SMD for `ps_weight` | Numeric only |
| `hvtiRtables` `hv_tbl_summary(compare = "smd")` | `gtsummary::add_difference(... ~ "smd")`, via the `smd` package | Two groups; no weights; a table column, not a dataset |
| `hvtiRbootstrap` `boot_predict_ci()` | Generic resampling of `statistic(data, ...)` with a cluster `id`, `PCTLDEF=1` percentiles (`type = 4`) | No `strata`, which `%mw_var` needs |

⚠️ **`hvtiRpropensity` disagrees with itself, and with the SAS.** The two
internal functions use different denominators:

- `.calc_smd()` pools by sample size, `sqrt(((n0-1)s0^2 + (n1-1)s1^2) / (n0+n1-2))`,
  citing Austin 2009 and Cohen 1988.
- `.calc_smd_weighted()` averages the two weighted variances, `sqrt((v0 + v1) / 2)`,
  and those variances divide by `sum(w)` with no small-sample correction.
- `stddiff.sas` averages the two sample variances, `sqrt((var1 + var0) / 2)`,
  and when weighted uses the `PROC MEANS` weighted variance with an `n - 1`
  denominator (§2), not `sum(w)`.

With unequal group sizes, which is every unmatched cohort, the unweighted
before-matching table therefore does not reproduce the SAS number. With equal
sizes the first and third agree. The `smd` package's denominator has **not been
checked** and must be before `hvtiRtables` is pointed at the new function.

## 4. Design: the point estimate

One exported function in `hvtiRpropensity`, a port of `%stddiff`:

```r
ps_stddiff(data, group,
           gaussian = NULL, nong_ord = NULL, binary = NULL, categorical = NULL,
           weight = NULL)
```

- **Returns a data frame**, one row per variable: `variable`, `type`, `stddiff`,
  plus the per-group summaries the SAS dataset carries. A data frame is what
  `hvtiPlotR::hv_balance()` and a later table read; a printed table is not.
- **`group` must be 0/1**, as in the macro, and binary variables must be 0/1.
  Both are errors, not coercions: the macro's banner says so in capitals, and a
  quietly recoded factor is how 1 minus 0 becomes 0 minus 1.
- **The variable lists stay separate by type**, mirroring `GAUSSIAN=`,
  `NONG_ORD=`, `BINARY=`, `CATG=`. The type decides the formula, and inferring
  it from column class would pick Gaussian for an ordinal NYHA score stored as
  an integer.
- **No `SUBSET=`.** In R the caller filters the data frame first; a where-clause
  string argument is a SAS idiom.
- **Formulas are the §2 table exactly**, weighted variants using weighted means
  and variances. Parity with a production `est.stddiff` is the acceptance test,
  not agreement with a textbook.
- **The three internal callers switch to it** in the same change, which removes
  the §3 disagreement. That changes the numbers `ps_match()` reports before
  matching, so it is a behaviour change and gets a `NEWS.md` entry saying so.

## 5. Design: the permutation reference interval

```r
ps_stddiff_perm(data, group, ..., weight = NULL, reweight = NULL,
                n_perm = 1000, seed = NULL)
```

- Permutes `group`, calls `ps_stddiff()`, and returns the observed value
  beside the 2.5, 16, 50, 84 and 97.5 percentiles, computed with `type = 4`
  to match `PCTLDEF=1`. The 2021 correction (16/84, not 14/86) is the point of
  listing the percentiles explicitly.
- **`reweight`** is a function of the permuted data returning a weight vector.
  It replaces the precomputed `<weight>_<i>` columns. With a weight and no
  `reweight`, the function errors: holding weights fixed under a permutation
  answers a different question, and it should not be possible by omission.
- **Name the output honestly.** Columns are percentiles of a permutation
  distribution, not `lower`/`upper` confidence limits.

## 6. Design: matching-weight treatment-effect variance

```r
ps_mw_var(data, group, outcomes, weight, n_rep = 1000, seed = NULL)
```

- Bootstrap stratified on `group` and on nothing else, which is exactly
  `%mw_var`'s `strata &GROUP`. There is deliberately no `strata` argument: the
  SAS has none, and adding one would be a feature with no parity target.
  Weighted mean difference per outcome,
  then SD, the five percentiles, z = estimate / SD and its two-sided p.
- Weights held fixed, as §2 records, and said so in `@details`.
- **Reuse.** `hvtiRbootstrap::boot_predict_ci()` has the percentile convention
  but no strata. Either it gains `strata`, and `hvtiRpropensity` takes a
  dependency on `hvtiRbootstrap` (today it imports only `rlang` and `stats`),
  or `hvtiRpropensity` carries a 20-line stratified resampler. See §10.

## 7. Three-way matching

**What exists in R.** `hvtiRpropensity::ps_nominal()` fits a multinomial
propensity model (`nnet::multinom`, SAS `link=glogit`) and returns one
probability per level. Nothing downstream consumes it: `ps_match()` and
`ps_weight()` both call `.check_binary()`.

**What exists in the SAS library.** No three-group matching macro. `gmatch`,
`vmatch` and `match` match cases to controls, two groups at a time; `usmatchd`
is not a matcher at all, it builds US Life Table reference survival
(`2026-08-11-r-hazard-job-templates-design.md` §4.2). The only multi-group
difference is `%std_df4g`, whose max-minus-min definition discards which pair
differs.

### 7.1 Census, 2026-09-16

Content search over the program files listed in the 2026-08-27 corpus sweep
(`census-ALL.csv`, 2,240,554 rows): every `.sas`, `.R`, `.r`, `.Rmd` and `.qmd`
file with a study and not a `tp.` template, **71,326 files**. Counts only; no
study is named here.

| signal | pattern | studies |
|---|---|---|
| SAS multinomial model | `link = glogit` | 46 |
| R multinomial model | `multinom(` | 2 |
| "generalized propensity score" in text | | 4 |
| k-group matching weight | `min(` over three or more probability columns | **0** |
| `twang::mnps()`, `WeightIt` | | **0** |

Reading the jobs in the glogit studies, the shape is consistent and **it is not
three-way matching**. A study with three or more groups fits the glogit model to
describe how the groups differ, then compares them **pairwise**: a binary
logistic propensity model per pair, the binary Li and Greene weight
`min(p, 1 - p) / (p z + (1 - p)(1 - z))` per pair, and one `%gmatch` call per
pair. The most recent study with three arms, active 2024 to 2026, has three of
each. In the studies read, weighted balance and `%mw_var` then run per pair, from `dc` jobs.

One study, in 2018, went further: it built a three-column generalized
propensity score from a random forest and passed all six orderings to
`GPSCDF`, a covariate-balancing method for multiple treatments. That is one
study, and a different method from generalised matching weights.

**Limits of the search.** It reads text, so a k-group weight written as
`min(of p1-p3)` or through an intermediate variable is missed. To cover that
case, every program file in the 42 glogit studies found by a first, narrower
pass (3,873 files) was searched for matching-weight and match-macro calls, and
the jobs of five were read. The four studies the wider pass added were not.
It cannot see jobs that were never saved under `/studies`.

### 7.2 Decision

**The two-study gate is closed for three-way matching.** Zero studies compute a
k-group matching weight and one uses a k-group balancing method. What the corpus
does run, at 46 studies, is pairwise comparison, and §4 to §6 already cover it:
the job subsets to a pair, recodes it 0/1, and calls the two-group functions.

So §4 to §6 stay binary. A `group` with more than two levels is an error, with a
message saying to subset to a pair and recode. Nothing in their signatures
changes if k-group support is ever added, but the validation and the contrast
definition would, and that is new design, not an extension.

**If the gate opens later**, the candidate method is matching weights
generalised to k groups, `w_i = min_k(e_k) / e_{z_i}` (Yoshida et al. 2017,
*Epidemiology*; verify the citation before quoting it in roxygen), computed from
`ps_nominal()` output. Its balance check needs `ps_stddiff()` on **every** pair
of levels, not only against a reference: two non-reference groups can differ
more than either differs from the reference, and each pair has its own pooled
denominator. The summary is the maximum absolute difference over all
`k(k - 1) / 2` pairs per variable.

**What would be worth building now instead** is a helper that does the pairwise
recode the 46 studies do by hand. That is a template concern, not a package one,
and belongs in the `dc-stddiff` template's narration first.

## 8. Templates

| row | template | depends on |
|---|---|---|
| `dc-stddiff` | balance table from `ps_stddiff()`, optional permutation reference | §4, §5 |
| `%mw_var` | treatment-effect table from `ps_mw_var()` | §6; prefix undecided, though the studies read call `%mw_var` from `dc` jobs (§7.1) |

Both follow once the function ships in a released `hvtiRpropensity`. Each needs
`EDIT:` markers on the variable lists, its own `.lintr` file key, and the
catalog row updated.

⚠️ **The roadmap's propensity-matching block is generated from the job catalog**,
so the owner change is a catalog edit, not an edit to
`2026-08-29-template-conversion-roadmap.md`. Hand-editing the generated block
fails `check-roadmap-counts.py` on the next regeneration.

## 9. Acceptance

1. `ps_stddiff()` reproduces a production `est.stddiff` from one study to
   4 decimal places, for each of the four types, weighted and unweighted.
2. `ps_stddiff_perm()` with a fixed seed is reproducible, and its observed
   column equals `ps_stddiff()`.
3. `ps_mw_var()` SDs fall within Monte Carlo error of a `%mw_var` run on the
   same data (bootstrap draws cannot match SAS `SURVEYSELECT` row for row).
4. `ps_match()`, `ps_logistic()` and `ps_weight()` tables come from `ps_stddiff()`,
   and a test asserts the unequal-group-size case against the SAS formula, so
   the §3 disagreement cannot return.

## 10. Open questions

1. Names: `ps_stddiff`, `ps_stddiff_perm`, `ps_mw_var`, against the package's
   `ps_`, `sa_`, `bs_` prefixes. `sa_` (sensitivity analysis) is arguably the
   home for the permutation reference.
2. `hvtiRbootstrap` dependency for §6, or a local resampler.
3. The template prefix for `%mw_var`: its own row, or a `dc` qualifier beside
   `dc-stddiff`, as the corpus runs it.
4. Units: proportion or percent (§2).
5. Which study supplies the parity `est.stddiff` and `%mw_var` output.
6. Whether `hvtiRtables::hv_tbl_summary(compare = "smd")` should call
   `ps_stddiff()`, which would make `hvtiRtables` depend on `hvtiRpropensity`.
