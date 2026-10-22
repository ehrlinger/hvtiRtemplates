- `add_job()` now records the template's SHA-256 in the job's stamp, beside the template and package version. A version
  names a range of texts (nine for `nb.boostmtree` at 1.4.1); the hash names the one the job was copied from, which
  the coming three-way merge in `upgrade_job()` needs as its base. The package ships the archive of every template
  text on `main` since stamping began, in `inst/extdata/template-history.rds` (about 140 KB).
