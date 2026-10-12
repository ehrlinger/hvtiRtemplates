* Every template opens with one `setup` chunk, where it opened with four
  (`setup`, `guard-edits`, `guard-partial` and `set`). The chunk declares
  `SUBJECT` and `TYPE`, attaches the template's packages and calls one internal
  function, `.job_setup()`, which finds the study root, sources the study's `R/`,
  runs the `EDIT:` marker and partial-render guards, checks the file name against
  `SUBJECT` and `TYPE`, and returns the root and `set_path()`. A report now opens
  with one "Code" fold instead of four, and a change to the marker guard is one
  edit instead of 34. The guard's behavior and messages are unchanged, with two
  exceptions: the draft callout's first sentence read "not" and "a result" run
  together, and the `lm` and `lp` templates now print the same marker list as the
  rest (`bd` still prints only the count). The bootstrap templates `bc`,
  `bh`, `bl` and `br` now source the study's `R/` as the others do. Jobs already
  in studies keep their four chunks and render as before.

* Every template carries `date: now` and `date-format: "YYYY-MM-DD HH:mm"` in its
  own front matter, so the title block shows when the report was rendered.

* A report opens with a one-line box under the title: whether it is final or a
  draft (with the count of open markers and skipped chunks), the dataset and its
  dated version file with the date it was registered, who rendered it and on which
  host, and the hvtiRtemplates version. The box is printed before the data are
  read, so it names the dataset the job's file declares with
  `DATASET <- "name"` and otherwise the study dataset.

* Every report ends with an unnumbered "About this run" table: the run (start and
  end with time zone, duration, status, user, host), the job (file, template,
  subject, type, hvtiRtemplates version), each dataset read (name, version file,
  registration date, source file, rows and patients kept, `WHERE`, the first 12
  characters of the sha256 and whether a newer source file is waiting), each
  upstream handoff, the seed when the job sets `SEED`, and whether renv is active
  with the first 12 characters of `renv.lock`'s sha256. The same facts are in the
  embedded provenance under `run`. The table holds names, dates, counts and
  hashes, never a patient identifier or a data value. The user and host are the
  login and machine names; `HVTI_RUN_USER` and `HVTI_RUN_HOST` replace them, and
  the template gallery sets both so its published reports name no one.
