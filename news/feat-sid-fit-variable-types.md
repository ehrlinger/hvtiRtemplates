- `sid-fit` takes `FACTORS`, the clustering variables to treat as categories
  rather than numbers, such as a graded degree or a coded class. They become
  factors before the missing values are counted and imputed, are listed in the
  "What the forests were grown on" table and are saved in `sid.rds`, so
  `sid-stability` refits on the same types. `FACTORS <- NULL`, the default,
  keeps every variable that is not text a number, as before, so a study's
  existing copy reads unchanged and its caches still load (#610).
