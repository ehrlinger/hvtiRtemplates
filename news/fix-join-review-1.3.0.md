* **With `REDUCE`, `WHERE` on a joined column now filters the records before
  one is chosen per patient** (maintainer's decision). `REDUCE <- list(rule =
  "last", by = "echo_date")` with `WHERE <- quote(echo_type == "TTE")` keeps
  each patient's last TTE, where it used to keep the last echo and then drop
  the patient if that echo was not a TTE. A condition on cohort columns still
  filters the reduced rows. The data table shows the record filter between the
  join and the reduction, and counts the patients left with no record after
  it; the selection records the conditions in the order written.
* `REDUCE`'s `by` may name several columns, such as
  `c("echo_date", "echo_seq")`: each later one breaks a tie on those before
  it, in the rule's direction. A tie that remains still stops (maintainer's
  decision), and the message now says what tied (for `"nearest"`, records
  equally far from the target, not "the same date"), how many patients, and
  how to break it. `by` and `to` match their columns ignoring case, as every
  other column setting does.
* `nb-boostmtree` takes a long join whose visit time is only in the joined
  dataset: a `KEY` that names a joined column is checked on the joined rows.
  A `KEY` of cohort columns is checked on the cohort, as before.
* A join stops when some joined identifiers match the cohort's only once
  surrounding spaces, leading zeros or letter case are set aside, instead of
  counting those records as outside the cohort. The message gives counts
  only. A cohort row with a missing identifier stops a join as missing, rather
  than as a repeated patient. A long join keeps the cohort's identifier type.
* `key_hash` covers the joined dataset's key, so a downstream job sees that
  `REDUCE` chose a different record for a patient. `hm`, `hp` and `hs-setup`
  record the joined dataset's provenance when they rebuild a joined
  selection. A selection without a join carries no empty join fields, and a
  join's `REDUCE` and `JOIN_VARS` are recorded as resolved, so the same join
  written two ways records the same selection and `hp` accepts matching `ac`
  and `hz` hand-offs. `hp`'s mismatch message names the join settings.
* `read_job_data(one_row_per_patient = TRUE)` also stops when the rows kept
  repeat a patient, as a dataset of repeated records read whole would. Its
  refusal names the templates that take repeated records (`dc-general`,
  `dc-tables`, `dp-eda`, `dp-trends`, `nb-boostmtree`), read from the
  templates themselves. A patient whose records all lack the `by` value is no
  longer counted again as a patient with no record.
* `KEY <- ID` no longer draws a "differs from the registered key" note when
  the ID falls back to MRN on a dataset registered on its MRN.
* `stop_here()` refuses a final render itself, so one the source scan cannot
  see (inside `if ()`, or called with an argument) no longer truncates a final
  report silently; in a draft it is recorded as a partial-render stop.
* A job's name is read through knitr's `.knit.md` and `.utf8.md`
  intermediates. `dc-stddiff` asks for hvtiRpropensity 0.1.7, as DESCRIPTION
  does. The cairo probe runs once a session. `dp-gfup`'s deprecation note names
  `add_job("dc.gfup", ...)`. DESCRIPTION spells out the Heart, Vascular and
  Thoracic Institute.
