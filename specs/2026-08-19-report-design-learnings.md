# Findings: what a job report has to say, from two production runs

**Date:** 2026-08-19
**Source:** the `ac`, `hz`, `hp`, `hm` and `bh` jobs in the `survival` study,
across a 13-hour and a 19-hour bootstrap screen and the reports over them.
**Status:** design consequences for stage 3. Supersedes part of
`2026-08-17-job-template-findings.md`, which is marked where it does.
**No code in this package has been changed by this note.**

Everything here was measured on a real study. Where a claim has a number, the
number is from that study and not an illustration.

---

## 1. Reversal: do NOT prune competing transformations from the pool

`2026-08-17-job-template-findings.md` recorded that `bh` pruned to one form per
concept and `hm` did not, and treated the asymmetry as the problem. Both jobs
were then pruned to match. **That was wrong and has been reversed.** The
template guidance should be: **screen every form, group only when reading.**

**Why, measured.** Pruning assumes forms of one concept are near-duplicates.
Of the 57 forms it removed from this study's pool, **16 correlated at |r| < 0.9
with the form it kept, and five below 0.5**:

| kept | dropped | r |
|---|---|---|
| `zexp` | `in2zexp` | **−0.099** |
| `zexp` | `in_zexp` | **−0.195** |
| `blrbn_pr` | `in_blrbn` | −0.367 |
| `gfr_pr` | `in_gfr` | −0.434 |
| `ln_crcl` | `crcl2` | 0.480 |

`in_zexp` **is** `1/zexp` — r = 0.9997 against the reciprocal — yet correlates
with `zexp` at only −0.195, because `zexp` spans **0.038 to 151.9**. Over a
4000-fold range a value and its reciprocal are different information. The
study's published model uses **`zexp` and `in_zexp` in the same phase, both
significant** (z = 4.00 and 2.76): a two-parameter flexible form that pruning
forbids.

The naming convention tells you two variables are RELATED. Only the data tells
you whether they are REDUNDANT.

**What replaces it.** A concept-level frequency table computed after the fact,
reporting the union across a concept's forms. It answers the same question
without deleting anything, and it earns its place immediately: in the unpruned
run the `zexp` concept is **retained at 56.6%** while its best single form
reaches only **28.2%**. Under pruning only `zexp` would have been offered, which
scores 16.6%. The concept would have been missed with no diagnostic showing it.

**A threshold does not rescue pruning.** A correlation guard was sized: at
`|r| >= 0.90` it restores 16 candidates, at 0.95 restores 26, at 0.99 restores 40 —
and 0.99 un-groups `area_int`/`in_arin`, which correlate at 0.9735 and are
genuinely one concept. There is no gap in the distribution to put a threshold
in. Any value is a judgement dressed as a measurement.

**Cost side of the trade was zero here.** `max_steps` is 50 and the median
replicate entered 17 covariates, so the step budget never bound. Pruning bought
nothing and deleted informative candidates.

---

## 2. A selection frequency is conditional on the candidate pool

Re-running the same study, same seeds, same data, changing only the pool from
189 pruned concepts to 226 screened candidates:

| concept | pruned pool | unpruned pool |
|---|---|---|
| early `ht` | 26.6% | **95.2%** |
| early `effic` | 93.8% | **20.2%** |
| early `area_int` | 86.4% | 15.8% |
| early `zexp` | 32.0% | 56.6% |

Seven of nine retained concepts were common to both runs; two differed each way.
In a forward stepwise what enters at step 3 depends on what entered at steps 1
and 2, so changing which competitors exist changes the whole path.

**Consequence for stage 3:** a template producing a "Reliability (%)" column
must state that the figure is conditional on the pool, and the pool must be
reported alongside it. This is a limitation to publish, not a defect to fix.

---

## 3. Every report needs a provenance stamp, and it must degrade honestly

Two different facts, which must not share a line:

- **render stamp** — when and where this document was produced. Correct for a
  job whose expensive work happens during the render (`ac`, `hz`, `hp`, `hm`).
- **run stamp** — when and where a saved result was produced. Correct for a job
  reading artifacts written hours earlier (`bh`).

Both read: `Run <ISO-8601 UTC> on <host> (<platform>), R <version>, <package>
<version> (<short sha>).`

**The degradation is the design.** Results predating the change record no run
time, so the stamp falls back to the file's mtime and **says so**:
`Written 2026-08-19 01:38:04 EDT (file mtime; run time not recorded), host and
platform not recorded`. A fallback that reads like the real thing is the exact
failure this whole design exists to remove.

**The version string alone is not enough.** `TemporalHazard 1.2.0` exists as two
codebases — `main` without the score criterion the runners require, `dev` with
it. A result recording only `1.2.0` cannot say which produced it, and the
criterion decides what a screen selects. Record the commit; show it only when
it is there, never as empty parentheses.

It paid for itself the same day: the same document stamps
`x86_64-pc-linux-gnu, R 4.6.0` on the study server and
`aarch64-apple-darwin23, R 4.6.1` on a laptop. A report that cannot say where it
ran cannot reveal that it ran on the wrong R — and a terminal-versus-IDE R
mismatch has already changed a candidate pool in this study once.

---

## 4. A degenerate value must not print as a finding

Three instances, one rule.

- **`hr_per_iqr`** reports `NA` for a 0/1 covariate rather than a 1.0 that would
  read as "no effect".
- **Survival at a horizon** returns `NA` beyond end of follow-up rather than
  carrying the last value forward.
- **But survival of 0 is absorbing**, so it is legitimately carried forward —
  and that is where it bites. One stratum reported **0.0% ten-year survival** on
  n = 43. Traced: the curve reached zero at 9.71 years with **n_risk = 1**. Had
  that single patient been censored instead of dying, the cell would read `NA`
  at about 36%. Printed beside 55.8% in the next row, a bare `0.0` reads as a
  finding about the stratum rather than the end of its follow-up.

The fix was not to change the estimate, which is correct, but to **print the
risk set beside it**: `at risk @ 10 years` reads 0 for that cell and 29 for its
neighbour. The support for a number belongs next to the number.

**Template rule:** wherever a template reports an estimate at a horizon, a
threshold, or a ratio, ask what the degenerate case prints — and make it print
something a reader cannot mistake for a result.

---

## 5. A chunked job must declare what it expects

Each chunk records everything about itself and **nothing knows how many siblings
it was launched with**. So a pool of 12 of 25 chunks is not detectably different
from a complete run of 12: every health check passes and every frequency is
honestly computed over the wrong denominator.

Expected totals are instantiation knobs (`EXPECT_CHUNKS`, `EXPECT_BOOT`), and a
shortfall raises a callout rather than a table cell. A reader who must compare
two cells to discover a report is provisional will not discover it — and neither
will a colleague who receives the rendered `.html` with no memory of when it was
made.

**The same argument makes the planned `inst/sas/` and `inst/macros/` file-count
test correct.** A partial corpus copy and a partial chunk pool are the same
failure, and both are invisible from the inside.

---

## 6. Guards: check absence before agreement

A gate comparing recorded values across artifacts must establish the values were
recorded before comparing them. In R, `format(NULL)` is the **string** `"NULL"`,
so a field no artifact records compares equal across all of them, passes
unanimously, and hands back `NULL` as the agreed value. A step-cap guard was
vacuous in a test fixture for exactly this reason, and the suite was green.

Three language-level traps, all invisible at the call site:

- `format(NULL)` is `"NULL"`, so absent values compare equal to each other.
- `!is.null(x)` wrapped around a check turns a missing value into a skipped
  check that still reports OK.
- A command writing its error to **stdout** defeats `[ -n "$out" ]` as a success
  test. (Written into a retry loop an hour after filing the report on this
  pattern. It printed `POSTED:` followed by the error text and exited 0.)

**Test:** if every input to this comparison were missing, would it pass?

**And prefer independent read-back over the operation's own report of itself.**

---

## 7. A template must not describe a handoff that does not exist

The `bh` report stated that its retained set is what `hm` fits, and wrote
`selection_bh.csv` to make the handoff explicit. **Nothing read that file**, and
it had never been created. `%hazboot` and `%model` were parallel analyses in
SAS, not a pipeline, so the code was right and the sentence was wrong. A reader
who believed it would assume the model had been screened for reliability first.

Related: the two jobs legitimately screen different pools — `bh` main effects
only, `hm` additionally 25 interaction terms (`agee_fem` is exactly
`agee * female`). An interaction the model selects can never carry a bootstrap
reliability, and that is by design rather than a gap. Say so.

---

## 8. Small things a template should carry verbatim

- **Write the model formula literally at the call site.** Not in a variable, not
  via `as.formula()`. `hzr_bootstrap()` and `hzr_stepwise()` rewrite the stored
  formula per step; a symbol does not survive that. The screen then halts having
  selected nothing, with `n_success` at maximum and no warning.
- **A screen that selected nothing is a failure, not a finding.**
- **A free parameter must vary across resamples.** Check `sd()` of one and stop
  if it is zero; a bootstrap on the vector interface returns the original fit
  every replicate with `n_failed = 0`.
- **Quoted runtimes must name the pool they were measured on.** Cost scales with
  candidate count because every step scores every candidate: 189 → 13 h,
  226 → 19 h on the same job.
- **Never edit a script while `Rscript` executes it.** It reads and evaluates
  incrementally, so the file changes under the read position. Launch from a
  snapshot copy. This cost nine hours here.

---

## What this means for stage 3

`new_job()` and the five templates should ship with, as template content rather
than as documentation:

1. a render or run stamp, chosen per job by where the expensive work happens;
2. expected-total knobs and a provisional callout for any chunked job;
3. a concept-level reporting table, and **no pool pruning**;
4. degenerate-value handling that prints `NA` or the supporting count;
5. the guard discipline in section 6 wherever artifacts are compared.

Items 1, 2 and 4 are mechanical and belong in every template. Item 3 is specific
to jobs with a candidate pool (`bh`, `hm`). Item 5 belongs in any helper the
package ships that compares saved runs.
