- `upgrade_job()` now keeps the old job and its report in an `_archive/` folder
  beside the upgraded job, as `<job>.<stamp>.pre-upgrade` and
  `<job>.<stamp>-upgrade.md`, where the stamp is the date and time of the
  upgrade. The job's folder holds only the job, Quarto renders nothing in
  `_archive/`, and the same job can be upgraded again without moving the last
  upgrade's files aside by hand.
