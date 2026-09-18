# ML family roadmap: `rfs`/`rfc`/`rfr`, `sid`, `vt`

**Date:** 2026-09-17
**Status:** Approved (John Ehrlinger, 2026-09-17); sub-project 1 spec approved
**Parent:** `dev/specs/2026-08-29-template-conversion-roadmap-design.md` §3.4,
which hands the random forest family, `sid` and `vt` to an "ML family design
spec". This note is that spec's top level: it fixes package boundaries and
build order. Each sub-project gets its own design and plan.

## 1. What this decides

- Where machine learning method code lives, and which way dependencies run.
- The order the family is built in.
- Which existing analyses are the reference inputs for each template.

It decides no template contents.

## 2. Dependency rule

**Internal `hvtiR*` packages depend on the public packages, never the
reverse.** The public modelling layer is:

- TemporalHazard
- ggRandomForests
- ggBoostedTrees

ggRandomForests is large and public, so **no SID- or virtual-twins-specific
code goes into it**; it stays the study-agnostic `gg_*` layer over
randomForestSRC and varPro.

Method code for this family goes to a **new internal package,
`hvtiRforests`**, which may depend on the public trio and on other `hvtiR*`
packages as required (for example `hvtiRutilities`).

Consequence for the job catalog: the `hvtiR/inst/extdata/jobs.json` rows for
`sid` and `vt` currently name `destination: ggRandomForests`. They are
repointed to `hvtiRforests` once that package exists (sub-project 3). The
`rf*` rows' `replaced_by` guidance (`gg_*` functions) stays valid for plotting;
templates call those functions.

> **Note, 2026-09-18.** The "Consequence for the job catalog" paragraph above
> is **historical**, superseded by `2026-09-18-template-catalog-design.md`: do
> not repoint anything. There is no `destination` to repoint: that field is removed, every catalog row is a template owed in
> `hvtiRtemplates`, and `sid`/`vt` carry `blocked_on: hvtiRforests#1`, which
> is the whole of their dependency on `hvtiRforests`. `replaced_by` is renamed
> `uses`. The package boundaries in this section are unchanged.

## 3. Layers

| Layer | Package | Holds |
|---|---|---|
| Public | TemporalHazard, ggRandomForests, ggBoostedTrees | fitting and plotting primitives, unchanged |
| Shared infrastructure | `hvtiRutilities` | `cache_fit()`: strict, call-keyed cache for any expensive step (forests, varPro, imputation, TemporalHazard, boostmtree, partial dependence) |
| ML methods | `hvtiRforests` (new) | SID fit with PAM over K, cluster label alignment and collapse, swapped-arm prediction, RMST difference |
| Jobs | `hvtiRtemplates` | thin one-file templates: `rfs`, `rfc`, `rfr` as base forest jobs; `sid` and `vt` composed on them |

`sid` and `vt` **drive or reuse the `rf*` templates**. For example, virtual
twins eligibility is an `rfc` job and the per-arm fits are `rfs` jobs;
per-cluster varPro in SID is an `rfc`-shaped job with cluster as outcome.

## 4. Build order

Each sub-project gets its own design, plan and PRs.

| # | Sub-project | Repo | Output |
|---|---|---|---|
| 1 | `cache_fit()` | `hvtiRutilities` | spec: `hvtiRutilities/dev/specs/2026-09-17-cache-fit-design.md` (PR #123) |
| 2 | `rf*` base templates | `hvtiRtemplates` | `rfs`, `rfc`, `rfr`; owns the `rfsrc` to outcome-axis migration story from the parent roadmap |
| 3 | `sid` | `hvtiRforests` (created here) + `hvtiRtemplates` | SID + PAM, choose K, cluster summaries parameterised by K, per-cluster varPro |
| 4 | `vt` | `hvtiRforests` + `hvtiRtemplates` | eligibility, per-arm fits, swapped-arm prediction, RMST difference, outcomes |

Order rationale: each layer builds on the one below; `rf*` precedes `sid` and
`vt` because both compose on it.

## 5. Reference inputs

- **`rf*`:** the older study templates
  `tp.rf.{survival,classifier,classification,regression,multivar}.study.qmd`
  (Quarto predecessors of the outcome-axis split).
- **`sid`:** the **first** SID clustering analysis (a biventricular repair
  morphology study) is the plan of record: a single notebook,
  `sidcluster_pam.<...>.morph.qmd`, whose pipeline is the plan. Its stages:
  setup and caching; data and imputation; SID fit; PAM over K with Sankey
  across K; per-K cluster summaries; choosing K (elbow, silhouette, gap);
  per-cluster varPro and partials. Stages 5 and 7 are repeated once per K,
  about 80% of the notebook, which the templates replace with a `K`
  parameter. The **second** SID analysis (a later morphology Quarto book)
  already splits these into chapters and is the check on the decomposition.
- **`vt`:** a virtual twins Quarto book (ingestion, survival overview,
  feature selection, case eligibility, per-arm survival forests,
  counterfactuals, outcomes, post-hoc cluster outcomes). Clusters enter only
  as a post-analysis stratifier joined on the patient key, never as a model
  covariate; that is the interface between `sid` and `vt`.

Study paths and identifiers are kept out of this repository.

## 6. Prefix work still blocking

`sid`, `vt` and `rfr` are proposed prefixes. Adding them to
`hvtiRutilities::hvti_taxonomy()`, demoting `rf`/`rfsrc`, and pinning the
catalog here remain the cross-repo PR sequence the parent roadmap describes;
it blocks sub-project 2's naming, not sub-project 1.
