- `nb-boostmtree_fit` and `nb-boostmtree_explain` need ggBoostedTrees 0.10.3.
  In 0.10.2 `boost_shadow()` refused every labeled covariate as varying within
  subject, so on data read from SAS the fit job stopped at its fit chunk. A
  study with 0.10.2 installed is now stopped at setup, with the install line
  for 0.10.3.
