# The template catalog

## What is here

Every analysis job an HVTI study runs starts from a template: a Quarto
file with the study-specific lines marked `EDIT:`. This page lists them
all, what each one does, and how close each is to being delivered. It is
built from the package’s own catalog when the page is rendered, so a
template added, renamed or shipped shows up here without anyone
remembering to update the page.

A template becomes a job in your study with
[`add_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md).
The first argument is the template’s prefix, then the subject and type
that name the job’s set, and the qualifier when the prefix has one:

``` r

add_job("dp", "cohort", "eda", qualifier = "gfup")
```

In a new study that writes `40_graphs/cohort-eda-dp-gfup.qmd`; a legacy
study that already uses bare folder names gets
`graphs/cohort-eda-dp-gfup.qmd`. The job refuses to overwrite an
existing file, because a job accumulates a study’s edits.

## Delivery

Each template carries a light.

- 🟢 **Shipped** (28): on disk and supported. Scaffold it and use it.
- 🟡 **In progress** (21): on disk but being reworked, or scheduled into
  a delivery batch with nothing blocking it.
- 🔴 **Not yet on the way** (16): waiting on a function in another
  package, or not yet scheduled. The job type is known and counted; for
  now, write it by hand.

## Available now

Every template on disk, grouped by the study folder a job lands in,
named without its digits (`graphs` is `40_graphs` in a new study).
[`add_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
places each one; you do not choose the folder.

### descriptive

| Delivery | Template | Description | Scaffold |
|:---|:---|:---|:---|
| 🟢 Shipped | `dc-general` | First look at a built cohort: what the data contain, how each categorical variable breaks down, how each continuous variable is distributed, and which variables move together. | `add_job("dc", subject, type, qualifier = "general")` |
| 🟢 Shipped | `dc-gfup` | Checks recorded follow-up before any time-related analysis: counts for the cohort, the event and censored subsets, and the missing, negative and zero intervals. | `add_job("dc", subject, type, qualifier = "gfup")` |
| 🟢 Shipped | `dc-tables` | The formatted descriptive table: every reported variable under its section heading, categorical as n (%) and continuous as the summary you choose, written to Word. | `add_job("dc", subject, type, qualifier = "tables")` |
| 🟢 Shipped | `dp-postage` | Data-checking sweep over a new build: one small panel per variable against operation year, to find coding errors, drift and missingness. Not a manuscript figure. | `add_job("dp", subject, type, qualifier = "postage")` |

### distributions

| Delivery | Template | Description | Scaffold |
|:---|:---|:---|:---|
| 🟢 Shipped | `ac` | Nonparametric life tables by stratum, with estimates at the reporting horizons. Figures over them are an hp job. | `add_job("ac", subject, type)` |
| 🟢 Shipped | `hz` | Fits and saves the multiphase parametric hazard model whose shape the later hm, hp and hs jobs read. | `add_job("hz", subject, type)` |

### analyses

| Delivery | Template | Description | Scaffold |
|:---|:---|:---|:---|
| 🟢 Shipped | `bc` | Bootstrap variable-selection screen over a Cox proportional hazards model. | `add_job("bc", subject, type)` |
| 🟢 Shipped | `bh` | Bootstrap variable-selection screen for a hazard model: how often each candidate survives, and which to carry into hm. It screens; it does not fit the final model. | `add_job("bh", subject, type)` |
| 🟢 Shipped | `bl` | Bootstrap variable-selection screen over a logistic model. | `add_job("bl", subject, type)` |
| 🟢 Shipped | `br` | Bootstrap variable-selection screen over a linear model. | `add_job("br", subject, type)` |
| 🟢 Shipped | `hm` | Multivariable risk-factor model built on the shape parameters the hz job fitted. | `add_job("hm", subject, type)` |
| 🟢 Shipped | `lm-balancing_count` | Poisson or negative-binomial balancing score for a count exposure, with the distribution as a reviewed study choice. | `add_job("lm", subject, type, qualifier = "balancing_count")` |
| 🟢 Shipped | `lm-binary` | Binary outcome logistic model, saving the fitted model, predictions and pooled inference across imputations. | `add_job("lm", subject, type, qualifier = "binary")` |
| 🟢 Shipped | `lm-checkpred` | Applies a saved lm-binary model to a validation cohort. It never refits the source model. | `add_job("lm", subject, type, qualifier = "checkpred")` |
| 🟢 Shipped | `lm-nominal` | Generalized-logit model for a nominal outcome with a declared level set and reference. | `add_job("lm", subject, type, qualifier = "nominal")` |
| 🟢 Shipped | `lm-ordinal` | Proportional-odds model for an ordered outcome whose full order is declared, not inferred. | `add_job("lm", subject, type, qualifier = "ordinal")` |
| 🟢 Shipped | `lm-propensity_binary` | Propensity model for a binary treatment, scoring the columns that matching and weighting jobs use. | `add_job("lm", subject, type, qualifier = "propensity_binary")` |
| 🟢 Shipped | `lm-propensity_nominal` | Generalized-logit propensity model for a nominal treatment with an explicit reference level. | `add_job("lm", subject, type, qualifier = "propensity_nominal")` |
| 🟢 Shipped | `lm-propensity_ordinal` | Proportional-odds propensity model for an ordered treatment. | `add_job("lm", subject, type, qualifier = "propensity_ordinal")` |
| 🟢 Shipped | `rfc-explain` | Explains a saved classification forest: variable importance, VarPro and dependence plots. | `add_job("rfc", subject, type, qualifier = "explain")` |
| 🟢 Shipped | `rfc-fit` | Grows a classification forest and checks it: out-of-bag error and the ROC curve with its AUC. | `add_job("rfc", subject, type, qualifier = "fit")` |
| 🟢 Shipped | `rfr-explain` | Explains a saved regression forest: variable importance, VarPro and dependence plots. | `add_job("rfr", subject, type, qualifier = "explain")` |
| 🟢 Shipped | `rfr-fit` | Grows a regression forest and checks it: out-of-bag error and predicted against observed. | `add_job("rfr", subject, type, qualifier = "fit")` |
| 🟢 Shipped | `rfs-explain` | Explains a saved survival forest: variable importance, VarPro and dependence plots. It never grows a forest. | `add_job("rfs", subject, type, qualifier = "explain")` |
| 🟢 Shipped | `rfs-fit` | Grows a random survival forest and checks it learned something: out-of-bag error, predicted survival and the Brier score. | `add_job("rfs", subject, type, qualifier = "fit")` |

### graphs

| Delivery | Template | Description | Scaffold |
|:---|:---|:---|:---|
| 🟢 Shipped | `dp-gfup` | The goodness-of-follow-up figure: each patient’s follow-up against operation year, alive in blue and dead in red, under the diagonal the close date allows. | `add_job("dp", subject, type, qualifier = "gfup")` |
| 🟢 Shipped | `dp-trends` | How the cohort changed over the years of operation: the share with a characteristic, or the level of a measurement, year by year with a smooth. | `add_job("dp", subject, type, qualifier = "trends")` |
| 🟡 In progress | `hp` | Nomogram and hazard figures, read from the ac life table and the hz fit rather than recomputed. | `add_job("hp", subject, type)` |
| 🟢 Shipped | `hs` | Patient-level predictions from the hm model, set against the survival of a matched general population. | `add_job("hs", subject, type)` |

## Coming

Job types the SAS library and the study corpus carry that have no
template yet. **SAS jobs** counts the distinct studies with a SAS job of
that type, so a larger number is a template more studies are waiting
for. *Unmeasured* means nobody has counted it yet, which is not the same
as zero.

| Delivery | Template | Description | SAS jobs | Waiting on |
|:---|:---|:---|:---|:---|
| 🟡 In progress | `ar` | Analysis report | 394 |  |
| 🟡 In progress | `lg` | Logit trends | 362 |  |
| 🟡 In progress | `lp` | Logistic plot | 310 |  |
| 🟡 In progress | `nd` | Non-linear distributions | 244 |  |
| 🟡 In progress | `np` | Non-linear plot | 241 |  |
| 🟡 In progress | `dp-variable` | Distribution of a variable | 237 |  |
| 🟡 In progress | `cd` | Cumulative distribution | 190 |  |
| 🟡 In progress | `dc-dead` | Descriptive: mortality | 171 |  |
| 🟡 In progress | `rm` | Regression model | 170 |  |
| 🟡 In progress | `nm` | Non-linear model | 121 |  |
| 🟡 In progress | `gm` | Generalized model | 73 |  |
| 🟡 In progress | `rp` | Regression plot | 68 |  |
| 🟡 In progress | `mm` | Mixed model | 56 |  |
| 🟡 In progress | `rg` | Regression trends | 45 |  |
| 🟡 In progress | `mp` | Mixed model plot | 41 |  |
| 🟡 In progress | `dp-spaghetti` | Descriptive plot: spaghetti | 40 |  |
| 🟡 In progress | `cm` | Cox matching | 35 |  |
| 🟡 In progress | `dp-procs` | Descriptive plot: procedures over time | 35 |  |
| 🟡 In progress | `ls` | Life table / STS | 32 |  |
| 🟡 In progress | `si` | Single imputation | 1 |  |
| 🔴 Not yet on the way | `bd` | Build | 1094 | hvtiRdatabuild |
| 🔴 Not yet on the way | `vars` | Variables | 912 | hvtiRdatabuild |
| 🔴 Not yet on the way | `dt` | Data check | 503 | hvtiRdatabuild |
| 🔴 Not yet on the way | `ce` | Competing events | 128 | hvtiPlotR#134 |
| 🔴 Not yet on the way | `dc-stddiff` | Descriptive: standardized differences | 120 | hvtiRpropensity#34 |
| 🔴 Not yet on the way | `bn` | Bootstrap non-linear | 108 |  |
| 🔴 Not yet on the way | `gp` | Generalized model plot | 50 | hvtiPlotR#136 |
| 🔴 Not yet on the way | `dc-trends` | Descriptive: trends | 43 |  |
| 🔴 Not yet on the way | `nb` | Boosting | 18 | ggBoostedTrees#9 |
| 🔴 Not yet on the way | `mi` | Multiple imputation | 18 | hvtiRimputation |
| 🔴 Not yet on the way | `fp` | Forest plot | 11 | hvtiPlotR#133 |
| 🔴 Not yet on the way | `dp-boxplot` | Descriptive plot: boxplot | 9 |  |
| 🔴 Not yet on the way | `cp` | Cumulative probability plot | 4 | hvtiPlotR#135 |
| 🔴 Not yet on the way | `bq` | Bootstrap quantile | 2 | hvtiRbootstrap#16 |
| 🔴 Not yet on the way | `sid` | Random forest clustering (sidClustering) | unmeasured | hvtiRforests#1 |
| 🔴 Not yet on the way | `vt` | Virtual twins | unmeasured | hvtiRforests#1 |

## Where to read more

- [`template_catalog()`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_catalog.md)
  returns this table with every field the catalog keeps, including the
  design note behind each row.
- `inst/templates/README.md` in the package source explains the naming
  and the folder layout.
- The *From SAS descriptive jobs to R* vignette walks through running
  the descriptive templates against a study.
