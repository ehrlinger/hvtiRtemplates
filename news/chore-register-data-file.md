* The templates, tests and gallery scripts call `register_data()` and `declare_data()` with `file =`, which
  replaced `built =` in hvtiRutilities 1.5.20, so a job no longer prints its deprecation warning on every render.
  hvtiRtemplates now requires hvtiRutilities 1.5.20, and the `bd` job checks for it.
