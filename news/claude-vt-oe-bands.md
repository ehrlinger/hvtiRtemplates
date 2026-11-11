* `vt-fit` sets the deaths each arm had against the deaths the other arm's forest expects for the same
  patients, each followed to their own follow-up: the one-sample log-rank, with O/E, its exact interval
  (`TEST_LEVEL`, 95%) and a p-value, as `hs-concordance` has. A forest against its own arm is tested out of
  bag too, marked so, with its p-value read as a calibration check: the arm's other deaths grew it. Patients in distribution
  only, counted to `TAU`. New figures `vt-fit-expected-km` (the average expected curve, the spread of the
  patients' predictions and the Kaplan-Meier) and `vt-fit-spaghetti` (`SPAGHETTI_N`). The test is saved in
  `vt.rds` as `oe`, with `tau` and `test_level` in `settings`; `vt.rds$curves` is unchanged.
