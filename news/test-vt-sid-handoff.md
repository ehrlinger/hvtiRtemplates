- A test now runs the whole morphology-paper chain in one study: `sid-fit`, then
  `sid-clusters`, then `vt-fit` with `ELIGIBILITY = "sid"`, then `vt-explain`
  with `STRATIFY = list(set = ..., column = "group")`. It proves that each job
  finds the file the one before it wrote, and that all of them label patients
  with the same study-keyed ID digests. Until now the `sid` eligibility method
  was tested only against hand-built files, and no test drove a `STRATIFY` that
  names a sid set.
