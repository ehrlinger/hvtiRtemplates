* `nb-boostmtree`'s setup chunk, when boostmtree is missing or too old, now
  gives the install line for boostmtree 2.0.8 (`v2.0.8-ccf`). Its partial
  effects walk the boosting steps one at a time instead of holding every step
  for every patient at once, and match each distinct time vector to the fitted
  grid once: on a synthetic ordinal fit, one `partial.plot()` call fell from
  87 s and 4.5 GB to 2.4 s and 0.4 GB, with results unchanged. The floor stays
  at 2.0.4.
