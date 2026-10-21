* `hz`, `hm` and `hs-setup` now draw a figure in their own report, so each step
  can be checked before the next job reads it. `hz` draws its fitted survival
  over the Kaplan-Meier estimate of the rows it fitted (`hz-fit`). `hm` draws
  observed against expected events in each group of predicted risk
  (`hm-calibration`). `hs-setup` draws the cohort's model-predicted survival
  against the matched population's, on a grid out to the last horizon
  (`hs-setup-expected`). Each is saved through the job's `save_figure()`
  under the new `SAVE_FIGURES` and `FIGURES` study choices. Existing jobs are
  unchanged until they add the figure chunk and those two choices.
