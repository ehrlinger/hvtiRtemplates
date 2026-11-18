- `vp-dependence`'s coverage gate no longer stops a small study on one unexamined variable. It stopped when the
  unexamined were more than `MAX_UNTESTED`'s share of the variables, and at the default 0.1 that allowed none at
  10 variables or fewer: a nine-variable cohort stopped at the template's own 1,000 trees, with one variable left
  without a release rule. A new study choice, `MIN_UNTESTED <- 1`, is a floor under that allowance, so the render
  now stops only when the unexamined pass both the share and the count. From 11 variables up the share allows at
  least one and nothing changes. `MIN_UNTESTED <- 0` restores the old rule. **A job already in a study is a copy
  of the old template** and keeps the old gate until it is re-copied or edited. `vp-fit` keeps its share-only
  gate, which `ggRandomForests::varpro_coverage()` applies.
