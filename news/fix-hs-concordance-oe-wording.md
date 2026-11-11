* `hs-concordance` no longer says a model fitted on the tested deaths makes O and E depend on each other.
  They always do, through each patient's own follow-up; the test rests on O - E against a fixed reference,
  and a model that learned those deaths is not one: its fit looks better than it is and the p-value has no
  valid reference distribution.
* `hs-concordance` and `vt-fit` now say beside the O/E result that a large p-value is not evidence of
  agreement: a small group rarely rejects even a poorly calibrated model.
