* `upgrade_job()` now carries a study's own comment above a choice, such as the reasons for leaving variables out
  of `PREDICTORS`, into the upgraded job, directly above the choice and below the current template's comment. A comment set off from the choice by a blank
  line counts too.
  It used to drop those lines and only name them in the report, so a study's rationale had to be restored by hand
  from the archived job. A comment line is the study's when no version of the template in
  `inst/extdata/template-history.rds` has it in that chunk, so the template's own earlier wording is still left
  behind. The report names the old lines carried and never quotes them. A job whose only edits are such comments
  is now current with its template, and an upgrade leaves it alone.
