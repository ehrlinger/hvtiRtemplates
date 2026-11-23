- A `JOIN` without `REDUCE` no longer drops cohort patients silently (#613). It was an inner join, so a
  one-row-per-patient file, such as age at the index echo, cut the cohort to the patients it had a row for,
  and only the data table's count of "Cohort patients with no joined record" said so. `read_job_data()`
  gains `keep_unjoined`, whose default, `NULL`, decides by the join's type. A wide join, keyed on the ID
  alone, now keeps every cohort patient, a patient with no row having the joined columns missing. A long
  join, of repeated records such as echoes, still keeps only the patients with records, since its rows are
  the records, but now says how many it left out: in the data table, in `unjoined`, and in a sentence in the
  report of every template that takes a long join (`dc-eda`, `dc-general`, `dc-tables`, `dc-trends`, `mm`,
  `rhf-fit`, `nb-boostmtree_fit` and `nb-boostmtree`). `TRUE` or `FALSE` overrides the default. A job
  already in a study reads as it did, except that a wide join now keeps every cohort patient.
- A `JOIN` keeps every variable label (#614). Selecting rows dropped the `label` attribute of every plain
  column, so a joined `dc-eda` report warned that every variable lacked a label and showed raw column names.
  The labels of the cohort and of the joined dataset now survive, with or without `REDUCE`.
- `sid-clusters` can take its letters at K from an earlier assignment of the same patients (#611).
  `COLLAPSE` names letters that the lineage rule chose for this render, so a collapse copied from a published
  analysis could merge clusters other than the ones it named, without warning. A new study choice,
  `REFERENCE <- list(dataset = "<registered>", col = "<column>")`, matches each cluster at K to the reference
  group it shares the most patients with: best Jaccard, one to one. A table reports each match. `COLLAPSE` set
  with neither `REFERENCE` nor `OVERRIDES` at K now warns, and with `REFERENCE` it stops on a letter no
  cluster matched. The `OVERRIDES` comment says that PAM numbers go
  stale after a refit, and shows where to read them.
