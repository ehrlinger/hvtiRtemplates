* `nb-boostmtree` is split into two jobs, as `rfs-fit` and `rfs-explain` are. `nb-boostmtree_fit` fits with five
  shadow copies of every predictor (`K_SHADOW`), optionally refits under other seeds (`N_REFITS`), reports the
  plateau of iterations within 1% of the lowest cross-validated error beside Best M, records the boostmtree,
  randomForestSRC and ggBoostedTrees versions, and saves `nb-boostmtree_fit.rds`. `nb-boostmtree_explain` reads
  it, never fits, runs importance `N_VIMP` times on each fit and pools the runs with ggBoostedTrees 0.10.2, reporting
  how often each predictor cleared its run's noise band; it warns when boostmtree or randomForestSRC differ from the
  fit's. Both need boostmtree 2.0.13 and ggBoostedTrees 0.10.2. `nb-boostmtree` is deprecated and goes in the
  release after; `migrate_job()` writes `nb-boostmtree_fit` and its warning names `nb-boostmtree_explain`, and
  `upgrade_job()` keeps an existing job on its own template.
* The nb end-to-end render tests print Quarto's own error output when a render fails (#493).
