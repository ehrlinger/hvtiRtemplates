* `add_job()` installs the packages a template needs into the study's library, and records them in
  `renv.lock`, when the study is a renv project. It asks first, and writes nothing if the packages cannot be had.
  It needs hvtiRutilities 1.5.6 or later, the first release with `study_need()`.
