* Two regression-model templates: `rm-balancing_continuous`, a least-squares
  balancing score for a continuous exposure, and `rm-linear`, an ordinary
  least-squares outcome model. Both pool stacked imputations with Rubin's
  rules. They need `hvtiRpropensity` 0.2.0, and the `lm` templates, `dc-stddiff`
  and `lp-mirror` now ask for it too.
