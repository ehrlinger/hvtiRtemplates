- `vp-dependence` draws its noise columns by kind in proportion to the variables, with at least one of each kind
  present, instead of half categorical whenever any variable is categorical. With one factor among 31 variables,
  half and half made 10 of the 20 columns binary copies of that factor, and they took nearly half the forest's
  rules. `NTREE` and `MAX_TREE` are now 1,000 (were 500), and `MAX_UNTESTED` now defaults to 0.1 (was `NULL`), so
  a render stops when more than a tenth of the variables get no release rule. In simulations at the new defaults
  every variable got a rule at every seed. The lasso takes about twice as long as at 500 trees. **A job already in
  a study is a copy of the old template and changes only when it is brought up to date with `upgrade_job()`. One
  that is will draw different noise columns and more trees, so its bar and graph change, and it stops at its
  cached fit until `REFIT <- TRUE`.**
