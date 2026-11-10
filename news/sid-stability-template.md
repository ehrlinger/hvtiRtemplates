* New in-flight template `sid-stability` (`add_job("sid", subject, type, qualifier = "stability")`), the third job in a
  SID set. It grows the SID forest again over `REPEATS` seeds on `sid-fit`'s patients and first imputation (read from
  its cache, never imputed again), runs PAM as `sid-clusters` does, and compares every refit with the reported groups:
  adjusted Rand index (with and without label matching), how often each group is found and its Jaccard overlap, where
  a group's patients go when no refit finds it, a co-association heatmap with PAC, an optional `TRACK` share per group,
  and, with `DROP_VARS`, a second set of refits without the named clustering variables. Each refit is cached on its own,
  so an interrupted run resumes. Built from one study's 50-seed stability analysis; a second study ships it.
