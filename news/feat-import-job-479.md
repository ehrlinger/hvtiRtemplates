* New `import_job()` brings a job from another study into the current one, keeping that study's edits, so a
  variant such as an aorta-specific `ac` job is carried forward instead of copied by hand (#479). The job is
  written where `add_job()` would write it, with the same setup: the packages, the Quarto provenance hooks and the
  refusal to overwrite. `subject` and `type` can be changed on the way in, and its runner comes with it. Nothing
  study-specific is rewritten. The message lists by line number the `DATASET`, any `WHERE` selection, every
  `EDIT:` marker and every absolute path the job carried, without quoting their values. The job keeps its
  template stamp, so `upgrade_job(import_job(from))` brings an older variant up to the current template.
* A job's setup chunk is now read for `library("pkg")`, `library(package = pkg)` and `library(pkg, quietly =
  TRUE)` as well as `library(pkg)`, so the pre-render package check and `import_job()` see packages attached
  that way. Every shipped template yields the same package list as before.
