* New `upgrade_job()` rewrites a job from the current version of its template
  and carries the study's choices across: the upper-case assignments in its
  `edit-*` chunks, multi-line values included. A choice the current template
  no longer has is kept in the job, commented out under an `EDIT:` marker, and
  the `-upgrade.md` report beside the job lists what was carried, not placed and
  new, and which chunks to review, by name and never by value. The old job is
  kept as `<file>.pre-upgrade` (#307).
* `add_job()` now stamps each job with the template and package version it was
  copied from, as one HTML comment after the front matter, which
  `upgrade_job()` reads.
