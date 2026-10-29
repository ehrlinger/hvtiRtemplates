* `vt-fit` and `rfs-fit` report events per candidate feature, for each arm's
  forest in `vt-fit` and for the cohort in `rfs-fit`. Below the study choice
  `MIN_EVENTS_PER_FEATURE` (default 20) the job warns and the report is marked
  draft, and a final render stops. The default is a guess with no study behind
  it; 0 reports the ratio only.
* `vt-fit` takes `ELIGIBILITY_VARS`, a separate set of variables to judge
  eligibility on: the Gower distance, the out-of-distribution features and the
  propensity comparison use it, and the arm forests keep their predictors. NULL,
  the default, judges on the predictors as before. The saved handoff records the
  set under `eligibility$variables`.
* `vt-fit` shows how far the eligibility rules overlap: patients counted by the
  exact set of rules that flag them, in each arm, and each pair's agreement with
  Cohen's kappa. The propensity common-support rule is shown beside the
  `ELIGIBILITY` methods for comparison, so the panel appears with one method too.
