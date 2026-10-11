* New template `lp-mirror`, the mirrored histogram of the propensity score:
  `add_job("lp.mirror", subject, type)` with the subject and type of the
  `lm-propensity_binary` job it plots. It reads that job's saved bundle and
  never refits, drawing treated patients above the axis and controls below:
  all patients, then under the matching weights, and, when `MATCH` names a
  pair-match column, the matched patients. The y-axis is derived from the
  counts, the same above and below. The groups are labeled by the declared
  treatment levels, or by `GROUP_LABELS`. A bundle without lineage, or whose
  rebuilt read has different rows, patients or patient hash, stops with the job to render again.
  `MATCH` is joined onto the scored patients by a study-keyed digest of `ID`,
  so the job keeps and prints no identifier; it counts the scored patients
  with no flag and the flags with no score, and stops when fewer than half
  the scored patients are in the dataset, when `MATCH` is not a column coded 0 and 1 or flags no
  scored patient, and when a score, weight or group is missing. `lp` becomes a qualified prefix.

* `lm-checkpred`'s `MODEL_FILE` and `MODEL_SET` checks are now shared with
  `lp-mirror`. An `NA` in either now stops with the setting's own message
  rather than an R error.
