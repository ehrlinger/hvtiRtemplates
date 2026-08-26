# The second exemplar: an `ac` → `hz` → `hp` chain in maze

**Date:** 2026-08-26
**Status:** design, approved for planning
**Repos touched:** `hvtiRtemplates` (this spec, and the templates it unblocks),
`hvtiRutilities` (`study_init()`, `assert_cohort()`), the maze study tree.

---

## 1. Why this exists

`inst/templates/README.md` states the gate plainly:

> `hz` (parametric temporal-hazard fit) and `hp` (nomogram and figures) are
> **not templated yet**. Both shapes exist in exactly one study, and a template
> extracted from a single example encodes that study's choices as though they
> were general. They arrive once a second study has run them.

That one study is `preserve_root`. This design runs the second, so the gate
opens for `ac`, `hz` and `hp` together.

It is not only a formality. A 2026-08-26 census of the SAS corpus
(3,269 listings, 4,843 fit blocks, 527 studies; see
`PARITY-HANDOFF.md` §14 in the preserve_root tree) shows **preserve_root's
phase shape is a minority one**:

| shape | fit blocks |
|---|---|
| `E+L` | 3,157 |
| `E+C` (preserve_root) | 472 |

Extracting a template from preserve_root alone would encode an
`Early+Constant` habit that six sevenths of the corpus does not share, along
with interval censoring that most jobs do not have. The second exemplar is
what stops that.

## 2. The study

`/studies/cardiac/rhythm/maze/atricure/gender` — *Gender differences in
post-op outcomes of RF ablation for treatment of AFIB*, CCF 2001 to 2004.

Chosen because it differs from preserve_root on the axes that matter, while
remaining checkable:

| | preserve_root | maze/atricure/gender |
|---|---|---|
| phase shape | `E+C` (minority) | **`E+L`** (majority) |
| interval censoring | yes — dominates the job | **none** |
| cohort | job-filtered, 291 of 378 | **whole dataset, 512** |
| cohort gate | Shape B | **Shape A** |
| `noconserve` reference | none usable | **yes** — see §6 |
| nomogram on the target fit | yes | **yes** |

### The §6.1 gate — run 2026-08-26, passes 5/5

`hz.dead.sas` applies no cohort filter (`data built; set library.built;` plus
a column drop), so the job cohort is the whole dataset. Verified against
`hz.dead.lst`'s own printed figures:

| check | R, from `built.sas7bdat` | `.lst` |
|---|---|---|
| N | 512 | 512 |
| events | 53 | 53 |
| right censored | 459 | 459 |
| `IV_DEAD` min | 0.008213721 | 0.008213721 |
| `IV_DEAD` max | 4.175308 | 4.175308 |

No `NA` in either gate variable. **This is the first §6.1 gate in the parity
effort that passed without a fight** — preserve_root's needed a job-defined
`predim_avail` filter that cannot be recovered from the `.lst` at all.

## 3. Layout — the taxonomy, not preserve_root's

preserve_root's R jobs live in `analyses/R_hazard/{R,qmd}`. That is **legacy**:
the 2026-08-13 provenance design records `_study.yml` as the thing that
"subsumes the `_quarto.yml` walk that `R_hazard` ... uses". Building the second
exemplar there would copy a superseded layout and force template extraction to
translate placement as well as content.

So the jobs go where `new_job()` puts them:

| file | origin |
|---|---|
| `distributions/dead-hz-03.01-ac.qmd` | `new_job("ac", "dead", "hz")` |
| `distributions/dead-hz-04.01-hz.qmd` | hand-written — **establishes the `hz` ordinal** |
| `graphs/dead-hz-06.01-hp.qmd` | hand-written — **establishes the `hp` ordinal** |

Generated artifacts follow the rule already stated in the templates README —
authored files flat, generated artifacts under `<endpoint>-<type>/`:

```
estimates/dead-hz/ac.rds
estimates/dead-hz/hz.rds
graphs/dead-hz/hp-*.png
```

### Ordinals

`template_list()` reads the ordinal from the **filename**, not from
`hvti_taxonomy()`, so no canonical value exists until a template does. `ac` is
`03.01` and the README's own layout example already shows `hp` at `06.01`, which
implies the number tracks position in the overall study chain rather than
position within a folder. `hz` therefore takes **`04.01`**.

This is a precedent-setting decision and is recorded here so the next person
does not have to re-derive it.

## 4. Study scaffold

maze has no `_study.yml`. One call, using the gate-verified figures:

```r
study_init(root       = "/studies/cardiac/rhythm/maze/atricure/gender",
           study      = "Gender differences in post-op outcomes of RF ablation for AFIB",
           population = "CCF 2001 to 2004",
           built      = "built.sas7bdat",
           event      = "dead",
           time       = "IV_DEAD")
```

Because the job cohort equals the study cohort, `assert_cohort()` is a genuine
gate here rather than a restatement of itself.

## 5. The `hz` job

preserve_root's `02-hz-dead_pa.qmd` is the skeleton. Everything specific to
interval censoring drops out: no `Surv(type = "interval2")`, no `icensor`
mapping, no `objective = "sas"`. The response is simply `Surv(IV_DEAD, dead)`.

SAS's fit 1, read from `hz.dead.lst`:

```r
phases <- list(
  early = hzr_phase("cdf", t_half = 0.9996401, nu = 2.550286, m = -0.337948),
  late  = hzr_phase("g3", tau = 1, gamma = 1, alpha = 1, eta = 2.574888,
                    fixed = c("tau", "gamma", "alpha"))
)
```

`DELTA = 0`. With `TAU = GAMMA = ALPHA = 1` the late phase is the pure Weibull
`G3 = t^eta`. Branch is **Case 2** (`m < 0`, `nu > 0`).

**Targets:** log likelihood **−176.934**, 53 events conserved,
`Conservation of events: Invoked at each iteration`.

Retained from the exemplar, deliberately:

- the **blocking** cohort gate — the job does not run on a wrong cohort;
- the `check_fit()` guard asserting the objective is a finite, negative
  log-likelihood, so a plateau is never reported as a fit;
- deterministic fit (from SAS's own estimates) reported separately from the
  multi-start fit. *Does R agree with SAS* and *is SAS at the optimum* are
  different questions and must not be conflated;
- the conditioning report against SAS's printed condition number.

### What `hz` writes

```
estimates/dead-hz/hz.rds   # list(deterministic =, multistart =, noconserve =)
```

⚠️ **This shape is provisional.** `hm` ("risk factor analysis; builds on the
HZ fit") and `hs` ("patient-level survival predictions from the HM model")
will consume it, and neither has been ported. The shape mirrors what
preserve_root's job already saves; it is recorded as a contract so the first
`hm` port either confirms it or changes it deliberately, rather than
inheriting an accident. See §8.

## 6. A `noconserve` reference preserve_root cannot provide

`hz.dead.lst` carries **two fits**, and fit 2 is
`Conservation of events: Not invoked` — the same model with conservation off,
LL **−176.746**.

preserve_root has no such reference. Its second fit adds a `G_ROOT` covariate
to both phases and fits six parameters, so its LL confounds two changes at
once; the job's own text says it "cannot serve as a conservation target". maze
closes that gap as a side effect of being chosen for other reasons.

## 7. Verification

Fit 1 prints a nomogram (23 points). The `hp` job overlays R's `S(t)` and
`h(t)` on SAS's printed values using the same rule as
`shape-parity-sweep.R`: a point passes if SAS's printed value is reachable
from **any** `t` within the printed `YEARS` rounding interval, to that
column's own print half-ulp, with the precision **inferred per column** rather
than assumed.

Both halves of that rule exist because ignoring either fabricates failures:
SAS's print width varies between files, and the 30-day row's printed `0.0821`
is really `30/365.25`.

The job therefore carries its own parity evidence. A rendered page is itself
evidence the gate passed.

## 8. `hm`, `hs` and `bh` are NOT mocked in

Deliberate, and load-bearing. Job counts:

| prefix | maze | preserve_root |
|---|---|---|
| `ac` | 30 | 40 |
| `hz` | 24 | 35 |
| `hp` | 28 | 67 |
| `hm` | **0** | 1 |
| `hs` | **0** | 3 |
| `bh` | **0** | 6 |

`hm`, `hs` and `bh` exist **only in preserve_root**. Stubbing them into maze
would:

1. **Create jobs with nothing to gate against.** Every job in this design
   earns its place by having a `.lst` to check — cohort counts, printed
   estimates, a nomogram. A mocked `hm` in maze has none, so it would emit
   numbers no one can check. That is the failure mode this whole effort
   exists to catch.
2. **Invert the template gate.** For `hm`/`hs`/`bh`, preserve_root is the
   *first* study and maze cannot be the second, because it has no such jobs.
   A mock would make the roster look like two exemplars exist when it is
   still one — manufacturing exactly the false confidence the gate prevents.
   A template from one example encodes that study's choices as general; a
   template from zero encodes a guess.
3. **Rot.** A stub nobody runs drifts from the interface it stubs.

The roles therefore split:

- **maze** — second exemplar for `ac` / `hz` / `hp`.
- **preserve_root** — sole source of truth for `hm` / `hs` / `bh`, and the
  study to port them from when those templates are wanted.

`bh.dead.sas` and `bh.dead_summary.sas` appeared as untracked files in
preserve_root on 2026-08-26, so bootstrap-hazard work may already be in
flight. `bh` is the natural next port — not a mock.

## 9. Constraint carried for a project not being done

maze is **Shape A** (job cohort = study cohort); preserve_root is **Shape B**
(291 of 378, the filter living in the `.sas`, not the `.lst`). The cohort gate
must therefore be an **explicit, named section** of the `hz` job rather than
hardcoded to Shape A.

This is the one place the design accepts cost for future work: aligning
preserve_root to the templates is a separate project, and hardcoding Shape A
here would mean rewriting the gate then.

## 10. Out of scope

- Aligning preserve_root to the taxonomy layout (its own project, sequenced
  **after** this one so the conventions settled here are migrated onto rather
  than invented twice). While there, its `hz` job's `callout-important` is
  stale — it documents the −268.65 vs −239.194 discrepancy as unresolved and
  pins TemporalHazard 1.2.1, but that was solved and shipped as
  `objective = "sas"` in 1.2.4. The parity documents were repointed on
  2026-08-25; the production job was not.
- Repeated-events jobs (`hz.ce_cardioversion_repeated`, grade 4 and the
  largest remaining `hzr_decompos_g3` widening — a **parity** target, a poor
  template exemplar).
- Longitudinal (`mm`, `gm`, `mp`, `gp`).
- A job-type inventory sweep across `/studies` (cheap, filename-only, and the
  thing that would have answered §8's table in one lookup instead of by hand).

## 11. Open, to pin during implementation

- The positional order of `theta` for an `E+L` model. preserve_root documents
  it for `E+C` (`log(mu_early), log(t_half), nu, m, log(mu_constant)`); the
  `g3` late phase adds `tau, gamma, alpha, eta` and the order must be read from
  the package, not guessed.
- Whether the shipped `03.01-ac` template needs any change for a study with no
  interval censoring.

## 12. Success criteria

1. `_study.yml` exists in maze and `assert_cohort()` passes on the real data.
2. All three jobs render from a clean session.
3. The `hz` deterministic fit reproduces SAS's LL of **−176.934** and conserves
   **53** events.
4. The `noconserve` fit reproduces **−176.746**.
5. The `hp` job reproduces SAS's nomogram at **23/23** points for both `S(t)`
   and `h(t)`, under the per-column print-precision rule.
6. `template_list()` in `hvtiRtemplates` is unchanged — this design produces
   *jobs*, not templates. Extraction is the next project, and it now has two
   exemplars to intersect.
