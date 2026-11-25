- `sid-fit` takes `IMPUTE <- "none"`, for data already completed upstream, such
  as one draw of the imputation a published analysis used. It imputes nothing,
  stops naming each clustering variable that still has a missing value, and
  needs `M = 1`. The report says the data were complete as supplied, and
  `sid.rds` and the report's provenance record `"none"`. Until now a rerun that
  supplied completed data got a report describing an imputation that did not
  run (#643).

- `sid-fit` takes `SID_ARGS`, a named list of other `sidClustering()` arguments
  (`ntree.reduce`, `fast`, `dist.sharpen`) and of the `rfsrc()` arguments it
  passes on (`mtry`, `nodesize`), so a rerun can match an analysis that set
  them. It refuses the arguments the job sets itself, `formula`, `na.action`,
  the arguments that carry patient data (`x.no.sid`, `case.wt`, `samp`) and any
  name neither function takes. The arguments are written into the
  cached call and saved in `sid.rds` and the provenance. `SID_ARGS <- list()`,
  the default, makes the call the job always made, so a study's existing
  caches still load (#644). `sid-stability` does not yet refit with them.

- `sid-fit` says why it asks for randomForestSRC 3.7.0: it is the release the
  random forest templates were written against, and this job needs nothing new
  in it. randomForestSRC is in `Suggests`, so the floor gates the job, not
  installing hvtiRtemplates (#646).
