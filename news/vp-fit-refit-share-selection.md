* vp-fit now hands vp-explain the variables selected in at least `SELECT_SHARE` (default 0.5) of its
  stability refits, instead of the full fit's selection. One fit's noise bar is the best of a few noise
  columns, and on a small cohort it moves with the noise draw: on a 58-event screen the full fit selected 16
  candidates, most of them binary variables just over a low categorical bar, while a majority of 20 refits
  selected 4. `SELECT_SHARE <- NA`, or `REPEATS <- 0`, keeps the full fit's selection. The coverage table and
  the funnel still report the full fit, and the stability chunk names the set it hands on.
* vp-individual's coverage table now marks the handoff's selection, so its `selected` column agrees with the
  variables it draws by default. vp-explain says when a selected variable is left out because the saved full
  fit did not test it, and stops with that reason, not "selected none", when no variable is left to draw.
