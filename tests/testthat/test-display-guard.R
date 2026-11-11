test_that(".no_values names the ID, the KEY, what read_job_data() drops, and record numbers under other names", {
  d <- data.frame(randid = 1:3, visit = 1:3, pt_mrn = 1:3, hosp_mrn = 1:3, medrec = 1:3, medical_record = 1:3,
                  patid = 1:3, cnum = 1:3, ccfid = 1:3, clinic_no = 1:3, age = 1:3, nyha = 1:3)
  out <- hvtiRtemplates:::.no_values(d, "randid", c("randid", "visit"), "clinic_no")
  expect_setequal(setdiff(names(d), out), c("age", "nyha"))
})

test_that(".refuse_display says when a column is refused only because it is in KEY", {
  # The 2026-11-11 training: KEY <- c("ccfid", "dt_surg") with X_VAR <- "dt_surg" stopped the job
  # with "which identifies patients", and nobody could tell that KEY was the reason.
  d <- data.frame(ccfid = 1:3, dt_surg = Sys.Date() + 0:2, pt_mrn = 1:3, age = 1:3)
  no_values <- hvtiRtemplates:::.no_values(d, "ccfid", c("ccfid", "dt_surg", "pt_mrn"))
  expect_error(hvtiRtemplates:::.refuse_display("DT_SURG", no_values, "X_VAR"), "X_VAR names DT_SURG, which is in KEY")
  expect_error(hvtiRtemplates:::.refuse_display("dt_surg", no_values, "X_VAR"), "or take it out of KEY")
  # A KEY column that is an identifier in its own right keeps the identifier message.
  expect_error(hvtiRtemplates:::.refuse_display("pt_mrn", no_values, "X_VAR"), "identifies patients")
  expect_error(hvtiRtemplates:::.refuse_display("ccfid", no_values, "X_VAR"), "identifies patients")
})

test_that("a KEY column whose values look like record numbers is an identifier, not only a KEY column", {
  # Found in review of #515: such a column was told to leave KEY, which the value check then refuses.
  d <- data.frame(ccfid = 1:12, local_code = 10000000 + seq(1, 120, by = 10), dt_surg = Sys.Date() + 0:11)
  no_values <- hvtiRtemplates:::.no_values(d, "ccfid", c("ccfid", "local_code"))
  expect_error(hvtiRtemplates:::.refuse_display("local_code", no_values, "X_VAR"), "identifies patients")
  # Said to be a measurement, it is refused for KEY alone again.
  withr::local_options(hvtiRtemplates.not_identifiers = "local_code")
  cleared <- hvtiRtemplates:::.no_values(d, "ccfid", c("ccfid", "local_code"))
  expect_error(hvtiRtemplates:::.refuse_display("local_code", cleared, "X_VAR"), "which is in KEY")
})

test_that("a setting naming a KEY column and an identifier is refused for the identifier first", {
  d <- data.frame(ccfid = 1:3, dt_surg = Sys.Date() + 0:2, pt_mrn = 1:3)
  no_values <- hvtiRtemplates:::.no_values(d, "ccfid", c("ccfid", "dt_surg"))
  expect_error(hvtiRtemplates:::.refuse_display(c("dt_surg", "pt_mrn"), no_values, "VARIABLES"),
               "VARIABLES names pt_mrn, which identifies patients")
})

test_that(".refuse_display stops on a named identifier, whatever its case, and names no value", {
  expect_error(hvtiRtemplates:::.refuse_display(list(a = c("age", "MRN")), "mrn", "GROUPS"), "GROUPS names MRN")
  expect_true(hvtiRtemplates:::.refuse_display(c("age", NA), "mrn", "GROUPS"))
  expect_true(hvtiRtemplates:::.refuse_display(NULL, "mrn", "GROUPS"))
})

test_that(".displayable leaves out identifiers by name and by their values", {
  d <- data.frame(age = 40 + 1:20, counts = rep(1000:1009, 2L), lab = 1000.5 + 1:20, rec = 500000L + 1:20, nid = 1:20)
  out <- hvtiRtemplates:::.displayable(names(d), hvtiRtemplates:::.no_values(d, "nid"))
  expect_identical(out$keep, c("age", "counts", "lab"))
  expect_identical(out$left_out, c("rec", "nid"))
  expect_false(hvtiRtemplates:::.looks_like_identifier_values(c(1000, 1001, NA)))
  expect_false(hvtiRtemplates:::.looks_like_identifier_values(letters))
  expect_false(hvtiRtemplates:::.looks_like_identifier_values(1990:2009))
})

test_that("a setting cannot name a column whose values look like record numbers, unless the job clears it", {
  d <- data.frame(subject = 1:30, recordnumber = 7700000L + 1:30, age = 40 + 1:30 %% 20)
  no_values <- hvtiRtemplates:::.no_values(d, "subject")
  expect_error(hvtiRtemplates:::.refuse_display("recordnumber", no_values, "GROUPS"), "look like record numbers")
  expect_error(hvtiRtemplates:::.refuse_display("recordnumber", no_values, "GROUPS"), "not_identifiers")
  expect_true(hvtiRtemplates:::.refuse_display("age", no_values, "GROUPS"))

  withr::local_options(hvtiRtemplates.not_identifiers = c("recordnumber", "subject"))
  cleared <- hvtiRtemplates:::.no_values(d, "subject")
  expect_true(hvtiRtemplates:::.refuse_display("recordnumber", cleared, "GROUPS"))
  expect_identical(hvtiRtemplates:::.displayable("recordnumber", cleared)$keep, "recordnumber")
  # It clears a shape, never a column the job or the names call an identifier.
  expect_error(hvtiRtemplates:::.refuse_display("subject", cleared, "GROUPS"), "identifies patients")
})

# A canary: synthetic record numbers planted in the data must appear nowhere in the
# report, with the job's defaults and with each column named where a report could show it.
canary_report <- function(prefix, qualifier, edits) {
  plant <- function(built) {
    built$ccfid <- 7700000L + built$ccfid - 1000L
    built$pt_mrn <- 9000000L + seq_len(nrow(built))
    built
  }
  root <- migration_study_fixture(NULL, .local_envir = parent.frame(), edit_built = plant)  # nolint: object_usage_linter.
  s <- scaffold_job(prefix, qualifier, edits, root = root)  # nolint: object_usage_linter.
  quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
  html <- list.files(root, pattern = "[.]html$", recursive = TRUE, full.names = TRUE)
  gsub("base64,[A-Za-z0-9+/=]+", "", paste(unlist(lapply(html, readLines, warn = FALSE)), collapse = "\n"))
}

test_that("planted identifiers reach no report", {
  skip_on_cran()
  skip_if_not(quarto::quarto_available())
  general <- canary_report("dc", "general", list("^ID_COL <- " = "ID_COL <- \"ccfid\""))
  expect_false(grepl("90000(01|40)|77000(01|40)", general))
  expect_match(general, "Left out as patient identifiers", fixed = TRUE)
  eda <- canary_report("dc", "eda", list("^VARIABLE_SET <- " = "VARIABLE_SET <- \"all\"", "^ANALYSIS_SET <- " = "ANALYSIS_SET <- NULL",
                                         "^ORIGIN_YEAR <- " = "ORIGIN_YEAR <- 1980", "^X_VAR <- " = "X_VAR <- \"year\""))
  expect_false(grepl("90000(01|40)|77000(01|40)", eda))
})

test_that("vt-explain refuses a STRATIFY that is a column of the job's resolved KEY", {
  # Read from the source: running the chunk needs a fitted vt.rds, and no fixture fit carries a KEY.
  src <- paste(readLines(template_path("vt", "explain"), warn = FALSE), collapse = " ")
  expect_match(src, ".no_values(.d_all, .vt$settings$id, attr(.jd$record, \"selection\")$key)", fixed = TRUE)
})

test_that("dc-tables stops when GROUPS names a record number under a name nobody listed", {
  skip_on_cran()
  skip_if_not(quarto::quarto_available())
  root <- migration_study_fixture(NULL, edit_built = function(built) {  # nolint: object_usage_linter.
    built$recordnumber <- 5500000L + seq_len(nrow(built))
    built
  })
  edits <- list("^GROUPS <- NULL$" = "GROUPS <- list(Symptoms = c(\"recordnumber\"))")
  s <- scaffold_job("dc", "tables", edits, root = root)  # nolint: object_usage_linter.
  # quarto_render(quiet = TRUE) hides why a render failed, and any failure would pass an expect_error().
  out <- suppressWarnings(system2(quarto::quarto_path(), c("render", shQuote(s$job), "--execute-dir", shQuote(dirname(s$job))),
                                  stdout = TRUE, stderr = TRUE))
  expect_gt(attr(out, "status"), 0L)
  expect_match(paste(out, collapse = " "), "names recordnumber, whose values look like record numbers", fixed = TRUE)
  expect_false(any(grepl("5500001", out, fixed = TRUE)))
})

test_that("vt-fit's out-of-distribution table shows counts, and survives a job with none", {
  lines <- readLines(template_path("vt", "fit"), warn = FALSE)
  start <- match("#| label: tbl-ood", lines)
  end <- start + match("```", lines[(start + 1L):length(lines)])
  code <- chunk_expression(lines[seq.int(start, end - 1L)], "tbl-ood")
  rows <- data.frame(ID = c("digest1", "digest2"), method = "gower", arm = c("A", "B"), in_distribution = TRUE,
                     distance = 1, reference = 2, features = "")
  env <- list2env(list(.elig_rows = rows), parent = baseenv())
  out <- capture.output(res <- eval(code, env))
  expect_false(any(grepl("digest", c(out, res))))
  rows$in_distribution[1L] <- FALSE
  env <- list2env(list(.elig_rows = rows), parent = baseenv())
  capture.output(res <- eval(code, env))
  expect_false(any(grepl("digest", res)))
  expect_true(any(grepl("gower.*A.*1", res)))
})
