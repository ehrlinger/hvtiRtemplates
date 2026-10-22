* New templates `sid-fit` and `sid-clusters` (in flight). `sid-fit` fills
  missing values by mice or forest imputation, `M` times, grows one seeded
  SID clustering forest on each and averages their distances. It saves them
  keyed by a study-keyed digest of the patient ID, never the ID.
  `sid-clusters` runs PAM on that distance over a range of K, reports the
  elbow and silhouette, gives letters that keep their identity across K,
  saves the chosen solution for `vt`, and registers the assignments so a
  later job can `JOIN` them. The `sid` prefix
  is now qualified, so `add_job("sid", ...)` needs `qualifier = "fit"` or
  `"clusters"`.
