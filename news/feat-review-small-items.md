- Reports now show who rendered them by name when the group's people file
  lists their login: `Pat Example (pexample)`, in the box under the title and
  in the "About this run" table. The file is YAML under `people:`, read from
  `/studies/general/administrative/hvti_people.yml` or the path in
  `HVTI_PEOPLE`. A login it does not list, or no file, shows the login alone,
  as before. The provenance JSON keeps the login and adds `user_name`.
- The `add_job()` example and the "Work a job" vignette scaffold `dc.gfup` as
  `subject = "reop", type = "hz"`, the analysis it checks, in place of
  `cohort` and `eda`. They explain that a job with an event names the event.
- `dc-trends` explains, beside `ylim`, why its limits zoom with
  `coord_cartesian()` and never with a scale limit. It also says what to do
  when a percent smooth overshoots 0 or 100 at the ends of the year range.
