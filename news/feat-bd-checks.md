* The `dt` template is removed, one release after it arrived as in-flight: its checks are `bd`'s Checks section.
  A job scaffolded from it should move its choices into the study's `bd` job. The taxonomy keeps its `dt` row, so
  `job_census()` still counts the legacy SAS `dt` jobs.
