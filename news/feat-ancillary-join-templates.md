* **Jobs can join an ancillary dataset to their cohort.** `read_job_data()`
  gains `join`, `join_vars`, `reduce` and `join_key`, and the study choices of
  every template that reads its own data gain `JOIN`, `JOIN_VARS`, `REDUCE`
  and `JOIN_KEY`, all `NULL` and without an `EDIT:` marker, so a finished job
  is unchanged. `JOIN` names one dataset registered with
  `kind = "ancillary"`, such as echoes or labs. The cohort decides the
  patients and must be one row per patient; the join keeps one row per joined
  record, keyed on that dataset's key, or one row per patient with
  `REDUCE = list(rule = "first" | "last" | "nearest", by = ...)`. A tie on
  `by` stops rather than pick one record silently. `WHERE` applies to the
  joined rows. The job's data table names the joined dataset and its rows,
  counts its records outside the cohort and the cohort patients with none, and
  names the reduction; its provenance records the joined dataset's version. A
  downstream job rebuilds the same join from its upstream job's selection.
* `read_job_data()`'s `key` now defaults to the key registered for the dataset
  (hvtiRutilities 1.5.1), and to `id` when none is registered, as before. A
  `KEY` or `JOIN_KEY` that differs from the registered key is used, and noted
  in the data table. Templates set `KEY` themselves, so they read the same
  rows as before, with that note when the study registered another key.
* A stale analysis set that hvtiRdatabuild reads in a draft render is now a
  note in the job's data table, as an out-of-date dataset already was, rather
  than a message wherever the chunk prints it.
