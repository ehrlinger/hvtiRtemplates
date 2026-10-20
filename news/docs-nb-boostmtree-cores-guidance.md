* `nb-boostmtree`'s `CORES` choice now says what to set it to. Its comment
  carries a table, measured on the server, of peak memory at `M = 10` and
  hours scaled to `M = 1000`, by patients and cores, with the smallest session
  each needs. The cross-validated fit's parallel share levels off near 80%, so
  speed stops improving past 4 to 5 times, and memory is what limits `CORES`
  on a large study: at 4,000 patients and `M = 10`, 4 cores needed about 70 GB
  and 8 ran out. The fit itself keeps every step, so memory grows with `M`
  and the sessions are a floor at `M = 1000`, not a fit.
