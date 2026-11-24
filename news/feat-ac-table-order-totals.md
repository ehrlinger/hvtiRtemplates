- `life_table_at()` puts `n_risk` right after `time`, ahead of survival and
  its limits, so the count read against a horizon sits beside it in a wide
  table. The `ac` horizon tables, overall and by stratum, follow. Code that
  reads the columns by name is unaffected.
- The `ac` life tables, overall and by stratum, end each stratum on a "Total"
  row that sums its events, so the count can be checked against the cohort
  table. Only events are totalled: on an event-rows table the censored column
  leaves out patients censored after the last event.
