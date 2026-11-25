- `vt-explain`'s two stratum figures now say in their captions how many patients
  they leave out for want of a stratum, as the stratum table already did. A
  sid-clusters set run on a narrower cohort than `vt-fit` leaves some patients
  unclustered, and a figure lifted into a paper on its own gave no sign of them.
  Each figure counts its own patients: the RMST-difference figure draws every
  treated patient, the curves only those in distribution.
- A patient whose `STRATIFY` column is missing now counts as having no stratum
  in the stratum table and both figures. The table left such a patient out of
  its counts without saying so, and the curves dropped them as well.
