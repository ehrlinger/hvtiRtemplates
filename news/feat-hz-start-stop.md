* `hz` fits a start/stop response, SAS `lcensor <start>; time <stop>; event <e>;`, the layout
  HAZARD uses for time-varying covariates (#436). Set `START` beside `TIME` and `EVENT`, and
  `KEY <- c(ID, START)`, and the fit takes `Surv(START, TIME, EVENT)`: one row per patient
  segment, each contributing H(stop) − H(start). `hz` stops when `KEY` leaves out the start,
  which would collapse the segments, and when a segment does not start before it stops.
  `EXPECTED` then counts rows, as SAS counts observations.
* The start travels in `hz.rds`'s selection, and `hm` builds `Surv(START, TIME, EVENT)` from it
  with no edit. `hm` stops on a response that drops the start: fitted without it, every segment
  is followed from time zero, a different model that converges without complaint.
* A start/stop `bh` screen stops, in the runner before `hzr_bootstrap()` and in the report on a
  bag with several rows per patient. `hzr_bootstrap()` resamples rows, which splits a patient's
  segments across replicates; SAS `%HAZBOOT _TVC=1 _IDVAR=` resamples patients. It waits on
  [TemporalHazard#667](https://github.com/ehrlinger/TemporalHazard/issues/667).
* `hp` and `hs-setup` stop on a start/stop fit. They predict one row per patient per horizon,
  which a time-varying model does not define, and the rule to use instead is still open (#436).
