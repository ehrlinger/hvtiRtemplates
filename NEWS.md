# hvtiRtemplates 1.0.16

## Guards

* Retired the two tests asserting that within-folder ordinal minors follow
  `hvti_taxonomy()` row order. They enforced the derivation #56 removed: an
  ordinal is a key, assigned once and recorded in the ledger, never recomputed
  from a position. #56 established that rule in `AGENTS.md`, the ledger and
  `check-roadmap-counts.py`, but left the test suite asserting the opposite —
  two guards on one repository disagreeing, which is the drift the guards exist
  to prevent. Measured before removal: reordering two **templated** prefixes
  within a folder turned CI red, while inserting or reordering an untemplated
  one was always safe.

* Replaced them with a **key** check rather than another position check:
  `check-roadmap-counts.py` validates every ordinal's major against a
  **hardcoded** `FOLDER_ORDINAL` map, whose authority is `hvti_taxonomy()`'s
  folder order — a table that lives in `hvtiRutilities`, a different
  repository. `test-roadmap.R` now asserts the map still matches. That closes
  the same class of failure one level up from the one #56 fixed. The Python
  guard cannot check its own map: reading the taxonomy needs R, which is why
  the guards are split by language.

## `graphs/06.02-hs.qmd`

* Now calls `hvtiRlifetables::us_cohort_curve()` instead of deriving the cohort
  expected-survival curve inline. The template shipped that derivation
  deliberately, as the specification for
  [hvtiRlifetables#16](https://github.com/ehrlinger/hvtiRlifetables/issues/16),
  with a comment promising that when the function landed "this chunk becomes one
  call and the result must not change". It landed in `hvtiRlifetables` 0.1.3;
  the numbers were checked to 1e-12 against the derivation before the swap.

  The function is not merely a convenience. Its averaging follows `%usmatchd`
  (lines 338-350) — the unweighted cohort mean, over survival rather than
  cumulative hazard, no patient weighted by follow-up — and it deliberately does
  **not** drop `NA`, where the inline version used `na.rm = TRUE` and would have
  hidden one.

* Added an `EDIT:` marker for `us_cohort_curve()`'s `by =`, covering
  [hvtiRlifetables#17](https://github.com/ehrlinger/hvtiRlifetables/issues/17).
  Grouping is not stratification: `table =` chooses which strata the life *table*
  is built from, `by` chooses how the resulting curves are grouped for reporting.

* `HORIZONS` must now be sorted and distinct, checked where it is declared.
  `us_matched()` enforces sortedness too, but three chunks later and about its
  own `times` argument rather than the value the author edited — and the
  expected-survival join pairs `us_cohort_curve()`'s output, ordered by first
  appearance, with `split()`'s, ordered numerically. They agree only while
  `HORIZONS` is sorted.


# hvtiRtemplates 1.0.15

* **The bootstrap screen template is now `analyses/04.05-bh.qmd`**, renamed from
  `04.06-bh.qmd`. The ordinal had been derived from the prefix's row position in
  `hvti_taxonomy()`, and that derivation had already failed: `bh` was 6th in
  `analyses` when the number was assigned, `hvtiRutilities` then moved `hs` out
  to `graphs`, and every prefix below it shifted up one while the filename
  stayed put. The identity was positional across a repository boundary, so a
  correctness fix in the upstream vocabulary silently invalidated a downstream
  filename, and nothing caught it: the ordinal checks verify format,
  folder-major and uniqueness, never position.

  ⚠️ **A job already scaffolded from 1.0.13 or 1.0.14 is unaffected.**
  `new_job()` bakes the ordinal into the job filename at copy time, so existing
  jobs keep theirs and do not need renaming. Only newly scaffolded `bh` jobs
  take `04.05`.

* **An ordinal is now a key, assigned once, and never recomputed from row
  order.** `NN` is the taxonomy folder's position, which is stable; `MM` is
  assigned from the next free minor in that folder and recorded in the roadmap
  ledger. Row order may drift; ordinals may not. Stated in `AGENTS.md`, so the
  next template is not numbered by counting rows.

* **`04.06` is retired, not freed.** It shipped in two releases, so a study that
  scaffolded `bh` from either carries it in a filename. It is recorded under
  `retired_ordinals` in the ledger, and `check-roadmap-counts.py` now fails any
  row that claims a retired ordinal, naming when and from what it was retired.

# hvtiRtemplates 1.0.14

* **`analyses/04.06-bh.qmd` gains the data-driven half of the SAS `%cluster`
  contribution.** `boot_clusters()` counts replicates retaining any member of a
  list you declare and computes no correlation at all, so the section's claim to
  group "by DATA" described the SAS macro rather than the R helper. A
  `pool_collinear_pairs()` chunk now makes it true. The two are kept apart
  deliberately: a declaration says a clinician treats several variables as one
  thing, a correlation says the pool cannot tell them apart, and only the second
  is a property of the data.

  This is why the template now reads the built dataset. The one failure that
  introduces is guarded: a build that moved since the screen ran would leave the
  correlations describing one dataset and every frequency above describing
  another. `n_rows` catches it, as a warning rather than a stop, because only
  this table goes stale.

* **Concept-level union frequencies.** A per-form row cannot answer "how often
  was this *concept* selected", which is the figure a paper quotes. Nothing is
  collapsed — every form keeps its own row — but each concept now also carries
  `union_pct`, `best_form_pct` and the `spread` between them, which is how much
  the per-form table understates it.

  Computed from the replicate table, never from the summary: a union across a
  concept's forms cannot be recovered from marginal percentages. Two forms at
  30% each are anywhere between 30% and 60% of replicates depending on how often
  the same replicate took both, and the summary does not record that.

# hvtiRtemplates 1.0.13

<sub>Superseded 2026-08-31: this template is `analyses/04.05-bh.qmd` from 1.0.15
onward. The sentences below are left as they shipped. A job scaffolded from this
release keeps `04.06-bh` in its filename and needs no rename.</sub>

* Added `analyses/04.06-bh.qmd`, the bootstrap variable-selection screen that
  replaces a SAS `%hazboot` / `%sumboot` / `%cluster` chain
  ([#8](https://github.com/ehrlinger/hvtiRtemplates/issues/8)). Scaffold it with
  `new_job("bh", <endpoint>, <type>)`. Requires `hvtiRbootstrap` >= 0.1.1 and
  `hvtiRutilities` >= 1.1.6. Design in
  `dev/specs/2026-08-28-bh-template-design.md`.

  The template is the **report**, not the runner. `hzr_bootstrap()` writes
  nothing until its final replicate and a full screen is days of compute, so
  the run is chunked from a companion script and this file pools what that
  script wrote. That file boundary is a durability boundary, not tidiness, and
  the runner stays untemplated until `new_job()` grows multi-file templates.

  It carries four traps that are silent rather than loud when they go wrong:
  competing transformations must be screened and grouped only at read time,
  never pruned beforehand; a screen that selected nothing is a failed screen
  rather than a null result, and now stops the render; `EXPECT_CHUNKS` and
  `EXPECT_BOOT` state what was *launched*, so a partial pool is flagged as
  provisional instead of quietly reporting over the wrong denominator; and the
  summed elapsed time is CPU cost, not wall clock. `bh` and `hm` are parallel
  analyses, not a pipeline, so the template deliberately writes no handoff file.

* Added `tests/testthat/test-bh-helpers.R`, covering `boot_clusters()` and
  `boot_shortfall()` against synthetic input. Both are first called from this
  template, and a render cannot stand behind them: it stops before reaching
  either whenever no bootstrap output exists, which is every CI run.

* Declared `hvtiRbootstrap` in `Suggests` and `Remotes`. The templates' study
  dependencies stay out of `DESCRIPTION` deliberately, but the test above calls
  the package directly, and `R CMD check` resolves what tests reference — left
  undeclared it reports an unstated dependency.

# hvtiRtemplates 1.0.12

* Added `graphs/06.02-hs.qmd`, the patient-level prediction template. It reads
  the model an `hm` job fitted, predicts survival per patient at the horizons a
  study reports, and sets those against age/sex/race-matched population survival
  from `hvtiRlifetables`. Its `vintage` marker has no default on purpose: the
  SAS macro it replaces inherited a default that moved twice with no signal, and
  a job that does not state its vintage cannot be reproduced. Design in
  `dev/specs/2026-08-29-hs-template-design.md`.

# hvtiRtemplates 1.0.11

* Added the template conversion roadmap: a ledger of all 42 taxonomy prefixes
  plus three proposed ones, the roadmap document generated from it, and two CI
  guards that fail when the two disagree or when a row claims a template that
  is not on disk. Design and reasoning in
  `dev/specs/2026-08-29-template-conversion-roadmap-design.md`.

# hvtiRtemplates 1.0.10

## Documentation

- **The institutional SAS licence runs into 2027, not out in 2026.** The wrong date
  `2026-09-29` was stated in eleven places: the package `README.md`, the 1.0.0
  provenance note below, and nine statements across the design and artifact records
  in `dev/specs/`. `README.md` is corrected outright, because it states a present
  fact to a reader. Everything else is a historical record, so the original sentence
  is left standing with a dated correction beside it, following the convention this
  repository already uses for a superseded claim.
- **`2027-09-29` is a working date, not a confirmed one.** Every note states it the
  same way and defers to one canonical note, so confirming the real date is a single
  edit rather than another eleven. What is settled is the year, not the day. Writing
  an unconfirmed date as flatly as the wrong one was written is the mistake this
  entry exists to correct.
- Two of those statements used the date as a **deadline**, and they came out
  differently. The "forcing function" in the AVR/LV-function parity design keeps its
  argument: fresh SAS execution genuinely needs a live licence, so the pressure is
  real and simply further out than stated. The macro-allocation design's claim that
  the licence "bounds the window" for re-running the corpus scan is **withdrawn, not
  re-dated.** That scan reads `.sas` files as text and never invokes SAS. What
  threatens it is loss of the sources, which are unversioned or unreplicated, and
  the mitigation is a remote rather than a deadline.
- What the licence date does not bound, in either case, is reading: compiled SAS data
  stays readable well beyond expiry, so what ends is the ability to *run* SAS, not to
  read what it produced.

# hvtiRtemplates 1.0.9

## Documentation

- **Development records moved to `dev/specs/`,** adopting the portfolio
  convention settled in `ehrlinger/house-style`. The stray top-level `plans/`
  is gone with it: this repo carried `plans/` *and* `specs/` *and* a
  `specs/plans/` convention that said plans belonged in neither, which is the
  drift the new rule exists to stop. All three plans now sit beside the designs
  they implement, under a shared slug.
- **`spec-counts.yaml` moved in the same commit.** Its two path filters and two
  `run:` paths point at `dev/specs/`, and a comment at the top of the file says
  why they cannot be left behind — a stale path filter does not fail the check,
  it stops the job from starting, and the PR goes green having verified nothing.
- `specs/artifacts/` became `dev/specs/artifacts/`, staying nested inside the
  prose directory because `check-spec-counts.py` resolves its target through
  `os.pardir`. Both checks were run at the new location and pass unchanged.
- `inst/templates/README.md` is the one shipped file affected, which is what
  makes this a patch bump rather than a governance-only change.

# hvtiRtemplates 1.0.8

## New features

- **`analyses/04.01-hm.qmd`** — the multivariable hazard model, replacing a SAS
  `PROC HAZARD` job with a `selection` statement (#8). Scaffold with
  `new_job("hm", <endpoint>, <type>)`. Design:
  `dev/specs/2026-08-27-hm-template-design.md`. **Requires hvtiRutilities >=
  1.1.4**, which ships the candidate-pool helpers it calls.

  Unlike `hz` and `hp`, `hm` had only **one** R exemplar, so its second was a
  SAS job (`.../dm_nodm/analyses/hm.dead.sas`). That is enough for the gate's
  purpose — it exists to stop one study's choices being encoded as general, and
  a SAS job states those choices as plainly as an R one does. It earned its
  place immediately: it carries a **`%deciles` calibration** step the R
  exemplar has no equivalent for, and `TemporalHazard` already exports
  `hzr_deciles()` for it. Without the second exemplar the template would have
  shipped a model-selection job that never asks whether the model calibrates,
  and nothing in its output would have looked missing.

  ⚠️ **Two traps specific to this job, both silent:**

  - `hzr_stepwise()`'s defaults are **not** SAS's — `slentry = 0.3` /
    `slstay = 0.2` against a typical `sle = 0.1` / `sls = 0.07`. Accepting the
    R defaults runs a different screen from the job being reproduced, admits
    more variables, and does not error. The template sets them from the `.sas`.
  - The default `criterion = "score"` has a known defect
    (temporal_hazard#130): it declines the strongest candidates, because the
    observed information goes indefinite at `beta = 0`.

  Covariates are **read out of the SAS job** with `sas_variable_block()` rather
  than transcribed, taking only names — a `name=value` block carries the other
  study's converged answers. `covariate_audit()` then stops the render rather
  than fitting a model whose covariates are not what the job specifies, and
  `pool_collinear_pairs()` reports exact complements like `male`/`female`.

  The fit is **two stages**, mirroring what the SAS job does: shapes held at
  the `hz` fit while covariates are screened, then freed. Fitting both together
  from a neutral start lands in the wrong basin and reports `converged = TRUE`
  while doing it. Which stage is reported is an `EDIT:` decision with the
  evidence table beside it.

  The calibration chunk uses `print(dec)`, **not** `knitr::kable(dec)`: the
  print method carries the overall chi-square, its degrees of freedom and its
  p value — the one number that answers "does this model calibrate" — and
  `kable()` renders only the per-group frame, dropping it silently.

## Bug fixes

- **`dev/specs/2026-08-21-template-set-layout-design.md` §5 corrected.** It said
  the ordinal minor is "the next free position within it"; the rule that
  actually reproduces every shipped ordinal is the prefix's **position among
  its folder's taxonomy rows**. The two agree for everything templated so far
  and diverge on the third `analyses` template, where next-free would put `bh`
  before `hs` and fail the within-folder ordering test in `test-taxonomy.R` —
  a failure whose only fix is renumbering a shipped template, which §5
  promises never happens.

- `DESCRIPTION` now requires `hvtiRutilities (>= 1.1.4)`. The old `>= 1.1.1`
  was correct until this release -- `hz` and `hp` call nothing newer -- so the
  bound went stale as a side effect of adding a template rather than as an
  error in its own right. An install satisfying the old bound would have
  shipped a template whose helpers do not exist, failing at **render** time in
  a study rather than at install time.

- The `selection-monotone` chunk handles a **zero-step** screen. A screen that
  admitted nothing is a real outcome -- no candidate cleared the entry level --
  but `which.max()` on an empty vector is `integer(0)` and the report frame
  then failed with "arguments imply differing number of rows": an error about
  the report, in a job whose actual finding is that nothing entered.

- Convergence failure names the stage and what to check, instead of
  `stopifnot()`'s "isTRUE(stage1$fit$converged) is not TRUE" -- a message that
  tells a reader of the rendered report nothing they can act on.

## Internal

- `.lintr` gains a file entry for the new template, per the note in that file
  that a directory key would silently disable every linter on the path.

- New test: the `hvtiRutilities` helpers the templates call must appear in a
  declared list. It cannot check the version bound directly (CI installs the
  latest, not the declared minimum), but it makes the **trigger** loud -- a
  template that starts calling a new helper fails the test, and whoever adds it
  is standing in the right place to ask whether `DESCRIPTION` needs bumping.
  The scan reads code chunks only: a test that fires on prose is a test that
  gets deleted.

- The `03.01-ac` template's local `imputed_levels()` is removed in favour of
  the `hvtiRutilities` export. The two were identical, and the duplicate
  arrived only because hvtiRutilities#47 lifted the same function out of the
  same study.
# hvtiRtemplates 1.0.7

## New features

- **`graphs/06.01-hp.qmd`** — the nomogram and hazard figures, replacing a SAS
  `HAZPRED` job and the figure jobs over it (#8). Scaffold with
  `new_job("hp", <endpoint>, <type>)`. Design:
  `dev/specs/2026-08-27-hp-template-design.md`.

  `hp` **reads** its inputs rather than recomputing them — the `ac` life table
  and the `hz` fit, both by set. A job that recomputes its upstream can
  silently disagree with it.

  ⚠️ **Two settings are silently wrong if omitted**, both decoded from the
  `HAZPRED` source during parity work:

  - **`CLEVEL` defaults to `0.68268948`** — one standard deviation, **not**
    95%. It is exactly `pnorm(1) - pnorm(-1)`. `%kaplan` uses the same
    convention (`T_ALPHA = 1`), so the `ac` life table's limits are also a ~68%
    band. That collides in `hp` specifically, because `hp` is where both bands
    are drawn on one figure: internally consistent, and misread by anyone
    taking either for 95%. On the same fit and grid the 95% band measures
    **1.97× the width** of the SAS default. The template labels the coverage in
    the caption.
  - **Survival limits are formed on the `logit` scale.** `predict.hazard()`
    defaults to `"log-log"`, so `conf.type = "logit"` must be passed
    explicitly. Omitting it does not error — it shifts every limit.

  Two grids, not one, and **two independent horizons**: a sparse irregular
  **reporting** grid for the nomogram table, and a dense **log-spaced**
  plotting grid for the curves. Tabulating to 10 years while plotting to 3 is a
  normal thing to want, and SAS sets its plotting maximum as its own literal —
  so `t_max` is its own value rather than derived from the reporting grid.
  `followup-gate` checks both. A linear grid
  to the last event time under-resolves the early phase, which is where the
  action is. A wrong grid does not error; it produces a plausible nomogram.

  `followup-gate` warns when either horizon runs past the end of follow-up — a
  parametric model returns a number at any horizon asked of it, and nothing
  else marks that as extrapolation. The bound is computed over the **rows the
  fit used**, because `hz` drops rows missing either time or event and a
  max() over everything would overstate follow-up, making the guard under-warn.

  `fig-phases` asserts the components sum to `total`, since otherwise it is not
  a decomposition, and derives the component list from what `predict()` returns
  rather than naming early/late — so a three-phase model needs no edit.

## Internal

- `.lintr` gains a file entry for the new template, per the note in that file
  that a directory key would silently disable every linter on the path.

# hvtiRtemplates 1.0.6

## New features

- **`distributions/03.02-hz.qmd`** — the multiphase parametric hazard fit,
  replacing a SAS `PROC HAZARD` job (#8). Scaffold it with
  `new_job("hz", <endpoint>, <type>)`. Design:
  `dev/specs/2026-08-27-hz-template-design.md`.

  Extracted from **three** R exemplars — `preserve_root`,
  `maze/atricure/gender` and `lv_function/survival` — chosen because they
  disagree. Two seed `theta` from SAS's converged estimates so that any
  disagreement is about the likelihood rather than about where the search
  began; the third seeds neutral shapes with the time scale taken from the
  data, because it has no SAS predecessor to seed from. Both are correct for
  their own case, so the `start` chunk carries both as Shape A / Shape B, the
  way the `ac` template's `cohort` chunk already does. From either exemplar
  alone the template would have made the other case silently wrong.

  Three checks are carried from a single exemplar each, because in every case
  their absence is silent rather than loud: `numderiv-gate` (without `numDeriv`
  an interval-censored fit produces **no standard errors and does not say so**
  — `converged` is `TRUE` and `vcov()` is simply absent); `response-check`
  (mis-building the response still converges, on a number that is merely
  wrong); and `conservation-binding` (reporting `Σ Λ(tᵢ)` under both `conserve`
  settings is the only way to tell "the control did nothing" from "the control
  had almost nothing to do" — identical in the likelihood column, opposite in
  meaning).

  Parity is deliberately **not** in the template: a parity job borrows the
  ordinal of the job it checks and lives in `parity/`.

  The response formula is built **once**, in the `response` chunk, and reused
  by all three `hazard()` calls, so the Shape A / Shape B choice is made in one
  place rather than in three literal formulas an author could edit
  inconsistently.

## Internal

- `.lintr` gains a file entry for the new template, per the note already in
  that file that a directory key would silently disable every linter on the
  path. Indentation and brace linting stay **on** for it, and the six lints the
  first draft produced were fixed rather than exempted.

# hvtiRtemplates 1.0.5

## Bug fixes

- **An unedited job no longer renders green** (#27). Templates now carry an
  `edit-guard` chunk that scans the rendering file for unresolved `EDIT:`
  markers and stops, naming each one. `inst/templates/README.md` has always
  said that a job still containing a marker has not been finished; nothing
  checked it, and the `03.01-ac` template made the gap concrete — its `derive`
  chunk indexed a placeholder column, and an absent column makes
  `!is.na(d$<col>)` `logical(0)`, so every assignment is a **silent no-op**.
  Every patient stayed in one category, the downstream life tables ran over a
  single dummy stratum, and the render completed with 12 markers still in the
  file.
- `derive_cats()` and the `DERIVED` map now assert that the columns they name
  are in the data. This is the half a marker scan cannot reach: a placeholder
  replaced with a mistyped or renamed column leaves no marker behind.

## New features

- `HVTI_TEMPLATE_DRAFT=1` renders a partly-worked job anyway. The guard warns
  instead of stopping and the report carries a DRAFT banner listing the
  unresolved markers. It is an environment variable rather than a YAML
  parameter on purpose: a parameter lives in the file, so it would be
  committed and forgotten, re-opening the hole this closes. `1`, `true` and
  `yes` enable it; any other value, `0` included, leaves the guard strict, so
  a variable set to `0` meaning "off" cannot switch it off by being non-empty.

## Internal

- Two tests over the shipped template sources: every template must carry an
  `edit-guard` chunk, and no template may write the marker token as a string
  literal. The second guards a trap worth naming — Quarto knits through an
  intermediate and `knitr::current_input()` returns *that* file, so the scan
  reads the guard's own chunk. A literal `grep("<token>", src)` matches its own
  source line and fires on every render, finished or not; a probe found three
  markers in a file containing two. The token is built with `paste0()` instead.

# hvtiRtemplates 1.0.4

## Internal

- `hvti_taxonomy()` and `hvti_non_prefixes()` now live in `hvtiRutilities`
  and are re-exported from here. Callers are unaffected — both are still
  available unqualified from `hvtiRtemplates`. The table is shared
  vocabulary rather than template machinery, and `hvtiRutilities` is the
  lower layer, so the dependency now points that way.
- Added `tests/testthat/test-reexports.R`, which checks `getNamespaceExports()`
  directly, so a dropped `@export` on a re-export is caught by the suite
  instead of passing silently.

# hvtiRtemplates 1.0.3

## Breaking changes

- `new_job()` now takes `endpoint` and `type` in place of `basename`, and `dir`
  defaults to the study root rather than `"qmd"`. It writes
  `<folder>/<endpoint>-<type>-<NN.MM>-<prefix>.qmd` — into the taxonomy folder
  the template belongs to, not a flat `qmd/`. The `type` is required because a
  set is keyed on `(endpoint, analysis type)`: one endpoint is analysed by
  several methods and those chains share their upstream, so keyed on the
  endpoint alone two sets would write to one filename.
- `template_path()`'s argument is renamed from `name` to `prefix`, which is what it
  always matched on.
- `template_list()` gains an `ordinal` column, and reports `folder` from the
  directory a template sits in rather than by looking its prefix up in
  `hvti_taxonomy()`.

## Improvements

- Templates are named `<NN.MM>-<prefix>.qmd` and live in the taxonomy folder
  they scaffold into. The name is parsed by pattern rather than by splitting on
  dots, which the old `.prefix_of()` heuristic could not do once the ordinal
  contained one.
- The `ac` template declares its set with `ENDPOINT` and `TYPE` markers and
  resolves artifact paths from them, so a scaffolded job needs no output path
  edited by hand. `new_job()` now substitutes the caller's `endpoint`/`type`
  into those declarations after copying the template, so a scaffolded job's
  body agrees with its own filename instead of still naming the template's
  placeholder set. The template itself checks this at render time — comparing
  its `ENDPOINT`/`TYPE` declarations against `knitr::current_input()` — and
  errors if they disagree, because a mismatch resolves `set_path()` into
  another set's artifact directory silently. The check is a no-op outside a
  knitr render, so editing the file interactively in RStudio is unaffected.
- `new_job()` validates `endpoint` and `type`: each must be a single non-`NA`
  string matching `^[A-Za-z0-9_]+$`, since `-` is the filename's field
  separator and `.` is reserved to the ordinal. This also rejects a leading
  `../` that would otherwise escape the taxonomy folder.
- New tests cross-check every template's ordinal against `hvti_taxonomy()` —
  the major against the folder it sits in, and the minors against row order
  within that folder — and assert that no two templates share a prefix, since
  `template_path()` and `new_job()` both resolve with `match()`, which takes
  the first hit silently.
- `hs` is refiled from `distributions` to `analyses`, immediately after `hm`,
  the job it actually consumes. `hvti_taxonomy()` gains an `estimates` row for
  the artifact directory that design already relies on; the row carries no
  prefix (`NA_character_`), since `estimates` is an artifact kind rather than
  an analysis type. Its position shifts the folder majors: `graphs` is now
  `06` and `documents` `07` (`distributions` is unaffected, so `ac` stays
  `03.01`).

## Bug fixes

- `new_job()` no longer leaves a copied-but-unsubstituted job file behind when
  writing the `ENDPOINT`/`TYPE` markers fails. Previously a template whose
  markers had moved or been removed still left its copy on disk after
  erroring — a job named for one set but declaring the template's placeholder
  set, and a retry then hit the refuse-to-overwrite guard and reported
  "already exists" instead of the actual template problem.
- The `ac` template's render-time filename guard strips whatever extension
  `knitr::current_input()` reports instead of a hard-coded `.qmd`. Quarto
  knits through an intermediate `.rmarkdown` file, so the old pattern never
  matched under a real render; it happened to be harmless because the stray
  extension landed on a field the guard does not read, but the fix removes
  the reliance on that coincidence.

# hvtiRtemplates 1.0.2

## Bug fixes

- `.Rbuildignore` now excludes `.claude` and `.remember`, which hold session
  tooling; `.claude` can also contain a git worktree. Their contents were
  raising two NOTEs — hidden files, and non-portable paths over the tarball
  length limit — neither of which is about the package. `.remember` was
  invisible until `.claude` was excluded, because `R CMD check` reports every
  hidden path in one NOTE.

# hvtiRtemplates 1.0.1

## New features

- `new_job()` scaffolds an analysis job from a supported template, naming the
  file `<prefix>.<basename>.qmd` and refusing to overwrite an existing job.
- `inst/templates/ac.qmd` — the first supported job template, for actuarial
  life tables. It carries its own `format:` block so that a copied job renders
  standalone, resolves the project root itself so no path needs editing, and
  marks every study-specific line `EDIT:`.

  The cohort section offers two shapes, because the choice is not cosmetic:
  a job analysing the whole study uses `assert_cohort()`, while a job
  analysing a filtered subset must supply its own gate — `_study.yml` records
  the study cohort, so `assert_cohort()` would pass while the job ran on a
  cohort nobody checked.

  `hz` and `hp` are deliberately absent: each exists in only one study, and a
  template extracted from a single example encodes that study's choices as
  though they were general.

# hvtiRtemplates 1.0.0

* Initial release.

* `hvti_taxonomy()` encodes the group's analysis-prefix system as data rather
  than as a README, so the test suite checks it against the templates actually
  present instead of letting it drift.

* `template_list()` and `template_path()` resolve a template name to an
  installed file, so a study binds to a versioned template rather than to a
  copy. Both return empty until stage 3 of the templates-and-provenance design
  adds the templates.

* `hvti_non_prefixes()` records the leading name fields that are utilities
  rather than analysis prefixes, which is what lets the test suite tell "not a
  prefix" apart from "a prefix nobody documented".

## Provenance

During development this repository also carried the legacy SAS template corpus
(240 files) and the SAS macro library (495 files, with history imported from
2014) as a reference specification. Both were removed before release, and
every path was purged from every commit with `git filter-repo`. They are not
recoverable from this repository's history.

Parity checks against the SAS originals therefore need a source outside this
repository. The institutional SAS licence expires 2026-09-29.

**Corrected 2026-08-29: the licence runs into 2027, not out in 2026** (working
date `2027-09-29`, not yet confirmed). The date above was wrong when 1.0.0
shipped. It is left as written and corrected here; see the 1.0.10 entry.

A result filed before the migration still cannot say which macro version
produced it. That was already true — `%inc` bound late to a mutable directory
with no version — and removing the corpus neither creates nor worsens it.
