- `sid-stability` measures its refits against `sid-clusters`' `REFERENCE` too,
  when that job set one: the adjusted Rand index against the reference's
  groups beside this rerun's own, and each reference group's Jaccard overlap
  across the refits. Refits are matched to the reference groups by the
  patients they share, never by letter, and collapsed as `COLLAPSE` collapses
  the reference. `sid-clusters` now saves each patient's reference group in
  its handoff, so the two jobs read the reference once and cannot disagree
  (#623).
- `sid-clusters` takes `PAM_ON <- "profile"` to run PAM on the matrix of SID
  distances, as some earlier analyses did, in place of the SID distance
  itself (`"sid"`, the default). `sid-stability` reads the choice from
  `sid-clusters.rds`, so its refits always use the same metric, and caches
  profile refits under names of their own (#629).
- `sid-stability`'s `TRACK` takes one level of a coded column,
  `TRACK <- list(var = "<column>", level = 2)`, beside a 0/1 column as
  before, and its tables name the level (#624). `TRACK` refuses an identifier
  column, whose name and level would otherwise print in the tables and figure.
- `sid-stability` reports each refit to `job_status()` and the render log as
  done of total with an estimate of the time left, counting only refits that
  fit, not ones read from the cache (#622). The templates README adds the rule
  for new templates with long loops.
- Studies' existing copies of `sid-clusters` and `sid-stability` run
  unchanged. A `sid-clusters.rds` written before this release refits on the
  SID distance with no reference, and refits cached before it still load.
- **Upgrade `sid-stability` with `sid-clusters`.** A study copy of
  `sid-stability` from before this release reads none of the new choices, so
  once an upgraded `sid-clusters` sets `PAM_ON <- "profile"` or
  `CLUSTER_METHOD <- "hclust"`, the old copy refits with PAM on the SID
  distance. Then it compares those refits with groups found another way, with
  no error, and the mismatch reads as instability. It also ignores a
  `REFERENCE`. Run `upgrade_job()` on both jobs together.
