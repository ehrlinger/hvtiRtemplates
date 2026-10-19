* `nb-boostmtree` runs its cross-validated fit on several cores, through a new
  study choice, `CORES` (4, or 1 on Windows, which cannot fork). The fit's cost
  grows with the square of the number of patients, and most of it now runs in
  parallel: at 600 patients, 4 cores fit 3.3 times faster than before. The fit
  is identical on any number of cores, so `CORES` is left out of the cache
  key and changing it never forces a refit. This needs `boostmtree` 2.0.4 from
  the CCF fork (`v2.0.4-ccf`), which the setup chunk now requires. A job
  scaffolded before this change keeps its own copy of the fit call, so its
  cached fit is unaffected until the job is upgraded; the first render after
  an upgrade finds the cached fit stale and stops until `REFIT = TRUE`,
  because the call itself changed. The upgraded job also carries `CORES` under
  its own `EDIT:` marker, so it renders as a draft until the marker is
  resolved.
