* `hm` offers each covariate only to the phases whose block names it. It built
  one formula from every block, so every covariate entered every phase and the
  estimates were not comparable with the SAS model it replaces (#171). A block
  naming a phase the `hz` fit does not have now stops the job.
* `hm` no longer needs a companion SAS job: with `SAS_JOB <- NULL` the
  covariates are listed per phase in R, and the covariate table says which
  source was used (#178).
