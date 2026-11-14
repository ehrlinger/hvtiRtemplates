- `vp-fit` and `vp-dependence` now impute missing predictor values once, by random forest and without the
  outcome, before the screen (`NA_ACTION <- "na.impute"`), instead of dropping every patient with a missing value,
  which varPro did silently whatever `na.action` it was given. **Existing jobs will use more patients and may
  select differently on their next render.** Set `NA_ACTION <- "na.omit"` to keep complete cases. A predictor
  missing in more than `MAX_MISSING` (0.4) of the patients is refused, not imputed, and a patient missing the
  outcome is dropped and counted either way. The missing-values table now gives patients supplied, imputed or
  dropped, and used.
- The vp reports now keep a variable the screen did not examine apart from one it examined and did not select.
  `vp-fit`'s refit vote counts only the refits that tested a variable (`MIN_TESTED_SHARE`), `MAX_UNTESTED`
  defaults to 0.1 (was 0.5), and `vp.rds` names the variables not examined, which `vp-explain` and `vp-individual`
  report as such.
- `vp-dependence` exposes `uvarpro()`'s rule limits (`MAX_TREE`, `MAX_RULES_TREE`), reports which variables the
  forest built no rule for, and names them in `dependence.rds` as `not_examined`. Its stability shares count only
  the refits that examined the variable concerned, so the signal table gains a `refits` column and a share can be
  `NA`. `MAX_UNTESTED` is available there but off by default: on wide data the noise columns take most of the
  rules, and a redesign of the noise draw comes first.
