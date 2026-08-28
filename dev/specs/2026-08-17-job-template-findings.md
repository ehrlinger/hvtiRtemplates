# Findings for the R job templates, from running the jobs

**Date:** 2026-08-17
**Source:** the `bh` (bootstrap screen) and `hm` (multivariable selection) jobs
in the `survival` study tree, during a live 25 chunk bootstrap run.
**Status:** findings and design consequences for stage 3 (`new_job()` and the
five templates). No code in this package has been changed by this note.

> ⚠️ **PARTLY SUPERSEDED by `2026-08-19-report-design-learnings.md`.** Section 3
> below recommends that `bh` and `hm` screen the same pool, which was done by
> pruning both to one form per concept. That was **reversed on 2026-08-18**
> after measurement showed the pruning deleted informative candidates rather
> than redundant ones: 16 of 57 removed forms correlate at |r| < 0.9 with the
> form kept. Read section 1 of the 2026-08-19 note before acting on section 3
> here. Sections 1, 2, 4 and 5 below stand unchanged.
**Design spec referenced below:** `dev/specs/2026-08-13-templates-and-provenance-design.md`.
It was migrated out of the `survival` study tree into this repository on
2026-08-18, so the section numbers cited here now resolve against a copy that
sits beside this note. It previously lived at
`analyses/R_hazard/docs/specs/2026-08-13-templates-and-provenance-design.md`.

These are the things that only showed up by running the jobs at real scale.
Every one of them is a property a template must carry, because the study author
who instantiates it will not rediscover them.

---

## 1. A template for a chunked job must declare what it expects

The `bh` job runs as 25 independent chunks that land over roughly twelve hours.
Each chunk `.rds` records everything about itself: seed, entry and stay criteria,
step cap, dataset checksum, elapsed time. **None records how many siblings it
was launched with**, because no chunk can know.

So a report that pools whatever is on disk cannot tell a partial run from a
small one. Rendering at hour eight with 12 of 25 chunks present produces a
document in which every health check passes and every selection frequency is
honestly computed over 240 replicates instead of 500. Nothing on the page is
false. The denominator is simply not the intended one, and there is no evidence
on the page that it is not.

**Consequence for the `bh` template:** it must carry an expected chunk count and
expected replicate total as instantiation knobs beside the existing
`RETAIN_PCT` and `DISPLAY_FLOOR`, and it must raise a visible callout when the
pool falls short, not merely print a number in a provenance table. A reader who
has to compare two table cells to discover a report is provisional will not
discover it, and neither will a collaborator who receives the rendered `.html`
with no memory of when it was made.

**The general rule, which stage 3 should apply beyond `bh`:**

> A completeness expectation cannot be derived from the artifacts being checked.
> It has to be declared somewhere the artifacts cannot influence.

This is the same argument that makes the planned `inst/sas/` and
`inst/macros/` file count test correct (design spec section 7). That test works
precisely because the expected count is recorded separately from the files it
checks. Note the symmetry and keep it: a partial corpus copy and a partial chunk
pool are the same failure, and both are invisible from the inside.

---

## 2. A step cap and competing transformations interact, and both must be reported

The `hm` job reproduces a SAS `%macro model` with `maxsteps = 10`. Measured on
this study:

- the selection used all 10 steps, so it stopped on budget, not because nothing
  further qualified;
- at least 2 of those 10 slots went to a second and third form of one concept
  (`late.age`, `late.age2`, `late.ln_age`).

Neither fact is visible in a coefficient table, and each is misleading without
the other. A capped run alone says "this list is where the screen got to". A
crowded run alone says "some of these are the same variable". Together they say
something stronger: the model is budget limited **by redundancy**, and whatever
would have entered at steps 11 onwards never had the chance.

**Consequence for the `hm` template:** report both, together, and raise the
combination to a callout. Reporting the cap alone is not enough, and the `hm`
job already reported the cap.

**Consequence for template design generally:** where a template exposes a step
cap as an instantiation knob, it must also expose what the cap did. A knob whose
effect is invisible in the output invites the next person to leave the default
in place without knowing what it cost. The study's own history bears this out:
the `bh` job ran at `max_steps = 10` before anyone noticed the phases were
competing for a shared budget, and the early phase had starved.

---

## 3. `bh` and `hm` do not screen the same pool, and the templates must not imply they do

The `bh` job prunes competing transformations to one form per concept, a
deliberate and documented departure from the SAS. The `hm` job does not, because
the `%macro model` it reproduces had no notion of a concept and SAS could not
have done otherwise.

Both choices are defensible. The consequence is that **`bh` reports reliability
for concepts while `hm` may fit a model holding several forms of one**, so the
two variable lists are not directly comparable and neither substitutes for the
other.

A related documentation defect was found and corrected in the study: the `bh`
report stated that its retained set is what `hm` fits, and wrote
`selection_bh.csv` to make that handoff explicit. Nothing reads that file.
`%hazboot` and `%model` were parallel analyses in SAS, not a pipeline, and the R
jobs faithfully reproduce that. A reader who believed the claim would assume the
`hm` model had been screened for reliability first. It has not been.

**Consequence for stage 3:** the `bh` and `hm` templates must state their
relationship accurately, and must not describe an output as an input to another
job unless something reads it. This is the kind of claim that survives copying
for twenty years, which is the failure mode this whole design exists to remove.

---

## 4. Candidates for promotion out of the study, and where each belongs

The study tree now holds several helpers that are not study specific. The design
spec's own test applies: *if it would mean anything outside this institution it
belongs in a method package; if not, it belongs in `hvtiRutilities`.* Templates
depend on utilities, never the reverse.

| Helper | Currently | Suggested home | Reasoning |
|---|---|---|---|
| `pool_bagging()`, `bagging_chunk_files()`, `bagging_shortfall()` | `R_hazard/R/bagging-pool.R` | method package | Pooling iid bootstrap replicates from restartable chunks is general. Nothing in it is institutional. |
| `concept_map()`, `prune_to_one_form()`, `selection_crowding()` | `R_hazard/R/pool-prune.R` | **split** (see below) | The algorithm is general; the affix vocabulary is not. |
| `covariate_audit()`, `covariates_to_numeric()` | `R_hazard/R/covariates.R` | `hvtiRutilities` | These exist because `vars.sas` mean imputes and adds `ms_*` indicators, so 0/1 clinical variables arrive as three level factors. That is an institutional data contract, not a statistical idea. |
| `r_dir_impurities()` | `R_hazard/R/purity.R` | `hvtiRutilities`, used by both packages | Already specified this way in the design spec, section 7. |
| `sas_variable_block()` | `R_hazard/R/sas-blocks.R` | this package | It reads a candidate block out of a SAS job. That is corpus handling, which is what this package is for. |

### The split worth making explicit

`concept_map()` groups `age`, `ln_age`, `in_age`, `age2` as one concept by
stripping known affixes and checking the stem is itself in the pool. The
**grouping rule is general**: any stepwise screen over a pool containing
transformations of the same variable has this problem, and the conservative
"only group when the stem is in the pool" rule is a good general answer.

The **affix vocabulary is institutional**. `ln_`, `in_`, `in2`, `_pr`, and the
trailing `2` come from `vars.sas` naming conventions. The rule that `in2` is
stripped before `in_`, and the deliberate refusal to reduce `agee` to `age`, are
facts about this institution's variable names, not about statistics.

So the shape to aim for is a general function taking a configurable affix
vocabulary, with the institutional vocabulary supplied by `hvtiRutilities` or
declared in `_study.yml`. Shipping the vocabulary inside the general function
would export this institution's naming conventions as though they were a
statistical standard.

---

## 5. Small things worth carrying into the templates verbatim

Each of these cost real time to find and none is obvious from reading the code.

- **Write the model formula literally at the call site.** Not in a variable, not
  via `as.formula()` or `reformulate()`. Both `hzr_bootstrap()` and
  `hzr_stepwise()` rewrite the stored formula per step or per replicate, and a
  symbol standing where the formula should be does not survive that rewrite: the
  refit errors, the error is caught, the step reports nothing accepted, and the
  screen halts having selected nothing, with no warning and `n_failed = 0`. Both
  runners now carry a guard that reads the variables off the stored call and
  fails loudly before the compute starts.
- **A screen that selected nothing is a failure, not a finding.** It is the exact
  signature of the defect above, and the resulting summary reads as a table of
  perfectly reliable variables.
- **A free parameter must vary across resamples.** A bootstrap built on the
  vector interface returns the original fit every replicate, with
  `n_success = 500`, `n_failed = 0`, and no warning. Check `sd()` of a free base
  parameter and stop if it is zero.
- **Progress rates do not transfer between configurations.** A helper script
  documented a steady state rate measured on a much smaller candidate pool. The
  25 chunk run over 189 usable candidates per phase ran at roughly half that,
  turning a predicted 6 hour job into 13. Every step scores every candidate, so
  the rate is set by the pool. A template that quotes a runtime must say what
  pool it was measured on.

---

## Evidence

All figures above were measured on 2026-08-17 against the live study, not
inferred: the crowding count and cap status from `_output/selection_hm.rds`, the
partial pool behaviour from a synthetic 25 chunk pool and from real runner
output, the rate from the running job. The formula and resampling traps are
recorded from earlier sessions in the study's runner comments and were not
re-derived here.
