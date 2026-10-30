* `vp-fit` now stops when more than `MAX_UNTESTED` of the real candidates went untested, 0.5 by default, so a screen
  that tested too little cannot read as one that found no effect. Its importance figure draws the noise bar the
  coverage table judged each variable against, in place of varPro's fixed 0.79 cutoff. The job needs
  ggRandomForests 4.0.0-rc12 or later, and says so when it finds an older build.
