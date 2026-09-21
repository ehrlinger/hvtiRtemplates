# Logistic-model template family: `lm`

**Date:** 2026-09-21
**Status:** Approved by John Ehrlinger on 2026-09-21
**Parent:** `2026-08-29-template-conversion-roadmap-design.md`; implements the
`lm` member of the models family and the propensity-matching workflow overlay.

## 1. Objective

Replace the catalog's single unqualified `lm` row with a qualified family that
covers the recurring, legitimate `PROC LOGISTIC` workflows in the legacy
corpus. The first cut includes pooled inference for multiply-imputed data and
keeps statistical method code in `hvtiRpropensity`, leaving the shipped Quarto
files thin.

The family is:

| qualifier | job |
|---|---|
| `binary` | binary logistic outcome model |
| `ordinal` | proportional-odds cumulative-logit outcome model |
| `nominal` | generalized-logit outcome model |
| `propensity_binary` | binary-treatment propensity model |
| `propensity_ordinal` | ordered-treatment propensity model |
| `propensity_nominal` | nominal-treatment propensity model |
| `checkpred` | validation of a saved binary model without refitting |
| `balancing_count` | Poisson or negative-binomial balancing score; absorbs retired `pm` work |

Every `lm` row is qualified. There is no `lm.qmd`, because an unqualified row
beside qualified rows would create a choice callers cannot name consistently.

## 2. Evidence and scope

The 2026-09-21 content census scanned 12,065 candidate SAS programs in 1,220
study roots (1,222 roots across all program extensions). It classified the
eight admitted shapes at the following study breadths: binary 1,172, ordinal
535, nominal 524, binary propensity 1,134, ordinal propensity 819, nominal
propensity 1,049, prediction checking 863 and count balancing 549. The
corresponding program counts are recorded in the catalog and public census
artifact. Multiple-imputation use is substantial rather than exceptional:
1,781 binary, 2,389 binary-propensity and 547 count-balancing programs use it.
The scan completed with no traversal or unreadable-candidate errors; 25
syntax-ambiguous programs received manual review and 15 semantically misfiled
programs were excluded from the interface.

Those filenames are discovery evidence, not the interface. Before a qualifier
ships, a content census must classify the actual model statement and establish
that at least two studies exercised that shape. Only aggregate counts enter
this public repository. Study names, paths, identifiers and built-dataset names
do not.

"Full legacy breadth" means legitimate logistic-model and diagnostic shapes
after semantic triage. It does not preserve jobs that happen to carry `lm` or
`lp` while implementing learning curves, boosting or another prefix's work.
Those are migration findings, not new `lm` interfaces.

## 3. Package ownership

### 3.1 `hvtiRpropensity`

`hvtiRpropensity` owns fitting, multiple-imputation pooling and validation:

- binary logistic fits through `stats::glm(..., family = binomial())`;
- proportional-odds ordinal fits through `MASS::polr()`;
- nominal generalized-logit fits through `nnet::multinom()`;
- Poisson and negative-binomial balancing-score fits through the existing
  `bs_count()` interface;
- one fit per imputation for stacked long-form imputed data;
- Rubin-pooled coefficients and covariance matrices;
- predictions, convergence state, analysis-row accounting and fit metadata;
- binary-model calibration, observed-versus-expected summaries and
  discrimination on a declared validation cohort.

The upstream sub-project must define one result contract shared by general
logistic fits and the existing propensity functions. An object contains:

- `data`: analysed or scored patient-level data;
- `models`: the single fitted model or every per-imputation fitted model;
- `meta`: formula, response/treatment column, model family, event/reference
  levels, ordered levels, identifier and imputation columns, imputation count,
  and row counts;
- `tables`: coefficient estimates, pooled estimates, pooled covariance,
  convergence and exclusion summaries, and model-specific diagnostics.

Existing `ps_logistic()`, `ps_ordinal()`, `ps_nominal()` and `bs_count()` keep
their current scored-data interface. Adding model and pooled-inference fields
must be backward compatible. General outcome-model entry points may share the
same internal fitting and pooling primitives, but no pooling implementation is
copied into a template.

Rubin pooling is performed over identically named coefficient vectors and
covariance matrices. The implementation hard-stops when imputations disagree
on terms, response levels or reference levels; when any constituent fit fails
to converge; or when a covariance matrix is absent or non-finite. Its total
covariance and degrees-of-freedom convention must be documented and verified
against synthetic `PROC MIANALYZE` output rather than inferred from agreement
among R implementations.

### 3.2 `hvtiRtemplates`

`hvtiRtemplates` owns eight thin Quarto jobs. Each job:

1. declares study choices with `EDIT:` fields;
2. reads one registered dataset;
3. validates the declared columns and outcome/treatment contract;
4. calls one `hvtiRpropensity` engine;
5. displays row accounting, fit health, estimates and relevant diagnostics;
6. saves a versioned model bundle below the analysis set's `estimates/`
   artifact directory.

`lm-checkpred` reads a saved bundle and never refits. The bundle retains all
per-imputation fits as well as pooled results so validation, audit and later
plots use the model actually reviewed.

## 4. Shared template contract

Every template carries its own `format:` block, exactly one
`^ENDPOINT\s+<- ` assignment and exactly one `^TYPE\s+<- ` assignment. The
study-specific interface is a compact `EDIT:` block containing only choices
that genuinely vary:

- registered dataset name;
- response or treatment column;
- predictor vector or formula components;
- patient identifier;
- imputation column, or `NULL` for a single dataset;
- event, reference or ordered levels as required;
- model-specific choices named below.

No template guesses a clinically meaningful level from factor order, recodes a
response silently, or treats missing values as a level. Each reports counts for
input rows, excluded rows, analysed rows and, where relevant, every
imputation. A stacked imputed dataset must have the declared patient key in
every imputation and a stable response/treatment value per patient.

Generated model bundles and figures use `set_path()` and remain below the
`<endpoint>-<type>/` artifact directory. Authored files remain flat. A bundle
records package versions and enough model metadata for a downstream job to
refuse an incompatible object.

## 5. Template-specific contracts

### 5.1 `lm-binary`

Fits an ordinary binary logistic outcome model. The author declares the two
accepted outcome values and the event value explicitly. The report includes
coefficient estimates, standard errors, confidence intervals, odds ratios,
convergence, analysed/excluded counts and predicted probabilities. With
multiple imputations, inferential tables and covariance are Rubin-pooled while
patient predictions follow the documented aggregation rule.

### 5.2 `lm-ordinal`

Fits a proportional-odds cumulative-logit outcome model. The complete ordered
level vector is required and must match every imputation. Threshold parameters
are retained and distinguished from predictor coefficients. The report states
the direction of the cumulative probability and includes pooled thresholds,
coefficients and covariance when imputed data are supplied.

### 5.3 `lm-nominal`

Fits a generalized-logit outcome model. The complete level vector and
reference level are explicit. Coefficient and covariance names include the
non-reference outcome level so flattening a coefficient matrix cannot collapse
two parameters onto one name. Pooled inference preserves the same level-by-term
ordering across imputations.

### 5.4 `lm-propensity_binary`

Calls `ps_logistic()` for a binary treatment. It produces treatment
probabilities, logits, matching weights, quintiles/deciles, balance diagnostics
and pooled inference. The treatment values and treated value are explicit.

### 5.5 `lm-propensity_ordinal`

Calls `ps_ordinal()` for an ordered treatment. It requires the full treatment
order and produces one probability column per level, declared strata,
diagnostics and pooled inference.

### 5.6 `lm-propensity_nominal`

Calls `ps_nominal()` for a nominal treatment. It requires the full level set
and an explicit reference level, and produces level-specific probabilities,
diagnostics and pooled inference.

### 5.7 `lm-checkpred`

Validates a saved `lm-binary` bundle on a declared cohort. The first cut is
binary because the legacy `checkpred` shape is binary. It reports calibration,
observed-versus-expected summaries and discrimination. It verifies the saved
formula, event level and required predictors before predicting and stops on an
incompatible bundle. It never refits, updates or overwrites the source model.

### 5.8 `lm-balancing_count`

Calls `bs_count()` for a count exposure and absorbs the retired `pm` workflow.
The author chooses Poisson or negative-binomial explicitly; the template never
selects a distribution from the observed variance. It reports the log-scale
linear-predictor balancing score, declared strata, their counts, fit health and
pooled inference.

## 6. Multiple-imputation semantics

Imputed input is stacked long-form data. The template does not impute and does
not pool a dataset that lacks an identifier or imputation index. The package
fits the same declared model independently within every imputation.

Two outputs answer different questions and are kept separate:

- per-patient predictions or propensity scores are averaged across
  imputations only for workflows whose SAS predecessor did so;
- coefficients and covariance use Rubin pooling for inference.

The report shows each constituent fit's convergence and row count beside the
pooled result. Pooling cannot turn a failed constituent fit into a successful
report. A missing level, aliased term, changed reference, changed coefficient
set or unusable covariance in any imputation is an error with the affected
imputation named.

## 7. Legacy mapping and migration boundary

The first cut documents how common SAS shapes map to qualifiers:

| legacy shape | qualifier |
|---|---|
| binary `PROC LOGISTIC`, including fixed-set outcome models | `binary` |
| default cumulative-logit ordinal model | `ordinal` |
| `link=glogit` or otherwise nominal response | `nominal` |
| binary treatment propensity score | `propensity_binary` |
| ordered treatment propensity score | `propensity_ordinal` |
| polytomous treatment propensity score | `propensity_nominal` |
| apply a saved binary model to a validation cohort | `checkpred` |
| retired `pm` count balancing score | `balancing_count` |

There is no automatic `migrate_job()` adapter in this sub-project. Reliably
rewriting arbitrary SAS `CLASS`, `MODEL`, `BY _IMPUTATION_`, transformation,
contrast and output blocks is a parser project of its own. A partial parser
would be dangerous because it could produce a plausible job with a different
scientific model. Migration guidance identifies choices that must be carried
over and reviewed manually.

## 8. Catalog and documentation

The unqualified catalog row is replaced atomically by eight qualified rows.
Each row records its content-derived SAS-program and R-exemplar counts,
upstream API, status and evidence note. The prefix-wide `sas_breadth` value
cannot be attributed to semantic shapes and is not copied onto any qualifier;
the family note instead records the corpus-wide scan totals once. Until a
row's two-study gate and upstream dependency are satisfied, it remains
`queued`; the family may contain queued and shipped rows, but never an
unqualified row.

The change regenerates the roadmap tables and updates the supported-template
README, package README, NEWS and dependency floors. Every shipped template has
its own file key in `.lintr`; no directory-wide exclusion is introduced.

## 9. Verification

### 9.1 Upstream statistical tests

- Single-dataset binary, ordinal, nominal and count fits match their underlying
  R engines.
- Event, reference and ordered levels are invariant to incidental factor order.
- Coefficient and covariance naming is stable across imputations.
- Hand-calculated Rubin fixtures verify pooled estimates and covariance.
- Synthetic SAS fixtures verify binary, ordinal, nominal, pooled-MI and count
  estimates, covariance, probabilities and strata where applicable.
- Missing levels, changed terms, failed convergence and invalid covariance
  matrices fail before pooling.
- Existing propensity return fields remain unchanged.

### 9.2 Template tests

- Every substantive chunk runs on identifier-free synthetic data.
- Every template scaffolds and renders.
- Saved bundles contain the declared model type, levels, fits, pooled tables,
  covariance, predictions and version metadata.
- `lm-checkpred` is proved not to call a fitting function.
- Catalog ambiguity tests require a qualifier for `lm` and list all eight
  choices.
- Template placement, `EDIT:` guards, privacy checks and `.lintr` coverage run
  through the package's existing gates.

### 9.3 Completion gates

- The content census establishes at least two studies per shipped shape.
- `devtools::document()` leaves `man/` and `NAMESPACE` current.
- `devtools::test()` passes with the expected platform skip count.
- `devtools::check()` reports 0 errors, 0 warnings and 0 notes.
- `lintr::lint_package()` is clean.
- The roadmap, spec-count and flow-count guards pass.

## 10. Build order

1. Specify and implement the shared fit/pool/validation contract in
   `hvtiRpropensity`, with SAS parity fixtures.
2. Run the shape census and replace the unqualified catalog row with eight
   qualified queued rows.
3. Implement `binary`, `ordinal` and `nominal`.
4. Implement the three propensity templates.
5. Implement `checkpred` against the saved binary bundle.
6. Implement `balancing_count` and complete the retired-`pm` mapping.
7. Regenerate documentation and run every completion gate.
8. Design the qualified `lp` family against the saved prediction and
   diagnostic contracts; `lp` is dependent work, not folded into this spec.

## 11. Non-goals

- Preserving jobs that use an `lm` filename for learning curves, boosting or
  another method.
- Automatic SAS source translation.
- Variable selection; `bl` owns bootstrap logistic selection and `lm` fits a
  declared model.
- Ordinal or nominal `checkpred` in the first cut.
- Designing the `lp` qualifier set before the `lm` output contract exists.
