* `nb-boostmtree` reports each boosting iteration and each partial-effect prediction to
  `<job>.run.progress` and the render log, so `job_status()` can say how far a fit has got
  and how long its stage has left. It needs boostmtree 2.0.8. Existing jobs need not
  change: they still report stages, and adding these lines to one means refitting it.
