* `hs-setup` derives the life tables' 0/1 male and non-white indicators from
  the study's own coding. New settings `MALE_LEVEL` and `OTHER_LEVELS` name the
  values that count as male and as non-white, so a `female` column
  (`MALE_LEVEL <- 0`), a sex factor or a race factor is used as it is, without
  first deriving the indicators by hand. Both default to 1, which leaves a job
  with 0/1 `male` and `other` columns unchanged. A level the column never takes
  stops the job, and a new table shows how each value was counted, so a race
  level left out of `OTHER_LEVELS`, and therefore counted as white, is visible
  (#183).
