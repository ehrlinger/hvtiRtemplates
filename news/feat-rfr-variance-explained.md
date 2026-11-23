* `rfr-fit` reports the forest's variance explained under "Does the forest work?": a table of how many patients have
  an out-of-bag prediction, the out-of-bag mean squared error after the last tree, the variance of the outcome and
  one minus their ratio, the R squared randomForestSRC prints with the forest. A note explains each row, why the
  error rests only on patients with an out-of-bag prediction, and why R squared can fall below 0.
