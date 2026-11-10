* New in-flight template `sid-stability` (`add_job("sid", subject, type, qualifier = "stability")`), the third job in a
  SID set. It rebuilds `sid-fit`'s distance over `REPEATS` new seeds: the same M forests on the same completed
  datasets (read from `sid-fit`'s caches and checked against fingerprints `sid-fit` now records in `sid.rds`, never
  imputed again), averaged as `sid-fit` averages them. It runs PAM as `sid-clusters` does, and compares every refit with the reported groups:
  adjusted Rand index (with and without label matching), how often each group is found and its Jaccard overlap, where
  a group's patients go when no refit finds it, a co-association heatmap with PAC, an optional `TRACK` share per group,
  and, with `DROP_VARS`, a second set of refits without the named clustering variables. Each refit is cached on its own,
  so an interrupted run resumes. Built from one study's 50-seed stability analysis; a second study ships it.
