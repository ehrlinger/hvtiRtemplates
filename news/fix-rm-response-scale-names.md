* `rm-linear` and `rm-balancing_continuous` read a named `RESPONSE_SCALE`, such
  as one looked up with `scales["outcome"]`, as its value. Before, a named
  `"identity"` fitted `log()` while the report read the coefficients as
  measured, and a named `"log"` was read as measured and left the residual
  axes unlabeled.
