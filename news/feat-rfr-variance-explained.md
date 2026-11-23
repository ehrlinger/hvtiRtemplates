* `rfr-fit` reports the forest's variance explained under "Does the forest work?": a table of how many patients have
  an out-of-bag prediction, the out-of-bag mean squared error after the last tree, the variance of the outcome and
  one minus their ratio, the R squared randomForestSRC prints with the forest. A note explains each row, why the
  error rests only on patients with an out-of-bag prediction, and why R squared can fall below 0.
* `rfc-fit` and `rfs-fit` report the counterpart, a Brier skill score. `rfc-fit` compares the forest's out-of-bag
  Brier score with that of giving every patient the class shares; `rfs-fit` compares its integrated out-of-bag
  Brier score with that of giving every patient the cohort's Kaplan-Meier curve, scored with the same censoring
  weights, and adds the forest's out-of-bag Harrell's C beside it. Each table counts the patients with an
  out-of-bag prediction, and a note explains each row.
