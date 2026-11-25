- `sid-clusters` takes `CLUSTER_METHOD <- "hclust"` to cut one
  complete-linkage tree of the SID distance at each K,
  `cutree(hclust(as.dist(D)), k)`, which is the `$clustering` that
  randomForestSRC's `sidClustering()` returns when given `k`. An analysis that
  reported those clusters can now be rerun like with like. `"pam"`, the
  default, is unchanged. The silhouette and the elbow come from the chosen
  fits, the elbow being the tree's height at K under `"hclust"`, and the
  report says which method ran. `"hclust"` with `PAM_ON <- "profile"` stops:
  the profile distance reproduces a PAM analysis, and `sidClustering()` cuts
  the SID distance itself (#642).
- `sid-stability` reads the method from `sid-clusters.rds`, so its refits cut
  the distance the same way, and caches hclust refits under names of their
  own. A `sid-clusters.rds` written before this release refits with PAM, and
  PAM refits cached before it still load.
  A study's copy of `sid-stability` from before this release does not read
  the method and refits with PAM, so upgrade it (`upgrade_job()`) before
  rendering it on clusters made with `"hclust"`.
