# Regression-model template family: `rm`

**Date:** 2026-10-13
**Status:** Approved by John Ehrlinger on 2026-10-13; census run on the server 2026-10-13
**Parent:** `2026-08-29-template-conversion-roadmap-design.md`; implements the
`rm` member of the models family and the continuous step of the
propensity-matching workflow overlay. Follows the precedent set by
`2026-09-21-lm-template-family-design.md`, which this document assumes and
does not repeat except where `rm` differs.

## 1. Objective

Replace the catalog's single unqualified `rm` row with a qualified family of
ordinary least-squares jobs. Statistical method code lives in
`hvtiRpropensity`; the shipped Quarto files stay thin.

The first cut is:

| qualifier | job | engine |
|---|---|---|
| `balancing_continuous` | balancing score for a continuous exposure | `bs_continuous()`, brought onto the result contract |
| `linear` | OLS model of a continuous outcome, with pooled inference | `fit_linear()`, new |

Further qualifiers ship only when the census in §2 finds the shape in at least
two studies. A transformed outcome, for instance, is an `EDIT:` choice in the
formula of `rm-linear` unless the census shows it recurring as a distinct job.

Every `rm` row is qualified. There is no `rm.qmd`, for the reason the `lm`
design gives: an unqualified row beside qualified rows is a choice no caller
can name, and `check-roadmap-counts.py` refuses a half-qualified prefix.

### 1.1 Why the balancing score is `rm`'s and not an outcome model

The roadmap design's overlay table lists `tp.rm.continuous.balncing_score.sas`
as "outcome, continuous". That was a reading of the filename. The SAS job, and
`bs_continuous()`, which its help page says mirrors it, regress a continuous
**exposure** on pre-exposure covariates and stratify patients on the averaged
fitted value. It is the continuous sibling of the retired `pm` count balancing
score, which the `lm` design absorbed as `lm-balancing_count`.

It stays under `rm` rather than joining `lm-balancing_count` because the fit
is a linear model and the legacy jobs already carry `rm`. Moving it to `lm`
would stretch "logistic model" past the Poisson fit it already holds, and
would retire a prefix from the work it names.

The roadmap overlay row is corrected to read "balancing score, continuous
exposure" in the implementation PR that ships `rm-balancing_continuous`.

## 2. Evidence and scope

The 2026-10-13 content census scanned 577 candidate SAS programs under the
`rm` prefix. Legacy `tp.*` template copies were skipped (see below). The scan
completed with no traversal errors and no unreadable candidates. It classified
two admitted shapes:

- **Linear outcome** (`rm-linear`): 524 SAS programs in 160 studies, of which
  238 use multiple imputation.
- **Continuous balancing score** (`rm-balancing_continuous`): 39 SAS programs
  in 9 studies, of which 15 use multiple imputation.

Both shapes pass the two-study gate. Five programs were syntax-ambiguous and
went to manual review, and 6 were semantically misfiled and are excluded. The
migration findings are 2 programs for `mm`, 1 for `gm` and 0 for `nm`. No R job
fits an ordinary least-squares model: the 85 R files under `rm` names are
plotting jobs filed under the wrong prefix, so neither shape has an R precedent.

A transformed response is common but not the majority. 190 linear programs in
74 studies (46%) model a transformed response, below the majority stop gate, so
no `linear_log` qualifier ships and the log option stays an `EDIT:` choice in
`rm-linear`'s formula. Among the continuous balancing programs, 4 in 3 studies
are transformed.

The first run of the census did not skip legacy templates and reported 1,142
studies. Those were `tp.*` template files copied into study folders, not jobs:
2,983 copies in all. The script now skips them and reports the count. The
2026-09-21 `lm` census used the same file filter, so its published breadths
likely include such copies. That is a follow-up and is not settled here.

The census is `dev/specs/artifacts/2026-10-13-rm-shape-census.py`, a sibling
of `2026-09-21-lm-shape-census.py`, and inherits its rules:

- Candidates are programs whose filename carries the `rm` prefix field.
- It classifies the model statement, not the filename. Admitted procedures
  are `PROC REG` and `PROC GLM` with a continuous response.
- `PROC MIXED`, `PROC GENMOD` and `PROC NLIN` fits under an `rm` name are
  counted as **migration findings** for `mm`, `gm` and `nm` respectively, and
  do not become `rm` interfaces. Neither does any other method filed as `rm`.
- Each admitted shape records SAS programs, SAS studies, R jobs, R studies,
  multiple-imputation programs and whether it passes the two-study gate.
- Syntax-ambiguous programs go to manual review and are counted as such.
- Only aggregate counts enter this repository. Study names, paths,
  identifiers and built-dataset names do not.

The share's mount name changes across remounts, so the script resolves it at
run time rather than hard-coding it, and it walks study roots it is given
rather than running `find` over the share.

The catalog previously recorded `rm` at a SAS breadth of 174 studies and 8 R
exemplars over 94 R jobs. Those were filename counts, which the census replaces.

## 3. Package ownership

### 3.1 `hvtiRpropensity`

One upstream pull request adds the OLS engine and brings the existing
balancing score onto the contract the `lm` family established:

- `fit_linear(formula, data, outcome_col = NULL, id_col = "id",
  imputation_col = NULL, ...)` fits `stats::lm()` once per imputation, or once
  for a single dataset, and returns the `data` / `models` / `meta` / `tables`
  object that `fit_logistic()` returns.
- `bs_continuous()` keeps its signature and its scored `$data`, and gains
  `estimates`, `covariance`, `by_imputation` and fit status in `$tables` by
  calling the same fitting and pooling code. Today it returns
  `strata_counts` alone, so a template built on it could show no coefficients
  and no fit health. The change is additive and backward compatible.
- Rubin pooling reuses the primitives behind `fit_logistic()` and
  `bs_count()`. No pooling code is copied into a template, and none is
  written twice upstream.

`hvtiRbootstrap::fit_linear()` already exists, with a different signature
(`data, formula, select`) and a different job: it is the fitter that
`boot_select()` calls during bootstrap variable selection. Both packages
already export `fit_logistic()` on the same terms, and the shipped templates
call each by its full namespace. `rm` templates do the same, so the shared
name is unambiguous.

### 3.2 `hvtiRtemplates`

Two thin Quarto jobs, each of which declares study choices with `EDIT:`
fields, reads one registered dataset, validates the declared columns, calls
one `hvtiRpropensity` engine, displays row accounting, fit health and
estimates, and saves a versioned model bundle.

## 4. Shared template contract

The contract is the shipped `lm-*` templates', as they stand on `main`, not
as the `lm` design described them. In particular the jobs declare `SUBJECT`,
not `ENDPOINT`, and open with the single `setup` chunk that calls
`hvtiRtemplates:::.job_setup()`.

- Its own `format:` block, exactly one `^SUBJECT\s+<- ` line and exactly one
  `^TYPE\s+<- ` line.
- The standard data block: `DATASET`, `ANALYSIS_SET`, `WHERE`, `ID`, `KEY`,
  and the `JOIN`, `JOIN_VARS`, `REDUCE` and `JOIN_KEY` fields.
- `OUTCOME`, `PREDICTORS` and `IMPUTATION` as `EDIT:` fields.
- Tables of fit status, estimates and covariance, read from the engine's
  `$tables`.
- The bundle is saved with `set_path("estimates", "rm-<qualifier>.rds")`
  through `hvtiRtemplates:::.digest_bundle_ids()`, so no identifier reaches the
  saved file in the clear.
- Rows dropped for missing values are reported beside the data, as the
  templates fixed in #318 do. No template imputes, recodes a response, or
  treats a missing value as a level.
- Its own file key in `.lintr`.

## 5. Template-specific contracts

### 5.1 `rm-balancing_continuous`

`SUBJECT <- "exposure"`, `TYPE <- "balancing"`. Calls `bs_continuous()`, with
`N_STRATA` as an `EDIT:` field. Reports the averaged fitted-value balancing
score, the stratum counts, fit health and pooled inference.

The template does not transform the exposure. If the analysis plan models a
logged exposure, the author writes the transformation into the formula and
the report states the formula it fitted.

### 5.2 `rm-linear`

`SUBJECT` names the outcome; `TYPE <- "linear"`. Calls `fit_linear()`. In
addition to the shared tables it reports:

- the residual standard error;
- R², for a single dataset only. It is withheld for multiply-imputed data,
  where Rubin pooling defines no R², rather than reported from an average
  that would look authoritative and is not;
- a residual-versus-fitted figure and a normal Q-Q plot of residuals. Under
  multiple imputation both are drawn from the first imputation and labeled so.

## 6. Multiple-imputation semantics

As `lm` §6. Input is stacked long-form data; the package fits the same
declared model within every imputation; coefficients and covariance use Rubin
pooling. Per-patient fitted values are averaged across imputations only for
`balancing_continuous`, because its SAS predecessor did so.

A differing coefficient set, an aliased term or a non-finite covariance in any
imputation is an error that names the imputation. Pooling cannot turn a failed
constituent fit into a successful report.

The degrees-of-freedom convention for the pooled t statistics is verified
against synthetic `PROC MIANALYZE` output, not inferred from agreement among
R implementations.

## 7. Legacy mapping and migration boundary

| legacy shape | destination |
|---|---|
| `tp.rm.continuous.balncing_score.sas` and its descendants | `rm-balancing_continuous` |
| `PROC REG` / `PROC GLM`, continuous outcome | `rm-linear` |
| `PROC MIXED` filed as `rm` | migration finding for `mm` |
| `PROC GENMOD` filed as `rm` | migration finding for `gm` |
| `PROC NLIN` filed as `rm` | migration finding for `nm` |

There is no automatic `migrate_job()` adapter, for the reason the `lm` design
gives: a partial parser of SAS `CLASS`, `MODEL` and `BY _IMPUTATION_` blocks
could produce a plausible job that fits a different model.

## 8. Catalog and documentation

The implementation replaces the unqualified `rm` row in
`inst/extdata/templates.json` with one row per shipped qualifier, carrying the
census counts. The roadmap ledger flips to match, and the propensity-matching
workflow, of which both are members, moves from 9 of 12 to 11 of 13: the
unqualified `rm` row becomes two rows. `rm-linear` belongs because a continuous
outcome analyzed on the matched cohort is a workflow step, the continuous
counterpart of `cm` for time to event (spec 1.1 reread the legacy
balancing-score file, which is why the step is now carried by `rm-linear`, not
by that file). `inst/templates/README.md` lists the new templates.

## 9. Verification

### 9.1 Upstream

- `fit_linear()` coefficients and standard errors equal `stats::lm()`'s on a
  single dataset.
- The pooled result equals a hand-computed Rubin pool on a small synthetic
  imputed dataset, and matches synthetic `PROC MIANALYZE` output.
- `bs_continuous()`'s scored `$data` is unchanged by the upgrade: a snapshot
  taken before the change must still pass after it.
- Each hard-stop in §6 has a test that triggers it.

### 9.2 Templates

- Each template renders end to end on `hvtiRpropensity::sample_ps_data()`,
  once as a single dataset and once stacked as imputations. A mutation check
  confirms that the imputed render takes the pooled path: forcing the single
  path must turn the test red.
- The saved bundle passes the MRN scan.
- `spec-counts.yaml` and `check-roadmap-counts.py` pass against the new rows.

### 9.3 Completion gates

The census establishes at least two studies per shipped shape. Then the
definition of done in `AGENTS.md`: `devtools::test()` passes, `devtools::check()`
is 0/0/0, and `man/` and `NAMESPACE` are current.

## 10. Build order

1. Run the shape census, fill §2, and revise §1's qualifier list to match.
2. `hvtiRpropensity`: `fit_linear()` and the `bs_continuous()` contract
   upgrade, in one pull request.
3. Raise this package's `hvtiRpropensity` floor to that release.
4. `rm-balancing_continuous`, with the roadmap overlay correction from §1.1.
5. `rm-linear`, and any further qualifier the census admits.
6. Replace the catalog row, flip the ledger, and run every completion gate.

## 11. Non-goals

- Mixed, generalized and non-linear models, which belong to `mm`, `gm` and
  `nm`.
- Variable selection; `br` owns bootstrap linear selection and `rm` fits a
  declared model.
- An `rm` analog of `lm-checkpred`, unless the census finds one at two studies.
- Automatic SAS source translation.
- A regression-plot family; `rp` is dependent work, designed against the
  bundle this family saves.
