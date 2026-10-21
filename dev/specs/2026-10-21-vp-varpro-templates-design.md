# `vp` templates: design, 2026-10-21

**Status** Design, approved section by section on 2026-10-21. Not implemented.
**Adds** a `vp` prefix to the taxonomy and two templates, `vp-fit.qmd` and
`vp-explain.qmd`, both shipped with ledger status `in-flight`.
**Starts from** the Virtual Twins study (ST1267): notebook chapter 13, "varPro
Coverage", and report Appendix C, "Variable Screen Coverage Check", built
2026-10-14.

## 1. Why a prefix of its own

VarPro needs only the data and an outcome. It grows its own `rfsrc` forests,
and never reads a forest a `rf*-fit` job saved; `rfs-explain` already says so
in its narration. So varPro output is not random forest explainability, and it
does not belong to the `rf*` family.

It also has two uses:
- **a screen**, choosing the predictors a later model is fit on (Virtual Twins
  chapter 3 screened 101 candidates before the twin forests were grown); and
- **a stand-alone analysis**, asking which variables carry the outcome and how.

The closest existing jobs are `bh`/`bl`/`bc`, which select variables by
bootstrap and report the selection's stability. `vp` is the same kind of job
with a different selection rule.

**Why the coverage check is the point.** `varPro::importance()` scores a
variable by a winsorised mean of its per-tree importance, and a tree with no
usable release rule for the variable counts as zero. A variable tested in fewer
than about 10% of the trees therefore comes back with z exactly 0. That is
*untested*, not unimportant. In the Virtual Twins screen every z = 0 term sat in
at most 7% of trees, and every z > 0 term in at least 15%. A template that
draws varPro's fixed cutoff (0.79) and nothing else cannot tell the two apart.

## 2. Taxonomy, ledger and naming

- **Taxonomy row:** `vp | VarPro | analyses | rule-based variable screen:
  coverage, noise and stability checks`. `hvti_taxonomy()` lives in
  **hvtiRutilities** (`R/taxonomy.R`); this package only re-exports it. The
  row goes there, growing its `main` from 47 rows to 48. `vp` is in neither
  `hvti_taxonomy()` nor `hvti_non_prefixes()`, and the 2026-09-02 census
  holds no `vp` jobs.
- **Cross-repo order**, the route `rfr`, `sid` and `vt` took through
  hvtiRutilities PR #127. This repo's `test-roadmap.R` fails in one direction
  if the taxonomy names a prefix the ledger lacks, and in the other if a
  non-`intake` ledger row names a prefix the taxonomy lacks. So:
  1. here, the two ledger rows land at status `intake`, blocked on the
     taxonomy row;
  2. in hvtiRutilities, the taxonomy row lands on `main` (CI here installs
     hvtiRutilities from `main`, since `Remotes` are unpinned);
  3. here, the templates land and both rows move to `in-flight`.
- **Files:** `inst/templates/30_analyses/vp-fit.qmd` and
  `inst/templates/30_analyses/vp-explain.qmd`. The pair mirrors
  `rfs-fit`/`rfs-explain`, and `template_list()` shows them as `vp.fit` and
  `vp.explain`.
- **The prefix is wholly qualified.** `add_job("vp", ...)` with no qualifier
  errors and lists both, as `template_path()` does for every qualified prefix.
- **Ledger rows** `(vp, fit)` and `(vp, explain)`, both `in-flight`.
- **The two-study gate.** Other studies run varPro, so the basic fit has more
  than one exemplar. Virtual Twins is the only study to have reached the
  coverage, noise and stability stage. `in-flight` records that; both rows
  flip to `shipped` once a second study runs `vp-fit` through to its
  stability section. This is the route `bd` took in 1.2.4.
- **One outcome-agnostic template, not three.** `varpro()` infers survival,
  classification or regression from its formula, so `vp-surv`, `vp-class` and
  `vp-regr` would be three copies of one job. `vp-explain` carries the one
  family-specific choice (section 5).

## 3. `vp-fit.qmd`

Chunks, in order:

1. **`setup`**, the standard opening: `SUBJECT`, `TYPE`, `.in`, `library()`
   calls with version floors for `varPro (>= 3.2.0)`, `randomForestSRC` and
   `ggRandomForests` (the floor that exports `varpro_coverage()`), then
   `hvtiRtemplates:::.job_setup()`.
2. **Study choices**, each marked `EDIT:`:
   - the outcome and the candidate predictors;
   - `NOISE_N` (default 20), the number of noise columns;
   - `REPEATS` (default 20), the stability refits, where `0` skips the
     stability section, and `SUBSAMPLE` (default 0.632), the share of
     patients each refit draws;
   - `SEED`, part of every cache key and handed to `varpro()` as
     `seed = -abs(SEED)`, with `set.seed()` before each random call. Both are
     needed: `varpro()` draws on R's generator even with `seed =`, which made
     the Virtual Twins screen irreproducible until 2026-10-07;
   - `TRIM` (default 0.1), below which a variable counts as untested;
   - the varPro settings `ntree`, `nvar` and `split.weight`, with a comment
     that guided split weights cut variables before any rule is built (104 of
     154 terms in the Virtual Twins screen).
3. **Data.** Complete cases on the outcome and candidates, with the count
   dropped stated in the report. `varpro()` drops a patient with any missing
   value, so the template drops them first and says so, rather than letting
   the fit describe fewer patients than the report claims.
4. **Noise.** Each noise column is a permuted copy of a real candidate, so it
   keeps that candidate's marginal distribution and loses any link to the
   outcome. This is Virtual Twins' `coverage_add_noise()`, with one change:
   the sources are drawn **half from categorical and half from continuous**
   candidates, as far as each kind allows, so both kinds always have noise to
   be judged against. Kind uses `varpro_coverage()`'s rule: a factor,
   character or logical column, or a numeric one with at most 5 distinct
   values, is categorical. Noise columns are named `noise<i>_<source>`.
5. **Fit.** One cached `varpro()` on the real candidates plus the noise.
6. **Coverage.** `ggRandomForests::varpro_coverage(fit, by = "variable",
   trim = TRIM, noise = "^noise")`, then:
   - a coverage table: eligible, trees tested in, coverage, z, tested,
     selected, and the bar each variable was judged against;
   - the funnel from Appendix C: candidates, eligible, tested, selected.
7. **Figure.** z against coverage for every eligible variable, faceted by kind.
   Noise is gray, the noise bar for each kind is dashed and the `TRIM` line is
   vertical. This is the chapter 13 figure. The `gg_varpro()` panel follows,
   still showing the 0.79 cutoff for reference, with a caption saying it is
   not the selection rule here.
8. **Stability**, skipped when `REPEATS` is 0. `REPEATS` refits, each on a
   subsample of `SUBSAMPLE` (default 0.632) of the patients drawn without
   replacement and with a fresh noise draw, both seeded `SEED + r`, and each
   cached on its own key. This is chapter 13's loop: redrawing the noise alone
   would hold the patients fixed and understate how much the selection moves.
   Then a table of how often each real variable was selected and tested, and
   the range of the number selected per repeat.
9. **Reading the result.** Appendix C's prose made general: what eligible,
   tested, untested and selected mean; that z = 0 is untested and never
   evidence of no effect; and that this is a *screen*, not a selection. It
   keeps everything it could not rule out. A selection would also need the
   unguided screen, a tuned bar and the stability check to agree.
10. **Save** one handoff, `estimates/<subject>-<type>/vp.rds`: a list of
    `fit` (the varPro fit), `coverage` (the judged coverage table) and
    `selected` (a character vector of the selected variables, which a later
    model job reads when `vp` is used as a screen), with the handoff lineage
    attached. One file rather than three, because the package's handoff
    reader validates the lineage of one object, and three files could drift
    apart, leaving a stale coverage table beside a new fit.

### The selection rule, and the categorical fallback

A real variable is **selected** when it is tested and its z beats every
*tested* noise column of its kind. The fixed 0.79 cutoff does not carry across
settings, because z shrinks as more variables share each tree.

**The categorical fallback.** In Virtual Twins, categorical noise was rarely
tested and almost always scored z = 0 when it was. Across 40 repeats, none was
tested in 20 and all scored zero in 18. A categorical bar of 0 lets any tested
categorical variable through. So:

> When no categorical noise is tested, or every tested categorical noise
> column scores z = 0, categorical variables are judged against the
> **continuous** bar.

The coverage table names the bar each variable was judged against. The
continuous bar is the stricter one, because continuous noise picks up
split-point bias (up to 0.188 in Virtual Twins' setting F). The rule therefore
errs toward missing a real categorical effect rather than admitting a false
one, which is the right direction for a screen. `varpro_coverage()` already
falls back to the overall bar when a kind has *no tested* noise; the case it
does not cover is tested categorical noise that all scores 0. The template
therefore judges the coverage table itself, in a small `vp_judge()` defined in
a chunk of its own, so the rule can be tested on a hand-built table without a
fit.

**No bar from noise that scored 0.** A bar is usable only above 0. A
categorical kind with no usable bar borrows the continuous bar; a continuous
kind never borrows, because the overall bar may itself come from categorical
noise at 0. A kind left with no usable bar has nothing selected, and the table
says "no usable noise bar". (Found in review of the plan, 2026-10-21: borrowing
the overall bar selected a categorical candidate at z = 0.05.)

**One core.** `options(rf.cores = 1L)` limits randomForestSRC's threads, not
varPro's own workers, which read `cores =` or `mc.cores`. Both templates set
`options(rf.cores = 1L, mc.cores = 1L)`, and every `varpro()` call passes
`cores = 1L`.

## 4. The handoff

`vp-explain` reads the `vp.rds` that `vp-fit` saved, the way `rfs-explain`
reads `rfs.rds`, and never calls `varpro()`. It stops with a message naming the
missing file when no `vp-fit` has run in its set.

## 5. `vp-explain.qmd`

- **Which variables get partials.** The saved selected set by default. An
  `EDIT:` line can name a list instead. An untested variable is never drawn,
  because its partial rests on almost no rules; the report lists any it left
  out and why.
- **Survival choices.** `SCALE` (default `"surv"`) and `HORIZON`, both
  `EDIT:`, passed to `gg_partial_varpro(scale = SCALE, time = HORIZON)`. A
  horizon past the largest follow-up time is an error, not a flat curve. That
  is the Virtual Twins units bug (2026-06-22: horizons in days on a fit in
  years, giving seven identical curves) caught at the source. `HORIZON` is
  ignored for a classification or regression fit.
- **Pages.** The partials are paged with `.page_child()`, as `rf*-explain`'s
  `dependence-varpro` chunk does, and each page is cached.

## 6. Testing

A new `tests/testthat/test-vp-templates.R` runs the templates chunk by chunk,
parsed out of the **installed** templates by label, as `helper-rf.R` does, in
the throwaway `rf_study()` fixture. `rf_run()` is generalised or a `vp_run()`
added beside it.

1. **A planted signal decides the selection.** A synthetic cohort of about 200
   rows with one strong continuous predictor, one strong two-level factor and
   null distractors: the strong pair is selected and no noise column is.
   `REPEATS = 2`, small `ntree`.
2. **The categorical fallback, proven by mutation.** `vp_judge()` on a
   hand-built coverage table where every tested categorical noise row scores
   0 and a null factor is tested above 0: the factor is not selected and the
   table names the continuous bar. No fit, so this test runs on CRAN too.
   Revert the fallback and confirm the test fails.
3. **The handoff.** `vp-fit` writes `vp.rds`; `vp-explain` reads it with no
   `varpro(` call in its source, and stops naming the file when no fit has
   run.
4. **`HORIZON` past the largest follow-up time errors** for a survival fit.
5. **The stability cache.** Moving `REPEATS` from 2 to 3 computes one new fit
   and reuses two.
6. **No MRN in any saved file**, with the existing `rf_mrn_data()` scan.

The catalog-wide tests cover format block, `SUBJECT`/`TYPE` lines, the single
`setup` chunk, no study identifiers, `EDIT:` markers, package floors,
provenance and lineage for both files with no new code.

**Gates outside `testthat`:** a `.lintr` **file** key for each template; the
two ledger rows, with the roadmap tables regenerated by
`python3 dev/specs/artifacts/roadmap_render.py` and `test-template-catalog.R`'s
counts moved from 66 rows and 44 prefixes to 68 and 45. The job flow diagrams
need no change: their prefix map is a frozen 2026-08-22 corpus snapshot, which
`sid` and `vt` were never added to either.

**CI cost.** Tests 1, 3, 5 and the MRN scan fit varPro, so they carry
`skip_on_cran()`. That is about six small fits at `ntree = 50`, a few seconds
each. Under `NOT_CRAN=true`, as CI runs, the expected `SKIP 0` on macOS and
Ubuntu and `SKIP 3` on Windows do not change. A CRAN-mode check skips about
four more tests than today, by design.

**Not tested:** whether the noise bar is a good rule. That is a statistical
claim, Virtual Twins chapter 13 is its evidence, and `in-flight` records that a
second study has yet to confirm it.

## 7. Out of scope

- **`rf*-explain` keeps its varPro panel and varPro partial.** Each gains a
  one-line pointer to `vp-fit`/`vp-explain`. Removing them is a separate pull
  request once `vp` ships, so that studies part-way through an analysis are
  not surprised.
- **Chapter 13's A/B/D/F settings comparison.** It was Virtual Twins'
  experiment on its own screen, not a general step.
- **Moving the noise and stability helpers into ggRandomForests** beside
  `varpro_coverage()`. That is their natural home later. It is a change to a
  CRAN-target package whose v4 is held for review, and it need not block this.
