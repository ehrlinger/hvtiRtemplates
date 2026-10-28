* New template `hs-score` scores each start/stop segment with the time-varying
  `hm` model at the segment's own start, as the SAS `hs.*.mort_score.tvc` jobs do:
  `scr_haz` is 100 times the hazard there, and `scr_mort` is 100 times one minus
  the survival, one row per segment (#436). It saves a row and patient number,
  never the identifier, and stops on a model fitted with one row per patient.
* `hp`, `hs-setup` and `hs-concordance` still stop on a start/stop fit, and now say
  why: SAS has no start/stop counterpart for their predictions. `hs-setup`'s
  message points to `hs-score`.
