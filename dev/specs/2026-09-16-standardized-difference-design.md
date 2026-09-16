# Standardized differences, their reference intervals, and matching-weight variance

**Date:** 2026-09-16
**Status:** design, not started. No code in any package yet.
**Supersedes:** the owner named for `dc-stddiff` in
`2026-09-02-dp-dc-decomposition-design.md` §5 and
`2026-08-29-template-conversion-roadmap.md` (propensity-matching workflow).
The macro choice made there stands; the owner does not.

## 1. Decisions taken 2026-09-16

- **`hvtiRpropensity` owns standardized differences**, not `hvtiRutilities`.
  It already computes them, internally, for every object it returns (§3), and
  the matching and weighting objects are the thing a balance check is about.
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
| categorical, k > 2 levels | Mahalanobis form, `sqrt(t' S^-1 t)` over the k-1 level proportions (Yang and Dalton 2012) | 560 to 602 |
| one-level variable | 0 | 278 |

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
within `strata &GROUP` and recomputes only the weighted means, never the
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
- `stddiff.sas` averages the two sample variances, `sqrt((var1 + var0) / 2)`.

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

- Stratified bootstrap within `group`, weighted mean difference per outcome,
  then SD, the five percentiles, z = estimate / SD and its two-sided p.
- Weights held fixed, as §2 records, and said so in `@details`.
- **Reuse.** `hvtiRbootstrap::boot_predict_ci()` has the percentile convention
  but no strata. Either it gains `strata`, and `hvtiRpropensity` takes a
  dependency on `hvtiRbootstrap` (today it imports only `rlang` and `stats`),
  or `hvtiRpropensity` carries a 20-line stratified resampler. See §10.

## 7. Three-way matching

**What exists.** `hvtiRpropensity::ps_nominal()` already fits a multinomial
propensity model (`nnet::multinom`, SAS `link=glogit`) and returns one
probability per level. Nothing downstream consumes it: `ps_match()` and
`ps_weight()` both call `.check_binary()`. On the SAS side, the library has no
three-group matching macro (`gmatch`, `vmatch`, `match` and `usmatchd` are all
case-control), and the only multi-group difference is `%std_df4g`, whose
max-minus-min definition discards which pair differs.

**The method that fits this family** is matching weights generalised to k groups
(Yoshida et al. 2017, *Epidemiology*, "Matching weights to simultaneously compare
three treatment groups"; verify the citation before quoting it in roxygen):
`w_i = min_k(e_k) / e_{z_i}`. It is the k-group form of the Li and Greene weight
`%mw_var` already uses, it is computed directly from `ps_nominal()` output, and
it avoids the combinatorics of forming matched triplets.

**What a k-group balance check needs**: `ps_stddiff()` run pairwise against a
reference level, plus the maximum absolute difference over all pairs per
variable. `%std_df4g`'s single number is not reproduced.

**Gate.** Nothing here is built until a census shows the shape in at least two
studies, the rule every template follows. The corpus has not been searched for
three-group propensity work; `hvtiRutilities::job_census()` over `/studies`
is the next step, looking for `link=glogit` beside a weight or match step.
Until then §7 is a direction, not a commitment, and §4 to §6 are designed so a
`group` with more than two levels can be added without changing their signatures.

## 8. Templates

| row | template | depends on |
|---|---|---|
| `dc-stddiff` | balance table from `ps_stddiff()`, optional permutation reference | §4, §5 |
| `%mw_var` | treatment-effect table from `ps_mw_var()` | §6; prefix undecided |

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
4. `ps_match()`, `ps_score()` and `ps_weight()` tables come from `ps_stddiff()`,
   and a test asserts the unequal-group-size case against the SAS formula, so
   the §3 disagreement cannot return.

## 10. Open questions

1. Names: `ps_stddiff`, `ps_stddiff_perm`, `ps_mw_var`, against the package's
   `ps_`, `sa_`, `bs_` prefixes. `sa_` (sensitivity analysis) is arguably the
   home for the permutation reference.
2. `hvtiRbootstrap` dependency for §6, or a local resampler.
3. The template prefix for `%mw_var`.
4. Units: proportion or percent (§2).
5. Which study supplies the parity `est.stddiff` and `%mw_var` output.
6. Whether `hvtiRtables::hv_tbl_summary(compare = "smd")` should call
   `ps_stddiff()`, which would make `hvtiRtables` depend on `hvtiRpropensity`.
