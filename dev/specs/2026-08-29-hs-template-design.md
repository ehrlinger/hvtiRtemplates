# The `hs` template — patient-level predictions and expected survival

**Date:** 2026-08-29
**Status:** designed, not started
**Roadmap:** batch 1 of `2026-08-29-template-conversion-roadmap-design.md`.
`hs` is one template, and it closes the authoring chain
`ac → hz → hm → hs → hp`.
**Issue:** [#8](https://github.com/ehrlinger/hvtiRtemplates/issues/8)

This note is self-contained. It assumes no memory of the session that
produced it.

---

## 1. What this decides

The contents and placement of `inst/templates/graphs/06.02-hs.qmd`, the
prerequisite that blocks it, and what it asks of `hvtiRlifetables`.

It decides nothing about the other 37 prefixes.

---

## 2. What `hs` is, measured rather than assumed

`hvti_taxonomy()` describes `hs` as "patient-level survival predictions from
the HM model". The corpus agrees, and adds detail.

**Ten `tp.hs.*` SAS templates, and every one of them is in `graphs/`:**

| cluster | templates |
|---|---|
| predictions | `tp.hs.dead.setup`, `tp.hs.dead_uses_setup`, `tp.hs.dead.conditional.setup`, `tp.hs.dead.conditional.uses_setup`, `tp.hs.dead.compare_benefit.setup`, `tp.hs.dead.procedure.tdepth` |
| expected survival | `tp.hs.uslife_generates_matched_estimates`, `tp.hs.uslife_estimates_generate_stratify_.age` |
| validation | `tp.hs.dead.C_Index`, `tp.hs.BRIER.test_sample_cabg` |

The `setup` / `uses_setup` pairing is the shape that matters: **one job
computes estimates, siblings read them.** That is already this repository's
`estimates/` convention, so it needs no new mechanism.

The R side, from the 2026-08-27 census: 11 job files across **7 studies**, ten
of them in `graphs/`.

⚠️ **The ledger's `r_exemplars: 7` for `hs` overstates the R precedent, and
this spec does not lean on it.** Reading those files, they are thin R shims
around SAS-computed results rather than R implementations of `hs`:

- `hs.dead_5yr_pred.R` reads `datasets/dd5ypred.xpt` — predictions **already
  computed in SAS** — and draws a `coplot`. It is a plot, not a prediction job.
- `hs.brier.R` reads two `.xpt` exports, sources a loose script, and writes a
  text file "if you want to plot this in SAS".

The count is honest about what it measures — files with an `hs` prefix and an
R extension — and that is not the same question as *is there an R
implementation to generalise from*. **The real R precedent for this template is
`hvtiRlifetables` and the parity document
`.../preserve_root/analyses/R_hazard/parity/05-hs-uslife-parity.qmd`**, neither
of which the census counts as an `hs` job at all.

---

## 3. Placement, and the prerequisite that blocks it

**`inst/templates/graphs/06.02-hs.qmd`.**

The taxonomy files `hs` under `analyses`. The corpus files it under `graphs`,
unanimously: 10 of 10 SAS templates, 10 of 11 R jobs. The corpus wins, because
a template's whole purpose is to land where the job actually goes.

⚠️ **This is blocked on a PR to `hvtiRutilities`, and two properties of that PR
matter, not one.** Both are enforced by tests in this repository:

1. **Folder.** `test-taxonomy.R`'s "a template sits in the folder its prefix is
   filed under" does `expect_equal(tl$folder, tx$folder[match(tl$prefix, tx$prefix)])`.
   A `graphs/` template for a prefix filed under `analyses` fails outright.
2. **Row position.** "within a folder, ordinal minors follow taxonomy row
   order" means the minor is **not free**. The `hs` row must sit immediately
   after `hp` in the taxonomy's `graphs` block for `06.02` to be correct. Placed
   at the end of that block it would have to be `06.10` instead.

The `graphs` block is currently `hp → mp → lp → np → dp → fp → gp → cp → ce →
rp`. Inserting `hs` after `hp` shifts the **implied** minor of every prefix
below it by one — `mp` becomes 06.03, `lp` 06.04, and so on.

⚠️ **That costs nothing today and will not stay free.** `hp` is the only
templated prefix in `graphs`, and it keeps `06.01`, so no shipped file and no
scaffolded job changes name. Once any of `mp`, `lp`, `np`, `dp`, `fp`, `gp`,
`cp`, `ce` or `rp` ships, the same insertion would renumber a live template.
**Insertions into a taxonomy block are cheap only while the block is
mostly untemplated** — which argues for settling the folder question for the
whole `graphs` block before the plots family (batch 3) starts, not after.

The roadmap ledger's `hs` row changes with it — `folder: "graphs"`,
`ordinal: "06.02"` — or `check-roadmap-counts.py` fails the PR, which is what
that guard is for.

**Do not ship the template before the taxonomy PR merges.** The ordinal is in
every scaffolded job's filename, so a later move is a rename with a migration
behind it.

⚠️ This is one instance of a contradiction the roadmap design records as
systemic — `rfc` and `rfs` have the same disagreement, and every R job under
`analyses/R_hazard/` reports misfiled for the mirror-image reason. **Settling
`hs` here does not settle those**, and the general rule still needs its own
spec. This decides one row on its own evidence.

---

## 4. Interface

| | |
|---|---|
| **reads** | `set_path("estimates", "hm.rds")` — `reported`, `stage1`, `stage2`, `covariates`, `audit`, `deciles`; and `read_built()` for the cohort |
| **writes** | `set_path("estimates", "hs.rds")` |

The shipped `04.01-hm.qmd` already names this seam in its save chunk: "`hs`
builds patient-level predictions from this model and `bh` bootstraps this
screen, both by set." This template is the other half of a contract that
already exists.

⚠️ **The shipped `06.01-hp.qmd` reads `ac.rds` and `hz.rds`, not `hm.rds`.** It
plots the actuarial and hazard fits, not the multivariable model. So shipping
`hs` does **not** make the shipped `hp` consume it — in SAS that is a different
`hp` variant, `tp.hp.dead.ideal_multivariable_time_depiction.sas`. What `hs`
closes is the **authoring** chain: every job type in the set has a template.
Wiring a model-consuming `hp` variant is separate work and is not in scope here.

---

## 5. The two halves

### 5.1 Patient-level predictions

Evaluate the fitted hazard at each patient's covariates via
`TemporalHazard::hzr_phase_cumhaz()`, convert cumulative hazard to survival,
and report at study-chosen horizons. The corpus shows 30-day, 5-year and
10-year in use; `tp.hs.dead.conditional.*` shows conditional survival as a
recurring variant.

`EDIT:` markers: `ENDPOINT`, `TYPE`, `HORIZONS`, and the covariate profile(s)
to predict at.

### 5.2 Expected population survival

`hvtiRlifetables::us_matched(age, male, other, times, id, vintage, table,
scale, individual)`, then observed-versus-expected against the cohort.

`EDIT:` markers: the cohort's age / sex / race columns, `table` (default
`"sexrace"`), and `vintage`.

---

## 6. The `vintage` marker, and why it carries a paragraph

**`vintage` gets no default and a required `EDIT:`.**

`%usmatchd` took no vintage argument, so every SAS `hs.uslife` job silently
inherited the macro default **as of its run date**. That default moved twice —
`table84` → `table2008` → `table2023` (2025-12-23) — **with no signal at either
move**. The vintages are structurally different fits rather than perturbations
of one another, so a wrong vintage is wrong by orders of magnitude, not by a
rounding error.

The consequence is concrete and already documented: `05-hs-uslife-parity.qmd`
could not read the vintage off the job it was reproducing. It had to **recover**
it, by fitting all three and seeing which landed at machine precision.

A job that does not state its vintage cannot be reproduced. So the template
states it, or stops. `hvtiRlifetables::us_lifetable_vintages()` enumerates the
valid values and the comment points at it.

This is the house rule working as intended: the comment records *why the choice
matters*, and it exists because the alternative fails quietly rather than
loudly.

---

## 7. What this asks of `hvtiRlifetables`

`hvtiRlifetables` is at 0.1.1 with three exports — `us_matched()`,
`us_lifetable_model()`, `us_lifetable_vintages()` — and no open issues. **`hs`
is its first real consumer, so this section is a demand signal, not a
complaint.** Two gaps show up in writing the template, both recurring in the
corpus:

1. **A cohort expected-survival curve.** `us_matched(individual = TRUE)`
   returns per-patient expected survival. What gets overlaid on an actuarial
   curve is the **cohort average at each time**, which every study then derives
   for itself. `tp.hs.uslife_generates_matched_estimates.sas` is that
   derivation. Deriving it per study is how two studies end up averaging
   differently and neither knows.
2. **Stratified expected survival.** `tp.hs.uslife_estimates_generate_stratify_.age.sas`
   stratifies the expected curve by an arbitrary grouping. `table =` chooses the
   life table's own strata, which is a different axis and does not serve this.

Neither is a blocker. **The template ships with these derived inline and marked
`EDIT:`**, and the derivations are the specification for what the package
should later absorb. If they move into `hvtiRlifetables`, this template gets
simpler and the ordinal does not change.

---

## 8. Out of scope

**Validation metrics — C-index and Brier.** `hs.brier.R` does
`source("/programs/apps/R-Splus/brier.multph.haz.R")`: a loose script on a
shared drive, with no package and no version. **No shipped template depends on
an unpackaged file, and this one will not be the first.** The corpus files
these under `hs`, so they belong here eventually — after `brier.multph.haz.R`
has a home in `hvtiRutilities` or `TemporalHazard`. Recorded so a later reader
does not read the omission as an oversight.

**A model-consuming `hp` variant.** See §4.

---

## 9. Definition of done

- Renders.
- Its own key in `.lintr`, and the key is the **FILE**, not the directory.
- An `edit-guard` chunk, and every study-specific line marked `EDIT:`.
- Exactly one `^ENDPOINT\s+<- ` line and one `^TYPE\s+<- ` line.
- No study identifiers — `test-new-job.R` asserts this.
- A row in `inst/templates/README.md`.
- The roadmap ledger's `hs` row at `status: "shipped"`, `folder: "graphs"`,
  `ordinal: "06.02"`.
- `devtools::test()` passes; `devtools::check()` is 0/0/0; `document()` run.
- Patch version bump with a matching `NEWS.md` entry.

---

## 10. Rejected

**`analyses/04.02-hs.qmd`, following the taxonomy.** Needs no upstream PR, and
files the template where no study puts the job. Every scaffolded `hs` job would
sit apart from the siblings that read it.

**Covering validation metrics too.** Most faithful to what the corpus calls
`hs`, and it would bake a `source()` of an unversioned shared-drive script into
a supported template.

**Predictions only, dropping expected survival.** Smallest template with the
cleanest single responsibility. Rejected because observed-versus-expected is
the output the chain exists to produce, and `us_matched()` is already
parity-tested to 1e-12 against this study's stored SAS answer — leaving it out
would send every study to re-derive the one part that is already proven.

**Settling the folder contradiction across all prefixes first.** The right
long-run move, and it blocks batch 1 on a spec covering `hs`, `rfc`, `rfs` and
the misfiled-R-jobs case together. `hs`'s own evidence is unanimous — 10 of 10
and 10 of 11 — so it does not need the general rule to decide it.
