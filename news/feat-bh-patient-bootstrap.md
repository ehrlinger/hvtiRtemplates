* A start/stop `bh` screen resamples patients, not rows (#436). When the runner reads several rows
  per patient, it passes the patient of each row to `hzr_bootstrap(id =)`, so each replicate
  keeps every segment of each patient it draws, as SAS `%HAZBOOT _TVC=1 _IDVAR=` does. With one
  row per patient it resamples rows, as before. The runner stops before the screen on segmented
  rows fitted without their start, and the report stops on a segmented bag that resampled rows.
  The bag records which it did, as `resampled`.
* The `bh` runner, and hvtiRtemplates' suggested TemporalHazard, now need TemporalHazard 1.2.17
  or later, which added `hzr_bootstrap(id =)`
  ([TemporalHazard#667](https://github.com/ehrlinger/TemporalHazard/issues/667)).
