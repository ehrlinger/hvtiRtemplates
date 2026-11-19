* `DESCRIPTION` now asks for ggRandomForests 4.0.1, the first release that exports `gg_learning()` and
  `learning_subsample()`. The `rfs-fit`, `rfc-fit` and `rfr-fit` learning curves need both, and 4.0.0, which the
  floor used to admit, stops those templates with "This job needs a ggRandomForests with gg_learning() and
  learning_subsample()". A new CI job, `family-floors`, tests the package against every hvtiR family floor
  `DESCRIPTION` declares, and found the gap.
