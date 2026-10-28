# hs-score: a start/stop model scored at each segment's start

Decided 2026-10-28 by the maintainer, closing item 4 of
[#436](https://github.com/ehrlinger/hvtiRtemplates/issues/436): **follow SAS**.

## The question

`hz` and `hm` fit a start/stop response, `Surv(start, stop, event)`, one row per
patient segment. `hp`, `hs-setup` and `hs-concordance` predict one row per
patient per horizon, which a time-varying model does not define: a patient has
a covariate row per segment, and nothing says which one to predict from.

## What SAS does

SAS has no horizon prediction for a time-varying model. Its prediction jobs read
a model fitted with one row per patient: in the HSICH study, `hp.st_dead.sas`
predicts from `est.hzstdead`, not the time-varying model.

The one thing SAS does with the time-varying model is score it,
`hs.st_dead.mort_score.tvc.sas` lines 96 to 131:

```sas
data built_pred; set built; years = iv_start;
%hazpred(proc hazpred data=built_pred inhaz=est.hmstdeadtvc_t out=built_pred; time years;);
scr_haz  = 100 * _hazard;
scr_mort = 100 * (1 - _surviv);
```

Each segment is predicted at its own start, with its own covariates, one output
row per segment.

## Decision

- **`hs-score`**, a new `hs` template, does exactly that: `predict()` on the
  reported `hm` model with `time` set to the segment's start, giving
  `scr_haz = 100 * hazard` and `scr_mort = 100 * (1 - survival)`. It stops on a
  model fitted with one row per patient, pointing to `hs-setup`.
- `hs-setup`'s horizon path is unchanged.
- `hp`, `hs-setup` and `hs-concordance` keep stopping on a start/stop fit, and
  their message now says SAS has no start/stop counterpart. `hs-setup`'s names
  `hs-score`; the other two name no alternative, because `hs-score` answers a
  different question from theirs.

## Choices made here

- **No identifier is saved.** SAS keeps `recordid`; `hs-score.rds` keeps `row`,
  the row of the selection as the job rebuilds it, and `patient`, a sequence
  number in order of first appearance, as SAS's `ptid` is. `CARRY` adds columns
  a later job needs and refuses the identifier, as `hs-concordance` does.
- **No confidence limits.** The SAS job keeps none.
- **A segment starting at zero scores `scr_mort = 0`**, as in SAS. The report
  says so, and that `scr_haz` is the score that separates patients at entry.

## At time zero

Every patient's first segment starts at zero, so the score there is the common
case. What SAS does, read from the HSICH job's own output (nothing was run):

- The time-varying model has an early phase, `parms mue=0.03782943
  thalf=0.09157124 nu=-1 fixnu m=0 fixm` (`analyses/hm.st_dead.tvc.sas:107`).
- `graphs/hs.st_dead.mort_score.tvc.log` lines 104-107 compute
  `scr_haz=100*_hazard` over all 1,490,536 rows with no missing-values note, so
  `_hazard` is non-missing on every row, the first segments included.
- `graphs/hs.st_dead.mort_score.tvc.lst` line 255: `scr_mort` has N 1,490,536
  and minimum 0. `scr_haz` is not kept in `mscp_tvl.xpt` or printed, so its
  values at zero cannot be read, only that they are not missing.

TemporalHazard 1.2.17 agrees for that shape: a fit with `nu = -1, m = 0` fixed
predicts a finite, positive hazard at zero, and survival 1. `hs-score` therefore
scores zero as it scores any other start, with no special case, and a test runs
that shape through the scoring chunk.

One shape differs: with `nu > 0` and `m = 0`, TemporalHazard returns `NaN` for
the hazard at exactly zero, though the hazard just above zero is finite. No SAS
output for that shape has been read, so `hs-score` stops there, saying so,
rather than choose a value. That is a question for TemporalHazard.

## Gate

The two-study gate was not measured. The shape is admitted from one SAS job,
read line by line, on the maintainer's decision; a census of score jobs on
time-varying models runs on the server.

## Tests

`tests/testthat/test-hs-score.R` scaffolds the job with `add_job()`, runs it
after `hz` and `hm` on a multi-segment fixture, and checks every score against
`predict()` at that segment's start on the original rows. A mutant that scores
at the stop fails the check.
