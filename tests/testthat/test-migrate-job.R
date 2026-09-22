test_that(".infer_template reads prefix and qualifier from a corpus job name", {
  expect_identical(.infer_template("x/dc.tables.ods.sas", NULL, NULL), list(prefix = "dc", qualifier = "tables"))
  expect_identical(.infer_template("x/ac.dead.sas", NULL, NULL), list(prefix = "ac", qualifier = NULL))
  expect_identical(.infer_template("x/odd_name.sas", "dp", "trends"), list(prefix = "dp", qualifier = "trends"))
})

test_that(".infer_template refuses a qualified prefix it cannot resolve", {
  expect_error(.infer_template("x/dc.custom.sas", NULL, NULL), "tables")
  expect_error(.infer_template("x/oddname.sas", NULL, NULL), "prefix")
})

test_that("a prefix given without a qualifier still reads the qualifier from the filename", {
  expect_identical(.infer_template("x/dc.tables.ods.sas", "dc", NULL), list(prefix = "dc", qualifier = "tables"))
  # The caller's prefix wins over the filename's first field, and the second
  # field is read against that prefix's qualifiers.
  expect_identical(.infer_template("x/old.tables.sas", "dc", NULL), list(prefix = "dc", qualifier = "tables"))
  expect_identical(.infer_template("x/dc.custom.sas", "dc", NULL), list(prefix = "dc", qualifier = NULL))
  expect_error(.select_template(template_list(), "dc", NULL), "name one with `qualifier`")
  expect_identical(.infer_template("x/ac.tables.sas", "ac", NULL), list(prefix = "ac", qualifier = NULL))
  expect_identical(.infer_template("x/dc.sas", "dc", NULL), list(prefix = "dc", qualifier = NULL))
  root <- migration_study_fixture()
  source <- file.path(root, "descriptive", "dc.tables.ods.sas")
  writeLines("%desc_tab(vartype=continuous,input=built,varlist=/* Demography */ age);", source)
  job <- migrate_job(
    source = source, subject = "cohort", type = "eda", prefix = "dc", dir = root
  )
  expect_identical(basename(job), "cohort-eda-dc-tables.qmd")
  custom <- file.path(root, "descriptive", "dc.custom.sas")
  writeLines("proc means; run;", custom)
  expect_error(
    migrate_job(source = custom, subject = "cohort", type = "eda", prefix = "dc", dir = root),
    "migrate_job\\(\\).*name one with `qualifier`"
  )
})

test_that(".default_evidence has no default for a source without an extension", {
  d <- withr::local_tempdir()
  # The directory's dot must not count as the source's extension.
  d <- file.path(d, "study.v2")
  dir.create(d)
  src <- file.path(d, "dctables")
  file.create(src)
  expect_null(.default_evidence(src, "lst"))
  expect_null(.default_evidence(src, "log"))
})

test_that(".default_evidence finds a same-stem listing and log", {
  d <- tempfile("evidence-")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  src <- file.path(d, "dc.tables.ods.sas")
  file.create(src, file.path(d, "dc.tables.ods.lst"))
  expect_identical(.default_evidence(src, "lst"), file.path(d, "dc.tables.ods.lst"))
  expect_null(.default_evidence(src, "log"))
})

test_that("migrate_job refuses out-of-root sources", {
  root <- migration_study_fixture()
  src <- withr::local_tempfile(fileext = ".sas")
  writeLines("proc means; run;", src)
  expect_error(migrate_job(source = src, subject = "cohort", type = "eda", prefix = "ac", dir = root), "beneath the study root")
})

test_that("migrate_job scaffolds a template with no converter and says so", {
  root <- tempfile("migrate-noconv-")
  suppressMessages(hvtiRutilities::study_setup(root, study = "No converter", study_tracker_id = 1L))
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  src <- file.path(root, "20_distributions", "ac.dead.sas")
  writeLines(c("proc lifetest data=built;", "run;"), src)

  out <- migrate_job(source = src, subject = "dead", type = "eda")

  expect_identical(basename(out), "dead-eda-ac.qmd")
  tpl <- readLines(template_path("ac"), warn = FALSE)
  tok <- paste0("ED", "IT", ":")
  expect_identical(sum(grepl(tok, readLines(out), fixed = TRUE)), sum(grepl(tok, tpl, fixed = TRUE)))
  report <- readLines(sub("[.]qmd$", "-migration.md", out))
  expect_true(any(grepl("No converter: every choice is manual", report, fixed = TRUE)))
  expect_identical(readLines(src), c("proc lifetest data=built;", "run;"))
})

test_that("optional evidence must exist when supplied", {
  root <- migration_study_fixture()
  source <- file.path(root, "descriptive", "dc.tables.sas")
  writeLines("%desc_tab(vartype=continuous, varlist=age);", source)
  expect_error(
    migrate_job(source = source, subject = "cohort", type = "eda", prefix = "dc", qualifier = "tables",
                log = file.path(root, "missing.log"), dir = root),
    "missing.log"
  )
})

test_that("region replacement requires exactly one ordered marker pair", {
  x <- c("# MIGRATE-BEGIN: config", "old", "# MIGRATE-END: config")
  expect_identical(.replace_regions(x, c(config = "new")), c(x[1L], "new", x[3L]))
  expect_error(.replace_regions(x[-3L], c(config = "new")), "exactly one")
  expect_error(.replace_regions(c(x, x), c(config = "new")), "exactly one")
  expect_error(.replace_regions(rev(x), c(config = "new")), "before")
})

test_that("region replacement preserves surrounding lines and handles multiple regions", {
  x <- c("before", "# MIGRATE-BEGIN: a", "old a", "# MIGRATE-END: a",
         "between", "# MIGRATE-BEGIN: b", "old b", "# MIGRATE-END: b", "after")
  expect_identical(
    .replace_regions(x, c(b = "", a = "one\ntwo")),
    c("before", "# MIGRATE-BEGIN: a", "one", "two", "# MIGRATE-END: a",
      "between", "# MIGRATE-BEGIN: b", "# MIGRATE-END: b", "after")
  )
  expect_error(.replace_regions(x, c("unnamed")), "named character")
  expect_error(.replace_regions(x, c(a = "first", a = "second")), "unique")
  nested <- c("# MIGRATE-BEGIN: a", "# MIGRATE-BEGIN: b", "# MIGRATE-END: b", "# MIGRATE-END: a")
  expect_error(.replace_regions(nested, c(a = "one", b = "two")), "overlap")
})

test_that("pair placement writes both complete files and removes staging files", {
  root <- withr::local_tempdir()
  out <- file.path(root, "jobs", "job.qmd")
  report <- file.path(root, "reports", "job-migration.md")
  .write_migration_pair(c("job", "complete"), "report", out, report)
  expect_identical(readLines(out), c("job", "complete"))
  expect_identical(readLines(report), "report")
  expect_setequal(list.files(root, recursive = TRUE, all.files = TRUE),
                  c("jobs/job.qmd", "reports/job-migration.md"))
})

test_that("pair placement refuses either existing target without changing it", {
  for (existing in c("job.qmd", "job-migration.md")) {
    root <- withr::local_tempdir()
    out <- file.path(root, "job.qmd")
    report <- file.path(root, "job-migration.md")
    writeLines("keep original", file.path(root, existing))
    expect_error(.write_migration_pair("new job", "new report", out, report), "refusing to overwrite")
    expect_identical(readLines(file.path(root, existing)), "keep original")
    expect_identical(list.files(root, all.files = TRUE, no.. = TRUE), existing)
  }
})

test_that("pair placement leaves neither output when the report directory is blocked", {
  root <- withr::local_tempdir()
  out <- file.path(root, "job.qmd")
  writeLines("blocking file", file.path(root, "blocked"))
  report <- file.path(root, "blocked", "job-migration.md")
  expect_error(.write_migration_pair("job", "report", out, report), "migration report")
  expect_false(file.exists(out))
  expect_false(file.exists(report))
  expect_identical(list.files(root, all.files = TRUE, no.. = TRUE), "blocked")
  expect_identical(readLines(file.path(root, "blocked")), "blocking file")
})

test_that("pair placement rejects identical destinations", {
  root <- withr::local_tempdir()
  path <- file.path(root, "job.qmd")
  expect_error(.write_migration_pair("job", "report", path, path), "distinct")
  expect_false(file.exists(path))
})

test_that("a second publication failure rolls back a successfully placed job", {
  root <- withr::local_tempdir()
  out <- file.path(root, "job.qmd")
  # These different spellings resolve to one target. Both staging writes
  # succeed; the second hard link fails because the first has occupied it.
  report <- file.path(root, ".", "job.qmd")
  expect_error(.write_migration_pair("job", "report", out, report), "Could not place migration report")
  expect_false(file.exists(out))
  expect_length(list.files(root, all.files = TRUE, no.. = TRUE), 0L)
})

test_that("evidence records relative paths, byte checksums, and numbered text without modifying files", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "descriptive"))
  source <- file.path(root, "descriptive", "job.sas")
  writeBin(charToRaw("abc"), source)
  log <- file.path(root, "job.log")
  writeLines(c("routine", "ERROR: missing variable"), log)
  lst <- file.path(root, "job.lst")
  writeLines(c("", "N = 40"), lst)
  ref <- file.path(root, "table.rtf")
  writeBin(charToRaw("abc"), ref)
  paths <- c(source = source, log = log, lst = lst, reference = ref)
  before <- lapply(paths, function(path) readBin(path, "raw", n = file.info(path)$size))
  evidence <- .migration_evidence(paths, normalizePath(root, winslash = "/"))
  expect_identical(evidence$source, data.frame(line = 1L, text = "abc"))
  expect_identical(evidence$log$line, 2L)
  expect_identical(evidence$lst$line, 2L)
  expect_identical(evidence$files$path, c("descriptive/job.sas", "job.log", "job.lst", "table.rtf"))
  expect_identical(evidence$files$sha256[c(1L, 4L)], rep(
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", 2L
  ))
  expect_identical(evidence$reference, "table.rtf")
  expect_identical(lapply(paths, function(path) readBin(path, "raw", n = file.info(path)$size)), before)
})

test_that("named path arguments retain their source and log roles", {
  root <- withr::local_tempdir()
  source <- file.path(root, "job.sas")
  log <- file.path(root, "job.log")
  writeLines("proc means; run;", source)
  writeLines("ERROR: failed run", log)
  paths <- c(source = c(filename = source), log = c(filename = log))
  evidence <- .migration_evidence(paths, normalizePath(root, winslash = "/"))
  expect_identical(evidence$source$text, "proc means; run;")
  expect_identical(evidence$log$severity, "error")
  expect_identical(evidence$files$role, c("source", "log"))
})

test_that("migration reports include decisions, provenance and checklist without absolute paths", {
  root <- withr::local_tempdir()
  source <- file.path(root, "job.sas")
  writeBin(charToRaw("abc"), source)
  evidence <- .migration_evidence(c(source = source), normalizePath(root, winslash = "/"))
  evidence$log <- data.frame(line = 3L, severity = "error", text = paste("ERROR: failed", source))
  evidence$lst <- data.frame(line = 2L, text = "N = 40")
  result <- list(
    regions = c(config = "AGE <- 40"),
    translated = data.frame(line = 7L, text = "var age", value = "age"),
    unresolved = data.frame(line = 9L, text = "%inc '/studies/private/vars.sas';", marker = "EDIT: review include"),
    ignored = data.frame(line = 12L, text = "ods close", reason = "output plumbing")
  )
  report <- paste(.migration_report(evidence, result, "dc-tables", version = "1.1.0"), collapse = "\n")
  for (expected in c("job.sas", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                     "dc-tables", "1.1.0", "Translated", "Unresolved", "Ignored", "Log findings", "Listing facts",
                     "line=7", "line=9", "line=12", "EDIT: review include", "output plumbing", "N = 40", "- [ ]")) {
    expect_match(report, expected, fixed = TRUE)
  }
  expect_false(grepl(root, report, fixed = TRUE))
  expect_false(grepl("/studies/private", report, fixed = TRUE))
  expect_match(report, "%inc '[string]';", fixed = TRUE)
})

test_that("report redaction removes complete quoted paths across operating systems", {
  root <- withr::local_tempdir()
  source <- file.path(root, "job.sas")
  writeLines("proc means; run;", source)
  evidence <- .migration_evidence(c(source = source), normalizePath(root, winslash = "/"))
  paths <- c(
    "/legacy/Study Alpha/private/vars.sas",
    "C:\\Legacy Studies\\Synthetic\\datasets",
    "\\\\server\\Legacy Studies\\Synthetic\\datasets"
  )
  result <- list(
    regions = character(), translated = data.frame(), ignored = data.frame(),
    unresolved = data.frame(
      line = 1:3,
      text = paste0("%include '", paths, "';"),
      marker = "EDIT: review include"
    )
  )
  evidence$log <- data.frame(line = 1:3, severity = "warning", text = paste0('WARNING: "', paths, '"'))
  evidence$lst <- data.frame(line = 1:3, text = paste0('Output: "', paths, '"'))
  report <- .migration_report(evidence, result, "dc-tables")
  for (i in seq_along(paths)) {
    # Masking hides the quoted path in the report; redaction still removes it wherever text is not masked.
    expect_true(paste0("- line=", i, "; text=%include '[string]';; marker=EDIT: review include") %in% report)
    expect_identical(.migration_redact_text(paste0("%include '", paths[[i]], "';")), "%include '[absolute path]';")
    expected <- paste0("- line=", i, "; severity=warning; text=SAS log message content withheld; review the source locally.")
    expect_true(expected %in% report)
    expect_true(paste0("- line=", i, '; text=Output: "[string]"') %in% report)
  }
  expect_false(any(grepl("Alpha|Synthetic|vars[.]sas|datasets", report)))
})

test_that("report provenance preserves punctuation and spaces in validated relative paths", {
  root <- withr::local_tempdir()
  relative <- c("descriptive/Source (legacy)/job.sas", "documents/Report (final)/table.rtf",
                "documents/Report, copy; [review]/table.docx")
  paths <- file.path(root, relative)
  for (path in paths) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    writeBin(charToRaw("abc"), path)
  }
  evidence <- .migration_evidence(
    c(source = paths[[1L]], reference = paths[2:3]), normalizePath(root, winslash = "/")
  )
  result <- list(regions = character(), translated = data.frame(), unresolved = data.frame(), ignored = data.frame())
  report <- .migration_report(evidence, result, "dc-tables")
  expected <- paste0(
    "- role=", c("source", "reference1", "reference2"), "; path=", relative,
    "; sha256=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  )
  expect_true(all(expected %in% report))
  expect_false(any(grepl("[absolute path]", report, fixed = TRUE)))
})

test_that("unstructured report paths redact safely at punctuation boundaries", {
  root <- withr::local_tempdir()
  source <- file.path(root, "job.sas")
  writeLines("proc means; run;", source)
  evidence <- .migration_evidence(c(source = source), normalizePath(root, winslash = "/"))
  text <- c(
    "value=[/secure/Patient Name/report.sas]",
    "url|/secure/Patient Name/report.sas|tail",
    "value={/secure/Patient Name/report.sas}",
    "value=</secure/Patient Name/report.sas>",
    "value=[C:\\Private Studies\\Patient Name\\report.sas]",
    "url|\\\\server\\Private Studies\\Patient Name\\report.sas|tail",
    "age / 10", "mean=42; label=Age (years)", "ratio=3/4"
  )
  expected <- c(
    "value=[[absolute path]]",
    "url|[absolute path]|tail",
    "value={[absolute path]}",
    "value=<[absolute path]>",
    "value=[[absolute path]]",
    "url|[absolute path]|tail",
    "age / 10", "mean=42; label=Age (years)", "ratio=3/4"
  )
  result <- list(
    regions = character(), translated = data.frame(), ignored = data.frame(),
    unresolved = data.frame(line = seq_along(text), text = text, marker = "EDIT: review")
  )
  report <- .migration_report(evidence, result, "dc-tables")
  for (i in seq_along(expected)) {
    expect_true(paste0("- line=", i, "; text=", expected[[i]], "; marker=EDIT: review") %in% report)
  }
  expect_false(any(grepl("Patient Name|Private Studies|report[.]sas", report)))
})

test_that("malformed adapter results cannot generate an incomplete report", {
  expect_error(.migration_report(list(), list(regions = "bad"), "dc-tables"), "adapter result")
})

test_that("template staging delegates names and declarations without publishing a scaffold", {
  for (folder in c("descriptive", "10_descriptive")) {
    root <- withr::local_tempdir()
    dir.create(file.path(root, folder))
    row <- .select_template(template_list(), "dc", "tables")
    prepared <- .migration_template(row, subject = "mortality", type = "eda", root = root)
    expect_identical(prepared$out, file.path(root, folder, "mortality-eda-dc-tables.qmd"))
    expect_true('ENDPOINT <- "mortality"' %in% prepared$lines)
    expect_true('TYPE     <- "eda"' %in% prepared$lines)
    expect_length(list.files(root, recursive = TRUE, all.files = TRUE), 0L)
  }
})

test_that("migration completion publishes the prepared job and report beside intact evidence", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "descriptive"))
  source <- file.path(root, "descriptive", "job.sas")
  writeLines("proc means; run;", source)
  evidence <- .migration_evidence(c(source = source), normalizePath(root, winslash = "/"))
  prepared <- .migration_template(.select_template(template_list(), "dc", "tables"), subject = "cohort", type = "eda", root = root)
  result <- list(regions = character(), translated = data.frame(), unresolved = data.frame(), ignored = data.frame())
  out <- .migration_finish(prepared, evidence, result)
  expect_identical(out, file.path(root, "descriptive", "cohort-eda-dc-tables.qmd"))
  expect_identical(readLines(out), prepared$lines)
  report <- sub("[.]qmd$", "-migration.md", out)
  expect_true(file.exists(report))
  expect_match(paste(readLines(report), collapse = "\n"), "descriptive/job.sas", fixed = TRUE)
  expect_identical(readLines(source), "proc means; run;")
  expect_error(.migration_finish(prepared, evidence, result), "refusing to overwrite")
})

test_that("failed region replacement never exposes the intermediate template", {
  root <- withr::local_tempdir()
  source <- file.path(root, "job.sas")
  writeLines("proc means; run;", source)
  evidence <- .migration_evidence(c(source = source), normalizePath(root, winslash = "/"))
  prepared <- .migration_template(.select_template(template_list(), "dc", "tables"), subject = "cohort", type = "eda", root = root)
  result <- list(regions = c(nonexistent = "new"), translated = data.frame(),
                 unresolved = data.frame(), ignored = data.frame())
  expect_error(.migration_finish(prepared, evidence, result), "exactly one")
  expect_identical(list.files(root, recursive = TRUE, all.files = TRUE), "job.sas")
})

test_that("log errors add a blocking review marker to the generated job", {
  root <- withr::local_tempdir()
  source <- file.path(root, "job.sas")
  writeLines("proc means; run;", source)
  log <- file.path(root, "job.log")
  writeLines("ERROR: failed run", log)
  evidence <- .migration_evidence(c(source = source, log = log), normalizePath(root, winslash = "/"))
  prepared <- .migration_template(.select_template(template_list(), "dc", "tables"), subject = "cohort", type = "eda", root = root)
  result <- list(regions = character(), translated = data.frame(), unresolved = data.frame(), ignored = data.frame())
  out <- .migration_finish(prepared, evidence, result)
  expect_true(any(grepl("EDIT: resolve SAS log errors", readLines(out), fixed = TRUE)))
  report <- paste(readLines(sub("[.]qmd$", "-migration.md", out)), collapse = "\n")
  expect_match(report, "severity=error", fixed = TRUE)
  expect_false(grepl("ERROR: failed run", report, fixed = TRUE))
})

test_that("output folder links cannot redirect migration outside the study", {
  root <- withr::local_tempdir()
  outside <- withr::local_tempdir()
  link <- file.path(root, "descriptive")
  linked <- suppressWarnings(file.symlink(outside, link))
  skip_if_not(linked, "This platform does not permit creating symbolic links.")
  # R's recursive unlink() on Windows deletes a directory reparse point as a
  # junction and warns on a true symbolic link, so remove the link itself
  # first; rmdir removes a directory link without touching its target. withr
  # runs deferred expressions LIFO, so registering this defer after `root`'s
  # and `outside`'s local_tempdir() cleanups guarantees it runs before either
  # of them, and in particular before withr's recursive unlink() of `root`.
  # The path is built from `link` itself, never normalizePath(), which follows
  # an existing link to its target and would have rmdir remove `outside`
  # instead (#124). A non-zero status is reported rather than discarded.
  if (.Platform$OS.type == "windows") {
    windows_link <- chartr("/", "\\", link)
    withr::defer({
      status <- system2("cmd", c("/c", "rmdir", shQuote(windows_link)))
      if (!identical(as.integer(status), 0L)) warning("rmdir on the test link returned ", status, call. = FALSE)
    })
  }
  row <- .select_template(template_list(), "dc", "tables")
  expect_error(.migration_template(row, subject = "cohort", type = "eda", root = root), "beneath the study root")
  expect_length(list.files(outside, all.files = TRUE, no.. = TRUE), 0L)
})

test_that("public validation follows source links", {
  root <- migration_study_fixture()
  outside <- withr::local_tempfile(fileext = ".sas")
  writeLines("proc means; run;", outside)
  source <- file.path(root, "job.sas")
  linked <- suppressWarnings(file.symlink(outside, source))
  skip_if_not(linked, "This platform does not permit creating symbolic links.")
  expect_error(
    migrate_job(source = source, subject = "cohort", type = "eda", prefix = "dc", qualifier = "tables", dir = root),
    "beneath the study root"
  )
})

test_that("public validation checks all optional evidence and filename fields", {
  root <- migration_study_fixture()
  outside <- withr::local_tempfile(fileext = ".sas")
  writeLines("proc means; run;", outside)
  inside <- file.path(root, "inside.sas")
  writeLines("proc means; run;", inside)
  for (argument in c("lst", "log", "reference")) {
    args <- list(source = inside, subject = "cohort", type = "eda", prefix = "dc", qualifier = "tables", dir = root)
    args[[argument]] <- outside
    expect_error(do.call(migrate_job, args), "beneath the study root")
  }
  expect_error(
    migrate_job(source = inside, subject = "bad-name", type = "eda", prefix = "dc", qualifier = "tables", dir = root),
    "subject"
  )
  expect_error(
    migrate_job(source = inside, subject = "cohort", type = "eda", prefix = "dc", qualifier = "tables", lst = root, dir = root),
    "beneath|readable file"
  )
  expect_error(
    migrate_job(source = inside, subject = "cohort", type = "eda", prefix = "dc", qualifier = "tables",
                reference = c(inside, file.path(root, "missing.rtf")), dir = root),
    "missing.rtf"
  )
})

test_that("render helpers remove only exactly declared review markers", {
  root <- withr::local_tempdir()
  job <- file.path(root, "job.qmd")
  original <- c("BY <- NULL # EDIT: select group", "AGE <- 40 # EDIT: review age")
  writeLines(original, job)
  .resolve_fixture_markers(job, original[[1L]])
  expect_identical(readLines(job), c("BY <- NULL # REVIEWED: select group", original[[2L]]))
  expect_error(.resolve_fixture_markers(job, "EDIT:"), "complete")
  expect_error(.resolve_fixture_markers(job, "unknown # EDIT: choose"), "not found")
})

test_that("render helpers reject unsupported fixture names before creating a study", {
  expect_error(render_migrated_fixture("unknown"), "Unknown migration fixture")
})

test_that("synthetic migration studies register both complete cohorts", {
  root <- migration_study_fixture()
  cfg <- hvtiRutilities::study_config(root)
  expect_equal(nrow(hvtiRutilities::read_built(cfg)), 40L)
  expect_equal(nrow(hvtiRutilities::read_built(cfg, dataset = "complete_cases")), 24L)
  expect_true(all(dir.exists(file.path(root, c("datasets", "descriptive", "graphs", "documents")))))
})

test_that("a qualifier given without a prefix is honoured, not ignored", {
  expect_identical(.infer_template("x/dc.gfup.sas", NULL, "tables"), list(prefix = "dc", qualifier = "tables"))
  root <- migration_study_fixture("dc-gfup")
  source <- file.path(root, "descriptive", "dc.gfup.sas")
  writeLines(c("%desc_tab(vartype=continuous,input=built,varlist=/* Demography */ age);"), source)
  job <- migrate_job(source = source, subject = "cohort", type = "eda", qualifier = "tables", dir = root)
  expect_identical(basename(job), "cohort-eda-dc-tables.qmd")
  expect_error(
    migrate_job(source = source, subject = "cohort", type = "eda", qualifier = "nosuch", dir = root),
    "migrate_job\\(\\).*nosuch"
  )
})

test_that("relative evidence paths resolve against the working directory, not the study root", {
  root <- migration_study_fixture("dc-tables")
  withr::local_dir(dirname(root))
  study <- basename(root)
  job <- migrate_job(
    source = file.path(study, "descriptive", "dc.tables.sas"), subject = "cohort", type = "eda",
    lst = file.path(study, "descriptive", "dc.tables.lst"),
    log = file.path(study, "descriptive", "dc.tables.log"),
    reference = file.path(study, "documents", "general.rtf"), dir = root
  )
  report <- paste(readLines(sub("[.]qmd$", "-migration.md", job)), collapse = "\n")
  expect_match(report, "role=lst; path=descriptive/dc.tables.lst", fixed = TRUE)
  expect_match(report, "path=documents/general.rtf", fixed = TRUE)
  # Root-relative spellings exist only beneath the study, so from here they are missing.
  for (argument in c("lst", "log", "reference")) {
    args <- list(source = file.path(root, "descriptive", "dc.tables.sas"), subject = "again", type = "eda", dir = root)
    args[[argument]] <- switch(argument, lst = "descriptive/dc.tables.lst", log = "descriptive/dc.tables.log",
                               reference = "documents/general.rtf")
    expect_error(do.call(migrate_job, args), paste0("migrate_job\\(\\): `", argument, "` not found: ", args[[argument]]))
  }
  expect_error(migrate_job(source = "descriptive/dc.tables.sas", subject = "again", type = "eda", dir = root),
               "migrate_job\\(\\): source not found: descriptive/dc.tables.sas")
})

test_that("dir and reference are validated with labelled errors", {
  root <- migration_study_fixture("dc-tables")
  source <- file.path(root, "descriptive", "dc.tables.sas")
  expect_error(migrate_job(source = source, subject = "cohort", type = "eda", dir = 5), "`dir`")
  expect_error(migrate_job(source = source, subject = "cohort", type = "eda", dir = NA_character_), "`dir`")
  expect_error(migrate_job(source = source, subject = "cohort", type = "eda", reference = file.path(root, "absent.rtf"), dir = root),
               "migrate_job\\(\\): `reference` not found: .*absent.rtf")
})

test_that("the report says whether same-stem listing and log were found", {
  root <- migration_study_fixture("dc-tables")
  source <- file.path(root, "descriptive", "dc.tables.sas")
  unlink(file.path(root, "descriptive", "dc.tables.log"))
  job <- migrate_job(source = source, subject = "cohort", type = "eda", dir = root)
  report <- readLines(sub("[.]qmd$", "-migration.md", job))
  expect_true("- Listing: found beside source" %in% report)
  expect_true("- Log: not found beside source" %in% report)
  job <- migrate_job(
    source = source, subject = "again", type = "eda",
    log = file.path(root, "descriptive", "dc.tables.lst"), dir = root
  )
  expect_true("- Log: supplied" %in% readLines(sub("[.]qmd$", "-migration.md", job)))
})

test_that("the overwrite refusal names the existing path", {
  root <- withr::local_tempdir()
  out <- file.path(root, "job.qmd")
  writeLines("keep", out)
  expect_error(.write_migration_pair("job", "report", out, file.path(root, "job-migration.md")),
               paste0("refusing to overwrite: ", .canonical_path(out)), fixed = TRUE)
})

test_that("pair placement falls back to renaming the prepared file when hard links fail", {
  local_mocked_bindings(.migration_link = function(from, to) FALSE)
  root <- withr::local_tempdir()
  out <- file.path(root, "job.qmd")
  report <- file.path(root, "job-migration.md")
  .write_migration_pair(c("job", "complete"), "report", out, report)
  expect_identical(readLines(out), c("job", "complete"))
  expect_identical(readLines(report), "report")
  expect_setequal(list.files(root, all.files = TRUE, no.. = TRUE), c("job.qmd", "job-migration.md"))
})

test_that("the rename fallback still refuses a target that appears after the existence check", {
  local_mocked_bindings(.migration_link = function(from, to) {
    writeLines("another writer", to)
    FALSE
  })
  root <- withr::local_tempdir()
  out <- file.path(root, "job.qmd")
  report <- file.path(root, "job-migration.md")
  expect_error(.write_migration_pair("job", "report", out, report), "refusing to overwrite an existing target")
  expect_identical(readLines(out), "another writer")
  expect_false(file.exists(report))
})

test_that("the rename fallback refuses an existing target by path and leaves it unchanged", {
  local_mocked_bindings(.migration_link = function(from, to) FALSE)
  root <- withr::local_tempdir()
  out <- file.path(root, "job.qmd")
  report <- file.path(root, "job-migration.md")
  writeLines("keep", report)
  expect_error(.write_migration_pair("job", "report", out, report),
               paste0("refusing to overwrite: ", .canonical_path(report)), fixed = TRUE)
  expect_identical(readLines(report), "keep")
  expect_identical(list.files(root, all.files = TRUE, no.. = TRUE), "job-migration.md")
})

test_that("a rename fallback failure removes only the output this call placed", {
  local_mocked_bindings(.migration_link = function(from, to) {
    # Another writer claims the report after the job has been placed.
    if (basename(to) == "job-migration.md") writeLines("another writer", to)
    FALSE
  })
  root <- withr::local_tempdir()
  writeLines("unrelated", file.path(root, "notes.txt"))
  out <- file.path(root, "job.qmd")
  report <- file.path(root, "job-migration.md")
  expect_error(.write_migration_pair("job", "report", out, report),
               paste0("refusing to overwrite an existing target: ", .canonical_path(report)), fixed = TRUE)
  expect_false(file.exists(out))
  expect_identical(readLines(report), "another writer")
  expect_identical(readLines(file.path(root, "notes.txt")), "unrelated")
  expect_setequal(list.files(root, all.files = TRUE, no.. = TRUE), c("job-migration.md", "notes.txt"))
})

test_that("migrate_job() labels its own argument validation", {
  root <- migration_study_fixture("dc-tables")
  source <- file.path(root, "descriptive", "dc.tables.sas")
  expect_error(migrate_job(source = source, subject = "cohort", type = "eda", prefix = "dc", qualifier = "tables", dir = 5),
               "^migrate_job\\(\\): `dir` must be a single non-empty")
  expect_error(migrate_job(source = 5, subject = "cohort", type = "eda", prefix = "dc", qualifier = "tables", dir = root),
               "^migrate_job\\(\\): `source` must be a single non-empty")
  expect_error(migrate_job(
    source = source, subject = "cohort", type = "eda", prefix = "dc", qualifier = "tables", lst = NA_character_, dir = root
  ),
  "^migrate_job\\(\\): `lst` must be a single non-empty")
})

test_that(".path_within compares at a separator boundary, and by case only on Windows", {
  expect_true(.path_within("/tmp/ab/x.sas", "/tmp/ab"))
  expect_true(.path_within("/tmp/ab/x.sas", "/tmp/ab/"))
  expect_false(.path_within("/tmp/abc/x.sas", "/tmp/ab"))
  expect_false(.path_within("/tmp/ab", "/tmp/ab"))
  expect_true(.path_within("/x.sas", "/"))
  expect_false(.path_within("/TMP/AB/x.sas", "/tmp/ab", windows = FALSE))
  expect_true(.path_within("C:/Users/RunnerAdmin/Temp/x.sas", "c:/users/runneradmin/temp", windows = TRUE))
  expect_true(.path_within("C:\\Data\\a\\x.sas", "C:/Data/a/", windows = TRUE))
  expect_true(.path_within("C:/Data/a/x.sas", "C:\\Data\\a", windows = TRUE))
  expect_false(.path_within("C:\\Data\\ab\\x.sas", "C:/Data/a", windows = TRUE))
  expect_true(.path_within("C:/x.sas", "C:/", windows = TRUE))
})

test_that(".canonical_path resolves the parent and keeps the final component as given", {
  root <- withr::local_tempdir()
  canonical_root <- normalizePath(root, winslash = "/")
  expect_identical(.canonical_path(file.path(root, "absent.qmd")), paste0(canonical_root, "/absent.qmd"))
  expect_identical(.canonical_path(file.path(root, "new", "deeper", "job.qmd")),
                   paste0(canonical_root, "/new/deeper/job.qmd"))
  writeLines("x", file.path(root, "present.qmd"))
  expect_identical(.canonical_path(paste0(root, "/present.qmd")), paste0(canonical_root, "/present.qmd"))
  expect_false(grepl("\\\\", .canonical_path(file.path(root, "absent.qmd"))))
})

test_that("evidence under an unresolved spelling of the root is still beneath it", {
  root <- withr::local_tempdir()
  source <- file.path(root, "job.sas")
  writeLines("proc means; run;", source)
  # tempdir() is unresolved on macOS (/var -> /private/var) and an 8.3 short
  # name on Windows; the root must be accepted in the spelling it was given.
  evidence <- .migration_evidence(c(source = source), root)
  expect_identical(evidence$root, normalizePath(root, winslash = "/"))
  expect_identical(unname(evidence$paths[["source"]]), "job.sas")
})
