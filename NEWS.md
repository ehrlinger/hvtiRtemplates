# hvtiRtemplates 1.5.2

* hvtiRtemplates now needs hvtiRutilities 1.5.15 or later. 1.5.15 adds the `rhf` row to
  `hvti_taxonomy()`, which this package re-exports, so the taxonomy classifies the prefix of
  the new `rhf-fit` and `rhf-explain` templates. 1.5.13 reads a label file's unquoted `No` and `Yes` as the text
  written, so a `value_labels.yml` declaring `0: No` / `1: Yes` prints No and Yes in a table
  rather than FALSE and TRUE. 1.5.1 asked for that release in its NEWS but declared only
  `>= 1.5.12`.

* The `ac` template's figures now mark each event with a point and join the points with straight
  lines, as the SAS `%KAPLAN` figures do. Set `STEPS <- TRUE` in a job for the Kaplan-Meier steps instead;
  the points stay either way. On the manuscript figure the line joins the events alone, so a censored
  time no longer puts a corner where survival did not change.
* Under the straight lines, a `CI_TIMES` bar stands at the last event at or before its time, where the line
  passes through the estimate the bar's limits bracket. The limits are still the horizon table's, but with
  sparse events a bar can stand well left of the time asked for. With `STEPS <- TRUE` a bar stands at its time.

* `officer` in Suggests now carries a floor, `>= 0.6.0`, the same as hvtiPlotR and
  hvtiRtables. The dc-tables Word output writes custom document properties with
  `officer::set_doc_properties(values =)`, which older officer releases do not accept.

* Every template in the gallery now has a run sheet, a page linked from its row beside "Then run it". The
  sheet outlines the job, and the template keeps the details. It says what to have ready, such as the
  registered data (a draft can read an unregistered build and a final render cannot), the jobs to render
  first in the same set, a bootstrap runner and the package floors. A saved result the job reads only when
  a choice asks for it, such as `vt-fit`'s screen or `hm`'s selection runner, is said as optional. It lists the job's own sections with
  what each one does, says how to run the job (in the background with `hvti run` when the fit is guarded as
  long) and names the jobs that read what it saves. Every sheet is generated from its template, so it
  cannot drift from it. The catalog's `upstream` now names what `lm-checkpred`, `vt-fit` and `vt-explain`
  read, and narrows `lp-mirror`'s to `lm-propensity_binary`.

* New in-flight templates `rhf-fit` and `rhf-explain`: a random hazard forest (randomForestRHF) on counting-process rows, one row per interval of a patient's follow-up, so a predictor may change over time. `rhf-fit` checks the rows before fitting and stops on an overlap, an interval of zero length, an event before a patient's last interval, or a missing predictor, naming the first few patients, unless the ID is an MRN, when it names row positions; `REPAIR <- "clip"` repairs the first two kinds and `"drop_na"` the last, in a draft while the dataset fix is in flight, and a final render refuses either. An event before the last interval has no repair. It tunes the tree size and saves `rhf.rds`. `rhf-explain` reads it and reports cumulative and incident AUC(t), out-of-bag hazard curves and VarPro importance at points across follow-up, caching the VarPro cache as `rhf-varpro-cache`. Patients are numbered 1 to n before the fit, so the saved forest holds no study identifier.
* `read_job_data()` has a `whole_patients` argument. With `TRUE` it stops when `where` keeps some of a patient's rows and drops others, which would shorten follow-up without a word.

* `rfs-explain`, `rfc-explain` and `rfr-explain` can draw 95% subsampling intervals on VIMP (randomForestSRC's
  anti-split importance) and pointwise bands on the partial-dependence plots. Set `BANDS_B` to the number of subsample
  forests (0, the default, draws none); `SUBRATIO`, `BAND_STYLE` (`"ribbon"` or `"bars"`) and `BAND_AT` tune them. The
  bands are cached per variable and run for hours at study size, so submit the job with `submit_job()`. The importance
  interval is the figure's own estimate plus and minus 1.96 jackknife standard errors taken about that estimate.
* The importance figure and table captions in `rfs-explain`, `rfc-explain` and `rfr-explain` now call the quantity VIMP
  (anti-split importance), which is what `vimp()` computes here, and not permutation importance.
* `guard_long_fit()` takes several cache names and refuses while any of them is missing.

* `vt-fit` shows the observed outcome before any model: Kaplan-Meier by arm with 70% confidence limits,
  the numbers at risk, and a table of each arm's patients, events and survival at `HORIZON`
  (`vt-fit-km`).
* `vt-fit` checks each arm forest's calibration at `HORIZON`: out-of-bag predicted survival in fifths
  against Kaplan-Meier, with one mean error per arm in percentage points (`vt-fit-calibration`). A fifth
  whose follow-up ends before `HORIZON` shows no observed survival and is counted rather than extrapolated. The
  C-index says whether a forest ranks patients; calibration says whether its survival is the right
  level, which is what an RMST difference compares. The table is saved in `vt.rds` as
  `settings$calibration`.
* `vt-fit` gains the `ORDINAL` study choice: graded predictors coded as numbers are ranked in the Gower
  distance, so a grade of 0 against 3 is farther than 0 against 1. Left empty, every mismatched grade
  counts the same, as before.
* `vt-fit` names why each out-of-distribution patient is out: up to three predictors outside the range
  of the arm they were judged against, or at a level at most two of its patients share. The out-of-
  distribution table shows them, and `vt.rds` carries them as `eligibility$rows$features`.
* `vt-explain` adds three views: each patient's predicted RMST under the arm received against the other
  (`vt-explain-components`); the difference against the distance to the other arm, with its eligibility
  line and a rank correlation per arm (`vt-explain-distance`); and, with `STRATIFY` set, the difference
  by stratum and the mean twin curves per stratum (`vt-explain-stratum`, `vt-explain-stratum-curves`).

# hvtiRtemplates 1.5.1

* New `vp-dependence` and `vp-individual` templates, in flight. `vp-dependence` runs unsupervised VarPro (`varPro::uvarpro()`) over the study's variables, optionally with the outcome among them, and draws a dependence graph whose edges must beat the largest weight a permuted noise column reached, with edge and signal stability across subsamples. `vp-individual` reads the `vp-fit` screen and draws each patient's local gradient for each predictor (`varPro::ivarpro()`), listing the predictors with no local estimate rather than drawing them. `ggraph` joins `Suggests`, and the `varPro` floor in `Suggests` rises to 3.3.0.

- `upgrade_job()` now keeps the old job and its report in an `_archive/` folder
  beside the upgraded job, as `<job>.<stamp>.pre-upgrade` and
  `<job>.<stamp>-upgrade.md`, where the stamp is the date and time of the
  upgrade. The job's folder holds only the job, Quarto renders nothing in
  `_archive/`, and the same job can be upgraded again without moving the last
  upgrade's files aside by hand.

- `dc-gfup` gains a **Potential follow-up** table. For each death panel (`PANELS`) it shows the
  follow-up recorded against the follow-up the close date allows, in
  patient-years, the percent of potential achieved, and the longest of each.
  It also counts patients with follow-up recorded past the close date. A
  patient who reached the panel's event counts as followed completely.
- The follow-up table in `dc-gfup` and in `dc-eda`'s follow-up section adds
  the 75th and 90th percentiles and `total`, the follow-up summed in
  patient-years.
- `dc-gfup` now checks that its figures draw `EVENT`, the event its table
  checks. A job checking reoperation in the table while drawing only deaths
  had shown no sign of the mismatch. A draft render now says so in a callout
  and marks itself a draft; a final render stops.
- A `dc-gfup` `PANELS` entry takes an optional `levels`, naming its two groups
  with the censored group first, for a non-fatal event drawn without death
  (`levels = c("No reoperation", "Reoperation")`). The legend and the caption
  use those names in place of Alive and Dead.

* The `dc-tables` group-heading parser now names an unclosed `/*` heading
  rather than failing with "subscript out of bounds" or folding the next group
  into the last. `migrate_job()` never reaches it today, because the comment
  masker treats an unclosed `/*` as running to end of file and the migration
  already stops for want of a `%desc_tab` call. The guard keeps a later parser
  change from reopening the confusing error.

- `upgrade_job()` moves the pair an upgrade before 1.5.1 left beside a job,
  `<job>.qmd.pre-upgrade` and `<job>-upgrade.md`, into the job folder's
  `_archive/` the next time it upgrades that job. The pair is stamped with the
  time of the upgrade that wrote it, taken from the report's modification time, and an archived name
  already taken gets a `-2` suffix rather than being overwritten. A copy renamed
  by hand, such as `<job>.qmd.pre-upgrade-20261020`, is left where it is.
  It refuses, before moving anything, when two of those files would take one
  archived name, or when one sits in a folder that resolves outside the study.

- `dc-tables` carries a fuller variable grouping to start from, commented out
  above `GROUPS`: the house summary-table categories, with the SAS template's
  added where they differ, 26 groups of CORR database columns. Uncomment it and
  delete the groups and rows the study's data does not have. It sits outside the
  block `migrate_job()` rewrites, so a migrated job keeps it too.

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

* A report's one-line box and its "About this run" table now call a dataset
  version's date what it is. The box reads `dated 2026-10-21`, not
  `registered 2026-10-21`, and the table's row is `Version date`, not
  `Registered`. The date is the version's extract date, the source file's
  modification date or the date given at registration, and never the day the
  version was registered, which the manifest does not record; read as a
  registration date, it made a version registered on a later day look like an
  older one. An analysis set still reads `written <date>`. The provenance JSON
  keeps the key `registered`, so reports rendered before and after read alike.

- The box under a report's title no longer names a registered version for a
  working read. With `HVTI_DATA=working` it names the working source file, such
  as `built.csv`, and says "working read, not a registered version", matching
  the "About this run" table. Before, it named the registered version file and
  its registration date, though the job never read them. Any other value of
  `HVTI_DATA` is refused when the data are read, so the box sends the reader to
  "About this run" rather than guess.

* `dc-gfup` draws competing non-fatal events and echoes, which hvtiPlotR 2.8.17 added; with the red and blue its captions name (below) it needs 2.8.18. An `EVENTS` entry may give `event`, `time` and `label` as vectors, up to four events in one panel; each patient shows the earliest event before death, in its own house color and shape, and the caption names each. The new `ECHO` choice names a one-echo-per-patient column, such as `iv_echo` from a `JOIN` reduced to one row per patient, and marks it on every panel with a gray tick; a patient with no echo gets none. `COLORS` repeats `event` for competing events, one color per event in order; the three-color form still works. `dc-eda` shares the color checks and the event-panel code, so it accepts the same `COLORS` and competing `EVENTS`.

* `rfs-fit` and `rfs-explain` draw patients who had the event in red and those censored
  in blue, as every house figure does, under one "Event" / "Censored" key, with the loess smooth in black. They had
  taken ggplot's default colors, which drew the censored patients red.
* `ac` draws a single survival curve in black rather than ggplot's default red, and
  strata in colors that are never the event's red or censored blue, so no stratum
  reads as the deaths. More strata than the house colors hold, seven or more, are drawn in
  `grDevices::hcl.colors(n, "Dark 3")` with a warning.
* `dc-gfup` and `dc-eda` captions call the deaths "red crosses", matching hvtiPlotR 2.8.18, whose
  event color is Paul Tol's red `#CC3311` rather than vermilion.
* `ac` stops at setup on hvtiPlotR older than 2.7.18, the first release with `hv_role_palette()`
  and `scale_color_hv()`, instead of failing mid-render; `rfs-fit` and `rfs-explain` stop below 2.8.18 (below). A test holds
  every template that colors by role to that floor.

* A study's render lock records the host that holds it, and a render on another server no longer takes it over. The lock's owner was checked against the local process table only, so a render started on one lri server read a render running on another as dead, took its lock and recovered its live provenance state as though it had crashed; the first render then stopped at its `provenance` chunk, after the fit had finished. A lock held on another host is now taken as alive, and the refusal, from Quarto or from `run_job()`'s preflight, names the host and the lock to delete if that render is no longer running. A lock written before this release has no host and keeps the local check.

- `dc-tables` prints its own labels, so a manuscript table no longer carries the
  dataset's analysis labels or raw codes, and nobody edits them in Word. The
  dataset's labels are left as read; only the copy the table is drawn from is
  relabeled. Two optional files at the study root, shared by every table job in
  the study: `table_labels.yml` gives a variable the label its table prints, in
  the format of `labels_overrides.yml`, and `value_labels.yml` gives a coded
  column its level text (NYHA 1 to 4 as I to IV). A column whose data carry value
  labels, such as a `haven` labeled column, prints its level text with no file and
  whatever `TABLE_LABEL_RULES` says. Every other label is tidied by
  rules: a leading "Preoperative" goes, as does a coding such as "(Y/N)" or
  "(for analysis)"; the label is set in sentence case, keeping the study's
  abbreviations and words already written as acronyms; and `kg/m2` becomes
  `kg/m^2^`. The new study choice `TABLE_LABEL_RULES` turns the rules off
  (`FALSE`) or keeps some of them. The report lists every label and level it
  changed, the rule or file behind each, and every variable with no label. From
  the 2026-10-22 Mitral umbrella meeting's feedback on a study's table.
- The Word file `dc-tables` saves carries what built it as document properties
  (File > Info in Word): the job, its render time and state, the hvtiRtemplates,
  hvtiRtables, flextable and officer versions, and the data it read with its
  checksum. A table that is emailed on can say which release made it without
  anyone finding the report.

* A job may now read an unregistered build in a draft rendered from its study folder, whatever the folder, and its report says so: the data table opens its notes with **Unregistered data** (or, under `HVTI_DATA=working`, **Working data**, naming that setting as the cause), the box at the top says it is a working read, and "About this run" marks the run a draft. A script run with `Rscript`, or a job at the study root, still reads registered data only. A final render reads registered data only, descriptive jobs included. A final render that reads a hand-off saved from an unregistered build stops and names `hvtiRutilities::update_manifest()`. Needs hvtiRutilities 1.5.12.

* `bd` with `REGISTER = FALSE` now names its working file in `_study.yml` on a study's first build, with no version registered, so draft jobs can read the build before it is registered. In a study whose dataset is registered under another file, a `REGISTER = FALSE` build writes its working file, declares and registers nothing, and its report says the study's dataset is unchanged (a comparison build).

* `dc-gfup`, `dc-eda`, `rfs-fit` and `rfs-explain` now need hvtiPlotR 2.8.18 or later,
  because their captions name the red and blue that release draws for an event and for
  censored. An older hvtiPlotR draws vermilion and a different blue, and the captions
  would misdescribe it. The `Suggests` floor moves to `hvtiPlotR (>= 2.8.18)` with them.

* Install hvtiRutilities 1.5.13 or later with this release. It reads a label file's
  unquoted `No` and `Yes` as the text written, so a `value_labels.yml` declaring
  `0: No` / `1: Yes` prints No and Yes in a table rather than FALSE and TRUE. This
  release's `DESCRIPTION` still declares `hvtiRutilities (>= 1.5.12)`; the 1.5.13 floor
  follows in the next release.

# hvtiRtemplates 1.5.0

* Requires hvtiRutilities 1.5.11. `nb-boostmtree` asks
  `hvtiRutilities::cache_would_fit()` whether its fit will run, the same
  decision `cache_fit()` makes, instead of reaching into hvtiRutilities'
  internals. A job scaffolded from the development version that still calls
  `hvtiRtemplates:::.cache_would_fit()` keeps working: that now passes through
  to the exported function. The `vp` templates also need hvtiRutilities 1.5.10 or
  later.

* Upgrading a study's jobs to 1.5.0: an `nb-boostmtree` job refits once,
  because its fit now reports progress and boostmtree 2.0.8 changes the cached
  fit's key; set `REFIT <- TRUE` for that one render. Large fits need a large
  session: an ordinal fit on about 5,500 patients and 13,900 visits needed more
  than Medium's 76.8 GiB. A `dc-tables` job now leaves out rows that are
  constant in the cohort (`DROP_CONSTANT <- TRUE`, the default), and lists them
  in a note; set `DROP_CONSTANT <- FALSE` to keep them.

* New `submit_job()` and `job_status()` render a job in the background,
  detached from the session, so a long fit survives a Workbench session that
  times out. The render is `render_job()` unchanged; it writes `<job>.run.log`
  and `<job>.run.yml` beside the job. Not available on Windows.
* New `guard_long_fit()` stops a long fit from starting in an interactive
  session when it is not cached yet, and names the `submit_job()` call to use.
  `nb-boostmtree` calls it before its cross-validated fit.

* `migrate_job()` words the reason for the `MANUSCRIPT_LAYOUT` it chose for a `dc-tables` job by what was migrated:
  a grouped table says one `n` column sits beside the groups, an overall table with no `by=` says one `n` column covers
  the whole cohort. The `dc-tables` template now says the report shows each variable's column name beside its label
  only while `SHOW_VARIABLE` is `TRUE`.

* A render records its progress in `<job>.run.progress`: the chunk running, the step within
  it, and how long each finished chunk took. `job_status()` prints it, with an estimate of
  the time left in the chunk, flags a render that has not moved for half an hour, and reads
  a render started without `submit_job()` from that file alone. A chunk that reports steps
  writes a line to the render log at most every `hvtiRtemplates.progress_every` minutes (default 10).

* `nb-boostmtree`'s setup chunk, when boostmtree is missing or too old, now
  gives the install line for boostmtree 2.0.8 (`v2.0.8-ccf`). Its partial
  effects walk the boosting steps one at a time instead of holding every step
  for every patient at once, and match each distinct time vector to the fitted
  grid once: on a synthetic ordinal fit, one `partial.plot()` call fell from
  87 s and 4.5 GB to 2.4 s and 0.4 GB, with results unchanged. The floor stays
  at 2.0.4.

* `nb-boostmtree` reports each boosting iteration and each partial-effect prediction to
  `<job>.run.progress` and the render log, so `job_status()` can say how far a fit has got
  and how long its stage has left. It needs boostmtree 2.0.8. Existing jobs need not
  change: they still report stages. Two things make an existing job's cached fit stale, so
  the next render stops until `REFIT`, and each is worth doing only when hours of refitting
  are acceptable: adding these lines to a job, which `upgrade_job()` does, and installing
  boostmtree 2.0.8, which the new floor requires, because `cache_fit()` records package
  versions.

* The `ac` template takes the biostats team's review of 2026-10-21. It now reports the number at risk beside
  survival at every horizon, overall and by stratum; prints the whole life table, with `EVENT_ONLY <- FALSE`
  adding a row for each censored patient as SAS `PEVENT=0` does; compares strata with the log-rank, Wilcoxon and
  `-2Log(LR)` tests; summarizes follow-up overall and among survivors with SAS's percentile definition; and draws
  its own figures: survival and four views of the cumulative hazard for reading, and a manuscript survival figure
  with the numbers at risk, saved as `ac-survival` (and `ac-survival-<variable>` for each stratification). A
  missing or mean-imputed stratum is now dropped, as `%KAPLAN` drops it, and the dropped patients are listed.
  `EXPECTED` is optional (`NULL` by default), `STRATA` defaults to the whole cohort only, derived strata are an
  optional, commented example, `labs` may be `NULL` to label each horizon by its value, and `TYPE` is explained as
  the chain the set belongs to. The nested-stratification chunk is gone: run a second job with a `WHERE` instead.
* New exported functions `life_table()`, `life_table_at()`, `life_table_tests()` and `life_table_keep()`, the
  R counterpart of `%KAPLAN` that the `ac` job calls, so its helpers are documented in `?life_table` rather than
  written out in every job. The tests reproduce SAS `PROC LIFETEST` on the Gehan leukemia data.

* The template catalog lists `vp-fit` and `vp-explain`, a VarPro variable screen and its partial dependence, at status `intake` until hvtiRutilities adds the `vp` prefix to `hvti_taxonomy()`.

* `hz`, `hm` and `hs-setup` now draw a figure in their own report, so each step
  can be checked before the next job reads it. `hz` draws its fitted survival
  over the Kaplan-Meier estimate of the rows it fitted (`hz-fit`). `hm` draws
  observed against expected events in each group of predicted risk
  (`hm-calibration`). `hs-setup` draws the cohort's model-predicted survival
  against the matched population's, on a grid out to the last horizon
  (`hs-setup-expected`). Each is saved through the job's `save_figure()`
  under the new `SAVE_FIGURES` and `FIGURES` study choices, and each job now
  stops in its setup chunk when hvtiPlotR is not installed. `upgrade_job()`
  brings an existing job up to date, keeping its own choices.

* New `vp-fit` and `vp-explain` templates, in flight, for a VarPro variable screen. `vp-fit` reports which candidates VarPro tested (z = 0 means untested, not unimportant), selects a variable only when it beats permuted noise of its own kind, checks the selection across subsamples of the patients, and saves the selected set in `vp.rds`. `vp-explain` draws VarPro partial dependence for that set and refuses a survival horizon past the longest follow-up. The `rfs`, `rfc` and `rfr` explain templates point to them.

* `upgrade_job()` carries the job's own description. Where the template opens
  with an `EDIT:` comment asking which job this replaces, the text the old job
  wrote there, once its marker is deleted, is kept instead of the comment
  returning, which had left an upgraded, finished job with an open marker and
  without its description.
* The `upgrade_job()` report lists comment lines above a carried choice that the
  current template lacks, under "Review", since they are not carried, and has a
  new "Description" section saying what happened to the job's description.
* An empty "Carried", "Not placed", "New" or "Markers left" list in the
  `upgrade_job()` report reads "None." rather than one blank entry.

* `render_job()`, and so `submit_job()`, now runs the job's chunks on the R
  that called it: it sets `QUARTO_R` to `R.home("bin")` for the render, unless
  `QUARTO_R` is already set. Quarto otherwise starts the first R on the `PATH`,
  which on a server with several R versions can be one whose `renv` library
  lacks the study's packages. Studies no longer need `QUARTO_R` in `.Renviron`.

- `add_job()` now records the template's SHA-256 in the job's stamp, beside the template and package version. A version
  names a range of texts (nine for `nb.boostmtree` at 1.4.1); the hash names the one the job was copied from, which
  the coming three-way merge in `upgrade_job()` needs as its base. The package ships the archive of every template
  text on `main` since stamping began, in `inst/extdata/template-history.rds` (about 140 KB).

* `rfs-explain`, `rfc-explain` and `rfr-explain` no longer fit VarPro. The VarPro importance panel and the VarPro partial dependence moved to the `vp` family: a `vp-fit` job screens the variables and a `vp-explain` job draws their VarPro partials. The explain jobs keep VIMP, minimal depth and the marginal and partial dependence plots of the saved forest, and no longer attach varPro. An explain job already in a study keeps its own copy of the code and is unchanged.

* `dc-tables` has a `TABLE_ORIENTATION` choice for the Word table's page,
  passed to `hvtiRtables::hv_man_table_save()`. `"auto"`, the default, turns
  a table too wide for portrait landscape, as before; `"portrait"` or
  `"landscape"` always wins. The job now needs hvtiRtables 1.0.11.

* New `cancel_job()` stops a job `submit_job()` started, on the job's own host:
  SIGTERM, then SIGKILL after a grace period, to the render and every process
  it started. It then records `cancelled` in `<job>.run.yml` and removes
  `<job>.run.progress`, so the job can be submitted again. `submit_job()` now
  marks the render's environment, which is how `cancel_job()` finds the Quarto
  and knitr processes that run in sessions of their own, out of reach of a
  `kill` on the runner's process group. It refuses a job recorded on another
  host, naming the host, and never signals a pid another process has since
  taken. A run whose runner is already gone is recorded `failed`, with the
  reason, after any render it left running is stopped.
* `submit_job()`'s "already running" refusal now points at `cancel_job()` and,
  for a job recorded on another host, names both `<job>.run.yml` and
  `<job>.run.progress`: deleting the status file alone left the job refused.

* `dc-tables` leaves out a row whose every recorded value is the same, such as
  a finding every patient has by inclusion, and names each one in a note under
  the report's table. A constant binary row no longer stops the job.
  `DROP_CONSTANT <- FALSE` keeps every row.

* The `ac` template's manuscript survival figure can mark confidence limits at chosen times, as the SAS figures do.
  `CI_TIMES` draws a bar at each time given, spanning the `CLEVEL` limits the horizon tables report there, and
  `CI_BAND` (still `TRUE` by default) controls the continuous band, so a figure carries the band, the bars, both or
  neither. `CI_BAND <- FALSE` with `CI_TIMES` set gives the SAS figure's bars alone. A time before the first event or
  past the end of follow-up draws no bar.

* The `cancel_job()` test of a live process without the run's marker no longer
  fails intermittently on Linux. It called `cancel_job()` while its bystander
  was still exec'ing from `sh` to `Rscript` to `R`, when Linux cannot read a
  process's environment, and `cancel_job()` rightly refused the process as
  ambiguous. The test now waits until R itself is running. `cancel_job()` is
  unchanged.

* New templates `vt-fit` and `vt-explain`, released for review (`in-flight`): virtual twins with one survival forest per arm, out-of-bag own-arm and swapped-arm curves, a per-patient RMST difference, and eligibility judged by a choice of methods (Gower, SID) combined by a stated rule. `vt-fit` reads a `vp-fit` screen's selected set or a list, and one completed dataset from stacked imputations; `vt-explain` reports the contrast by arm, eligibility rule and stratum, standardized betas and who might benefit.

* New templates `sid-fit` and `sid-clusters` (in flight). `sid-fit` fills
  missing values by mice or forest imputation, `M` times, grows one seeded
  SID clustering forest on each and averages their distances. It saves the
  distance in `sid.rds` keyed by a study-keyed digest of the patient ID, never
  the ID.
  `sid-clusters` runs PAM on that distance over a range of K, reports the
  elbow and silhouette, gives letters that keep their identity across K,
  saves the chosen solution for `vt` (by digest, as in `sid.rds`), and
  registers the assignments as a dataset carrying the study's own ID, by
  design, so a later job can `JOIN` them. The `sid` prefix
  is now qualified, so `add_job("sid", ...)` needs `qualifier = "fit"` or
  `"clusters"`.

* New `run_job()` checks a job before it starts a long render, then submits it with
  `submit_job()`. It refuses, all at once and with what fixes each, a session
  on a different R from the one `renv.lock` records (`r_version`), packages missing, unrecorded
  in `renv.lock`, or at a different version from it (`packages`), no Quarto (`quarto`), a job already running
  (`run_state`) and another job already rendering, or submitted and about to, in the same study (`study_render`).
  It then waits for the render's own checks, the R it runs on (`render_r`) and the memory
  its fit needs (`memory`), and prints the diagnosis if one fails. A job scaffolded before
  the setup consolidation has no in-render checks; `run_job()` says so and names
  `upgrade_job()`.
* New `hvti` shell command and `install_hvti()`, which copies it onto your `PATH`.
  `hvti run <job> [--final]`, `hvti status <job>` and `hvti cancel <job>` run
  `run_job()`, `job_status()` and `cancel_job()` on the R the study's `renv.lock` records,
  whichever R your own session started. `install_hvti("~/bin")` is the usual call; `dir` has no
  default. Run it again after updating the package.
* New `guard_memory()` stops a fit in the first minutes of a render when its expected
  memory exceeds 90 percent of the session's limit, and names the Workbench profile that
  would hold it and, given `cores_fit`, the largest core count that fits. Its estimator
  for boostmtree refuses the two fits measured being killed; it is not verified between
  them, and its coefficients are provisional until they are reviewed.
* `job_status()` now says why a failed run failed, with a fix, for out of memory, a package
  missing on the render's R, and the chunk and lines where the job stopped. It also shows
  the memory in use while the job runs, and its peak against the session's limit after.
* `nb-boostmtree` calls `guard_memory()` ahead of its cross-validated fit, with an
  estimate from the patients, visits, family and cores.

* Report figures are drawn at 9 x 6 in rather than 6 x 4, at the same 12 pt
  type, so they fill more of the report's page; free-size and paged figures
  grow by the same factor. The PNG, PDF and TIFF saved for a manuscript keep
  their 6 x 4 in default and the 6.5 x 9 in page limit.

* `vt-fit`'s Gower eligibility declares each 0/1 predictor symmetric binary
  before `cluster::daisy()`, which otherwise printed "binary variable(s) ...
  treated as interval scaled" in every report whose predictors mix a factor
  with a 0/1 flag. The distances are unchanged: on a 0/1 column the two
  readings agree.

# hvtiRtemplates 1.4.2

* `dc-tables` draws the `%summarytable` table the team asked for on
  2026-10-16: one table with continuous and categorical variables together,
  and, with `STDDIFF <- TRUE`, the standardized difference `%stddiff` printed
  beside the p-value. The difference comes from `hvtiRpropensity::ps_stddiff()`
  through `hvtiRtables::hv_tbl_compare()`. `MEAN_SD` shows named continuous
  variables as mean ± SD and the rest as `CONTINUOUS_STAT`, with every one
  still tested by Wilcoxon. `ORDINAL` names ordered categorical variables,
  which `%stddiff` ranks rather than treats as nominal. `GROUP_1` names the
  treated group when `BY` is not 0/1. `SHOW_VARIABLE <- FALSE` drops the new
  Variable column for a manuscript. The report now shows the table exactly as
  it is saved to Word, with its notes, not gtsummary's working copy. Needs
  hvtiRtables 1.0.6, and broom for `COMPARE <- "pvalue"`.

* `migrate_job()` on a `%desc_tab` job now writes the table that job printed:
  `COMPARE <- "pvalue"` when `by=` named a group, `CONTINUOUS_STAT <- "both"`
  for mean ± SD beside the percentiles, and `PERCENTILES` from `perctile=` when
  every call agrees on a low/median/high triple. Until now it wrote "none",
  "median" and 15, 85 whatever the SAS said. `exposure=0` (the group as an
  outcome, incidence by row) is listed as unresolved, since `dc-tables` does not
  draw it. The report lists where the R table differs from `%desc_tab` on
  purpose: Fisher's exact test for sparse categorical rows, the Wilcoxon test
  (exact in small groups) where `%desc_tab` reported Kruskal-Wallis for two
  groups, and percentiles: `%desc_tab` computed them with
  `PCTLDEF=4`, where the R table uses SAS's default definition, so the low and
  high percentiles can differ in small groups.

* `nb-boostmtree`'s partial-effects pages are drawn at their own height.
  Since 1.4.1 every page was emitted as tall as it was wide, because one
  `sprintf()` call built both chunk options and handed each the page width,
  so a one-panel page came out 3.25 by 3.25 in rather than 3.25 by 3. The
  saved files were already the right size; only the figure in the report was
  wrong, and the call raised a warning on every page.

* `dc-tables`' report shows the table with the same header marks, notes and
  abbreviation key as the saved Word table, through
  `hvtiRtables::hv_man_table_display()`, so an `ABBREVIATIONS` entry or a
  header asterisk is explained in the HTML as well. Needs hvtiRtables 1.0.7.

* `migrate_job()` now migrates a `%desc_tab` job in the shape
  `tp.dc.tables.ods.sas` ships: each table written twice, overall (`by=`
  blank) and by group. It stopped on that pair before, so the mapping added
  for `%desc_tab` jobs never reached a typical one. The group becomes `BY`
  and the overall calls become the table's Overall column, which the report
  says, but only when every patient has a group: where the registered data
  has patients with no `BY` value, which SAS's overall calls counted and the
  R table's Overall column leaves out, the report lists it as unresolved with
  the count instead. A group variable an overall call summarized as a row is
  taken out of `GROUPS`, since its levels are now the columns. Calls naming
  two different groups still stop.

* `nb-boostmtree`'s variable importance is seeded, so a re-render reproduces
  it. `vimp.boostmtree()` permutes each predictor at random and the template
  called it unseeded, so the importance figure, and the six most important
  variables the partial effects are drawn for, could change from one render
  of the same fit to the next. It now runs under `SEED` through
  `cache_fit()`, as the fit does. The seed-hygiene test now lists
  `vimp.boostmtree()` among the calls that draw from R's generator, which is
  how it had been missed.
* `nb-boostmtree` caches its partial effects beside the fit, as
  `nb-boostmtree-partial.rds`. `partial.plot()` makes one prediction over
  every patient for each of 25 grid values per continuous covariate, and was
  the slowest step after the fit; it re-ran on every render, even one that
  changed only prose. A changed `EFFECT_VARIABLES` or a refit stops the render
  until `REFIT = TRUE`, as a changed fit setting does. The importances are
  cached too, as `nb-boostmtree-vimp.rds`.

* `nb-boostmtree` runs its cross-validated fit on several cores, through a new
  study choice, `CORES` (4, or 1 on Windows, which cannot fork). The fit's cost
  grows with the square of the number of patients, and most of it now runs in
  parallel: at 600 patients, 4 cores fit 3.3 times faster than before. The fit
  is identical on any number of cores, so `CORES` is left out of the cache
  key and changing it never forces a refit. This needs `boostmtree` 2.0.4 from
  the CCF fork (`v2.0.4-ccf`), which the setup chunk now requires. A job
  scaffolded before this change keeps its own copy of the fit call, so its
  cached fit is unaffected until the job is upgraded; the first render after
  an upgrade finds the cached fit stale and stops until `REFIT = TRUE`,
  because the call itself changed. The upgraded job also carries `CORES` under
  its own `EDIT:` marker, so it renders as a draft until the marker is
  resolved.

* The study-setup article's "If EDA uses a subset" example now registers the subset with `kind = "subset"`, and points to an analysis set (`hvtiRdatabuild::write_analysis_set()`) as the alternative for a subset of the study dataset that several jobs share.

* `nb-boostmtree`'s setup chunk, when boostmtree is missing or too old, now
  gives the install line for boostmtree 2.0.5 (`v2.0.5-ccf`), whose
  cross-validation is faster for an ordinal response; the fit is the same.
  The floor stays at 2.0.4.

* `nb-boostmtree`'s `CORES` choice now says what to set it to. Its comment
  carries a table, measured on the server, of peak memory at `M = 10` and
  hours scaled to `M = 1000`, by patients and cores, with the smallest session
  each needs. The cross-validated fit's parallel share levels off near 80%, so
  speed stops improving past 4 to 5 times, and memory is what limits `CORES`
  on a large study: at 4,000 patients and `M = 10`, 4 cores needed about 70 GB
  and 8 ran out. The fit itself keeps every step, so memory grows with `M`
  and the sessions are a floor at `M = 1000`, not a fit.

* `nb-boostmtree`'s setup chunk, when boostmtree is missing or too old, now
  gives the install line for boostmtree 2.0.6 (`v2.0.6-ccf`), whose forked
  workers need about a third of the memory, so more `CORES` fit in a session.
  The fit is the same. The floor stays at 2.0.4.

* Tests and examples pass `renv` and `cleanup` to `hvtiRutilities::study_setup()` explicitly, ahead of
  `hvtiRutilities` turning both on by default. A new test fails on any call that leaves them implicit.
* The `hvtiRutilities` floor rises to 1.5.2, the first release whose `study_setup()` takes `renv` and `cleanup`.

* `nb-boostmtree`'s setup chunk, when boostmtree is missing or too old, now
  gives the install line for boostmtree 2.0.7 (`v2.0.7-ccf`). Its forked
  workers each use one BLAS thread, so a server whose R links a multithreaded
  OpenBLAS is no longer overloaded: at 1,000 patients on 4 cores, 616 s where
  2.0.6 took 1,488 s. The floor stays at 2.0.4.

* `add_job()` installs the packages a template needs into the study's library, and records them in
  `renv.lock`, when the study is a renv project. It asks first, and writes nothing if the packages cannot be had.
  It needs hvtiRutilities 1.5.7 or later, the first release whose `study_need()` leaves the study unchanged when an install is declined.

* `nb-boostmtree` gains a study choice, `MTRY`: the number of predictors tried
  at each split of each tree, passed to `boostmtree(mtry = )`. `NULL`, the
  default, tries every predictor, as the template has always done, so existing
  fits are unchanged. Set it to reproduce a study fitted with a smaller
  `mtry`. It is part of the cache key, because a different `MTRY` is a
  different fit. A job upgraded to this version finds its cached fit stale
  once, because the fit call changed.

* `dc-tables` saves its Word table in hvtiRtables' manuscript style: a full
  grid, a two-row header when the table is grouped, with the grouping spanning its levels, shaded section
  rows that span the table, the notes below it, and a caption above it. Three
  study choices set it: `MANUSCRIPT_LAYOUT` (`"compare"`, one `n` column beside
  the groups, or `"describe"`, a count beside each group), `MANUSCRIPT_CAPTION`
  and `MANUSCRIPT_FILL`. The report keeps the report style, with the Variable
  column, and shows the Word table beneath it. `SHOW_VARIABLE` now applies to
  the report only. `migrate_job()` writes `MANUSCRIPT_LAYOUT <- "describe"` for
  a `%desc_tab` job that printed mean ± SD beside the percentiles, which the
  compare layout cannot draw. Needs hvtiRtables 1.0.9. A job scaffolded before
  this keeps working and keeps its report-style Word table; `upgrade_job()`
  adds the three choices, each with its `EDIT:` marker. An upgraded job with
  `CONTINUOUS_STAT "both"` stops at its Word table until `MANUSCRIPT_LAYOUT` is
  set to `"describe"`. hvtiRtables' error names `layout =`; the study choice that sets it is
  `MANUSCRIPT_LAYOUT`.

* The `hvtiRtables` floor is now 1.0.9, in `DESCRIPTION` and in `dc-tables`'
  setup check. In 1.0.7 and 1.0.8, `hv_tbl_summary()` failed with "Value must
  be a named list of functions" on any mean±SD or median row when the study's
  `R/` folder defined `sd` or `median`, and every job sources `R/` into the
  global environment. 1.0.9 fixes that.

# hvtiRtemplates 1.4.1

* The `rfs-explain`, `rfc-explain` and `rfr-explain` dependence figures, and
  `nb-boostmtree`'s partial effects, are drawn on pages no larger than the
  printed page, 6.5 by 9 in, rather than as one figure that grew with the
  number of predictors: `rfs-explain`'s marginal dependence was 24 in tall in
  the template gallery and 48 in at the default `TOP_K = 8`, and the partial
  and VarPro dependence figures were 9 in wide. Panels sit two across; more
  than fit go on further pages, each a numbered figure whose caption names
  its predictors. Saved files gain a `-page-01` suffix. The `rfc-explain` and
  `nb-boostmtree` importance figures are 6.5 in wide rather than 9.

* `dc-eda` draws its pages on the printed page, 6.5 by 9 in portrait, rather
  than 11 by 8.5 in landscape, and its grid defaults to two panels across
  (`GRID_NCOL <- 2L`), so each 8 pt panel's title and year axis stay
  readable. A section takes more pages than before. A job that sets
  `GRID_NCOL` keeps its choice; more than two columns crowd the panels.
  Migrating a legacy EDA job that sets no grid now gives two columns.

* `dc-eda`'s categorical panels, percent and count, no longer name their
  categories, in a legend or beside the panel: the names took width the bars
  needed, so the bars now fill the panel. The house colors tell the
  categories apart, each panel's title still names its variable, and the
  section's frequency table names the categories.

* `dc-stddiff` draws its balance figure 6.5 in wide, not 7, and puts at most
  30 variables on a page of at most 9 in; more variables go on further pages,
  each a numbered figure (`fig-balance-1`, ...) whose caption names its first
  and last variable. The saved file is `dc-stddiff-balance-page-01.png` and
  so on, not `dc-stddiff-balance.png`.

* `upgrade_job()`'s help page now says first that it upgrades the one job
  named in `path`, shows a real job path and how to upgrade several jobs one
  call each, and says what to check afterwards.

* `dc-eda` draws against the surgery date by default, `X_VAR <- "dt_surg"`,
  rather than a `year` column no study dataset carries, which stopped a fresh
  job with "Unknown EDA column(s): year". A date column is drawn as a decimal
  calendar year: whole years for the percent and count bars, the point in the
  year for the continuous panels. Any other column is drawn as it is. The new
  `X_LABEL` choice titles the axis, "Year of operation" by default; set it
  and `X_VAR` when time 0 is not an operation, such as an enrollment date. A
  missing `X_VAR` column now stops with "Set X_VAR in the study choices to
  the study's reference date or year column."

* In the HTML report, `dc-eda`'s percent and count pages carry hover labels.
  The pages name no categories, so a reader hovers a bar to see its category,
  year and count and percent. Each page is a ggiraph widget of about 120 KB,
  with no embedded fonts. The saved PNG and PDF figures are unchanged. The
  hover labels need ggiraph, now in Suggests, and a hvtiPlotR that has
  `hv_girafe()`. Without either, the pages are images as before.

* A selected figure is saved as a TIFF too, beside its PNG and PDF: 300 dpi
  and LZW-compressed, through `ragg::agg_tiff()`, since `grDevices::tiff()`
  cannot compress on a Mac without XQuartz. Journals ask for a PDF or a TIFF,
  and the TIFF is the raster format the family delivers by default, as
  hvtiPlotR's `save_manuscript()` does. The PNG stays the image a report
  embeds. ragg is suggested: without it the TIFF is skipped, with a message
  once a session. ragg's floor is 1.2.1, which fixed a crash writing a TIFF
  with a transparent background. A transparent plot stays transparent in its
  TIFF, and saving a figure leaves the graphics device that was active before
  it active afterwards.

* The `hm` template's note on `vars.sas` columns (mean imputation, the `ms_*`
  flags, and why R reading a column as a factor would quietly change the model)
  is rewritten in plainer terms for readers new to R.

# hvtiRtemplates 1.4.0

* `dc-general` now says plainly that its tables are checks on the data, and
  points to `dc-tables` for a manuscript table saved to Word, with the
  `add_job()` call that scaffolds one (#308).

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

* `hm` offers each covariate only to the phases whose block names it. It built
  one formula from every block, so every covariate entered every phase and the
  estimates were not comparable with the SAS model it replaces (#171). A block
  naming a phase the `hz` fit does not have now stops the job.
* `hm` no longer needs a companion SAS job: with `SAS_JOB <- NULL` the
  covariates are listed per phase in R, and the covariate table says which
  source was used (#178).

* The `lm-*` and `rf*-fit` templates now show a table of missing values right
  after the data are read: each model variable that has any, with its count, and
  the cohort the fit will use ("725 of 800 rows analyzed; 75 dropped", or under
  `na.impute`, how many rows are imputed). Until now the drop showed only as a
  smaller sample size in the fit's own output. `hm` stops at that point instead,
  naming each column and its count, where `hazard()` had failed with "Predictor
  rows must match the length of 'time'" (#174).

* `hs-setup` derives the life tables' 0/1 male and non-white indicators from
  the study's own coding. New settings `MALE_LEVEL` and `OTHER_LEVELS` name the
  values that count as male and as non-white, so a `female` column
  (`MALE_LEVEL <- 0`), a sex factor or a race factor is used as it is, without
  first deriving the indicators by hand. Both default to 1, which leaves a job
  with 0/1 `male` and `other` columns unchanged. A level the column never takes
  stops the job, and a new table shows how each value was counted, so a race
  level left out of `OTHER_LEVELS`, and therefore counted as white, is visible
  (#183).

* `bl`, `br` and `bc` name the bag they read with `BOOT_PREFIX`, as `bh` does,
  in place of `BOOT_FILE`: each reads `<BOOT_PREFIX>.rds`, defaulting to its own
  prefix, and its runner in `inst/runners/` now writes `bl.rds`, `br.rds` or
  `bc.rds` rather than `bagging.rds`. One setting across the family lets a runner
  write where every report looks, and the three no longer overwrite one another
  when they share a subject and type. A job scaffolded earlier keeps its own
  `BOOT_FILE`; a runner still writing `bagging.rds` is read by setting
  `BOOT_PREFIX <- "bagging"` (#189).

* Every template now follows one figure standard. A single-panel figure is 6 in wide by 4 in
  tall, in the report through `fig-width` and `fig-height` in each template's `format:` block
  and in the saved PNG and PDF through `save_figure()`'s default. Faceted figures and plots
  with one row per variable keep a size of their own, and say why. Type is 12 pt in
  hvtiPlotR's theme, `theme_hv_manuscript(base_size = 12)`, on every ggplot, including those
  returned by a package's `plot()` method, and `theme_minimal()` is gone. The one exception is
  `dc-eda`'s pages of small panels, four to a row, which use 8 pt and name each category beside
  its panel in its own color instead of a legend, with about five labels on the year axis.
  Every figure's numbered caption now names the shape or line and the color of each mark, so
  the figure can be read from its legend alone. `test-figure-standard.R` guards the size, the
  theme and the captions (`dev/specs/2026-10-13-figure-standard-design.md`).
* `lg` sizes its figure with hvtiPlotR's `hv_panel_size()`, so it now needs
  hvtiPlotR 2.8.8, whose 6.5 inch page fits three columns, and the package
  requires 2.8.9, which stops that function leaving a graphics device open. Its six scales keep
  their two rows of three, each panel shrunk together to fit the page, with about
  three ticks on each x axis so the labels of panels under 2 inches wide do not
  run together.

* `hs-setup` accepts a cohort with no one in a life-table stratum, all female or
  all white, as `us_matched()` does. Under the default `MALE_LEVEL <- 1`, an
  all-zero `male` column stopped, because the level never appeared in it. A
  level the column could take is now accepted: 0 or 1 in a 0/1 column, or a
  level a factor declares. An empty `OTHER_LEVELS` counts no one as non-white. A
  level the column could not take still stops, because it is a typo (#183).

* `bd` no longer publishes catalog releases, which hvtiRutilities 1.5.3 retired.
  It writes the study's working file, `datasets/<DATASET_ID>.rds`, with a schema 1
  build record beside it, `<DATASET_ID>.build.yml`, and with `REGISTER <- TRUE`
  registers that file as a dated version with `register_data()` the first time
  and `update_manifest()` after that. The version's manifest provenance then reads
  `origin: bd`. The study choice `PUBLISH` is now `REGISTER`, and the `write-draft`
  and `publish` chunks are now `write-built` and `register`. The build record
  keeps a hash of the cohort rules, never their text, so an `EXCLUDE` rule that
  names a patient stays in the job file. A study registered under a file this job
  does not write still stops, now in `register`. A `DATASET_ID` ending in a date,
  or naming a file `dataset-catalog.yml` lists as a published release, stops before
  anything is written, so a working file never overwrites a release. `bd` needs hvtiRutilities 1.5.3
  and checks for it in its setup chunk. Its tests no longer call
  `publish_dataset()`, `register_data(release_id =)` or `adopt_data_update()`, so
  they run with no deprecation warning.

* Two regression-model templates: `rm-balancing_continuous`, a least-squares
  balancing score for a continuous exposure, and `rm-linear`, an ordinary
  least-squares outcome model. Both pool stacked imputations with Rubin's rules,
  and both model the response untransformed or on the log scale through the
  `RESPONSE_SCALE` study choice; the report states the formula it fitted and
  reads the coefficients on that scale. They need `hvtiRpropensity` 0.2.0, and
  the `lm` templates, `dc-stddiff` and `lp-mirror` now ask for it too.

* The study-setup vignette's "When registered data change" passage now reviews a rebuilt
  dataset with `hvtiRutilities::review_built()` and registers it with
  `hvtiRutilities::update_manifest(dataset = "study")`, replacing the retired catalog-release
  pair `review_data_update()` and `adopt_data_update()`.

* The `lm` templates read stacked multiple imputations again. Since 1.3.0 their data table stopped with "This job models
  one row per patient" on any `IMPUTATION`, because `read_job_data()` counted a patient once per row rather than once per
  imputation. It takes a new `imputation` argument, which each `lm` template passes as `IMPUTATION`, and counts a patient
  within each imputation: a patient once in each passes, a patient twice in one imputation, or in a long dataset with no
  imputation, still stops. The data table now says how many imputations the rows hold, for example
  "240 rows on 120 patients, in 2 imputations".
* `read_job_data()` pairs an ID with its imputation by value, so a `bit64` `integer64` ID is no longer taken for one repeated
  patient, and records the imputation column as the data spell it (`selection$imputation`). The `lm` templates read it
  back, so `IMPUTATION <- "IMP"` works for a column `imp`, as `KEY` does.

* `rm-linear` and `rm-balancing_continuous` read a named `RESPONSE_SCALE`, such
  as one looked up with `scales["outcome"]`, as its value. Before, a named
  `"identity"` fitted `log()` while the report read the coefficients as
  measured, and a named `"log"` was read as measured and left the residual
  axes unlabeled.

* `read_job_data()`, so every template, now drops direct identifiers beyond MRN
  and eMRN, unless one is the job's ID or a KEY column, including a KEY that names a joined column: `ccfid`, Social Security numbers
  (`ssn`, `soc_sec`, `social_security`, each with or without a `_no`, `_num` or `_number`
  suffix), and patient names and contact details held as text, by name (a 0/1 or Y/N
  contact indicator stays, however it is stored), and any column whose values are shaped like Social Security numbers,
  whatever its name. The data table lists every column dropped and notes the
  ones dropped by their values. `bd` drops the same columns from the built it
  writes, so `dc-eda` can no longer draw an SSN carried in from an SSDI join.

* A website article, "From vars.sas to R: study-build and variable actions",
  explains the design in `dev/specs/2026-10-14-bd-vars-action-items-design.md`
  for analysts who know SAS `vars.sas`: where each `%vars` switch,
  `tp.vars.<umbrella>` module, correction and deletion now lives, with
  illustrative R. The functions it describes are not built yet. Articles under
  `vignettes/articles/` are now left out of the package tarball.

* The README's Installation section now leads with `hvtiR::install()`, which
  installs the whole HVTI R family in one call, and then gives
  `pak::pak("ehrlinger/hvtiRtemplates")` for this package alone.

* `dc-tables` and `DESCRIPTION` now require hvtiRtables 1.0.5, whose Word
  tables follow the SAS `%summarytable` layout: section rows in the
  Characteristic column instead of a `groupname_col` column, no `%` sign in
  the cells, a dagger and sub-header that name the statistic each row shows,
  and a superscript `a` on each `n` with its footnote.

* `lg`'s calibration figure says it needs hvtiPlotR when hvtiPlotR is not
  installed, as it already did for ggplot2, instead of stopping on R's
  "there is no package called" error. The figure has used
  `hvtiPlotR::theme_hv_manuscript()` since the figure standard.

# hvtiRtemplates 1.3.1

* `lm-binary` no longer prints the saved model's full path in its report. A
  bare `MODEL_PATH` line showed the absolute path, study folder included, in a
  report meant to be shared. A test now stops any template from printing a path
  variable this way.

* `dp-postage` is removed, as its deprecation promised for the release after
  1.2.3. Use `dc-eda`: `add_job("dc.eda", subject, type)` with
  `SECTIONS <- c("continuous", "percent", "count")` draws the pages it drew.
  Asking for `dp.postage` now stops with the usual unknown-template error.

* Every `lm` template now checks the columns its study choices name before it
  fits, and a missing one stops with the setting to change, such as "OUTCOME
  names a column this dataset does not have: severity. Change OUTCOME in
  edit-study-choices." `OUTCOME` or `TREATMENT` and `PREDICTORS` are checked,
  including a variable used inside a term such as `I(age^2)`; `ID` and `KEY`
  were already checked by `read_job_data()`. Before, only `lm-binary` checked,
  and elsewhere a wrong name failed inside hvtiRpropensity with an error naming
  one of its functions (#179).

* `lm-checkpred` can read a model saved in another set. A new optional
  `MODEL_SET` names the training job's set, such as `"stroke-model"`, so a
  validation job no longer has to share the subject and type of its `lm-binary`
  job. `MODEL_FILE` must be a file name and `MODEL_SET` a set name, so neither
  can reach outside the study's estimates. The template now says how to register
  a validation cohort as a dataset of its own and read it with `DATASET`; it is
  checked against the training patients like any other cohort (#180).

* `lm-propensity_ordinal` and `lm-propensity_nominal` print a balance table, the
  standardized mean difference of each covariate between each treatment level
  and the reference level, in the place `lm-propensity_binary` prints its own.
  `lm-propensity_ordinal` also prints the cumulative direction of its
  proportional-odds model, as `lm-ordinal` does, which a reader needs to
  interpret the signs of its coefficients (#191).

* hvtiRpropensity 0.1.10 or later is now required, up from 0.1.7, by
  `DESCRIPTION` and by the version check of every `lm` template and of
  `dc-stddiff`. 0.1.10 returns the multi-level balance tables, labels the count
  family's exponentiated coefficients `rate_ratio` rather than `odds_ratio`,
  and names the declared treatment levels in `lm-propensity_binary`'s group
  counts rather than "control" and "treated" (#206).

* `dp-eda` and `dp-trends` are renamed `dc-eda` and `dc-trends`, so every
  descriptive template now carries the `dc` prefix. The old names, `dp.eda` and
  `dp.trends`, still work in `add_job()`, `open_job()`, `template_path()` and
  `migrate_job()` through the next release, each call warning once that the
  name is deprecated in favor of its `dc` replacement, and are removed in the
  release after. A job already scaffolded as `dp.eda.*` or `dp.trends.*` (or
  `*-dp-eda.qmd`, `*-dp-trends.qmd`) keeps its name and keeps rendering:
  `open_job()` opens it under either name, and `add_job()` refuses to write a
  second copy under the new one. A legacy SAS source named `dp.trends.*`
  migrates into `dc-trends` without a warning. The taxonomy keeps its `dp`
  row, since legacy jobs carry that prefix; the queued `dp-variable` and
  `dp-boxplot` templates are planned as `dc-variable` and `dc-boxplot`.

* A new `dc-trends` job is written to the study's descriptive folder
  (`10_descriptive/`, or `descriptive/` in a legacy study), where `dp-trends`
  wrote it to `graphs/`. Its figures are still saved under
  `graphs/<subject>-<type>/`, and the report links them from its new folder.

* `dp-gfup`, deprecated in favor of `dc-gfup` in 1.3.0, is removed.
  `add_job("dc.gfup", subject, type)` draws the same panels beside the
  follow-up tables. Asking for `dp.gfup` now stops with an error naming
  `dc.gfup`: an unknown template's error lists any template with the same
  qualifier under another prefix.

* New template `lp-mirror`, the mirrored histogram of the propensity score:
  `add_job("lp.mirror", subject, type)` with the subject and type of the
  `lm-propensity_binary` job it plots. It reads that job's saved bundle and
  never refits, drawing treated patients above the axis and controls below:
  all patients, then under the matching weights, and, when `MATCH` names a
  pair-match column, the matched patients. The y-axis is derived from the
  counts, the same above and below. The groups are labeled by the declared
  treatment levels, or by `GROUP_LABELS`. A bundle without lineage, or whose
  rebuilt read has different rows, patients or patient hash, stops with the job to render again.
  `MATCH` is joined onto the scored patients by a study-keyed digest of `ID`,
  so the job keeps and prints no identifier; it counts the scored patients
  with no flag and the flags with no score, and stops when fewer than half
  the scored patients are in the dataset, when `MATCH` is not a column coded 0 and 1 or flags no
  scored patient, and when a score, weight or group is missing. `lp` becomes a qualified prefix.

* `lm-checkpred`'s `MODEL_FILE` and `MODEL_SET` checks are now shared with
  `lp-mirror`. An `NA` in either now stops with the setting's own message
  rather than an R error.

* The template catalog names the `lg` prefix "Logit calibration", not "Logit
  trends", matching `hvti_taxonomy()` from hvtiRutilities. The description is
  unchanged: `lg` jobs calibrate a covariate against an event to choose its scale.

* New template `lg`, logit calibration: `add_job("lg", subject, type)`, usually
  with the outcome as the subject, as in `lg.dead.calibration`. It decides which
  scale a covariate should enter a model on, before it goes into `PREDICTORS` in
  an `lm` job. Each covariate in `VARIABLES`, continuous or ordinal, is ranked
  into groups as `PROC RANK GROUPS=` does, or takes each level as a group, as
  `%logitgr` did. The job takes each group's event rate on the logit, or, for
  time-related death, the log of the constant hazard, and plots it against the
  covariate on six scales (raw, log, inverse, inverse squared, squared and
  exponential), each panel with the R-squared of a straight line weighted by
  group size. `INTERVAL = c(start, end)` takes one phase of follow-up as the SAS
  early, constant and late jobs did: patients who ended before `start` are left
  out, and the rest are censored at `end`, so an event after `end` no longer
  counts. Under the hazard link the time at risk is the time inside the window,
  `pmin(TIME, end) - start`; the SAS template summed it from 0, which is the one
  deliberate difference. Under the logit link the same patients are kept and an
  event counts only inside the window. The job reports how many patients it left
  out, how many it censored and how many events fell after `end`. The scale
  chosen for each covariate is saved as `lg-scales.rds` with the term to write
  for it, such as `log(age)` or `I(50 / weight)`, and the job prints the
  `PREDICTORS` line to copy into an `lm` job. A blank `chosen` warns in a draft
  and stops a final render, as an open `EDIT:` marker does, and so does a chosen
  scale that is not a number for some patient, such as the log of a covariate
  that is 0 for a few, though every group mean is fine; the message counts those
  patients and shows no value. A group whose link value cannot be computed keeps
  its row, blank, and is named under its table; a scale that cannot be computed
  for a covariate is drawn as an empty panel. A patient with no event value is
  ranked but counts in no group's patients, events or follow-up. A covariate
  whose median rounds to 0, such as a 0/1 indicator, has no default `constant`:
  the inverse, inverse squared, squared and exponential scales are not computable
  for it until `constant` is set, and raw and log remain. Two checks keep a
  figure from resting on groups too small to read: an ordinal covariate with more
  than 20 levels stops the job, and so does any group with fewer than 5 patients,
  naming the covariate and never a value.

* `rfs-fit`, `rfc-fit` and `rfr-fit` now draw the out-of-bag error by number of
  trees as a curve. With importance off, randomForestSRC records the error only
  at the last tree, so the figure was one point and could not show whether
  `NTREE` was large enough. The fit now passes `block.size = 1`, which records
  the error after every tree and leaves importance off (#165).

* `rfs-explain`, `rfc-explain` and `rfr-explain` give VarPro the forest's
  imputed data when the fit used `na.impute`, so VarPro and the forest describe
  the same patients. Before, varPro dropped every patient with a missing value
  and its importance and partials described fewer patients than the forest, with
  a notice in the rendered report. The report now says that VarPro was given the
  imputed data. A saved `-varpro` result from an earlier render describes the
  old, smaller cohort, so `cache_fit()` stops on it and names the change: set
  `REFIT <- TRUE` once to recompute it (#166).

* The marginal plot of `rfs-explain`, `rfc-explain` and `rfr-explain` draws no
  loess smooth through a predictor with fewer than six distinct values, which
  stops the dozens of loess warnings a four-valued predictor raised in the
  rendered report. `rfc-explain` also draws its points for a 0/1 outcome:
  ggRandomForests read the outcome's levels "0" and "1" as missing, so every
  point was removed and only the smooths were left (#167).

* `dc-eda` prints the abbreviation key under a section from the abbreviations
  `label_map()` records for that section's variables, instead of searching the
  shortened labels for each abbreviation. A label that says "SP" in its own
  words and is only cut no longer produces `SP = Surgical procedure` under its
  section (#194).

* No template leaves placeholder prose in the rendered report. Sentences such as
  "Describe the question here." in the `rf*-explain` templates and "Replaces
  `analyses/<job>`: describe its outcome and candidate predictors here." in the
  `rf*-fit`, `ac`, `hz`, `hm`, `hp`, `hs`, `bh`, `bl`, `br`, `bc`, `nb`, `bd`,
  `dc-stddiff`, `dc-tables`, `dc-trends` and `lg` templates now sit inside the
  `EDIT:` marker that asks for them, so resolving the marker removes them (#182).

* The `bh` frequency figure sorts the variables within each phase. Before, one
  ordering across both phases left a variable offered to two phases out of order
  in each facet (#189).

* The `bh` default `CLUSTERS` is an empty list, with a commented example, and an
  empty list reports no clusters instead of stopping. The old default named
  terms such as `early.age` that a small run may never carry, and
  `boot_clusters()` refuses a name no replicate has (#188).

* The `bc` template says what its runner's `BASE` setting does and costs.
  Neither `boot_select()` nor `fit_cox()` can force a term into a Cox model, so
  `BASE` only names a screened candidate whose frequency the tables leave out
  and whose spread the check watches; the old advice to "force at least one
  term" could not be followed (#186).

* `hs-concordance` takes its time and event columns from the `hm` models it
  reads, as `hm`, `hp` and `hs-setup` take theirs from upstream, instead of
  declaring `TIME` and `EVENT` itself. Both settings default to `NULL`; a value
  that differs from a model's recorded one stops the job, and so do models that
  disagree. An `hm` model saved before it recorded its data selection stops the
  job, asking for the `hm` job to be rerun. The `cohort` chunk now follows the
  `models` chunk, because it needs the columns the models record (#176).

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
  own source, a joined dataset's separately), each upstream handoff, the seed when
  the job sets `SEED`, and whether renv is active with the first 12 characters of
  `renv.lock`'s sha256. The same facts are in the embedded provenance under `run`. The table
  holds names, dates, counts and hashes, never a patient identifier or a data
  value. The user and host are the login and machine names; `HVTI_RUN_USER` and
  `HVTI_RUN_HOST` replace them, and the template gallery sets both so its
  published reports name no one. (#303)

* The package no longer ships two stray, blank `Rplots.pdf` files (at the top
  level and in `tests/testthat/`) that a test run had left in the source; `R CMD
  check` flagged the top-level one as a non-standard file.

* The handoff bundles that jobs save now record `rendered_at`, the start of the
  render that saved them, as ISO 8601 with its time zone. The "About this run" table
  shows it for each upstream handoff, and "not recorded" for a bundle saved before
  this change; the file's modification time is never used in its place. Saving the
  same results again therefore writes a different file. (#306)

* A report that turns out to be a draft after its box was printed no longer reads
  as final. A `stop_here()` that the source scan could not see (inside an `if ()`)
  and that runs, an `lg` job with a covariate whose scale is not chosen, an
  incomplete bootstrap pool in `bc`, `bh`, `bl` or `br`, and a `dc-gfup` follow-up
  figure that was not drawn each mark the run a draft: the end table's status and the
  embedded `run` facts say `draft` (with `stopped_early` for a stop and the reasons
  under `draft_reasons`), and a callout above the table, "This run ended as a
  draft", names each reason. The box under the title is printed first and cannot
  change; the callout is what corrects it. (#306)

* In the "About this run" table, two reads of one dataset whose `WHERE` shows the
  same text because its values are masked (`age >= <value>`) are listed separately;
  a joined dataset's rows no longer read "on NULL patients" and carry no `WHERE`
  row of its own; and a `WHERE` that names a column with a space or backtick is
  shown whole. (#306)

* **`ANALYSIS_SET` now needs hvtiRdatabuild 0.3.0** (was 0.2.1), and 1.3.1 is
  tested against it. 0.2.4 stopped with "$ operator is invalid for atomic
  vectors" in `read_analysis_set()` and `write_analysis_set()` on any study
  registered with hvtiRutilities 1.5.1, which this package already requires.
  A stale analysis set no longer stops a draft in 0.3.0: it is read, and the
  "About this run" table carries a note naming the `write_analysis_set()` call
  that updates it. A final render (`render_job(final = TRUE)`) still stops.

# hvtiRtemplates 1.3.0

* A test now covers a new dataset version registered while a job is reading: the
  read is rejected as changed, as it already was in practice.

* The six forest templates (`rfc`, `rfs` and `rfr`, fit and explain) now hand
  `rfsrc()`, `vimp()` and `varpro()` a negative `seed = -abs(SEED)` as well as
  seeding R's generator through `cache_fit(seed = SEED)`. A study found that either
  half alone does not reproduce: `rfsrc()` without `seed =` draws one from R's
  generator, and `varpro()` with a fixed `seed =` still gave different importances
  after a different chunk. Both together reproduced to the last digit across a
  192-thread server and a Mac. The templates also set `options(rf.cores = 1L)`, since
  a varPro cutoff changed with the thread count. Jobs already scaffolded are not
  changed; to adopt this, make the same edits and render once with `REFIT = TRUE`.

* A new test parses every R chunk of every shipped template and fails on a call
  that draws from R's generator (`rfsrc`, `varpro`, `mice`, `sample`, `runif` and
  others) unless it is wrapped in `cache_fit(seed = )` or `with_seed()`, or has a
  `set.seed()` at most three lines above it in the same chunk. A randomForestSRC
  call that takes a `seed` must also be given a negative one.

* A job reading a dataset whose source file has been rebuilt but not yet
  registered runs on the registered version and says so in its "The data this
  job read" table, with a Note row naming the `update_manifest()` call that
  registers the new file. Before, hvtiRutilities' message printed bare wherever
  the data chunk happened to show it. The table's Source row names the dated
  version the job read, such as `built_20261007.parquet`, rather than the source
  file. `dp-postage`, which reads outside `read_job_data()`, prints the same note
  under its "Data read" line. Requires the hvtiRutilities release that added
  dated versions.

* Running a job's chunks in the console no longer ends with advice to run
  `add_job()`. The final provenance chunk, the one step that needs a render, now
  stops with an error of class `hvtiRtemplates_not_rendered` saying that every
  chunk above it ran and that the job should be rendered, with
  `hvtiRtemplates::render_job()` or the Render button. A render outside the
  study's Quarto project keeps the existing message about installing the hooks.

* The test suite runs in about two-thirds of the time: expensive fits and renders are
  shared within a test file, and fixtures are smaller. No assertion was dropped. About
  40 tests, the end-to-end Quarto renders, model fits and saved-file identifier scans,
  are skipped on CRAN (`skip_on_cran()`), so a CRAN-mode check fits the 10-minute
  budget; CI sets `NOT_CRAN=true` and still runs every one.

* `add_job()` and `open_job()` default to `dir = NULL`, which finds the study root by
  walking up from the working directory, and stop outside a study rather than writing
  a job into whatever directory R is in. A call from a study's subfolder now scaffolds
  into the study instead of under the subfolder. An explicit `dir` means what it did.

* Tests use at most two cores (`rf.cores`, `mc.cores` and `OMP_THREAD_LIMIT`) and
  leave the global random seed alone. The package description names the
  Cardiovascular Outcomes, Registries and Research (CORR) group in full.

* Articles on the pkgdown site put the table of contents on the left and use
  the full width of the window, through `pkgdown/extra.css`. The installed
  vignettes are unchanged: the Quarto vignette engine renders them in its own
  minimal format, which has no sidebar layout.

* `hm`'s first stage now holds every shape of each phase, as its two-stage fit
  intends: covariates are screened against `hz`'s shapes before the shapes are freed.
  It read the shapes from a field a TemporalHazard phase does not have, so stage 1
  held nothing beyond `hz`'s own fixed set and fitted the same model as stage 2. A
  shape a g3 `constraint` derives is left free, since it may not be fixed.

* A part-built job's report no longer lists a `stop_here()` that cannot run: one in a
  skipped chunk, or in a chunk whose `eval` is false as knitr reads it (`false`, `no`,
  `off` or `n` in any case, or `!expr FALSE`).

* Rendering a part-built job leaves the R session's options as they were. The record of
  skipped chunks is kept inside the package, and the `skip` chunk option acts only on
  the job that registered it, so another document knit later in the same session is
  not affected.

* `hz` no longer passes `condition = 14` to `hazard()`. It mirrored SAS's
  `CONDITION=` option, which `hazard()` does not have, so TemporalHazard ignored it
  and printed a warning into the report for every fit. The fit still reports the
  conditioning of its Hessian, as `rcond` in the convergence table (#172).

* `hz`'s start probes move only the free parameters. They used to shift every
  position of `theta0`, the fixed late-phase shapes included, so each probe fitted a
  different model and could beat the reported fit, falsely suggesting it was in the
  wrong basin. The held positions are read from `phases`: each phase's `fixed` set and
  any shape a g3 `constraint` derives. A probe edited to move one stops the job,
  naming the parameter (#169).

* `ac` and `hz` stop at the cohort when `TIME` holds a time of exactly zero or a
  negative time, giving the count of each. A same-day death used to stop `hz` later
  with an optimizer error that named neither. The message says to correct the times
  in the dataset build, since a job reshapes data and never corrects it: move only
  the zeros to a small positive value, such as 0.00025 years, and trace a negative
  time to its source (#175).

* `hm` and `hs-setup` no longer carry `EXPECTED` counts. The counts reconciled with
  the SAS reference are typed once, in `ac` and `hz`, whose hand-off already records
  them; `hm`, `hs-setup` and now `hp` count their rebuilt rows and stop when they
  differ from the upstream job's, naming the upstream file and both sets of counts. An
  upstream file that records no counts stops too, asking for it to be rerun (#177).
  `hs-concordance` keeps its own `EXPECTED`: it predicts for a cohort it chooses,
  spanning several `hm` models, so no single upstream job has its counts.

* The *Work a job* and *Adopt an existing study* articles say to always render a job, never
  to run its chunks by hand: Run All works in the current R session, where a setting
  left by another job can stand in for this job's and read the wrong patients. To
  look at the data, render a draft; to see only the top of a long job, use
  `stop_here()`.

* An `ANALYSIS_SET` the study has not built is named, with the fix: set
  `ANALYSIS_SET <- NULL` to read the registered study dataset. This covers every template
  reading through `read_job_data()` and the deprecated `dp-postage`, which reads its
  analysis set itself. They used to stop with a missing-file path that named neither,
  or, without hvtiRdatabuild installed, ask for it (#173).

* New template, `dc-stddiff`: the balance table. It reports the standardized
  difference of each baseline variable between two groups, from
  `hvtiRpropensity::ps_stddiff()`, the port of the 2019 `%stddiff` macro. The
  comparison is unadjusted, plus the matched set when `MATCH` names its column and
  matching weights when `WEIGHT` does. It counts the variables above a threshold
  (0.10 by default) and draws the differences with `hvtiPlotR::hv_balance()`. `N_PERM`
  adds the `%stddiffci` permutation reference through `ps_stddiff_perm()`. A study
  with three or more arms runs a job per pair, keeping the pair with `WHERE` and
  naming its group 1 with `GROUP_1`. Needs `hvtiRpropensity` 0.1.5 or later, which
  the existing `Suggests` bound of 0.1.7 already covers (#216).

* `hm` stops when the reported fit has no variance matrix, or when any of its free
  parameters has no finite standard error, instead of saving `hm.rds` with only a
  TemporalHazard warning in the log. The message names the phases and covariates
  involved. A degenerate fit, a phase whose `log_mu` has run off, used to fail only
  later in a downstream job (#228). The table that warned of covariates without a
  standard error is gone, since the stop now covers it.

* `hs-concordance` stops in its predictions when a group model gives no confidence
  limits, naming the model and saying its `hm` fit has no usable variance matrix. It
  used to stop later in the decision with "missing value where TRUE/FALSE needed".
  A job that has deleted the decision now stops too, where it used to save
  predictions without limits (#227). Limits that are undefined only because predicted
  survival at `HORIZON` is exactly 0 or 1 stop with their own message, not as a
  missing variance matrix.

* The `add_job()` help page and the template gallery now say plainly what `subject` and
  `type` are: names you choose, with no list to pick from, that name the job file, its
  `SUBJECT` and `TYPE` lines and the folder its results are saved in. Every job of one
  analysis should share them, because the next job in a chain finds the last one's
  results by that pair: `hm` reads `hz.rds` only when it carries the same subject and
  type as `hz`.

* `template_list()` prints only `name`, `prefix`, `qualifier` and `folder`, so the
  listing fits the console. `call` and `file` are still in the data frame: read them
  with `$call` and `$file`, or print a selection such as `tl[, c("name", "call")]`,
  which prints as selected.

* The descriptive templates report the 15th and 85th percentiles where they reported the
  quartiles: `dc-general`'s quantile table, the follow-up tables in `dc-gfup` and
  `dp-eda`, and the variable summaries in `dp-eda` and `dp-postage`. The follow-up tables
  take them from `hvtiRutilities::followup_check()`, whose default changed in
  hvtiRutilities 1.4.5, now the minimum.

* `add_job()` and `open_job()` called without `subject` or `type` now say which is
  missing, explain that both are names you choose (any name matching `^[A-Za-z0-9_]+$`,
  not a list in the catalog), and show the template's own call from `template_list()$call`
  as an example, in place of R's bare "argument is missing, with no default" (#224).

* Now requires R 4.4.0 or newer, up from 4.1.0, to match the rest of the
  HVTI family. `hvtiR::install()` installs the members together, and several
  already required 4.4.0, so on an older R the install failed whatever this
  package declared.

* New tutorial, *Work a job, from template to final report*, for a study author new to
  the package: find a template in the gallery or `template_list()`, add it with its
  `call`, find the `EDIT:` markers three ways, draft and final renders, rendering part
  of a job with `skip` and `stop_here()`, and what the common refusals mean.
* The template gallery is on the package site, at
  <https://ehrlinger.github.io/hvtiRtemplates/gallery/>, linked from the site's
  navbar and the README. Each template shows what it is for, the `add_job()` call
  that adds it, and the report it produces on a synthetic study. The table is
  generated from the catalog and the rendered reports, so it does not drift.
* Help-page examples for the job workflow. `migrate_job()` and `render_job()`, which
  had none, migrate a small legacy SAS job and render a draft and a final. The
  examples for `template_list()`, `template_path()`, `template_catalog()`, `add_job()`
  and `build_cohort()` now find a template by qualifier and copy its `call`, select a
  qualified template, show the refusal to guess an ambiguous prefix and to overwrite a
  job, show a deprecation warning, and read a cohort's attrition table.
* `dc-gfup` prints one follow-up table, a row per interval and patient group (all
  patients, event, censored), in place of five one-row tables. It shows missing,
  negative and zero counts within each group, and one set of quartiles, SAS
  `QNTLDEF=5`, where it printed two that could disagree. The suspicious-row table is
  shown only when there are suspicious rows; otherwise a sentence says there are none.
  `dp-eda`'s follow-up section shows the same table for each death panel.
* `dc-general` prints one frequency table and one quantile table per variable group,
  in place of a frequency table, a one-row count table and a quantile table for every
  variable. Each variable's extremes stay in their own table.
* A conditional table no longer leaves a gap in the table numbering when it is not
  shown.
* A part-built job renders. Give a chunk the option `skip` with the reason in quotes,
  `#| skip: "waiting on the corrected coding"`, to leave it out, or call the new
  `stop_here()` in a chunk to leave out everything below it. This replaces commenting
  unfinished sections out, which the SAS jobs did with a skip macro. A draft lists
  every skipped chunk and stop, by line, in a PARTIAL callout at the top of the report,
  and records them in its provenance. A final render, `render_job(final = TRUE)`,
  refuses them as it refuses an unresolved `EDIT:` marker. Every template carries a
  new `guard-partial` chunk, just after its `EDIT:` guard, that does this.
* `template_list()` gains a `call` column: the `add_job()` call that scaffolds each
  template, with only the arguments it requires and runnable as printed, e.g.
  `add_job("dc-gfup", subject = "cohort", type = "eda")`. The full name selects the
  template on its own, so no `qualifier =` is needed; `subject` and `type` are the
  template's own defaults, shown by name because they are yours to change.
* `dc-gfup` draws the goodness-of-follow-up figure beside its tables, so one job
  covers follow-up. It takes the figure's choices from `dp-gfup` (`OPYRS`,
  `ORIGIN_YEAR`, `CLOSE_DATE`, `PANELS`, `EVENTS`, `ALPHA` and `COLORS`), adds the
  operation-year and close-date table, and saves `dc-gfup-*.png` to `graphs/`. It
  now needs hvtiPlotR >= 2.8.0.
* `dp-gfup` is deprecated in favor of `dc-gfup` and will be removed in a later
  release. It still scaffolds; `template_path()`, `add_job()` and `open_job()` warn,
  and `migrate_job()` writes a `dc-gfup` job.

* `DESCRIPTION` now declares the Quarto command line tool in
  `SystemRequirements`. The vignettes have always needed it to build; the
  field makes that visible to installers and to `R CMD check`.

* **Every template figure is saved as a PNG and a PDF.** Figures go to the
  job's `graphs/<subject>-<type>/` folder as a 300 dpi PNG, for a Word draft,
  and a PDF of the same name with fonts embedded, for the publisher. Eight
  templates saved a PNG before, at 150 dpi; eleven (bc, bh, bl, br,
  nb-boostmtree and the six random-forest templates) only printed their
  figures. Each job's study choices gain `SAVE_FIGURES` and `FIGURES` to turn
  saving off or keep only some figures by name; `inst/templates/README.md`
  lists the names. A PNG the report shows keeps its name and is always written.
  The PDF falls back to the default `pdf()` device where `cairo_pdf()` cannot
  open, as on a Mac without XQuartz, whose R reports cairo as available anyway.

* `rfc-explain`, `rfs-explain` and `rfr-explain` key their partial-dependence
  cache on randomForestSRC, which computes it. The cache was keyed on
  ggRandomForests alone, so after a randomForestSRC upgrade it stayed valid and
  `REFIT = TRUE` kept the old result while the variable importance beside it was
  recomputed. The `gg_partial_rfsrc()` call now passes
  `packages = "randomForestSRC"` to `cache_fit()`; the VarPro partial is
  unchanged, since its varpro fit already carries varPro's version. Each
  existing `rf?-partial` cache goes stale exactly once, reporting
  `packages$randomForestSRC (absent) -> x.y.z`, and needs one render with
  `REFIT = TRUE`. Requires hvtiRutilities 1.5.0 or newer, up from 1.4.5.

* **Templates name the study dataset `"built"`, the team's word for it.** Every
  job's study choices now say `DATASET <- "built"`, and so do the `bc`, `bh`,
  `bl` and `br` runners and the jobs `migrate_job()` writes. `"study"` still
  works, so a job scaffolded before this change keeps running unchanged, and a
  downstream job agrees with an upstream one whichever name each used. Records
  still say `"study"`: the selection a job hands on and its provenance sidecar
  compare equal under either name. Requires hvtiRutilities 1.5.1, which made
  `"built"` a second name for the study dataset.

* **Jobs are named template first, with periods.** `add_job()` writes
  `<prefix>[.<qualifier>].<subject>.<type>.qmd`, such as `ac.death.hz.qmd` or
  `dp.trends.cohort.eda.qmd`, and a bootstrap job's runner beside it as
  `<prefix>.<subject>.<type>.runner.R`, so a study's jobs sort by template,
  then subject, then type. Jobs scaffolded before this release keep their
  `<subject>-<type>-<prefix>[-<qualifier>]` names and keep rendering: every
  template's name check reads both spellings. `add_job()` and `migrate_job()`
  refuse to write a second copy of a job that exists under its old name, and
  `open_job()` opens it. `template_list()` shows qualified templates as
  `dp.trends`, and its `call` column uses that name; `"dp-trends"` is still
  accepted. Results folders (`estimates/<subject>-<type>/`,
  `graphs/<subject>-<type>/`) are unchanged.
* `add_job()` also refuses when only a job's runner remains under its old `-runner.R`
  name, so an edited runner is never left behind beside a new, empty one.

* **Jobs can join an ancillary dataset to their cohort.** `read_job_data()`
  gains `join`, `join_vars`, `reduce` and `join_key`, and the study choices of
  every template that reads its own data gain `JOIN`, `JOIN_VARS`, `REDUCE`
  and `JOIN_KEY`, all `NULL` and without an `EDIT:` marker, so a finished job
  is unchanged. `JOIN` names one dataset registered with
  `kind = "ancillary"`, such as echoes or labs. The cohort decides the
  patients and must be one row per patient; the join keeps one row per joined
  record, keyed on that dataset's key, or one row per patient with
  `REDUCE = list(rule = "first" | "last" | "nearest", by = ...)`. A tie on
  `by` stops rather than pick one record silently, and so does a join that
  matches no cohort patient at all, which is a mismatch of identifiers.
  `WHERE` applies to the joined rows. The job's data table names the joined dataset and its rows,
  counts its records outside the cohort and the cohort patients with none, and
  names the reduction; its provenance records the joined dataset's version. A
  downstream job rebuilds the same join from its upstream job's selection.
  A template that models one row per patient (`ac`, `hz`, every `lm-*`,
  `rfc-fit`, `rfr-fit`, `rfs-fit`, `dc-stddiff`, `dc-gfup`, `dp-gfup` and
  `hs-concordance`) passes `read_job_data(one_row_per_patient = TRUE)` and stops on a `JOIN` without
  `REDUCE` before reading any data, since the long form would count every
  joined record as a patient; the other descriptive templates and
  `nb-boostmtree` keep the long form.
* `read_job_data()`'s `key` now defaults to the key registered for the dataset
  (hvtiRutilities 1.5.1), and to `id` when none is registered, as before. A
  `KEY` or `JOIN_KEY` that differs from the registered key is used, and noted
  in the data table. Templates set `KEY` themselves, so they read the same
  rows as before, with that note when the study registered another key.
* A stale analysis set that hvtiRdatabuild reads in a draft render is now a
  note in the job's data table, as an out-of-date dataset already was, rather
  than a message wherever the chunk prints it.

* **With `REDUCE`, `WHERE` on a joined column now filters the records before
  one is chosen per patient** (maintainer's decision). `REDUCE <- list(rule =
  "last", by = "echo_date")` with `WHERE <- quote(echo_type == "TTE")` keeps
  each patient's last TTE, where it used to keep the last echo and then drop
  the patient if that echo was not a TTE. A condition on cohort columns still
  filters the reduced rows. The data table shows the record filter between the
  join and the reduction, and counts the patients left with no record after
  it; the selection records the conditions in the order written.
* `REDUCE`'s `by` may name several columns, such as
  `c("echo_date", "echo_seq")`: each later one breaks a tie on those before
  it, in the rule's direction, and a missing tie-break value loses the tie
  rather than dropping the record. A tie that remains still stops (maintainer's
  decision), and the message now says what tied (for `"nearest"`, records
  equally far from the target, not "the same date"), how many patients, and
  how to break it. `by` and `to` match their columns ignoring case, as every
  other column setting does.
* `nb-boostmtree` takes a long join whose visit time is only in the joined
  dataset: a `KEY` that names a joined column is checked on the joined rows.
  A `KEY` of cohort columns is checked on the cohort, as before.
* A join stops when some joined identifiers match the cohort's only once
  surrounding spaces, leading zeros or letter case are set aside, instead of
  counting those records as outside the cohort. The message gives counts
  only. A cohort row with a missing identifier stops a join as missing, rather
  than as a repeated patient. A long join keeps the cohort's identifier type.
* `key_hash` covers the joined dataset's key, so a downstream job sees that
  `REDUCE` chose a different record for a patient. `hm`, `hp` and `hs-setup`
  record the joined dataset's provenance when they rebuild a joined
  selection. A selection without a join carries no empty join fields, and a
  join's `REDUCE` and `JOIN_VARS` are recorded as resolved, so the same join
  written two ways records the same selection and `hp` accepts matching `ac`
  and `hz` hand-offs. `hp`'s mismatch message names the join settings. A
  downstream `JOIN` or `REDUCE` against an upstream selection that read no
  join stops and names the setting.
* `read_job_data(one_row_per_patient = TRUE)` also stops when the rows kept
  repeat a patient, as a dataset of repeated records read whole would. Its
  refusal names the templates that take repeated records (`dc-general`,
  `dc-tables`, `dp-eda`, `dp-trends`, `nb-boostmtree`), read from the
  templates themselves. A patient whose records all lack the `by` value is no
  longer counted again as a patient with no record; the "no reduction value"
  row says how many patients it leaves with no record chosen.
* `KEY <- ID` no longer draws a "differs from the registered key" note when
  the ID falls back to MRN on a dataset registered on its MRN.
* `stop_here()` refuses a final render itself, so one the source scan cannot
  see (inside `if ()`, or called with an argument) no longer truncates a final
  report silently; in a draft it is recorded as a partial-render stop.
* A job's name is read through knitr's `.knit.md` and `.utf8.md`
  intermediates. `dc-stddiff` asks for hvtiRpropensity 0.1.7, as DESCRIPTION
  does. The cairo probe runs once a session. `dp-gfup`'s deprecation note names
  `add_job("dc.gfup", ...)`. DESCRIPTION spells out the Heart, Vascular and
  Thoracic Institute.

# hvtiRtemplates 1.2.5

* Every figure and table a template shows is numbered. Quarto numbers a figure only
  with a `fig-` label and `fig-cap`, and a table only with a `tbl-` label and `tbl-cap`;
  a `knitr::kable(caption = )` caption prints without a number. All 33 templates now
  carry numbered labels and captions, table captions moved into `tbl-cap`, chunks that
  showed several outputs are split, and loops that show one table or figure per item
  emit each as its own `knitr::knit_child()` chunk, so every item is numbered and
  citable. Chunks that hold `EDIT:` choices no longer also show output. A job built
  from a template starts numbered.
* New `test-template-numbering.R` enforces the rule for every template, and rejects
  the retired ColorBrewer palettes (`"Set1"`, `"Set2"`, `"Dark2"`, `"RdYlGn"` and
  others); categorical groups take `hvtiPlotR::hv_palette()`. A chunk that calls a
  table or figure function without showing one says so with
  `# unnumbered: <reason>`.
* `inst/templates/README.md` gains "Figures, tables and color", pointing to the
  recipes book chapter
  [Numbering figures and tables](https://ehrlinger.github.io/hvtiGraphics/numbering.html).
* The label `data` is now `tbl-data` in every template (dp-postage keeps `data`),
  with the other renames listed in the tests that extract chunks by label.

# hvtiRtemplates 1.2.4

* `ggBoostedTrees` is required at 0.9.1 or later. `boostmtree` now arrives only through
  `ggBoostedTrees`'s `Remotes:`, and 0.9.1 is the first release that pins the `v2.0.3-ccf` tag
  this package's `boostmtree (>= 2.0.3)` floor needs.

* New template `00_datasets/bd.qmd`, the first at the `00_datasets` level: a build job that cuts a study's
  dataset from a master snapshot, applies a cohort list and ordered exclusion rules (`condition ~ "Reason"`, where
  a missing condition is not excluded and is counted), derives the study's own variables, writes a draft, and with
  `PUBLISH <- TRUE` publishes a dated release with `hvtiRdatabuild::publish_dataset()` and registers it, or adopts
  it when an older release is registered. Its report shows counts and no code, so a rule naming a patient stays out
  of the HTML. New `build_cohort()` carries the cohort and attrition step (#223). The
  catalog lists `bd` as in flight: it is released so the stat programmers can review it in a real study, and it
  is marked shipped once they have and a timed render against the real master is recorded.

* `boostmtree` now comes from the CCF fork through `ggBoostedTrees`'s own
  `Remotes:` rather than a tag pinned here, with a floor of 2.0.3. The two had
  pinned different tags of the fork, so dependency resolution failed before
  any check ran; with one pin they cannot drift apart again. The
  `nb-boostmtree` install hint names the `v2.0.3-ccf` tag that
  `ggBoostedTrees` 0.9.1 installs from.

* Every template's HTML now reads full width with its contents on the left
  (`page-layout: full`, `toc-location: left`, a 2000px body ceiling and a
  250px sidebar), alongside the existing `embed-resources: true`. A new test
  checks all of it in every template's own header, so a copied template stays
  self-contained and laid out the same.

# hvtiRtemplates 1.2.3

* `read_job_data()` stops on a `WHERE` condition that mentions the patient
  identifier or a column named MRN or eMRN, directly or through `.data$x` or
  `.data[["x"]]`, before any row is filtered. A column reached any other way,
  as by `.data[[paste0(...)]]`, `get()` or another name bound to `get()`,
  stops too, since it could be the identifier. Values are checked as well as
  names, after every name check: the check covers literal values (including
  an outside vector of IDs) of five or more characters that equal a value of
  the identifier, MRN or eMRN in the data, and folds only arithmetic, `c()`,
  `paste`/`paste0` and numeric or character coercion of constants (such as
  `4730000000 + 1`) to check their result. So a wrapper function or a copy of
  the ID under another name is caught when compared with such a value. The
  check never calls any other function: a value produced by any other call,
  or computed from a data column, as in `id2 / 2 != 2365000000.5`, is not
  checked, and a refused condition runs no code. A threshold that happens to equal
  a patient's identifier is refused too, and the message says so. Thresholds
  shorter than five characters, such as 1, 18 or 2015, are not checked, so a
  study keyed on shorter identifiers relies on the name checks. Each condition
  is saved, values included, in the job's output, so a filter on identifier
  values would be saved with it. Exclude those patients in the dataset build,
  or with an hvtiRdatabuild analysis set. A downstream job
  rebuilding an upstream file saved with such a condition names the file and
  says to rerun the upstream job.

* `read_job_data()` stops on a `WHERE` that takes a data frame, list,
  environment or S4 object from outside the data, as
  `with(lookup, age) > 20` does. The condition is saved as text, so the whole
  object, ID column included, was saved with it; the message names the variable
  and says to filter on a column of the data instead. An outside `NULL` is now
  fixed in rather than dropped from the call. Closes #218.

* The bootstrap reports print the data selection their bag carries, and their
  runners read data through `read_job_data()`. Each runner is its own job:
  `add_job()` for `bl`, `br`, `bc` and `bh` also writes
  `<subject>-<type>-<prefix>-runner.R` beside the report, with its study
  choices marked `EDIT:`, and refuses to overwrite one. A runner stops until
  its `FINISHED` is set to `TRUE`, and checks its package floor
  (hvtiRbootstrap 0.9.3, TemporalHazard 1.2.8) before it screens, so a long
  run cannot finish only to be refused. The runner saves the
  selection in the bag's lineage and resamples only the model's columns.
  `WHERE`, `ID` and `KEY` in the report confirm the runner's values, and the
  collinearity table reads the rows the runner screened rather than the whole
  dataset. **A bag saved before this change carries no selection, and its
  report stops: rerun its runner.** So does a `bh` pool whose chunks were run
  on different rows.

* A bootstrap report stops on a bag that carries a patient identifier. The
  check is by name: it finds a field, column or matrix column named for the
  job's `ID`, `MRN` or `eMRN`, anywhere in the bag or its carried lineage,
  including inside the environment a saved formula or function carries. An
  active binding there is reported, never evaluated. It does not find an ID
  stored under another name or used as row names, nor data in an environment
  it does not read (a package or the global environment, or an unforced
  promise).

* `BOOTSTRAP_DATA` is removed from the bootstrap reports. A bag must come from
  its runner, which attaches the lineage and selection the report reads.

* `nb-boostmtree` is a new template: boosted multivariate trees for a
  response measured repeatedly over follow-up, fitted with `boostmtree` 2.0.2
  or later from the CCF fork (`ehrlinger/boostmtree_src`), whose fix the CRAN
  release lacks, and reported with ggBoostedTrees 0.9.0 or later. `KEY`
  defaults to the ID and the visit time. Patients are grouped by the
  study-keyed digest, so the fit, its cache and the saved file hold no patient
  ID. `PREDICTORS <- NULL` takes every column but the ID, the `KEY` columns,
  the time, the response and any ccfid, MRN or eMRN column, and names the
  identifier columns it left out; named `PREDICTORS` may hold none of those,
  nor a name twice. The partial effects of every response component come in
  one figure, faceted by component as ggBoostedTrees 0.9.0 draws them, with
  continuous and factor covariates in separate figures because one figure
  cannot hold both. BoostMLR (`nb-boostmlr`) is still to come; the
  ggBoostedTrees support it waited on shipped in 0.9.0.

* New template `hs-concordance`: every patient predicted through every
  treatment group's `hm` model at one horizon, the job the corpus calls
  concordance and discordance. It reads each group's model from that
  group's own set, saves one long artifact, `hs-concordance.rds`, and has
  an optional section that picks a best treatment per patient only where
  the confidence limits separate it. Design:
  `dev/specs/2026-09-30-hs-concordance-design.md`.

* The `hs` template is now `hs-setup`, because `hs` carries two job types
  and a prefix is either wholly qualified or wholly unqualified. The file's
  contents are unchanged and it still saves `hs.rds`.
  `add_job("hs", ...)`, `template_path("hs")` and `open_job("hs", ...)`
  without a qualifier stop and list `setup` and `concordance`. Migrating a
  SAS `hs` job needs `qualifier =` too: its filename's second field is the
  endpoint, not the job type.
  Jobs already scaffolded keep their names. `open_job("hs", ...,
  qualifier = "setup")` looks for `<subject>-<type>-hs-setup.qmd`, so in a
  study that already has `<subject>-<type>-hs.qmd` it scaffolds a fresh job
  beside it. Open the existing job by its file.

* `hs-setup` now requires TemporalHazard >= 1.2.12 and says what its
  `se.fit` column is. On the survival path it is se(S), the standard error of
  the survival estimate itself. A TemporalHazard build without #281 wrote
  se(H) into the same column, and #281 shipped inside version 1.2.11, so which
  one an `hs.rds` holds depends on the build that produced it, not on when it
  was written. The render stops on an older build instead of writing an
  ambiguous file, and the `Suggests` floor for TemporalHazard rises from 1.2.8
  to 1.2.12 to match.

* `hz` renders again with TemporalHazard 1.2.11. Its convergence table read
  an iteration count that a multiphase fit does not carry, so every render
  stopped there. The table now reports the optimizer's function and gradient
  evaluations, and shows "not reported" for a field a fit leaves out, so a
  missing field cannot stop the render (#168).

* `read_job_data()` is the shared data step for templates: it reads a
  registered dataset or analysis set, resolves the patient ID (`ccfid`, then
  `MRN`, then `eMRN`), drops `MRN` and `eMRN`, keeps the rows `WHERE`
  selects with `dplyr::filter()` rules, checks rows are unique on `KEY`, and
  records what it did. `ID` and `KEY` match their columns ignoring case, the
  values of a `WHERE` condition on `ID` or `KEY` are never printed, and an
  analysis set's attrition is returned with the data. A value `WHERE` takes
  from outside the data, such as `.env$min_age`, is fixed into the recorded
  condition when the data are read. A downstream job
  rebuilds its upstream job's rows from the selection the upstream hand-off
  carries, and stops when that hand-off predates it. Templates adopt it
  family by family.

* The descriptive templates and `dp-trends` read their data through
  `read_job_data()`: `ANALYSIS_SET` defaults to `NULL`, so they run on a newly
  registered study; `WHERE`, `ID` and `KEY` are new settings; `dc-general`'s
  `KEY_COLS` is `ID`; and `dp-eda` leaves the job's `ID` and `KEY` columns
  out, never draws the `ID`, and draws a `KEY` column such as a visit time only
  when `VARIABLES` names it. The deprecated `dp-postage` keeps its own data step. Every template's setup
  chunk says to run `study_setup()` when it is not inside a study.

* The logistic templates read their data through `read_job_data()`; `ID`
  defaults to `"ccfid"` (it was `"id"`, which no built dataset carries), and
  `lm-checkpred` stops when its validation patients were in the training data:
  its validation cohort is `DATASET` or `WHERE` like any job's.

* The `lm` templates save a study-keyed digest of each patient ID in their
  model files, not the ID, so a model keyed on `MRN` no longer stores MRNs.
  The key is made on first use in the study's `.hvti/` folder. `lm-checkpred`
  digests its validation IDs with the same key and compares digests; a model
  saved before this change still validates.

* The hazard chain reads its data through `read_job_data()`: `STATUS` is
  `EVENT`, the `iu_dead`/`idead` defaults are `iv_dead`/`dead`, the filter
  typed into every job is one `WHERE` in `ac` and `hz`, and `hm`, `hp` and
  `hs` take `WHERE`, `ID`, `KEY`, `TIME` and `EVENT` from `hz`'s saved fit,
  stopping if their own differ. `hp` also stops when `ac` and `hz` read
  different rows. `hm` fits on the model's columns only, so `hm.rds` no longer
  keeps the patient ID or MRN in its saved fits.

* The random-forest templates read their data through `read_job_data()`,
  gaining `WHERE`, `ID` and `KEY`; text predictors are converted to factors
  with a note; `explain` jobs take the fit's selection. `rfs-fit`'s `STATUS`
  is `EVENT`. A fit stops when `PREDICTORS` names the patient ID or a `KEY`
  column, or when an outcome (`TIME`, `EVENT` or `RESPONSE`) is the patient
  ID. A `KEY` column that is not the ID, such as a visit time, may still be an
  outcome, and is then saved with the forest. The forest's formula no longer
  carries the job's environment, so the saved forest and the `explain` caches
  hold no patient ID or MRN wherever the job is run. An `explain` job stops
  on a forest saved before this change; rerun its fit job first.

* `dp-postage` is deprecated in favor of `dp-eda`, and will be removed in the
  release after 1.2.3. For the same pages, scaffold
  `add_job("dp", subject, type, qualifier = "eda")` and set
  `SECTIONS <- c("continuous", "percent", "count")`: the sections call
  `hv_eda_pages()` with the same arguments, and a test checks that the pages
  match `dp-postage`'s byte for byte. They are saved as `dp-eda-*.png`.
  `dp-postage` still scaffolds and renders; `add_job()`, `open_job()` and
  `template_path()` warn once when it is used. The template catalog marks it
  with two new fields, `deprecated_by` and `deprecation_note`, which
  `template_catalog()` returns and the warning reads.

* `migrate_job()` now writes a `dp-eda` job for a legacy EDA report (the
  `tp.dp.DescriptiveSummary.qmd` and `tp.dp.EDA_barplots_scatterplots*.R`
  lineage), carrying over the same settings as before, `VARIABLES`, `X_VAR`,
  `EXCLUDE`, the grid size and `UNIQUE_LIMIT`, and leaving the color and
  stratification choices for review. The job draws
  `SECTIONS <- c("continuous", "percent", "count")`, because a legacy EDA
  report had no follow-up panels. Naming `qualifier = "postage"` warns and
  writes the `dp-eda` job.

* `dp-eda` and `dp-postage` take the medical record number as an identifier
  only under the exact names `MRN` and `eMRN` (ignoring case). They matched
  `mrn` anywhere in a name, so an mRNA variable such as `bnp_mrna` was left out
  as an identifier. The rule matches hvtiPlotR's `hv_eda_pages()`
  (hvtiPlotR#172).

* The data-route tests pass when run on their own. They evaluated template
  chunks that call `study_config()` without supplying it, so they depended on
  an earlier test file having attached hvtiRutilities, and a filtered run
  errored twice. No change to the templates.

* Every template chunk holding an `EDIT:` marker is now labeled `edit-`, so
  the editor's chunk outline lists the work a job still needs:
  `study-choices` is `edit-study-choices`, and nine templates carry further
  `edit-` chunks such as `edit-cohort` and `edit-derive`. The marker guard,
  `edit-guard`, is renamed `guard-edits` so it does not read as an edit site.
  A test holds the rule in both directions. Existing jobs keep their old
  labels and still render.

* `add_job()`, `open_job()`, `template_path()` and `migrate_job()` accept a
  template's full name, the `name` column of `template_list()`, in place of
  the prefix and qualifier pair: `add_job("dp-trends", "cohort", "eda")`. An
  error asking which template now lists the choices by full name. Giving a full name
  and a `qualifier` together is an error rather than a silent preference for
  either. A bare qualifier is not accepted, because `fit`, `explain` and
  `gfup` each name more than one template.

* The EDA abbreviation tests hold once hvtiRutilities carries its group
  abbreviation list (1.4.3). Four tests assumed the group list was empty and
  failed on every platform after it merged: they now turn the group list off
  when testing the job, study and initials levels, `dp-eda`'s provenance check
  finds its entry by position rather than by a name every row shares, and a
  new test checks that the group list does shorten labels when it is present.
  No change to the templates.

* `dp-postage` names its source correctly. Its header said it replaced the
  older `tp.dp.EDA_barplots_scatterplots*.R` sweep; it was built from the
  per-variable grid of the legacy EDA report, `tp.dp.DescriptiveSummary.qmd`,
  as the catalog records. The `EDIT:` note now names both, since a study's job
  may be a copy of either, and the descriptive migration vignette maps both.

* New template `dp-eda` (`10_descriptive/`), the whole EDA report in one
  render: an overview of every column (`proc_contents()`), goodness of
  follow-up with `dc-gfup`'s tables, then continuous variables, categorical
  variables as percentages and categorical variables as counts, each with its
  table. `SECTIONS` picks any subset; the report keeps that order. Each
  section calls the function its standalone job calls (`hv_followup_panels()`,
  `followup_check()`, `hv_eda_pages()`) with the same arguments, so a section
  is that job's figure; `test-dp-eda.R` checks the pages byte for byte against
  `dp-postage`. Needs hvtiPlotR 2.7.18 and hvtiRutilities 1.4.2, the current
  floors. It draws in the house colors and shortens labels in the house
  style (both below).

* `dp-postage` and `dp-eda` leave out identifiers written without a
  separator. Under `VARIABLES <- NULL` a column named `ccfid` or `patientid`
  passed the identifier rule, which wanted `id` as its own `_`-delimited
  token, and was drawn as one bar per patient and listed in the frequency
  table. The rule now also takes `ccfid`, `patid`, `patientid`, `studyid`,
  `subjectid`, `recordid`, `caseid` (each also with `_`, `num` or `no`),
  the exact names `MRN` and `eMRN`, and any text or factor
  column of ten or more values in which every value differs. A bare trailing `id` was declined: it would take `carotid`
  and `steroid`. The report lists what it left out, and naming a column in
  `VARIABLES` still draws it. `dp-eda`'s overview table leaves identifiers
  out too, whatever `VARIABLES` says, and names them beneath the table; date
  columns stay in it, because their share missing is worth seeing.

* `dc-general` explains each study choice where it is made. The notes on
  `CATEGORICAL`, `CONTINUOUS`, `CORR_VARS`, `KEY_COLS` and `ID_COL` sat in a
  `spec` chunk ninety lines below the settings they describe; they now sit
  beside them in `edit-study-choices`, and the empty chunk is gone. No change to
  what the job does. From Lauren's 2026-09-24 review.

* **The EDA templates draw in the house colors, which are colorblind safe.**
  `dp-postage` and `dp-eda` color their categorical pages with
  `hvtiPlotR::scale_fill_hv()`: each panel runs blue, vermillion, green and on
  from its own levels, and missing is light gray. `dp-gfup` and `dp-eda`'s
  follow-up section use `scale_color_hv()`. **The follow-up figures change
  color:** dead moves from Set1 red `#E41A1C` to vermillion `#D55E00`, alive
  from `#377EB8` to `#0072B2`, and a non-fatal event from `#4DAF4A` to
  `#009E73`. The pattern of red, blue and green is kept. `COLORS` is now
  `NULL` by default; name `alive`, `dead` and `event` to choose your own, and
  `c(alive = "#377EB8", dead = "#E41A1C", event = "#4DAF4A")` restores the
  earlier colors. Needs hvtiPlotR 2.7.18, now the floor.

* **`dp-gfup`'s `COLOURS` setting is renamed `COLORS`**, and `dp-eda` uses the
  same name. A `study-choices` chunk copied from an older job that still sets
  `COLOURS` stops with "COLOURS is now COLORS" rather than drawing the default
  colors without a word. Rename the setting in `study-choices` (`edit-study-choices` in a new job); its values are
  unchanged.

* The templates, their comments, the reference pages and these notes use US
  spelling. The templates call `scale_color_manual()` and `labs(color = )`,
  which ggplot2 treats as identical to their British spellings, and
  `hvtiPlotR::scale_color_hv()`, which needs hvtiPlotR 2.8.0, now the floor.
  `tools/check-us-spelling.sh` now fails the lint workflow on a British
  spelling.

* **`dp-postage` and `dp-eda` keep shortened labels distinct**, through
  `hvtiRutilities::label_map()`. Two new edit points: `LABEL_MAX` (default
  40), the longest label a figure or table shows, and `ABBREVIATIONS`
  (default `NULL`), the job's own abbreviations as `c("Phrase" = "Abbrev")`.
  The job merges them over the study's `abbreviations:` in `_study.yml` and the
  group default list with `hvtiRutilities::study_abbreviations()`, so every
  job in a study shortens labels the same way. Labels that share a heading
  over the cap show it abbreviated (`Surgical procedure: ...` becomes
  `SP: ...`), and each section prints a key of the abbreviations its shortened
  labels show. A wrong `LABEL_MAX` or `ABBREVIATIONS` stops the render with
  a message naming it, as the other edit points do. The cap and the merged list, with each entry's level, are recorded in
  the report's provenance. The settings apply to the figure pages and their
  captions; tables, including `dp-eda`'s Overview, keep full labels, so a
  reader can look up what a shortened label stands for. Needs hvtiRutilities
  1.4.2, now the floor; a migrated `dp-postage` job keeps both edit points at
  their defaults.

# hvtiRtemplates 1.2.2

* `DESCRIPTION`: a plain `&` in the Description (`\&` is not a valid escape
  there and printed a literal backslash), and a copyright holder in
  Authors@R. Both from the 1.2.2 release gate's CRAN Cookbook audit.

* `dc-gfup` and `dp-gfup` compute through shared functions, so the EDA report
  can call the same ones: `hvtiRutilities::followup_check()` for the follow-up
  tables and `hvtiPlotR::hv_followup_panels()` for the panels and their study
  window. The numbers and figures are unchanged. The validation errors now
  come from those functions and name their arguments (`` `event` ``,
  `` `origin_year` `` and so on) rather than the template's `EDIT:`
  constants, and `dc-gfup`'s unknown-column error reads "Unknown column(s)".
  Needs hvtiRutilities 1.4.1 and hvtiPlotR 2.7.17.

* Two vignette tests, on the SAS guide and on the tutorials' study root, now
  read the installed `doc/` copy when the source checkout is absent. Under
  `R CMD check` they had skipped on every platform since 2026-09-21.

* The legacy-article vignette test uses the same checkout-then-`doc/` lookup,
  and the `rfr-explain` test silences varPro 3.3.0's notice that it drops rows
  with missing values, so `R CMD check` reports no warnings.

* `dp-postage` draws in sections. `SECTIONS <- c("continuous", "percent",
  "count")` replaces `SHOW_PERCENT`, so one render shows the categorical
  variables both as percentages and as counts, with the same year bins. Each
  section opens with its table: `proc_means()` for continuous variables, and
  one `proc_freq()` table, missing counted, for the categorical ones.
  `VARIABLES <- NULL` is the new default and draws every column except `X_VAR`,
  `EXCLUDE` and any column that looks like an identifier or a date, which the
  report lists. `ALPHA` (0.5) sets point transparency. The pages come from
  `hvtiPlotR::hv_eda_pages()`, so the job needs hvtiPlotR 2.7.16.

* `migrate_job()` no longer carries a legacy `show_percent` into a
  `dp-postage` job; it records it as replaced by `SECTIONS`, whose default
  draws both views. A legacy point alpha now carries over into `ALPHA`, and a
  job with no variable list starts from `VARIABLES <- NULL`.

* New vignette, *The template catalog*: every template with a one-line
  description, the `add_job()` call that scaffolds it, and a delivery light
  (shipped, in progress, not yet on the way), grouped by study folder, followed
  by the queued job types ordered by how many studies carry them. It is built
  from the catalog when rendered, so it cannot fall out of date.

* `template_catalog()` gains a `description` column. Every template on disk
  has one, which a test and `check-roadmap-counts.py` both enforce.

* New `dp-gfup` template (`40_graphs/`): the goodness-of-follow-up figure over
  `hvtiPlotR::hv_followup()`. One panel per death indicator and an optional
  panel per non-fatal event; blue is alive, red is dead, and points are drawn
  at alpha 0.5. The close date is an edit point, estimated from the data when
  left `NULL`, and the report says which it drew. Every column named in the
  study choices is checked at once, so one render lists every missing name.

* `dc-gfup` now renders its cohort, interval, `proc_means()`, suspicious-row
  and cross-tab results as tables rather than printed console output, and
  points to `dp-gfup` for the figure.

* **Breaking:** `add_job()`, `open_job()`, and `migrate_job()` rename their
  public `endpoint` argument to `subject`, and templates rename their
  `ENDPOINT` marker to `SUBJECT`. Job sets are now named by **subject**, the
  leading grouping topic in `<subject>-<type>-<prefix>[-<qualifier>].qmd`.
  A subject can be a statistical endpoint such as `death`, or an endpoint-free
  topic such as `cohort`. Jobs now own their outcome and cohort definitions;
  dataset registration does not choose them.

* Requires hvtiRutilities 1.4.0 or later, whose endpoint-neutral study
  registration the subject-based jobs depend on. The floor is now 1.4.1, for
  `followup_check()` (see the `dc-gfup` entry above).

* Every scaffolded job now captures provenance while it executes, safely
  embeds that payload in its completed HTML, and publishes a same-stem
  `.provenance.json` sidecar through study-level Quarto hooks. `add_job()`
  installs the hooks idempotently without replacing existing project settings
  or user hooks. Publication follows Quarto's actual output paths, invalidates
  only the inputs being rendered, preserves prior sidecars when a failed render
  leaves its outputs untouched, and durably tracks multi-output publication.
  Failed publication removes partial new sidecars and restores a prior sidecar
  only while its recorded output hash still matches, retaining mismatched
  backups for explicit recovery.
  Records always carry the runtime subject and type and add only the analysis
  and observed-cohort facts the job actually used.

* Saved model and report handoffs now carry immutable `hvti_provenance`
  lineage. Random-forest explainers, logistic validation, bootstrap reports,
  and the actuarial-to-hazard graph chain retain their producers' data records
  and hash every artifact they read. A package handoff without lineage stops
  with rebuild guidance; external bootstrap artifacts instead require explicit
  original data records. The `ac` template now saves its overall life table as
  the real upstream artifact consumed by `hp`.

* All eight logistic-family templates now record their runtime model and
  cohort metadata. Records distinguish outcomes, treatments and count
  exposures; retain accepted and observed levels and applicable coding; and
  report the fitted formula, family, method, predictors, imputation details,
  and analyzed-row accounting. Stacked-imputation totals are labeled as
  stacked rows and accompanied by per-imputation counts. `lm-checkpred` keeps
  the source model's training metadata separate from the validation cohort it
  observes.

* New vignette, "Start a new study from a delivered dataset", takes a study
  from its Study Tracker record and the `study-setup` command through
  registration, a first descriptive job and its provenance sidecar, to a first
  `ac`, `hz` and `hp` chain. It complements "Adopt an existing study".

* The provenance test that asserts an embedded payload carries exactly one
  `<script` tag now counts real matches. `gregexpr()` reports no match as a
  length-one `-1`, so the old assertion also passed when the tag was missing.

# hvtiRtemplates 1.2.1

* Eight qualified `lm` templates now cover binary, ordinal and nominal outcome
  models; the corresponding three propensity shapes; saved binary-model
  validation without refitting; and count balancing scores. They use
  `hvtiRpropensity 0.1.7` model bundles, retain per-imputation fits, display
  Rubin-pooled estimates and covariance, and save their reviewed bundles below
  the analysis set's `estimates/` directory.

* **The study setup tutorial now follows one adoption path through the complete
  pre-analysis workflow.** It starts from an existing dataset opened as an
  RStudio Project, preserves an existing R-version pin or selects R 4.6 when
  none exists, and adopts the study without changing its working-directory
  layout or deleting `.git`, `tp.*` or copied template directories. Cleanup is
  deferred to a separate operational command. The tutorial registers data,
  declares and writes the `eda` analysis set, and explains how the descriptive
  and plot job names work before an endpoint or analysis type has been chosen.
  It also warns that `update_manifest()` alone cannot safely refresh a
  registered dataset while `_study.yml` still carries cohort metadata. `fs`
  and `yaml` join `Suggests` because the executable article writes the
  synthetic analysis-set declarations it teaches without replacing other
  sets.

* Six random forest templates: `rfs`, `rfc` and `rfr`, for survival,
  classification and continuous outcomes, each as a `fit` job and an `explain`
  job. The fit job grows the forest through `hvtiRutilities::cache_fit()` and
  saves it for the explain job, which reads it back for VIMP, VarPro and
  dependence plots and never refits. Old `rfsrc.*` and `rf.*` jobs map onto
  the three by outcome; `inst/templates/README.md` has the table. Fit jobs
  refuse outcomes or duplicate names in `PREDICTORS`, and `rfc-fit` requires
  the study to name the class whose one-versus-rest ROC curve it reports.
  `randomForestSRC (>= 3.7.0)` and `varPro (>= 3.2.0)` join Suggests, and
  `ggRandomForests` rises to `>= 4.0.0`.

* All 28 shipped job templates put editable study choices in one chunk near
  the top. Reading data and building output happen below those choices; SAS
  migration continues to fill the same settings.

* The 65-row template catalog now ships as `inst/extdata/templates.json` and
  is available through `template_catalog()`. Roadmap checks read this local
  catalog, the two CI catalog pins are removed, and the `hvtiRutilities`
  minimum is 1.3.0 for its machine-readable umbrella marker. The separate
  strict CI step is retired: with the catalog in the tarball, the first CI
  run showed every check leg running the catalog tests (`SKIP 0` on macOS and
  Ubuntu; `SKIP 1` on Windows, a deliberate POSIX-permissions skip).

* **The intake-row guard no longer goes quiet when intake is empty.** It
  asserted inside a `for` over the intake rows, so with none left it made no
  expectation at all; testthat reports that as an empty test, which reports as
  a SKIP. The strict CI step expects `SKIP 0`, but `HVTI_ROADMAP_STRICT` only
  promotes the helper-driven skips to hard stops and `stop_on_failure` does
  not fire on a skip, so the gate would have gone quiet under a green check.
  Its logic now lives in a helper that returns a value, so the check is an
  assertion at any row count, and a new test drives the empty case from a
  temporary catalog. That matters because CI reads the real catalog from a
  pinned `hvtiR` tag, which still has intake rows, so the empty path would
  otherwise never run there. `with_temp_catalog()` moves to `helper-ledger.R`
  so both test files can use it. Found when `rfr`, `sid` and `vt` left
  intake.

* Requires `hvtiRutilities` 1.2.1 or newer, up from 1.1.12 in the 1.2.0
  release. (`main` briefly carried a 1.2.0 floor that never shipped; this entry
  describes the change between releases.) 1.2.0 ports SAS
  `PROC FREQ` and `PROC UNIVARIATE` as `proc_freq()` and `proc_univariate()`,
  and corrects `proc_means()` weighted `nobs`, weighted `stderr` and the mode of
  a single observation. 1.2.1 adds `cache_fit()` and puts `rfr`, `sid` and `vt`
  in `hvti_taxonomy()`, which the job catalog this package now reads
  (`hvtiR` 1.1.15) depends on: with 1.2.0 the catalog names three prefixes the
  taxonomy lacks. No template calls the new functions yet, so nothing renders
  differently. The floor binds when `hvtiRtemplates` is installed or loaded; a
  copied job rendered with a bare `quarto render` is not covered, and a job that
  comes to need a newer function carries its own `packageVersion()` guard, as
  `dc-tables` does for its dependencies.

# hvtiRtemplates 1.2.0

* **The `hz` template renders again.** Its `phases` chunk read the order of
  `theta` through TemporalHazard's internal `.hzr_phase_theta_names()`, which
  changed shape once `hzr_theta_names()` was exported, so every `hz` job
  stopped there. It now calls `hzr_theta_names(phases)` and stops with a clear
  message on TemporalHazard older than 1.2.8. A job already scaffolded from the
  old template needs the same edit to its `phases` chunk. `TemporalHazard
  (>= 1.2.8)` joins `Suggests` so the test that runs that chunk runs in CI.

* A migration test no longer warns on Windows while removing its temporary
  folder link (#124).

* **Templates find the study root through `_study.yml`.** Each template calls
  `hvtiRutilities::study_root()` in place of looking for `_quarto.yml` in `.`
  or `..`, so a study needs no `_quarto.yml`, and a job renders the same from
  the Render button, `quarto render` or `render_job()`, at any depth. A study
  must have been adopted with `hvtiRutilities::study_setup()`.

* **`open_job()` finds the study root and opens or creates a job.** Called
  from anywhere inside a study, it resolves the root through the nearest
  `_study.yml` at or above `dir`, creates the job with `add_job()` when it
  does not exist, and opens an existing job as it stands, never overwriting
  it.

* `render_job()` renders a job from its own directory: a draft by default,
  and with `final = TRUE` a render that stops on an unfinished job.

* **The `dc-general` job template ships**, replacing `descriptive/dc.general`:
  overall statistics through `hvtiRutilities::proc_contents()` and
  `proc_means()`, then base-R contingency tables, cumulative distributions
  (SAS `QNTLDEF=5` quantiles and the five lowest and highest values) and a
  Pearson pairwise-correlation sweep. `ID_COL` is off by default, so no
  patient identifier reaches the report unless a study author sets it.
  `KEY_COLS` keeps identifier columns, `ccfid` by default, out of the overall
  statistics too. It reads data the same three ways as the other descriptive
  templates, `DATASET` or `ANALYSIS_SET`.

* **The descriptive templates can read a named dataset.** `dc-tables`,
  `dc-gfup` and `dp-postage` gain `DATASET`, passed to
  `read_built(dataset = )` when `ANALYSIS_SET` is `NULL`, so a job can read an
  extract declared under `additional_datasets:` in `_study.yml`, such as a
  column subset written for R. Naming such a dataset in `ANALYSIS_SET` failed
  with "No analysis set", because analysis sets and additional datasets are
  separate registries. Pairing an analysis set with a dataset other than
  `"study"` now stops, since a set is always derived from the study dataset.
  Each job now explains the three data routes above its `data` chunk and
  prints the dataset, file and dimensions it read, so a report says which
  data it describes. `vignette("sas-to-r-descriptive")` gains a "Which data a job
  reads" section covering the same ground for the biostatistics team.

* **Unworked `EDIT:` markers no longer stop a render; the job renders as a
  draft.** Every template's edit guard used to stop a render while any marker
  remained, unless `HVTI_TEMPLATE_DRAFT` was set. The default is now the draft:
  the render warns and the report opens with a DRAFT banner listing the open
  markers, so an author iterates towards a finished report and the banner goes
  when the last marker does. The guard only stops blocking: a section still
  holding a template placeholder stops with its own error, so a fresh job
  renders as far as the markers already worked. `HVTI_TEMPLATE_DRAFT` is gone
  from the templates. Set `HVTI_TEMPLATE_STRICT=1` to make an unfinished job
  stop, as a final render should; unset, `0`, `false` and `no` draft, and any
  other value stops. **This applies to jobs scaffolded from now on.** A job
  file is a copy of its template, so a job created before this release keeps
  the old guard: it still stops by default, still needs
  `HVTI_TEMPLATE_DRAFT=1` to draft, and ignores `HVTI_TEMPLATE_STRICT`. To
  move one over, replace its `edit-guard` chunk with the current template's.
  `vignette("sas-to-r-descriptive")` gains a section on the draft banner and
  the markers.

* `migrate_job()` reads a legacy SAS job and writes the matching template job
  plus an evidence report, preserving the source and refusing to overwrite
  either output. The template and its qualifier are read from the SAS
  filename (`<prefix>.<qualifier>.sas`), and `prefix`/`qualifier` override
  that reading when a source does not follow it; a `qualifier` given alone
  is used with the prefix from the filename. The study root is found
  from `_study.yml` above the source, and `dir` overrides that when the
  source sits outside the study. Relative `source`, `lst`, `log` and
  `reference` paths resolve against the working directory, and `dir` only
  locates the root. The listing and log default to the same-named files
  beside the source, `lst`/`log` override them, and the report says whether
  each was supplied, found or not found. A
  template with no migration adapter yet is still scaffolded, every `EDIT:`
  marker kept, with a report that says plainly that the migration is manual.
  Only deterministic extraction can remove an `EDIT:` marker; uncertain
  choices remain for review. The three descriptive templates listed below
  and the existing trends template have migration adapters.
  Log messages are withheld; reports keep their locations, severity, SAS error
  codes and recognized aggregate counts for review. Source text the report
  quotes is masked for every template: string literal contents, R raw
  strings included, comment bodies, `%let` values, whole even when a
  macro-quoted value such as `%str(a;b)` holds a semicolon, `%put` text,
  unquoted `title` and `footnote` text, and digit runs of five or more become
  placeholders such as `"[string]"` or `title2 [text];`, and Quarto prose and
  YAML are withheld. `dc-tables`
  group headings, which come from SAS comments, appear in the report as
  `[heading]` and in the job as `GROUPS` keys. The job itself is not masked. Outputs are placed by hard link. Where the
  filesystem refuses links, the prepared file is renamed into place after a
  check that the target is still absent, so a concurrent writer can race that
  check. A failed placement removes only the outputs that call placed. When `DATASET` is
  unresolved, the `dc-tables`, `dc-gfup`, `dp-postage` and `dp-trends` jobs
  stop before reading data and point to the migration report.
* `dc-tables` writes editable CORR DOCX output in place of the SAS RTF through
  `hv_tbl_summary()`, `hv_man_table()`, `hv_man_table_save()`, and
  `hv_check_docx()`. Structural findings stop the job. `dc-gfup` checks
  registered follow-up intervals with identifiers disabled; `dp-postage`
  writes numbered PNG pages through `hv_eda()` and `patchwork`.
* `vignette("legacy-study-migration")` teaches adoption of an existing study,
  separate registration of study and named-subset data, all four migrations,
  marker review, and output checks with synthetic data.

* **Three descriptive job templates ship: `dc-tables`, `dc-gfup` and
  `dp-postage`**, with `vignette("sas-to-r-descriptive")` walking a SAS user
  from `descriptive/dc.tables*`, `dc.gfup`, `dp.trends` and the EDA postage
  stamps to the R job that replaces each. `dc-tables` carries the correlation
  variant on `hvtiRtables::hv_correlation_table()` and
  `hvtiPlotR::hv_correlation_matrix()`; `dp-postage` is thin over
  `hvtiPlotR::hv_eda()`. The job-catalog pin advances to `hvtiR` `v1.1.11`
  in both workflows, and the roadmap is re-rendered: 44 templates are in scope
  and 13 are on disk.

* **`add_job()` replaces `new_job()` and follows the study's directory layout.**
  New studies receive jobs in numbered folders such as `20_distributions/`;
  adopted legacy studies retain bare folders such as `distributions/`. Mixed
  layouts are rejected. This requires `hvtiRutilities` 1.1.12.

* **The job-catalog pin advances to `hvtiR` `v1.1.10`**, in both
  `R-CMD-check.yaml` and `spec-counts.yaml`, and the roadmap is re-rendered
  from it. 1.1.10 carries [hvtiR#73](https://github.com/ehrlinger/hvtiR/pull/73)
  and [hvtiR#74](https://github.com/ehrlinger/hvtiR/pull/74): TemporalHazard
  functions named on the hazard rows, the relabeled names, and `pm`'s row
  dropped now that it folds into `lm`. It moves together with
  [hvtiRutilities#113](https://github.com/ehrlinger/hvtiRutilities/pull/113),
  which drops `pm` from `hvti_taxonomy()`, because `test-roadmap.R` checks
  catalog and taxonomy against each other both ways. The propensity-matching
  workflow reads 2 of 9, with `pm` no longer a member. 44 templates in scope,
  10 on disk, unchanged.

* **The job-catalog pin advances to `hvtiR` `v1.1.9`**, in both
  `R-CMD-check.yaml` and `spec-counts.yaml`, and the roadmap is re-rendered
  from it. 1.1.9 carries [hvtiR#61](https://github.com/ehrlinger/hvtiR/pull/61),
  [hvtiR#63](https://github.com/ehrlinger/hvtiR/pull/63) and
  [hvtiR#64](https://github.com/ehrlinger/hvtiR/pull/64). The roadmap now
  schedules 44 templates, not 43: `dc-trends` and `dp-boxplot` join from the
  2026-09-10 triage, and `pm` leaves, because it folds into `lm` and is
  `retire` over `hvtiRpropensity::bs_count()`. `lm` counts 470 studies and is
  `thin` over `hvtiRpropensity`, `si` and `mi` count jobs (1 and 18), and the
  measured `dc` and `dp` rows show R counts for the first time. The
  propensity-matching workflow reads 3 of 10, because `pm` is now owed
  elsewhere. Ten templates are on disk, unchanged.

* **`deade` and `deadl` are not landmark jobs, but the early/late landmark
  split is a real construct.** The per-folder parse design (section 8) now
  records the check. Both names are hazard-phase bagging output from the `bh`
  template: every `dead[elc]*` file on the share is a dataset, and no program
  is named `deade` or `deadl`. Nine programs carry the string inside a longer
  name, eight `deadexpl` jobs (death before explant) and `dc.deadlate`.
  Separately, job pairs such as `lg.dead.early` and `lg.dead.late` (10 and 8
  studies) or `dc.dead.early` and `dc.dead.late` (4 and 5) split follow-up at a
  cutoff: the early job censors at it, and the late job keeps only those who
  reach it. No taxonomy row names the construct; the job catalog records it as
  a shared `landmark` option from
  [hvtiR#61](https://github.com/ehrlinger/hvtiR/pull/61), shipped in `v1.1.9`.

* **`40_graphs/dp-trends.qmd` ships**, the first of the EDA templates and the
  first QUALIFIED template: a job is scaffolded with
  `add_job("dp", "cohort", "eda", qualifier = "trends")` and lands at
  `40_graphs/cohort-eda-dp-trends.qmd` in a new study. It is thin over
  `hvtiPlotR::hv_trends()`,
  which takes one row per patient and computes the per-year points itself, so
  the job never aggregates by hand. Of 50 trends job files across 24 studies,
  none used it. One job draws a list of figures, optionally once per subgroup
  on shared axes.

  The set key for an EDA job is `(subject, eda)`: `ENDPOINT` names what is
  described, `cohort` by default, and `TYPE` is always `eda`.

  It stops, rather than drawing, on an operation year outside 1900 to next year
  (the wrong-origin mistake), on a fractional year (which would draw one
  "annual" point per patient), on a year missing for every patient, on a percent
  column holding anything but 0/1 or logical, on a subgroup filter that is not
  one TRUE/FALSE per patient, and on a subgroup that selects nobody, and it
  prints each figure's dropped rows. Axis limits zoom through
  `coord_cartesian()` rather than dropping patients before the smooth is fitted.
  `hvtiPlotR (>= 2.7.7)` joins `Suggests` and `Remotes`; 2.7.7 rather than 2.7.6
  because the dropped-row count arrived part-way through 2.7.6 without a version
  bump. The Suggests-bound test now covers hvtiPlotR.

  Design: `dev/specs/2026-09-10-dp-trends-template-design.md`.

* **The job-catalog pin advances to `hvtiR` `v1.1.8`**, in both
  `R-CMD-check.yaml` and `spec-counts.yaml`. 1.1.8 carries one catalog change,
  [hvtiR#60](https://github.com/ehrlinger/hvtiR/pull/60): `dp-trends` is
  `shipped`. The pin moves in the pull request that adds the file, as the
  design's section 5 requires, because at `v1.1.7` the row was still `queued`
  and `spec-counts` failed on a template no ledger row claimed.

* **The job-catalog pin advances to `hvtiR` `v1.1.7`**, in both
  `R-CMD-check.yaml` and `spec-counts.yaml`, which `tools/check_pin_currency.py`
  requires to agree. 1.1.7 carries the EDA batch's catalog changes
  ([hvtiR#57](https://github.com/ehrlinger/hvtiR/pull/57),
  [hvtiR#58](https://github.com/ehrlinger/hvtiR/pull/58)): `dp-postage` joins the
  catalog, and `dc-general`, `dc-tables` and `dc-gfup` move into batch 3. The
  roadmap is re-rendered to match: 43 templates in scope, a `dp-postage` row with
  no blocker, and `descriptive` spanning batches 3 to 4.

* **`hvtiRlifetables (>= 0.1.2)` is now declared, in `DESCRIPTION` and in
  `40_graphs/hs.qmd`.** The template has called `us_cohort_curve()` since
  1.0.16, but nothing recorded which version provides it. `DESCRIPTION` did
  not name the package, and the template had no floor check, so a study on
  0.1.1 failed with "could not find function" part-way through a render,
  after the model had been read and every prediction made. It is now a
  versioned `Suggests` with a `Remotes` entry, as `hvtiRbootstrap` is, and
  the setup chunk refuses below 0.1.2 before anything is read.

  The floor is 0.1.2 because that is where the function was introduced. The
  1.0.16 entry below says it "landed in 0.1.3", which is wrong: 0.1.3 changed
  only the package's own tests.

  The test comparing `DESCRIPTION`'s bounds with the templates' floors now
  covers both packages, and FAILS rather than skips when a template enforces
  a floor `DESCRIPTION` does not declare. That is the case it could not see
  before, and the one this entry fixes.

* **A template's expected folder now comes from the job catalog, not from
  `hvti_taxonomy()` alone.** The taxonomy maps a prefix to ONE folder, but a
  prefix may span several: `dp` is `graphs` for `trends`, `gfup`, `spaghetti`
  and `procs`, and `distributions` for `variable`. The old check asserted
  `tl$folder == tx$folder[match(tl$prefix, tx$prefix)]`, so it would have
  rejected `dp-variable` the moment anyone wrote it, and `dp-variable` is
  already scheduled in batch 3. The catalog records `folder` per row, keyed on
  `(prefix, qualifier)`, and is consulted first; the taxonomy answers for rows
  the catalog does not have and whenever the catalog is absent. See
  [#97](https://github.com/ehrlinger/hvtiRtemplates/issues/97).

  ⚠️ **The fallback does not skip.** A missing catalog leaves the taxonomy
  answering for every template rather than the check quietly passing, because
  the taxonomy still catches a template filed under a folder no study uses,
  which is most of this guard's value. A silently skipped guard is worse than
  no guard.

  ⚠️ **The change had no CI coverage when it was first pushed, and ten green
  checks said otherwise.** `R-CMD-check.yaml`'s strict step ran
  `filter = "roadmap"`, so `test-taxonomy.R` executed only inside `R CMD
  check`, where the catalog is always absent and the new lookup always took
  the taxonomy fallback. The filter is now `roadmap|taxonomy`, and five tests
  drive the lookup against a temporary catalog so the catalog-first branch is
  asserted rather than merely executed. A test filter naming one file silently
  decides which code paths CI exercises; widen it whenever a test starts
  reading the catalog.

  The ledger helpers moved from `test-roadmap.R` to a new `helper-ledger.R`,
  because testthat gives each test file its own environment and `test-taxonomy.R`
  needs them too. A second copy of the path resolution was the alternative, and
  a copied authority free to drift is what retired the `FOLDER_ORDINAL` guard.

* **`spec-counts` now fails when the two hvtiR pins disagree with each other**
  (`tools/check_pin_currency.py`). `R-CMD-check.yaml` and `spec-counts.yaml`
  check the job catalog out independently, and advancing one while forgetting
  the other is the realistic mistake -- it leaves this repository validating
  against two different catalogs with both sides green.
* ⚠️ **The path filters were widened in the same commit, and that is the
  load-bearing half.** They matched `spec-counts.yaml` but not
  `R-CMD-check.yaml`, so a pull request advancing only the latter's `ref:`
  started no job at all and went green unverified -- the exact silent-drift
  failure this workflow's own header warns about, aimed at the guard being
  added.
* 🔴 **It also rejects refs that are not immutable tag pins**, added after
  review found the first version passed states it forbids: `ref: main` in both
  workflows agrees with itself, and so does an empty `ref:`, and both resolve
  to mutable default-branch behavior. **Equality is not pinning.** An empty
  `ref:` was the sharp edge — a missing `ref:` line yields `None` and was
  always rejected, but `ref:` with nothing after it yields `""`, which is not
  `None` and slipped through while the docstring claimed otherwise. A commit
  SHA is immutable and still rejected: hvtiR's `jobs-pin-drift` compares these
  against its newest *tag name*, so a SHA reads as permanently stale.
* **Lagging hvtiR's newest tag is deliberately NOT a failure here.** That alarm
  belongs to hvtiR's `jobs-pin-drift`, on a schedule with a grace period;
  failing every pull request the moment hvtiR cuts a tag would redden reviews
  for a reason unrelated to the change under review. This check answers the
  narrower question that only this repository can answer, in the pull request
  that caused it.

* **The job-catalog pin advances to `hvtiR` `v1.1.6`**, in both
  `R-CMD-check.yaml` and `spec-counts.yaml`. They are pinned independently and
  both must move; advancing one leaves the other validating against the old
  catalog with its guards still green. `v1.1.5` predates the `si` and `mi`
  imputation rows ([hvtiR#54](https://github.com/ehrlinger/hvtiR/pull/54)), so
  until now `test-roadmap.R` was checked against a 53-row catalog while `hvtiR`
  shipped 55.
* **The roadmap document is regenerated against the new catalog**, which is
  the half of a pin bump that is easy to miss. `dev/specs/2026-08-29-template-conversion-roadmap.md`
  is rendered from the catalog, so advancing the pin without re-rendering
  leaves a checked-in document contradicting the very catalog it was just
  pointed at. 40 templates in scope becomes 42, with queued rows for `mi` and
  `si`. ⚠️ Their "blocked on" cells differ and both are correct: `mi` is
  blocked on `hvtiRimputation` because `impute_multiple()` is unbuilt, while
  `si` is blocked on nothing because `impute_mean()` has shipped.
* Reading the catalog by tag is still the right call -- a dependency would
  invert the family, since `hvtiR` installs it, and tracking `main` would let
  an edit there fail every pull request here. What was missing is that nothing
  reported when the pin aged. `hvtiR` 1.1.6 adds that detector, and it now
  reads these two files directly: it will not consider the family current
  until both refs name its newest tag.

* **`bl`, `br` and `bc` now require `hvtiRbootstrap >= 0.9.3`**, and the
  reason is not a missing function. Below 0.9.3, `boot_select()` recorded
  `sle` and `sls` on the screen and then selected on AIC regardless, so the
  `boot_provenance()` table these reports print named an entry and a stay
  criterion the screen had never applied -- directly above the frequencies a
  reader attributes to them. A blank would have been obvious; a plausible
  number that describes nothing is not. 0.9.3's renamed bag columns do *not*
  affect these templates, which read `$boot$replicates` and rebuild the matrix
  themselves rather than reading `$boot$summary`.
* **The reports also refuse a bag *produced* below 0.9.3.** The version guard
  at the top of each one checks the `hvtiRbootstrap` installed where the report
  renders, which is not the version that matters: the report reads a bag some
  runner wrote earlier. A 0.9.2 bag survives 0.9.3's own documented migration,
  passes `boot_validate()`, and would render an AIC-selected screen beneath the
  entry and stay criteria it never used. `bag$engine` is now checked as well,
  and an absent, `NA` or unparseable one is refused rather than crashed on.
* **`bh` deliberately stays at `>= 0.9.0`.** Its screen comes from
  `TemporalHazard`, whose own stepwise has always honored `slentry` and
  `slstay`; `hvtiRbootstrap` is only the reporting layer there. Raising it
  would assert a dependency the template does not have.
* The Phase 3 render gate moves to 0.9.3 as well, because it *runs* a screen:
  below that, the bags it produces are not the bags these templates now
  declare they need.

# hvtiRtemplates 1.1.0

## Breaking

* **The ordinal is gone from every template and job filename.** A template is
  now `<prefix>[-<qualifier>].qmd` and a job is
  `<endpoint>-<type>-<prefix>[-<qualifier>].qmd`. `03.01-ac.qmd` becomes
  `ac.qmd`; `dead_pa-hz-03.01-ac.qmd` becomes `dead_pa-hz-ac.qmd`.

  `NN` was the taxonomy folder's position and duplicated the directory the
  file already sat in. `MM` was a per-folder key asserting an order among a
  folder's templates that does not exist. Both are removed. See
  `dev/specs/2026-09-03-template-identity-design.md`.

* **`inst/templates/` directories carry the ordering digits:**
  `00_datasets`, `10_descriptive`, `20_distributions`, `30_analyses`,
  `40_graphs`, `50_documents`, `90_estimates`. `NN` moved here, where it is
  the thing rather than a copy of the directory beside it, and the decade gaps
  are room to insert a folder without renumbering, which is what the `bh`
  rename cost last time.

  ⚠️ **The digits are ASSIGNED, not derived.** `estimates` is 90 though it is
  fifth in the taxonomy, because it holds saved output rather than jobs.

  ⚠️ **A STUDY does not use the numbered names.** `new_job()` writes into the
  bare taxonomy folder, `distributions/` and `analyses/`, because that is what
  studies already have (63,278 and 119,582 corpus files). Writing into
  `20_distributions/` would split a study's estate across two spellings.
  `template_list()` reports `folder` with the digits stripped, for the same
  reason.

* **`template_list()` drops its `ordinal` column**, and the roadmap ledger
  drops both `ordinal` and the `retired_ordinals` register.

## Removed machinery

* `check_ordinals()`, `check_retired()`, `FOLDER_ORDINAL` and `RETIRED_FIELDS`
  are gone from `check-roadmap-counts.py`, and the roadmap table drops its
  `ordinal` column. `check_disk()` now derives the folder-to-directory map by
  **reading `inst/templates/`**, so there is no hardcoded copy of the
  numbering to drift.

* The R test that parsed `FOLDER_ORDINAL` out of the guard and compared it to
  `hvti_taxonomy()` is retired with its reasoning: the right answer to "this
  constant can go stale" turned out to be deleting the constant.

## Note for old filenames

⚠️ **`04.06` will never be explained by anything else.** The retirement
register recorded that `04.06-bh` shipped in 1.0.13 and 1.0.14 before `bh` was
renumbered to `04.05`; it went with the ordinal. So: an `NN.MM` in a filename
is a pre-1.1.0 job, `04.06-bh` and `04.05-bh` are the same template, and no
ordinal will ever be issued again.

* **Copilot review credits are reported exhausted until October 2026, and
  that is recorded in `AGENTS.md` together with the evidence against it.**
  Reviews were still arriving the afternoon it was reported, including one on
  the PR recording it. The note says what the consequence would be if the
  cutoff lands (the rule does not block a merge, so a PR would go green and
  get no review, and with the approval rule nobody can satisfy on their own PR
  it would reach `main` unread) without asserting a state the evidence
  contradicts.

* **⚠️ `distributions/dp` is ONE ledger row, not the three that shipped in
  1.0.21.** Those three were keyed on measurement scale, recommended from a
  sample of two template filenames and released before anyone measured them.

  Measured over all 1,271 `distributions/dp` job rows: **666 of them, 52%,
  carry only the variable and no second field at all**, and a scale word
  appears in 110 stems, 8.7% (`binary` 51, `ordinal` 49, `continuous` 6). As
  a second qualifier `binary` (8 studies) and `ordinal` (10) rank fifth and
  sixth, behind `trend` (21), `tavr`, `gastroparesis` and `matched`.

  So it is one job parameterized by variable, which is what the design record
  said before it talked itself out of it. The row is `dp` / `variable`, 237
  job studies. `qualifier` is `variable` rather than null because a prefix
  must be wholly qualified or wholly unqualified and `graphs/dp` is
  decomposed.

  Recommending three templates from a sample of two, inside the work that
  exists because a convention was inferred from a small sample and applied to
  a whole corpus, is that error committed once more. It reached `main` and
  shipped. `trend` (100 rows, 21 studies) is the one second qualifier that
  might still earn a template, and is noted rather than acted on.

# hvtiRtemplates 1.0.21

* **`dp` and `dc` are decomposed in the roadmap ledger: two rows become
  twelve.** Enacts section 9 of
  `dev/specs/2026-09-02-dp-dc-decomposition-design.md`. `dc` becomes
  `general` (759 studies), `tables` (551), `gfup` (389), `dead` (171) and
  `stddiff` (59); `graphs/dp` becomes `trends` (80), `gfup` (48),
  `spaghetti` (40) and `procs` (35); `distributions/dp` becomes `binary`,
  `ordinal` and `continuous`.

  **No ordinals are assigned.** An ordinal is issued when a template is
  created and a retired one is never reissued, so assigning twelve now to
  templates that may never be written would burn them. Every row is `queued`
  with `ordinal: null`, as `dp` and `dc` were. No template has been written.

  The `distributions/dp` three are keyed on **measurement scale**, not
  variable, and are marked unmeasured: the census extracts the first
  qualifier, which there is the variable. The evidence is two of three local
  templates plus the same vocabulary recurring in `graphs`, and the rows say
  so.

* **`std_dif` versus `stddiff` is resolved: ship the 2019 successor.**
  `stddiff.sas` is 649 lines handling continuous, ordinal and categorical;
  `std_dif.sas` is 108 lines from 2009. Its wider corpus use, 72 studies
  against 59, is a macro outliving its replacement rather than a preference.
  The template therefore depends on `hvtiRutilities`, not `hvtiRtables`.

* **The roadmap table gains a `jobs` column.** `sas_breadth_jobs` has been
  in the ledger since the re-parse and rendered nowhere, so a decomposed row
  showed a dash for every count it actually has. Two measures, two columns,
  rather than one column falling back to the other.

* **A template name can now say which job it is: `<NN.MM>-<prefix>-<qualifier>.qmd`.**
  `graphs/dp` is `trends`, `spaghetti`, `procs` and more under one prefix, and
  the split is already present in the template estate rather than being
  proposed. A name that cannot say which job it is, is one a study author
  cannot search. Decided 2026-09-02; see
  `dev/specs/2026-09-02-dp-dc-decomposition-design.md`.

  `template_list()` gains a `qualifier` column. `NA` marks an unqualified
  template row, which is every template shipped today. `template_path()`
  and `new_job()` gain a `qualifier` argument. Nothing existing changes: all
  nine shipped templates are unqualified and every existing call still
  resolves.

  **Both refuse to guess.** Naming no qualifier where a prefix carries several
  is an error listing the choices. Selection was `match()`, which returns the
  first row and says nothing about the rest; that is safe only while every
  prefix has one template, and is the same shape as the bug that made `dp`
  look like one job type.

  The parser's prefix capture was `.+`, which is greedy and read
  `06.03-dp-trends.qmd` as the single prefix `dp-trends`. It parsed, it
  validated, and it was wrong. The prefix is now `[A-Za-z0-9]+`, so a prefix
  may never contain `-`.

* **The roadmap ledger is keyed on `(prefix, qualifier)`, not prefix alone.**
  A prefix may hold several rows, one per job type, and must be wholly
  qualified or wholly unqualified: a half-decomposed prefix would offer an
  unqualified row in the ambiguity error that no caller can ask for. The
  renderer labels a qualified row `dp-trends` so two rows for one prefix do
  not render identically. An empty-string qualifier is rejected outright,
  rather than being collapsed into an absent one by a truthiness test.

* **The allocation note's cross-package dependency count was wrong for
  nineteen days, and is now anchored.** It read "19 file-level dependencies
  span 3 package pairs". That was correct when written on 2026-08-14 and went
  stale the same day, at `77734a9`, which created `hvtiRbootstrap` and moved
  24 dependencies into two new package pairs without touching the sentence.
  The real figures are 43 across 5 pairs.

  The scan now emits `cross_package_dependencies` into the map, and
  `check-spec-counts.py` fails the PR when the prose, the edge list or the
  acyclic claim disagrees with it. Every other count in that document was
  already anchored and had been re-synced repeatedly over the same period;
  this one was prose, and prose is what drifted.

  The **acyclic** half of the claim was true throughout, and is now verified
  by a depth-first coloring rather than asserted. A stale number sitting
  beside a correct claim is harder to see than a wrong one on its own.

* **The corpus was re-parsed, and the batch order moved.** The census that
  ordered the conversion work was produced by a parser that captured a legacy
  job name's first dot-field and discarded the rest, so `dp.trends`,
  `dp.gfup` and `dp.spaghetti.echo` all counted as one bucket called `dp`.
  A bucket cannot be templated, which is why Batch 3 was stuck. The parser
  fix is upstream in `hvtiRutilities`; here, the roadmap ledger gains
  `sas_breadth_jobs` beside the existing `sas_breadth`, and
  `dev/specs/2026-09-02-per-folder-naming-parse-design.md` records what
  changed.

  The two counts differ because the old one counted every extension, so a
  `.lst`, a `.log`, a `.pdf` and a `.sas7bdat` each counted as evidence that
  a study runs a job of that type. Ten prefixes move three ranks or more.
  `lp` drops nine, from 636 studies to 310, because more than half its
  breadth was output rather than programs. The top four are unmoved.

* **The `hz +396` / `hm +172` hand corrections are withdrawn.** `hzdead` and
  `hmdead` are result datasets in `estimates`, `.sas7bdat` and `.ssd01`, not
  hazard jobs. Adding them added model output to a count of programs. The
  measured job breadth is `hz` 574 and `hm` 373.

* **`deade` and `deadl` are identified.** Hazard-phase estimate datasets,
  early and late, with `deadc` beside them at 60 studies. They sit in
  `estimates` and were never jobs.

* **The macro-allocation scan globbed one level deep** and missed 13 of the
  244 template `.sas` files. Three files change destination as a result, and
  `stddiff.sas` is the one that matters: it was allocated to a single package
  only because the glob hid the two `dc` templates that make it shared. Three
  retired destination slugs are also corrected, to `hvtiRdatabuild`,
  `TemporalHazard` and `hvtiRpropensity`.

# hvtiRtemplates 1.0.20

* **Three bootstrap screen templates ship**: `analyses/04.02-bl.qmd`
  (logistic), `analyses/04.03-br.qmd` (linear) and `analyses/04.04-bc.qmd`
  (Cox). All three report through `hvtiRbootstrap`'s reporting layer with
  `PHASE_OF <- NULL`, which is the single-phase path the same functions serve
  for `bh` with a term-splitting rule. One code path, four templates.

* **They read one screen rather than pooling chunks.** `bh` pools because a
  hazard screen is days of compute; these are not, and a chunked run is pooled
  in the runner, which is the only place that knows how many chunks it
  launched.

* **Two of `bh`'s warnings do not transfer, and were rewritten rather than
  copied.** A formula held in a variable is fine here: `boot_select()`'s
  fitters evaluate through an environment that binds `formula` and `data`
  where `step()` looks for them, and a variable-held formula gives
  byte-identical results. `bh` warns the opposite because `hzr_bootstrap()`
  rewrites the stored formula per replicate. The empty-screen and
  flat-bootstrap refusals stay, with diagnoses that fit a `boot_select()`
  screen.

* **`bc` carries a warning the other two do not need.** A Cox model has no
  intercept, so `base_params` cannot be the `"(Intercept)"` a logistic runner
  would pass. With nothing forced there is no free base parameter, the
  standard-deviation check reports `NA` rather than passing, and the guard
  that catches a bootstrap which refit nothing is silently inactive.

* **They require `hvtiRbootstrap (>= 0.9.2)`, and `DESCRIPTION` now says so.**
  0.9.2 adds `boot_bag()`, without which a `boot_select()` screen cannot be
  read by the reporting layer at all: the screen returns a wide coefficients
  matrix and the layer reads a long-form bag, and nothing converted between
  them. The declared bound had also drifted -- it read `>= 0.1.1` from 1.0.13
  while the `bh` template refused below 0.1.2 and later 0.9.0, for nine
  releases. A test now asserts the bound is at least the highest floor any
  template enforces.

* **All three were rendered against a screen run for the gate, not against a
  screen a study ran.** No R job found on the share calls `boot_select()`, so
  no `bl`, `br` or `bc` bag existed to read. The gate screens a real built
  dataset instead, which exercises real variable names, a real correlation
  structure and `read_built()`; what it does not exercise is a candidate pool
  a study author chose. `bc` is the weakest of the three: of the 16 studies
  with a `bc` job, none has an R exemplar.

* **Ordinals 04.02, 04.03 and 04.04** are free minors in `analyses`. `04.06`
  remains retired and unissuable.

# hvtiRtemplates 1.0.19

* **`graphs/06.02-hs.qmd` states its confidence coverage in reader-visible
  prose**, not only in a code comment. `CLEVEL` is `0.68268948`, plus or minus
  one standard error and about 68% rather than 95%. That is the SAS `HAZPRED`
  convention and the published papers state it, so the limits are correct and
  only the reading of them can be wrong. The templates ship `code-fold: true`,
  so the comment that said this was invisible to anyone reading the rendered
  report. `03.01-ac.qmd` and `06.01-hp.qmd` already said it in prose; this was
  the one job that did not, and it is the job whose `lower` and `upper` travel
  into the saved artifact for the plotting jobs to draw, arriving at a figure
  with nothing beside them recording the coverage.

# hvtiRtemplates 1.0.18

* **`analyses/04.05-bh.qmd` now reports through `hvtiRbootstrap`'s reporting
  layer** instead of building its own tables by hand. The template requires
  `hvtiRbootstrap (>= 0.9.0)` and refuses to render below it. The reporting
  layer itself exists from 0.1.2; the floor sits higher because 0.1.x strips a
  phase label whether or not a separator follows it, so a term named `earlyage`
  reports its variable as `age`, matching no concept and quietly absent from
  every grouped table. A wrong frequency is worse than a missing function,
  because nothing downstream can see it. The `contract` chunk now calls
  `boot_validate()`, which checks field shapes, not only presence.
  `provenance` and `seeds` call `boot_provenance()` and `boot_seeds()`. Both
  `dropped-*` chunks collapse into one `boot_dropped()` call. The `health`
  table comes from `boot_health()`; the two `stop()` refusals stay in the
  template, because `boot_health()` reports and never refuses on its own.
  `frequencies` and `concept-union` call `boot_frequencies()` and
  `boot_concepts()`, and `retained` now filters the package's own `retained`
  column rather than recomputing the cutoff locally.

* **The `health` table gained two columns.** It reports four now (`check`,
  `value`, `ok`, `note`) where it reported two before; `boot_health()`
  supplies `ok` and `note`, and the original two columns are unchanged.

* **`freq`, as saved to `bh-report.rds`, now carries eight columns where it
  carried seven, in a different order.** `boot_frequencies()` returns
  `phase, variable, term, n, pct, mc_error, near_threshold, retained`; the
  new column is `retained`. A study reading the saved object by name is
  unaffected, but one reading it positionally is not.

* **The template carries an eleventh `EDIT:` marker, `PHASE_OF`,** in the
  `criteria` chunk. It names the rule that splits a term into its phase and
  variable. `boot_frequencies()` and `boot_concepts()` also accept `PHASE_OF
  = NULL`, for a single-phase screen, and that is what lets one reporting
  code path serve the forthcoming `bl`, `br` and `bc` templates. This
  template assumes a phase dimension throughout, so `PHASE_OF` must name a
  real rule here.

* Rendered against a real 25-chunk bag and diffed against a reference
  captured from the pre-refactor template: the provenance, seeds, frequency
  and retained tables are byte-identical, the concept table has zero value
  mismatches across 184 rows, and the frequency figure has the same sha256.

# hvtiRtemplates 1.0.17

* **`analyses/04.05-bh.qmd` could not render on any multiphase bag** — which is
  every hazard bag, and `bh` is the bootstrap *hazard* screen. Its `provenance`
  chunk passed `bag$requested` and `bag$usable` to `data.frame()` as if they
  were scalars. They are per **phase**: a real bag carries
  `c(early = 230, late = 230)`, so a length-2 value met a length-13 item column
  and `data.frame()` errored. Now collapsed to one labeled string per row —
  `early 230, late 230` — with fallbacks for a single-phase run and for a runner
  that drops the names.

  Not summed: the pool is *offered* to each phase, so 230 and 230 is one pool
  seen twice, not 460 candidates.

  ⚠️ **Found by the first real render**, against the very study the template was
  written from — `EXPECT_CHUNKS <- 25L` and `EXPECT_BOOT <- 500L` are that
  study's own values. The template shipped in 1.0.13 and was renumbered in
  1.0.15 without anyone rendering it. Nothing in `R CMD check`, the test suite,
  `lintr` or three code reviews could see it: the defect is an assumption about
  the shape of a field in an artifact produced by another package.

# hvtiRtemplates 1.0.16

## Guards

* Retired the two tests asserting that within-folder ordinal minors follow
  `hvti_taxonomy()` row order. They enforced the derivation #56 removed: an
  ordinal is a key, assigned once and recorded in the ledger, never recomputed
  from a position. #56 established that rule in `AGENTS.md`, the ledger and
  `check-roadmap-counts.py`, but left the test suite asserting the opposite —
  two guards on one repository disagreeing, which is the drift the guards exist
  to prevent. Measured before removal: reordering two **templated** prefixes
  within a folder turned CI red, while inserting or reordering an untemplated
  one was always safe.

* Replaced them with a **key** check rather than another position check:
  `check-roadmap-counts.py` validates every ordinal's major against a
  **hardcoded** `FOLDER_ORDINAL` map, whose authority is `hvti_taxonomy()`'s
  folder order — a table that lives in `hvtiRutilities`, a different
  repository. `test-roadmap.R` now asserts the map still matches. That closes
  the same class of failure one level up from the one #56 fixed. The Python
  guard cannot check its own map: reading the taxonomy needs R, which is why
  the guards are split by language.

## `graphs/06.02-hs.qmd`

* Now calls `hvtiRlifetables::us_cohort_curve()` instead of deriving the cohort
  expected-survival curve inline. The template shipped that derivation
  deliberately, as the specification for
  [hvtiRlifetables#16](https://github.com/ehrlinger/hvtiRlifetables/issues/16),
  with a comment promising that when the function landed "this chunk becomes one
  call and the result must not change". It landed in `hvtiRlifetables` 0.1.3;
  the numbers were checked to 1e-12 against the derivation before the swap.

  The function is not merely a convenience. Its averaging follows `%usmatchd`
  (lines 338-350) — the unweighted cohort mean, over survival rather than
  cumulative hazard, no patient weighted by follow-up — and it deliberately does
  **not** drop `NA`, where the inline version used `na.rm = TRUE` and would have
  hidden one.

* Added an `EDIT:` marker for `us_cohort_curve()`'s `by =`, covering
  [hvtiRlifetables#17](https://github.com/ehrlinger/hvtiRlifetables/issues/17).
  Grouping is not stratification: `table =` chooses which strata the life *table*
  is built from, `by` chooses how the resulting curves are grouped for reporting.

* `HORIZONS` must now be sorted and distinct, checked where it is declared.
  `us_matched()` enforces sortedness too, but three chunks later and about its
  own `times` argument rather than the value the author edited — and the
  expected-survival join pairs `us_cohort_curve()`'s output, ordered by first
  appearance, with `split()`'s, ordered numerically. They agree only while
  `HORIZONS` is sorted.


# hvtiRtemplates 1.0.15

* **The bootstrap screen template is now `analyses/04.05-bh.qmd`**, renamed from
  `04.06-bh.qmd`. The ordinal had been derived from the prefix's row position in
  `hvti_taxonomy()`, and that derivation had already failed: `bh` was 6th in
  `analyses` when the number was assigned, `hvtiRutilities` then moved `hs` out
  to `graphs`, and every prefix below it shifted up one while the filename
  stayed put. The identity was positional across a repository boundary, so a
  correctness fix in the upstream vocabulary silently invalidated a downstream
  filename, and nothing caught it: the ordinal checks verify format,
  folder-major and uniqueness, never position.

  ⚠️ **A job already scaffolded from 1.0.13 or 1.0.14 is unaffected.**
  `new_job()` bakes the ordinal into the job filename at copy time, so existing
  jobs keep theirs and do not need renaming. Only newly scaffolded `bh` jobs
  take `04.05`.

* **An ordinal is now a key, assigned once, and never recomputed from row
  order.** `NN` is the taxonomy folder's position, which is stable; `MM` is
  assigned from the next free minor in that folder and recorded in the roadmap
  ledger. Row order may drift; ordinals may not. Stated in `AGENTS.md`, so the
  next template is not numbered by counting rows.

* **`04.06` is retired, not freed.** It shipped in two releases, so a study that
  scaffolded `bh` from either carries it in a filename. It is recorded under
  `retired_ordinals` in the ledger, and `check-roadmap-counts.py` now fails any
  row that claims a retired ordinal, naming when and from what it was retired.

# hvtiRtemplates 1.0.14

* **`analyses/04.06-bh.qmd` gains the data-driven half of the SAS `%cluster`
  contribution.** `boot_clusters()` counts replicates retaining any member of a
  list you declare and computes no correlation at all, so the section's claim to
  group "by DATA" described the SAS macro rather than the R helper. A
  `pool_collinear_pairs()` chunk now makes it true. The two are kept apart
  deliberately: a declaration says a clinician treats several variables as one
  thing, a correlation says the pool cannot tell them apart, and only the second
  is a property of the data.

  This is why the template now reads the built dataset. The one failure that
  introduces is guarded: a build that moved since the screen ran would leave the
  correlations describing one dataset and every frequency above describing
  another. `n_rows` catches it, as a warning rather than a stop, because only
  this table goes stale.

* **Concept-level union frequencies.** A per-form row cannot answer "how often
  was this *concept* selected", which is the figure a paper quotes. Nothing is
  collapsed — every form keeps its own row — but each concept now also carries
  `union_pct`, `best_form_pct` and the `spread` between them, which is how much
  the per-form table understates it.

  Computed from the replicate table, never from the summary: a union across a
  concept's forms cannot be recovered from marginal percentages. Two forms at
  30% each are anywhere between 30% and 60% of replicates depending on how often
  the same replicate took both, and the summary does not record that.

# hvtiRtemplates 1.0.13

<sub>Superseded 2026-08-31: this template is `analyses/04.05-bh.qmd` from 1.0.15
onward. The sentences below are left as they shipped. A job scaffolded from this
release keeps `04.06-bh` in its filename and needs no rename.</sub>

* Added `analyses/04.06-bh.qmd`, the bootstrap variable-selection screen that
  replaces a SAS `%hazboot` / `%sumboot` / `%cluster` chain
  ([#8](https://github.com/ehrlinger/hvtiRtemplates/issues/8)). Scaffold it with
  `new_job("bh", <endpoint>, <type>)`. Requires `hvtiRbootstrap` >= 0.1.1 and
  `hvtiRutilities` >= 1.1.6. Design in
  `dev/specs/2026-08-28-bh-template-design.md`.

  The template is the **report**, not the runner. `hzr_bootstrap()` writes
  nothing until its final replicate and a full screen is days of compute, so
  the run is chunked from a companion script and this file pools what that
  script wrote. That file boundary is a durability boundary, not tidiness, and
  the runner stays untemplated until `new_job()` grows multi-file templates.

  It carries four traps that are silent rather than loud when they go wrong:
  competing transformations must be screened and grouped only at read time,
  never pruned beforehand; a screen that selected nothing is a failed screen
  rather than a null result, and now stops the render; `EXPECT_CHUNKS` and
  `EXPECT_BOOT` state what was *launched*, so a partial pool is flagged as
  provisional instead of quietly reporting over the wrong denominator; and the
  summed elapsed time is CPU cost, not wall clock. `bh` and `hm` are parallel
  analyses, not a pipeline, so the template deliberately writes no handoff file.

* Added `tests/testthat/test-bh-helpers.R`, covering `boot_clusters()` and
  `boot_shortfall()` against synthetic input. Both are first called from this
  template, and a render cannot stand behind them: it stops before reaching
  either whenever no bootstrap output exists, which is every CI run.

* Declared `hvtiRbootstrap` in `Suggests` and `Remotes`. The templates' study
  dependencies stay out of `DESCRIPTION` deliberately, but the test above calls
  the package directly, and `R CMD check` resolves what tests reference — left
  undeclared it reports an unstated dependency.

# hvtiRtemplates 1.0.12

* Added `graphs/06.02-hs.qmd`, the patient-level prediction template. It reads
  the model an `hm` job fitted, predicts survival per patient at the horizons a
  study reports, and sets those against age/sex/race-matched population survival
  from `hvtiRlifetables`. Its `vintage` marker has no default on purpose: the
  SAS macro it replaces inherited a default that moved twice with no signal, and
  a job that does not state its vintage cannot be reproduced. Design in
  `dev/specs/2026-08-29-hs-template-design.md`.

# hvtiRtemplates 1.0.11

* Added the template conversion roadmap: a ledger of all 42 taxonomy prefixes
  plus three proposed ones, the roadmap document generated from it, and two CI
  guards that fail when the two disagree or when a row claims a template that
  is not on disk. Design and reasoning in
  `dev/specs/2026-08-29-template-conversion-roadmap-design.md`.

# hvtiRtemplates 1.0.10

## Documentation

- **The institutional SAS license runs into 2027, not out in 2026.** The wrong date
  `2026-09-29` was stated in eleven places: the package `README.md`, the 1.0.0
  provenance note below, and nine statements across the design and artifact records
  in `dev/specs/`. `README.md` is corrected outright, because it states a present
  fact to a reader. Everything else is a historical record, so the original sentence
  is left standing with a dated correction beside it, following the convention this
  repository already uses for a superseded claim.
- **`2027-09-29` is a working date, not a confirmed one.** Every note states it the
  same way and defers to one canonical note, so confirming the real date is a single
  edit rather than another eleven. What is settled is the year, not the day. Writing
  an unconfirmed date as flatly as the wrong one was written is the mistake this
  entry exists to correct.
- Two of those statements used the date as a **deadline**, and they came out
  differently. The "forcing function" in the AVR/LV-function parity design keeps its
  argument: fresh SAS execution genuinely needs a live license, so the pressure is
  real and simply further out than stated. The macro-allocation design's claim that
  the license "bounds the window" for re-running the corpus scan is **withdrawn, not
  re-dated.** That scan reads `.sas` files as text and never invokes SAS. What
  threatens it is loss of the sources, which are unversioned or unreplicated, and
  the mitigation is a remote rather than a deadline.
- What the license date does not bound, in either case, is reading: compiled SAS data
  stays readable well beyond expiry, so what ends is the ability to *run* SAS, not to
  read what it produced.

# hvtiRtemplates 1.0.9

## Documentation

- **Development records moved to `dev/specs/`,** adopting the portfolio
  convention settled in `ehrlinger/house-style`. The stray top-level `plans/`
  is gone with it: this repo carried `plans/` *and* `specs/` *and* a
  `specs/plans/` convention that said plans belonged in neither, which is the
  drift the new rule exists to stop. All three plans now sit beside the designs
  they implement, under a shared slug.
- **`spec-counts.yaml` moved in the same commit.** Its two path filters and two
  `run:` paths point at `dev/specs/`, and a comment at the top of the file says
  why they cannot be left behind — a stale path filter does not fail the check,
  it stops the job from starting, and the PR goes green having verified nothing.
- `specs/artifacts/` became `dev/specs/artifacts/`, staying nested inside the
  prose directory because `check-spec-counts.py` resolves its target through
  `os.pardir`. Both checks were run at the new location and pass unchanged.
- `inst/templates/README.md` is the one shipped file affected, which is what
  makes this a patch bump rather than a governance-only change.

# hvtiRtemplates 1.0.8

## New features

- **`analyses/04.01-hm.qmd`** — the multivariable hazard model, replacing a SAS
  `PROC HAZARD` job with a `selection` statement (#8). Scaffold with
  `new_job("hm", <endpoint>, <type>)`. Design:
  `dev/specs/2026-08-27-hm-template-design.md`. **Requires hvtiRutilities >=
  1.1.4**, which ships the candidate-pool helpers it calls.

  Unlike `hz` and `hp`, `hm` had only **one** R exemplar, so its second was a
  SAS job (`.../dm_nodm/analyses/hm.dead.sas`). That is enough for the gate's
  purpose — it exists to stop one study's choices being encoded as general, and
  a SAS job states those choices as plainly as an R one does. It earned its
  place immediately: it carries a **`%deciles` calibration** step the R
  exemplar has no equivalent for, and `TemporalHazard` already exports
  `hzr_deciles()` for it. Without the second exemplar the template would have
  shipped a model-selection job that never asks whether the model calibrates,
  and nothing in its output would have looked missing.

  ⚠️ **Two traps specific to this job, both silent:**

  - `hzr_stepwise()`'s defaults are **not** SAS's — `slentry = 0.3` /
    `slstay = 0.2` against a typical `sle = 0.1` / `sls = 0.07`. Accepting the
    R defaults runs a different screen from the job being reproduced, admits
    more variables, and does not error. The template sets them from the `.sas`.
  - The default `criterion = "score"` has a known defect
    (temporal_hazard#130): it declines the strongest candidates, because the
    observed information goes indefinite at `beta = 0`.

  Covariates are **read out of the SAS job** with `sas_variable_block()` rather
  than transcribed, taking only names — a `name=value` block carries the other
  study's converged answers. `covariate_audit()` then stops the render rather
  than fitting a model whose covariates are not what the job specifies, and
  `pool_collinear_pairs()` reports exact complements like `male`/`female`.

  The fit is **two stages**, mirroring what the SAS job does: shapes held at
  the `hz` fit while covariates are screened, then freed. Fitting both together
  from a neutral start lands in the wrong basin and reports `converged = TRUE`
  while doing it. Which stage is reported is an `EDIT:` decision with the
  evidence table beside it.

  The calibration chunk uses `print(dec)`, **not** `knitr::kable(dec)`: the
  print method carries the overall chi-square, its degrees of freedom and its
  p value — the one number that answers "does this model calibrate" — and
  `kable()` renders only the per-group frame, dropping it silently.

## Bug fixes

- **`dev/specs/2026-08-21-template-set-layout-design.md` §5 corrected.** It said
  the ordinal minor is "the next free position within it"; the rule that
  actually reproduces every shipped ordinal is the prefix's **position among
  its folder's taxonomy rows**. The two agree for everything templated so far
  and diverge on the third `analyses` template, where next-free would put `bh`
  before `hs` and fail the within-folder ordering test in `test-taxonomy.R` —
  a failure whose only fix is renumbering a shipped template, which §5
  promises never happens.

- `DESCRIPTION` now requires `hvtiRutilities (>= 1.1.4)`. The old `>= 1.1.1`
  was correct until this release -- `hz` and `hp` call nothing newer -- so the
  bound went stale as a side effect of adding a template rather than as an
  error in its own right. An install satisfying the old bound would have
  shipped a template whose helpers do not exist, failing at **render** time in
  a study rather than at install time.

- The `selection-monotone` chunk handles a **zero-step** screen. A screen that
  admitted nothing is a real outcome -- no candidate cleared the entry level --
  but `which.max()` on an empty vector is `integer(0)` and the report frame
  then failed with "arguments imply differing number of rows": an error about
  the report, in a job whose actual finding is that nothing entered.

- Convergence failure names the stage and what to check, instead of
  `stopifnot()`'s "isTRUE(stage1$fit$converged) is not TRUE" -- a message that
  tells a reader of the rendered report nothing they can act on.

## Internal

- `.lintr` gains a file entry for the new template, per the note in that file
  that a directory key would silently disable every linter on the path.

- New test: the `hvtiRutilities` helpers the templates call must appear in a
  declared list. It cannot check the version bound directly (CI installs the
  latest, not the declared minimum), but it makes the **trigger** loud -- a
  template that starts calling a new helper fails the test, and whoever adds it
  is standing in the right place to ask whether `DESCRIPTION` needs bumping.
  The scan reads code chunks only: a test that fires on prose is a test that
  gets deleted.

- The `03.01-ac` template's local `imputed_levels()` is removed in favor of
  the `hvtiRutilities` export. The two were identical, and the duplicate
  arrived only because hvtiRutilities#47 lifted the same function out of the
  same study.
# hvtiRtemplates 1.0.7

## New features

- **`graphs/06.01-hp.qmd`** — the nomogram and hazard figures, replacing a SAS
  `HAZPRED` job and the figure jobs over it (#8). Scaffold with
  `new_job("hp", <endpoint>, <type>)`. Design:
  `dev/specs/2026-08-27-hp-template-design.md`.

  `hp` **reads** its inputs rather than recomputing them — the `ac` life table
  and the `hz` fit, both by set. A job that recomputes its upstream can
  silently disagree with it.

  ⚠️ **Two settings are silently wrong if omitted**, both decoded from the
  `HAZPRED` source during parity work:

  - **`CLEVEL` defaults to `0.68268948`** — one standard deviation, **not**
    95%. It is exactly `pnorm(1) - pnorm(-1)`. `%kaplan` uses the same
    convention (`T_ALPHA = 1`), so the `ac` life table's limits are also a ~68%
    band. That collides in `hp` specifically, because `hp` is where both bands
    are drawn on one figure: internally consistent, and misread by anyone
    taking either for 95%. On the same fit and grid the 95% band measures
    **1.97× the width** of the SAS default. The template labels the coverage in
    the caption.
  - **Survival limits are formed on the `logit` scale.** `predict.hazard()`
    defaults to `"log-log"`, so `conf.type = "logit"` must be passed
    explicitly. Omitting it does not error — it shifts every limit.

  Two grids, not one, and **two independent horizons**: a sparse irregular
  **reporting** grid for the nomogram table, and a dense **log-spaced**
  plotting grid for the curves. Tabulating to 10 years while plotting to 3 is a
  normal thing to want, and SAS sets its plotting maximum as its own literal —
  so `t_max` is its own value rather than derived from the reporting grid.
  `followup-gate` checks both. A linear grid
  to the last event time under-resolves the early phase, which is where the
  action is. A wrong grid does not error; it produces a plausible nomogram.

  `followup-gate` warns when either horizon runs past the end of follow-up — a
  parametric model returns a number at any horizon asked of it, and nothing
  else marks that as extrapolation. The bound is computed over the **rows the
  fit used**, because `hz` drops rows missing either time or event and a
  max() over everything would overstate follow-up, making the guard under-warn.

  `fig-phases` asserts the components sum to `total`, since otherwise it is not
  a decomposition, and derives the component list from what `predict()` returns
  rather than naming early/late — so a three-phase model needs no edit.

## Internal

- `.lintr` gains a file entry for the new template, per the note in that file
  that a directory key would silently disable every linter on the path.

# hvtiRtemplates 1.0.6

## New features

- **`distributions/03.02-hz.qmd`** — the multiphase parametric hazard fit,
  replacing a SAS `PROC HAZARD` job (#8). Scaffold it with
  `new_job("hz", <endpoint>, <type>)`. Design:
  `dev/specs/2026-08-27-hz-template-design.md`.

  Extracted from **three** R exemplars — `preserve_root`,
  `maze/atricure/gender` and `lv_function/survival` — chosen because they
  disagree. Two seed `theta` from SAS's converged estimates so that any
  disagreement is about the likelihood rather than about where the search
  began; the third seeds neutral shapes with the time scale taken from the
  data, because it has no SAS predecessor to seed from. Both are correct for
  their own case, so the `start` chunk carries both as Shape A / Shape B, the
  way the `ac` template's `cohort` chunk already does. From either exemplar
  alone the template would have made the other case silently wrong.

  Three checks are carried from a single exemplar each, because in every case
  their absence is silent rather than loud: `numderiv-gate` (without `numDeriv`
  an interval-censored fit produces **no standard errors and does not say so**
  — `converged` is `TRUE` and `vcov()` is simply absent); `response-check`
  (mis-building the response still converges, on a number that is merely
  wrong); and `conservation-binding` (reporting `Σ Λ(tᵢ)` under both `conserve`
  settings is the only way to tell "the control did nothing" from "the control
  had almost nothing to do" — identical in the likelihood column, opposite in
  meaning).

  Parity is deliberately **not** in the template: a parity job borrows the
  ordinal of the job it checks and lives in `parity/`.

  The response formula is built **once**, in the `response` chunk, and reused
  by all three `hazard()` calls, so the Shape A / Shape B choice is made in one
  place rather than in three literal formulas an author could edit
  inconsistently.

## Internal

- `.lintr` gains a file entry for the new template, per the note already in
  that file that a directory key would silently disable every linter on the
  path. Indentation and brace linting stay **on** for it, and the six lints the
  first draft produced were fixed rather than exempted.

# hvtiRtemplates 1.0.5

## Bug fixes

- **An unedited job no longer renders green** (#27). Templates now carry an
  `edit-guard` chunk that scans the rendering file for unresolved `EDIT:`
  markers and stops, naming each one. `inst/templates/README.md` has always
  said that a job still containing a marker has not been finished; nothing
  checked it, and the `03.01-ac` template made the gap concrete — its `derive`
  chunk indexed a placeholder column, and an absent column makes
  `!is.na(d$<col>)` `logical(0)`, so every assignment is a **silent no-op**.
  Every patient stayed in one category, the downstream life tables ran over a
  single dummy stratum, and the render completed with 12 markers still in the
  file.
- `derive_cats()` and the `DERIVED` map now assert that the columns they name
  are in the data. This is the half a marker scan cannot reach: a placeholder
  replaced with a mistyped or renamed column leaves no marker behind.

## New features

- `HVTI_TEMPLATE_DRAFT=1` renders a partly-worked job anyway. The guard warns
  instead of stopping and the report carries a DRAFT banner listing the
  unresolved markers. It is an environment variable rather than a YAML
  parameter on purpose: a parameter lives in the file, so it would be
  committed and forgotten, re-opening the hole this closes. `1`, `true` and
  `yes` enable it; any other value, `0` included, leaves the guard strict, so
  a variable set to `0` meaning "off" cannot switch it off by being non-empty.

## Internal

- Two tests over the shipped template sources: every template must carry an
  `edit-guard` chunk, and no template may write the marker token as a string
  literal. The second guards a trap worth naming — Quarto knits through an
  intermediate and `knitr::current_input()` returns *that* file, so the scan
  reads the guard's own chunk. A literal `grep("<token>", src)` matches its own
  source line and fires on every render, finished or not; a probe found three
  markers in a file containing two. The token is built with `paste0()` instead.

# hvtiRtemplates 1.0.4

## Internal

- `hvti_taxonomy()` and `hvti_non_prefixes()` now live in `hvtiRutilities`
  and are re-exported from here. Callers are unaffected — both are still
  available unqualified from `hvtiRtemplates`. The table is shared
  vocabulary rather than template machinery, and `hvtiRutilities` is the
  lower layer, so the dependency now points that way.
- Added `tests/testthat/test-reexports.R`, which checks `getNamespaceExports()`
  directly, so a dropped `@export` on a re-export is caught by the suite
  instead of passing silently.

# hvtiRtemplates 1.0.3

## Breaking changes

- `new_job()` now takes `endpoint` and `type` in place of `basename`, and `dir`
  defaults to the study root rather than `"qmd"`. It writes
  `<folder>/<endpoint>-<type>-<NN.MM>-<prefix>.qmd` — into the taxonomy folder
  the template belongs to, not a flat `qmd/`. The `type` is required because a
  set is keyed on `(endpoint, analysis type)`: one endpoint is analyzed by
  several methods and those chains share their upstream, so keyed on the
  endpoint alone two sets would write to one filename.
- `template_path()`'s argument is renamed from `name` to `prefix`, which is what it
  always matched on.
- `template_list()` gains an `ordinal` column, and reports `folder` from the
  directory a template sits in rather than by looking its prefix up in
  `hvti_taxonomy()`.

## Improvements

- Templates are named `<NN.MM>-<prefix>.qmd` and live in the taxonomy folder
  they scaffold into. The name is parsed by pattern rather than by splitting on
  dots, which the old `.prefix_of()` heuristic could not do once the ordinal
  contained one.
- The `ac` template declares its set with `ENDPOINT` and `TYPE` markers and
  resolves artifact paths from them, so a scaffolded job needs no output path
  edited by hand. `new_job()` now substitutes the caller's `endpoint`/`type`
  into those declarations after copying the template, so a scaffolded job's
  body agrees with its own filename instead of still naming the template's
  placeholder set. The template itself checks this at render time — comparing
  its `ENDPOINT`/`TYPE` declarations against `knitr::current_input()` — and
  errors if they disagree, because a mismatch resolves `set_path()` into
  another set's artifact directory silently. The check is a no-op outside a
  knitr render, so editing the file interactively in RStudio is unaffected.
- `new_job()` validates `endpoint` and `type`: each must be a single non-`NA`
  string matching `^[A-Za-z0-9_]+$`, since `-` is the filename's field
  separator and `.` is reserved to the ordinal. This also rejects a leading
  `../` that would otherwise escape the taxonomy folder.
- New tests cross-check every template's ordinal against `hvti_taxonomy()` —
  the major against the folder it sits in, and the minors against row order
  within that folder — and assert that no two templates share a prefix, since
  `template_path()` and `new_job()` both resolve with `match()`, which takes
  the first hit silently.
- `hs` is refiled from `distributions` to `analyses`, immediately after `hm`,
  the job it actually consumes. `hvti_taxonomy()` gains an `estimates` row for
  the artifact directory that design already relies on; the row carries no
  prefix (`NA_character_`), since `estimates` is an artifact kind rather than
  an analysis type. Its position shifts the folder majors: `graphs` is now
  `06` and `documents` `07` (`distributions` is unaffected, so `ac` stays
  `03.01`).

## Bug fixes

- `new_job()` no longer leaves a copied-but-unsubstituted job file behind when
  writing the `ENDPOINT`/`TYPE` markers fails. Previously a template whose
  markers had moved or been removed still left its copy on disk after
  erroring — a job named for one set but declaring the template's placeholder
  set, and a retry then hit the refuse-to-overwrite guard and reported
  "already exists" instead of the actual template problem.
- The `ac` template's render-time filename guard strips whatever extension
  `knitr::current_input()` reports instead of a hard-coded `.qmd`. Quarto
  knits through an intermediate `.rmarkdown` file, so the old pattern never
  matched under a real render; it happened to be harmless because the stray
  extension landed on a field the guard does not read, but the fix removes
  the reliance on that coincidence.

# hvtiRtemplates 1.0.2

## Bug fixes

- `.Rbuildignore` now excludes `.claude` and `.remember`, which hold session
  tooling; `.claude` can also contain a git worktree. Their contents were
  raising two NOTEs — hidden files, and non-portable paths over the tarball
  length limit — neither of which is about the package. `.remember` was
  invisible until `.claude` was excluded, because `R CMD check` reports every
  hidden path in one NOTE.

# hvtiRtemplates 1.0.1

## New features

- `new_job()` scaffolds an analysis job from a supported template, naming the
  file `<prefix>.<basename>.qmd` and refusing to overwrite an existing job.
- `inst/templates/ac.qmd` — the first supported job template, for actuarial
  life tables. It carries its own `format:` block so that a copied job renders
  standalone, resolves the project root itself so no path needs editing, and
  marks every study-specific line `EDIT:`.

  The cohort section offers two shapes, because the choice is not cosmetic:
  a job analyzing the whole study uses `assert_cohort()`, while a job
  analyzing a filtered subset must supply its own gate — `_study.yml` records
  the study cohort, so `assert_cohort()` would pass while the job ran on a
  cohort nobody checked.

  `hz` and `hp` are deliberately absent: each exists in only one study, and a
  template extracted from a single example encodes that study's choices as
  though they were general.

# hvtiRtemplates 1.0.0

* Initial release.

* `hvti_taxonomy()` encodes the group's analysis-prefix system as data rather
  than as a README, so the test suite checks it against the templates actually
  present instead of letting it drift.

* `template_list()` and `template_path()` resolve a template name to an
  installed file, so a study binds to a versioned template rather than to a
  copy. Both return empty until stage 3 of the templates-and-provenance design
  adds the templates.

* `hvti_non_prefixes()` records the leading name fields that are utilities
  rather than analysis prefixes, which is what lets the test suite tell "not a
  prefix" apart from "a prefix nobody documented".

## Provenance

During development this repository also carried the legacy SAS template corpus
(240 files) and the SAS macro library (495 files, with history imported from
2014) as a reference specification. Both were removed before release, and
every path was purged from every commit with `git filter-repo`. They are not
recoverable from this repository's history.

Parity checks against the SAS originals therefore need a source outside this
repository. The institutional SAS license expires 2026-09-29.

**Corrected 2026-08-29: the license runs into 2027, not out in 2026** (working
date `2027-09-29`, not yet confirmed). The date above was wrong when 1.0.0
shipped. It is left as written and corrected here; see the 1.0.10 entry.

A result filed before the migration still cannot say which macro version
produced it. That was already true — `%inc` bound late to a mutable directory
with no version — and removing the corpus neither creates nor worsens it.
