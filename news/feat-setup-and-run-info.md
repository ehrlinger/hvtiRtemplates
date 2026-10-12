* Every template opens with one `setup` chunk, where it opened with four
  (`setup`, `guard-edits`, `guard-partial` and `set`). The chunk declares
  `SUBJECT` and `TYPE`, attaches the template's packages and calls one internal
  function, `.job_setup()`, which finds the study root, sources the study's `R/`
  (with `.root`, `.in` and `.provenance_data` already set, as the old chunk had
  them), runs the `EDIT:` marker and partial-render guards, checks the file name
  against `SUBJECT` and `TYPE`, and returns the root and `set_path()`. A report now
  opens with one "Code" fold instead of four, and a change to the marker guard is
  one edit instead of 34. The guard's behavior and messages are unchanged, with
  three exceptions: the draft callout's first sentence read "not" and "a result"
  run together, the `lm` and `lp` templates now print the same marker list as the
  rest (`bd` still prints only the count), and `bd`'s file-name check, which
  stopped with "bd: set (<file>): the file's name and its SUBJECT and TYPE
  disagree", now stops with the message every other template gives, "This file is
  named ... but declares SUBJECT = ... Fix the declaration or the filename". The
  bootstrap templates `bc`, `bh`, `bl` and `br` now source the study's `R/` as the
  others do. Jobs already in studies keep their four chunks and render as before;
  they gain neither the box nor the end table below. (#303)

* Every template carries `date: now` and `date-format: "YYYY-MM-DD HH:mm"` in its
  own front matter, so the title block shows when the report was rendered. (#303)

* A report opens with a one-line box under the title: whether it is final or a
  draft (with the count of open markers and skipped chunks), the data it reads,
  who rendered it and on which host, and the hvtiRtemplates version. The box is
  printed before the data are read, so it names data only when the job's file
  settles which: a literal `ANALYSIS_SET <- "name"` (with the time the set was
  written, when its sidecar says), or a literal `DATASET <- "name"`, in single or
  double quotes, with the dated version file and registration date when the
  manifest has them. When `DATASET` is `NULL`, inherited from an upstream handoff,
  computed or not declared, the box says "data: see About this run" and does not
  guess the study dataset; `bd`, which builds a dataset and reads none, names no
  data. (#303)

* Every report ends with an unnumbered "About this run" table: the run (start and
  end with time zone, duration, status, user, host), the job (file, template,
  subject, type, hvtiRtemplates version), each dataset read (name, version file,
  registration date, source file, rows and patients kept, `WHERE`, the first 12
  characters of the sha256 and whether a newer source file is waiting, each for its
  own source, a joined dataset's separately), each upstream handoff with the time
  its job rendered, the seed when the job sets `SEED`, and whether renv is active
  with the first 12 characters of `renv.lock`'s sha256. Two reads whose `WHERE`
  shows the same text because its values are masked (`age >= <value>`) are listed
  separately. The same facts are in the embedded provenance under `run`. The table
  holds names, dates, counts and hashes, never a patient identifier or a data
  value. The user and host are the login and machine names; `HVTI_RUN_USER` and
  `HVTI_RUN_HOST` replace them, and the template gallery sets both so its
  published reports name no one. (#303)

* The handoff bundles that jobs save (`hz`, `ac`, `hs`, `lg`, `lm`, `rf`, `bh` and
  the rest) now record `rendered_at`, the start of the render that saved them, as
  ISO 8601 with its time zone. The "About this run" table shows it for each upstream
  handoff, and "not recorded" for a bundle saved before this change; the file's
  modification time is never used in its place. Saving the same results again
  therefore writes a different file. (#303)

* A report that turns out to be a draft after its box was printed no longer reads
  as final. A `stop_here()` that the source scan could not see (inside an `if ()`)
  and that runs, an `lg` job with a covariate whose scale is not chosen, an
  incomplete bootstrap pool in `bc`, `bh`, `bl` or `br`, and a `dc-gfup` follow-up
  figure that was not drawn each mark the run a draft: the end table's status and the
  embedded `run` facts say `draft` (with `stopped_early` for a stop and the reasons
  under `draft_reasons`), and a callout above the table, "This run ended as a
  draft", names each reason. The box under the title is printed first and cannot
  change; the callout is what corrects it. (#303)
