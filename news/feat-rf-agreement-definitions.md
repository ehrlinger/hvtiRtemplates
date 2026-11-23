* `rfs-fit`, `rfc-fit` and `rfr-fit` now define the learning curve's two agreement measures where the table and figure
  first use them: Jaccard, from 0 (no top variable shared) to 1 (the same set), with the steps it can take for the
  top `LEARNING_TOP_K`, and Kendall tau, from -1 (order reversed) through 0 (no relation) to 1 (the same order). The
  stability figure carries a dashed line at 0 and its caption both ranges. The error figure draws a box per fraction
  from the 15th to the 85th percentile of its refits, with a line at the median.
* The three rf fit templates print a recommendation under the learning curve, as an advisory callout that never stops
  the render. **Events** reads the rightmost point: enough when Jaccard and Kendall tau both reach
  `LEARNING_AGREEMENT` (new `EDIT:`, default 0.8, a cautious start) and have levelled off; borderline when they reach
  it but are still rising, rest on fewer than 50 events, or read an optimistic point; not yet otherwise. **Predictors** compares the candidate
  count with `MIN_PREDICTORS` (new `EDIT:`, default 10): under it, the report suggests fitting the matching
  regression model (Cox, logistic or linear) alongside before relying on the forest.
