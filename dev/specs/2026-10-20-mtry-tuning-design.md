# Tuning boostmtree's `mtry` in `nb-boostmtree`

**Date:** 2026-10-20
**Status:** designed, not built. Approved in conversation 2026-10-20 (approach A, parts 1 and 2).
**Reads with:** `2026-10-01-nb-boostmtree-design.md`; hvtiRtemplates#370 (the `MTRY` study choice this builds on).
**Packages:** hvtiRtemplates.

## 1. The problem

`MTRY` (hvtiRtemplates#370) sets how many predictors `boostmtree()` tries at each
split. Its default, `NULL`, tries every one. The one study that set it, at 8,
inherited that value from an earlier analysis instead of choosing it. Nobody
on the team has guidance on the value, and a full cross-validated fit takes
hours, so comparing values by brute force is not practical.

Tuning has to be cheap. Cross-validation costs about the square of the number
of patients, and `mtry` does not reduce that cost. So the pilots that compare
candidates run on a random subsample of patients: 1,000 of 5,498 costs about
(1,000 / 5,498)², or 3%, of a full fit.

Only `mtry` is tuned. `nu` mostly trades off against `M`, which the error path
already shows. `n.knots` is left alone.

## 2. Provisional defaults, and the experiment that confirms them

Every default below is a reasoned guess. Section 6's experiment confirms or
replaces each one, and its write-up becomes the guidance behind `MTRY`.

| setting | default | reasoning | what the experiment must show |
|---|---|---|---|
| candidates | every predictor, half, a third, the square root (rounded, deduplicated; with 30 predictors: 30, 15, 10, 5) | spans the boostmtree default down to the usual random-forest values; 4 pilots | the best value lies inside the range, not at its edge |
| subsample | 1,000 patients, or every patient if fewer | about 3% of a full fit at about 5,500 patients | the ranking of candidates on the subsample matches the full data |
| pilot `M`, `NU` | 50 and 0.2 | covers about as much ground as a full fit, cheaply | the ranking is stable (no change at `M = 100`) |
| winner | lowest cross-validated error at each pilot's best M | the measure the full fit itself uses | how often the winner beats the default, and by how much |
| tie-break | the larger `mtry` | closer to the default; fewer surprises | none |

## 3. `tune_mtry()`

In hvtiRtemplates, beside `guard_long_fit()`:

```r
tune_mtry(x, tm, id, y, family, candidates = NULL, n_patients = 1000L, M = 50L, nu = 0.2,
          cores = 1L, ...)
```

- `candidates = NULL` derives the Section 2 set from `ncol(x)`. An explicit
  integer vector is used as given, after validation.
- The subsample is drawn by patient, never by row, so a patient's visits stay
  together. It draws from R's generator, so the caller seeds it (the template
  does, through `cache_fit(seed = SEED)`).
- For an ordinal or nominal response the subsample holds every level present
  in the data: a level the draw missed adds one random patient who has it. A
  pilot that never sees a level cannot fit it, and a rare level is exactly the
  one a 1,000-patient draw can miss.
- It fits one cross-validated pilot per candidate (`cv.flag = TRUE`,
  `mod.grad = TRUE`, and `cv.cores = cores`).
- It returns a list: `table`, a data frame with one row per candidate
  (`mtry`, `best_m`, `cv_error`, `chosen`), and `mtry`, the chosen value.
  `...` passes through to `boostmtree()`, for example `na.action`.
- **Failures.** If one candidate's pilot errors, its row records the error and
  the others still compete, and the table says which failed. If every pilot
  fails, it stops with the first error. It never returns a choice nobody
  measured.

## 4. In `nb-boostmtree`

- `MTRY` accepts `"tune"`, alongside a positive integer or `NULL`.
- The template calls `hvtiRtemplates::tune_mtry()` by its namespace. A job
  attaches only boostmtree, ggBoostedTrees and hvtiRutilities.
- Under `"tune"`, the fit chunk settles the tuning **before** it builds the
  fit's call. The fit's cache key and its memory check both depend on the
  `mtry` chosen, so neither can be computed first. The order is:
  1. `guard_long_fit("nb-boostmtree-mtry", ...)`, its own name, since the
     pilots are a long fit in their own right;
  2. `guard_memory()` sized for one pilot;
  3. `cache_fit("nb-boostmtree-mtry", hvtiRtemplates::tune_mtry(...), seed = SEED,
     dir = CACHE_DIR, refit = REFIT, packages = "boostmtree")`;
  4. then the fit's existing call, memory check and cache.
- `packages = "boostmtree"` is there because the pilots run inside `tune_mtry()`,
  where the key cannot see the dependency, and a boostmtree upgrade must rerun
  them. hvtiRtemplates is deliberately not keyed: a patch release should not
  rerun an hour of pilots.
- The tuning has its own cache, keyed on the data, `SEED` and the candidates,
  so changing the full fit's `M` does not rerun the pilots. The pilots report
  progress through the same `.job$progress()` as the fit.
- **An untuned job's cache key does not change.** The fit's call keeps
  `mtry = MTRY`. Under `"tune"` the chosen value is substituted into the call
  as a literal, so only a tuned fit has a new key.
- **Report.** Under `"tune"`, a table titled "Choosing mtry" lists each
  candidate's pilot error and marks the winner. The fit summary records the
  `mtry` actually used. Under a number or `NULL`, nothing changes.

## 5. Testing

- `tune_mtry()` on small simulated data (`boostmtree::simLong`):
  - it picks the lowest-error candidate;
  - ties go to the larger value;
  - the subsample keeps every patient's rows together and is reproducible with
    the same seed;
  - a failing candidate is recorded, and if every candidate fails it errors.
- The template under `MTRY = "tune"`: a test wraps `boostmtree()` and confirms
  the full fit receives the chosen value. The report table appears under
  `"tune"` and not otherwise.
- One render runs the real `tune_mtry()` end to end, so a call the job cannot
  resolve fails in the suite rather than in a study.
- An untuned job's fit call still reads `mtry = MTRY`; the tuning's stored key
  includes boostmtree's version; a cached rerender of a tuned job asks no
  memory for either the pilots or the fit; an ordinal sample holds a level
  only one patient has.
- Mutation: breaking the selection, sampling by row instead of by patient,
  dropping the level top-up, calling `tune_mtry()` without its namespace,
  dropping `packages =`, or keying the fit's memory check before the tuned
  value is substituted makes the tests fail.

## 6. The experiment (server, outside the repository)

Staged in `/studies/general/_development/` like the scaling benchmark, on two
real studies of different shapes:

- Study #1356, ordinal, 5,498 patients, mostly one echo each.
- COMMENCE, continuous mean gradient.

For each study:

1. Fit every candidate on the full data: the expensive truth.
2. Compare the subsample pilots at 500, 1,000 and 2,000 patients, and at `M` of
   50 and 100, against that truth.
3. Record whether the pilots pick the full data's winner, and how far apart
   the candidates' cross-validated errors are.

If every candidate sits within noise, the guidance is "leave the default", and
`"tune"` stays an option, not the advice. The write-up records the outcome and
updates Section 2's defaults by follow-up.

## 7. Not in scope

Tuning `nu` or `n.knots`; tuning in the boostmtree fork or in ggBoostedTrees;
any change to the default `MTRY = NULL`.
