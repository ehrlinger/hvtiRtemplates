test_that(".no_values names the ID, the KEY, what read_job_data() drops, and record numbers under other names", {
  d <- data.frame(randid = 1:3, visit = 1:3, pt_mrn = 1:3, hosp_mrn = 1:3, medrec = 1:3, medical_record = 1:3,
                  patid = 1:3, cnum = 1:3, ccfid = 1:3, clinic_no = 1:3, age = 1:3, nyha = 1:3)
  out <- hvtiRtemplates:::.no_values(d, "randid", c("randid", "visit"), "clinic_no")
  expect_setequal(setdiff(names(d), out), c("age", "nyha"))
})

test_that(".refuse_display stops on a named identifier, whatever its case, and names no value", {
  expect_error(hvtiRtemplates:::.refuse_display(list(a = c("age", "MRN")), "mrn", "GROUPS"), "GROUPS names MRN")
  expect_true(hvtiRtemplates:::.refuse_display(c("age", NA), "mrn", "GROUPS"))
  expect_true(hvtiRtemplates:::.refuse_display(NULL, "mrn", "GROUPS"))
})

test_that(".displayable leaves out identifiers by name and by their values", {
  d <- data.frame(age = 40 + 1:20, counts = rep(1000:1009, 2L), lab = 1000.5 + 1:20, rec = 500000L + 1:20, nid = 1:20)
  out <- hvtiRtemplates:::.displayable(names(d), d, "nid")
  expect_identical(out$keep, c("age", "counts", "lab"))
  expect_identical(out$left_out, c("rec", "nid"))
  expect_false(hvtiRtemplates:::.looks_like_identifier_values(c(1000, 1001, NA)))
  expect_false(hvtiRtemplates:::.looks_like_identifier_values(letters))
})

# A canary: synthetic record numbers planted in the data must appear nowhere in the
# report, with the job's defaults and with each column named where a report could show it.
canary_report <- function(prefix, qualifier, edits) {
  plant <- function(built) {
    built$ccfid <- 7700000L + built$ccfid - 1000L
    built$pt_mrn <- 9000000L + seq_len(nrow(built))
    built
  }
  root <- migration_study_fixture(NULL, .local_envir = parent.frame(), edit_built = plant)
  s <- scaffold_job(prefix, qualifier, edits, root = root)
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
