# `vp-dependence` and `vp-individual`: design, 2026-10-22

**Status** Design, approved by the maintainer on 2026-10-22. Not implemented.
**Adds** two templates to the `vp` family, `vp-dependence.qmd` (unsupervised
VarPro, `varPro::uvarpro()`) and `vp-individual.qmd` (individual VarPro,
`varPro::ivarpro()`), both shipped with ledger status `in-flight`.
**Builds on** [`2026-10-21-vp-varpro-templates-design.md`](2026-10-21-vp-varpro-templates-design.md),
which shipped `vp-fit` and `vp-explain` in
[#382](https://github.com/ehrlinger/hvtiRtemplates/pull/382).
**Starts from** the Virtual Twins study (ST1267), notebook chapter 11,
`11-exp-uvarpro-dag.qmd` (2026-10-06), for `uvarpro`. No study has run
`ivarpro` yet.
**Read against** varPro 3.3.0 and ggRandomForests 4.0.0, the installed
versions on 2026-10-22.

## 1. Why two more jobs

The `vp` family is becoming the single home for varPro in this package: a
separate piece of work removes the varPro panel and partial from the
`rf*-explain` templates. Two varPro analyses are not covered by `vp-fit` and
`vp-explain`:

- **`uvarpro`** asks how the variables depend on *each other*, with no outcome.
  `uvarpro()` grows an unsupervised forest (a forest autoencoder by default),
  `get.beta.entropy()` turns its region-release contrasts into an importance
  matrix `I`, where `I[s, j]` is how much predictor `j` helps separate the
  contrast formed by releasing `s`, and `sdependent()` thresholds `I` into a
  directed graph and names a signal set. Virtual Twins chapter 11 used it to
  ask where the outcome sits among its predictors, by entering the outcome as
  one more variable.
- **`ivarpro`** gives each patient a signed local gradient for each predictor:
  how the prediction moves with that predictor near that patient. It takes a
  `varpro` object directly and explains its out-of-bag prediction (mortality
  for a survival forest, the first class probability for a binary one).

Neither is a variant of the screen. `uvarpro` needs no outcome and reads no
fit; `ivarpro` describes one fit and selects nothing. So each is a job of its
own, not an option inside `vp-fit` or `vp-explain` (decided 2026-10-22).

## 2. Ledger and naming

- **Files:** `inst/templates/30_analyses/vp-dependence.qmd` and
  `inst/templates/30_analyses/vp-individual.qmd`, shown by `template_list()`
  as `vp.dependence` and `vp.individual`.
- **Ledger rows** `(vp, dependence)` and `(vp, individual)`, both `in-flight`.
  `vp` is already a taxonomy row in hvtiRutilities and already wholly
  qualified, so no cross-repo step is needed and no `intake` stage either:
  `test-roadmap.R` is satisfied by the prefix already present.
- **Catalog counts** in `test-template-catalog.R` move from 68 rows to 70; the
  prefix count stays at 45.
- **The two-study gate.** Virtual Twins chapter 11 is the only `uvarpro`
  exemplar, and no study has run `ivarpro`. Both rows ship `in-flight`, the
  route `vp-fit` and `bd` took: `vp-dependence` flips to `shipped` when a
  second study runs it through its stability section, `vp-individual` when two
  studies have run it.
- **The taxonomy row's description** ("rule-based variable screen: coverage,
  noise and stability checks") describes `vp-fit` only. Rewording it is an
  hvtiRutilities change and is left out (section 7).

## 3. `vp-dependence.qmd` (uvarpro)

Independent of `vp-fit`: it reads the dataset, not `vp.rds`, because
`uvarpro()` takes no outcome and no supervised fit.

Chunks, in order:

1. **`setup`**, the standard opening, with `varPro (>= 3.2.0)`,
   `ggRandomForests (>= 4.0.0)` and `igraph` attached and checked, and
   `options(rf.cores = 1L, mc.cores = 1L)`. `uvarpro()` passes `...` to
   `rfsrc()`, which reads `rf.cores`; `get.beta.entropy()` runs its release
   variables through `mclapply`, which reads `mc.cores`. Neither takes a
   `cores =` argument, so the options are the only lever.
2. **Study choices**, each marked `EDIT:`:
   - `VARIABLES`, the variables whose dependence is studied;
   - `OUTCOME`, optional columns entered as plain variables (`NULL`, the
     default, enters none). Chapter 11's question. The narration says a link
     to an outcome column is shared structure, not prediction;
   - `ORDINAL`, graded variables entered as numbers. Chapter 11's finding:
     left as factors, they are hot-encoded and the unsupervised forest finds
     structure almost only in the indicator columns;
   - `NOISE_N` (default 20), `REPEATS` (default 10, lower than `vp-fit`'s 20
     because each refit also runs the lasso step), `SUBSAMPLE` (0.632),
     `SEED`, `NTREE` (default 500; chapter 11 used 1000);
   - `THRESHOLD_FIXED` (0.25), the fixed edge cutoff the noise bar is
     reported beside and falls back to.
3. **Data.** Complete cases on `VARIABLES` and `OUTCOME`, with the count
   dropped stated. `uvarpro()` drops incomplete rows itself, as `varpro()`
   does, so the job drops them first and says so.
4. **Noise.** The same permuted copies as `vp-fit`, half drawn from
   categorical and half from continuous variables, named `noise<i>_<source>`.
   A permuted copy is independent of *every* other column, not only of an
   outcome, so in `uvarpro` it is a null for dependence itself. A variable
   named `noise…` is refused, as in `vp-fit`.
5. **Fit.** One cached `uvarpro(d, ntree = NTREE, seed = -abs(SEED))` after
   `set.seed(SEED)`, then `set.seed(SEED)` again and
   `get.beta.entropy(fit, pre.filter = FALSE, papply = lapply)`, cached with it.
   `pre.filter = FALSE` is required, not a preference: the pre-filter drops
   low-importance columns, which would drop the noise the bar is made from and
   any outcome column. The second seed is needed because the lasso
   cross-validation draws its folds from R's generator.
6. **The matrix.** `I` is padded to square over its row and column names and
   the links between levels of one factor are zeroed (a patient is only ever
   one level), as `gg_udependent()` does. Each processed term is mapped to its
   source column by `vpd_parent()`, the longest source name the term starts
   with.
7. **The noise bar.** `vpd_bar(I, noise)`: the largest entry of `I` in a row
   or a column whose source is a noise column. Section 3.1 has the rule.
8. **Graph and signal set.** `gg_udependent(fit, beta.mat = I, threshold =
   bar)`, plotted, with the signal set it names. Variables with no edge at
   the bar are not drawn; the narration says so.
9. **Heatmap.** Every variable against every other at any strength, ordered by
   hierarchical clustering on `pmax(I, t(I))`, outcome columns fenced off.
   Chapter 11's second view: it shows what the graph leaves out.
10. **Stability**, skipped when `REPEATS` is 0. `REPEATS` refits on
    subsamples of `SUBSAMPLE` drawn without replacement, each with a fresh
    noise draw, both seeded `SEED + r`, each cached on its own key. Each refit
    computes its own bar. A table of how often each edge clears its refit's
    bar and how often each variable is in the signal set, and the range of
    the bar across refits.
11. **Reading the result.** That an edge is statistical dependence in the
    data, not a causal arrow; that its direction reads "`j` helps separate
    `s`'s contrast"; that a variable missing from the graph has no link at the
    bar, which is not independence; and, when `OUTCOME` is set, where the
    outcome sits.
12. **Save** one handoff, `estimates/<subject>-<type>/dependence.rds`: a list
    of `fit`, `beta` (the zeroed square `I`), `bar`, `bar_from` (`"noise"` or
    `"fixed (fallback)"`), `edges`, `signal` and `stability` (`NULL` when
    `REPEATS` is 0), with the handoff lineage attached.

### 3.1 The dependence noise bar

**Rule.** An edge `s → j` is kept when `I[s, j]` is at least the bar, where
the bar is the largest entry `I[a, b]` with `a` or `b` a noise term, taken
over the off-diagonal entries after same-factor zeroing.

**Why both directions.** A noise row is the contrast formed by releasing noise:
any predictor that separates it does so by chance. A noise column is noise
used as a predictor: any weight it earns separating a real variable's
contrast is chance. Both are draws from the null the bar is meant to
describe, so both count.

**Why the fixed 0.25 stays in the report.** It is `sdependent()`'s and
`gg_udependent()`'s default and chapter 11's choice, so a reader comparing
with older work needs it. Like varPro's 0.79, it does not carry across
settings: the lasso coefficients scale with the data and with how many
variables share each contrast.

**No bar from noise that scored 0.** Carried from `vp-fit`: a bar is usable
only above 0. If every noise entry is 0 (the lasso selected no noise anywhere),
the bar falls back to `THRESHOLD_FIXED`, and the report and `bar_from` say so.
This differs from `vp-fit`, which selects nothing when no bar is usable,
because a dependence graph is a description rather than a selection, and an
empty graph would describe nothing.

**One bar, not one per kind.** `vp-fit` judges categorical and continuous
variables separately because continuous noise picks up split-point bias in a
supervised screen. Here, every factor is hot-encoded before the lasso, so
every predictor column the lasso sees is numeric, and the indicator columns
are judged on the same coefficient scale. The noise is still drawn half from
each kind, so both kinds of column contribute to the null. The stability
table, which reports the bar per refit, is where a second study can show
whether one bar is enough.

### 3.2 The outcome

When `OUTCOME` is set, its columns enter the noise source pool like any other
variable: a permuted outcome is as much a null as any other permuted column.
A survival outcome enters as the event (0/1) and the time, two columns, as
chapter 11's Experiment 1 did.

## 4. `vp-individual.qmd` (ivarpro)

Reads `vp-fit`'s `vp.rds` from its own set and never calls `varpro()`, the way
`vp-explain` does. When no `vp-fit` has run, it stops naming the file.

**Why not refit with `split.weight = FALSE`.** The varPro help example does,
so every predictor gets a gradient. A refit here would cost a fit, would be a
second varPro fit beside the screen with its own selection, and would break
the rule that `vp-fit` is the one varPro fit in a set. A variable with no
gradients is instead reported (below), and a study that wants gradients for
every variable sets `SPLIT_WEIGHT = FALSE` in `vp-fit`.

Chunks, in order:

1. **`setup`**, the standard opening, `options(rf.cores = 1L, mc.cores = 1L)`.
2. **Study choices**, each marked `EDIT:`:
   - `SHOW`, the variables to draw: `NULL`, the default, takes the screen's
     selected set;
   - `TARGET`, which target to draw when `ivarpro()` returns several (a
     multiclass forest, or multivariate regression). Ignored for one target;
   - `SCALE` (default `"local"`), passed to `ivarpro(scale =)`;
   - `SEED`, set before `ivarpro()` and part of its cache key.
3. **The screen.** `readRDS(set_path("estimates", "vp.rds"))`, its lineage
   checked as `vp-explain` checks it.
4. **Gradients.** One cached `ivarpro(fit, scale = SCALE, save.model = FALSE,
   path.store.membership = FALSE)`. `save.model = FALSE` because the fit is in
   `vp.rds` already; `path.store.membership = FALSE` because no figure here
   reads the rule memberships, and they are the large part of the object.
   `save.data` stays `TRUE`, which the plots need.
5. **Coverage, carried over.** A table, one row per processed predictor: the
   share of patients with no usable local estimate (`NA`), the median absolute
   gradient, and whether the screen tested and selected its source variable.
   A variable whose gradients are all `NA` was cut by split weights or never
   released; it is listed and not drawn, with the reason.
6. **The noise reference.** The fit carries `vp-fit`'s permuted noise columns,
   so `ivarpro()` returns gradients for them too, at no extra cost. The table
   gives the 95th percentile of the noise columns' absolute gradients beside
   each real variable's median. It is a reference, not a test: nothing is
   selected here.
7. **Beeswarm.** `gg_ivarpro()` over the shown variables plus the noise
   columns, noise drawn gray, so the spread a chance predictor reaches is
   visible beside each real one.
8. **Gradient against value**, one panel per shown variable, paged with
   `.page_child()` and cached per page as in `vp-explain`.
9. **Reading the result.** That a gradient is the local slope of the
   *prediction*, not of the outcome; that its sign says which way the
   prediction moves near that patient; that `NA` means no local estimate, not
   no effect; and that spread across patients is where an interaction would
   show, not proof of one.
10. **Save** `estimates/<subject>-<type>/individual.rds`: the `ivarpro`
    object and the coverage table, with the handoff lineage attached.

## 5. Testing

In the existing `tests/testthat/test-vp-templates.R`, run chunk by chunk from
the installed templates through `rf_run()`, with fixtures in `helper-vp.R`.

**`vp-dependence`:**

1. **The bar, on a hand-built matrix, no fit** (runs on CRAN): the bar is the
   largest noise entry in either a row or a column; every noise entry 0 gives
   the fixed threshold and `bar_from = "fixed (fallback)"`; links between two
   levels of one factor are zeroed before the bar is taken. Proven by
   mutation: drop the column direction, or the zeroing, and a test fails.
2. **`vpd_parent()`** maps `fsb` to `fs` and not to `f` when both `f` and
   `fs` are source names (longest match).
3. **A planted dependence is found.** A cohort where `c = a + noise` and `b`
   and `g1` are null: the edge between `a` and `c` clears the bar, and no
   noise column is in the signal set. `REPEATS = 2`, small `NTREE`.
4. **`pre.filter = FALSE` is in the source**, by a line check, since dropping
   it would silently drop the noise.
5. **The stability cache.** Raising `REPEATS` from 2 to 3 computes one refit.
6. **The handoff** carries `fit`, `beta`, `bar`, `bar_from`, `edges`, `signal`
   and `stability`.

**`vp-individual`:**

7. **It reads `vp.rds`** and no line calls `varpro(`; it stops naming the file
   when no `vp-fit` has run.
8. **A planted signal beats the noise reference:** on `vp_data()`, `xs`'s
   median absolute gradient exceeds the noise 95th percentile.
9. **A variable with all-`NA` gradients is listed, not drawn**, on a hand-built
   gradient table (no fit).

**Both:**

10. **No MRN** in `dependence.rds` or `individual.rds`, with `rf_mrn_data()`.
11. **One core:** both templates set `rf.cores` and `mc.cores` to 1 in `setup`.

Tests 3, 5, 6, 7, 8 and 10 fit and carry `skip_on_cran()`. The catalog-wide
tests cover the format block, `SUBJECT`/`TYPE`, the single `setup` chunk, no
study identifiers, `EDIT:` markers, floors, provenance and lineage, with no
new code.

**Gates outside `testthat`:** a `.lintr` **file** key per template; the two
ledger rows and the regenerated roadmap; catalog counts 68 → 70.

**CI cost.** `get.beta.entropy()` fits a cross-validated lasso per release
variable per rule, so the dependence tests use 6 variables, `NTREE = 30` and
`REPEATS = 2`, and must stay under about 30 s together on the Ubuntu leg;
the plan's first task measures it before the tests are written. Expected skip
counts under `NOT_CRAN=true` do not change.

**Not tested:** whether the dependence noise bar is a good cutoff. That is a
statistical claim with no evidence yet beyond its logic, and `in-flight`
records it.

## 6. What carries over from `vp-fit`, and what does not

| check | `vp-fit` | `vp-dependence` | `vp-individual` |
|---|---|---|---|
| coverage (untested is not unimportant) | z = 0 under `TRIM` | variables with no edge at the bar are listed as "no link at the bar" | all-`NA` gradients listed, not drawn |
| permuted noise | per-kind bar, selection | one bar for edges, fixed fallback | reference only, no selection |
| stability over subsamples | selection frequency | edge and signal frequency | none: it describes one fit |
| one core | `cores = 1L` and options | options only (no `cores` argument) | options only |
| seeds | `set.seed` + `seed = -abs()` | the same, plus a second `set.seed` before the lasso | `set.seed(SEED)` before `ivarpro()`, and in the cache key |

## 7. Out of scope

- **Removing varPro from `rf*-explain`.** Separate work, under way.
- **Rewording the `vp` taxonomy description** in hvtiRutilities to cover
  dependence and individual gradients. A one-line follow-up there.
- **`predict.ivarpro()` on new patients.** No study has asked for it.
- **A `gg_ivarpro()` or `gg_udependent()` change in ggRandomForests.** The
  templates use both as they are in 4.0.0; anything they lack is drawn in the
  template, and moves to ggRandomForests later if a second study wants it.
- **Chapter 11's two-experiment layout** (survival outcome, then a binary
  outcome). A study runs the job twice, as two sets, rather than the template
  carrying both.
