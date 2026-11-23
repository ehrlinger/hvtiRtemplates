- A `JOIN` without `REDUCE` no longer drops cohort patients who have no joined record (#613). It was an inner
  join, so "Rows kept" counted only the matched patients, and only the data table's count of "Cohort patients
  with no joined record" said that any were lost. The cohort now decides the patients in the long form as it
  does under `REDUCE`: a patient with no record keeps one row, with the joined columns missing.
  `read_job_data()` gains `keep_unjoined = TRUE`. `mm`, `rhf-fit`, `nb-boostmtree_fit` and `nb-boostmtree`
  model the joined records themselves, so they pass `FALSE` and leave those patients out. The data table says
  so, and each of the four prints how many patients it left out, returned as `unjoined`. **A job already in a
  study is a copy of the old template**: an `mm`, `rhf-fit` or `nb-boostmtree*` job with a `JOIN` and no
  `REDUCE` now reads those patients with their time missing, and `mm` stops on the missing `TIME`. Add
  `keep_unjoined = FALSE` to its `read_job_data()` call, or re-copy the job.
- A `JOIN` keeps every variable label (#614). Selecting rows dropped the `label` attribute of every plain
  column, so a joined `dc-eda` report warned that every variable lacked a label and showed raw column names.
  The labels of the cohort and of the joined dataset now survive, with or without `REDUCE`.
- `sid-clusters` can take its letters at K from an earlier assignment of the same patients (#611).
  `COLLAPSE` names letters that the lineage rule chose for this render, so a collapse copied from a published
  analysis could merge clusters other than the ones it named, without warning. A new study choice,
  `REFERENCE <- list(dataset = "<registered>", col = "<column>")`, matches each cluster at K to the reference
  group it shares the most patients with: best Jaccard, one to one. A table reports each match. `COLLAPSE` set
  with neither `REFERENCE` nor `OVERRIDES` at K now warns. The `OVERRIDES` comment says that PAM numbers go
  stale after a refit, and shows where to read them.
