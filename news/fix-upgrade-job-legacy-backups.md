- `upgrade_job()` moves the pair an upgrade before 1.5.1 left beside a job,
  `<job>.qmd.pre-upgrade` and `<job>-upgrade.md`, into the job folder's
  `_archive/` the next time it upgrades that job. The pair is stamped with the
  time of the upgrade that wrote it, read from the report, and an archived name
  already taken gets a `-2` suffix rather than being overwritten. A copy renamed
  by hand, such as `<job>.qmd.pre-upgrade-20261020`, is left where it is.
  It refuses, before moving anything, when two of those files would take one
  archived name, or when one sits in a folder that resolves outside the study.
