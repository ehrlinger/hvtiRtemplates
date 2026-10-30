identifiability_data <- function() {
  data.frame(nyha = c(rep(1L, 28L), 2L, 3L), age = c(rep(60, 28L), 91, 95), lab = seq_len(30L) + 0.5,
             dt_surg = as.Date("2020-01-01") + seq_len(30L), arm = rep(c("a", "b"), 15L), far = c(seq_len(29L), 500))
}

test_that("each check finds its case, by column and count", {
  f <- hvtiRtemplates:::.identifiability_check(identifiability_data(), c("nyha", "age", "dt_surg", "lab"),
                                               extremes = "far")
  expect_equal(f[f$check == "small", "column"], c("nyha", "age"))
  expect_equal(f[f$check == "small" & f$column == "nyha", "count"], 2L)
  expect_equal(f[f$check == "age", "count"], 2L)
  expect_equal(f[f$check == "date", "column"], "dt_surg")
  expect_equal(f[f$check == "extreme", "count"], 1L)
  # Every column has a maximum: one with no outlier finds nothing.
  expect_equal(nrow(hvtiRtemplates:::.identifiability_check(identifiability_data(), extremes = "lab")), 0L)
  # All values equal, or all missing, finds nothing and does not fail.
  same <- data.frame(a = rep(1, 10L), b = rep(NA_real_, 10L))
  expect_equal(nrow(hvtiRtemplates:::.identifiability_check(same, extremes = c("a", "b"))), 0L)
  expect_named(f, c("check", "column", "count"))
})

test_that("small cells are counted within `by`, and a threshold can be raised", {
  d <- identifiability_data()
  f <- hvtiRtemplates:::.identifiability_check(d, "nyha", by = "arm", small = 2L)
  expect_equal(f$count, 2L)
  expect_equal(nrow(hvtiRtemplates:::.identifiability_check(d, "nyha", small = 1L)), 0L)
})

test_that("a small group is flagged over continuous rows alone", {
  d <- data.frame(arm = c(rep("A", 3L), rep("B", 27L)), measurement = seq_len(30L))
  f <- hvtiRtemplates:::.identifiability_check(d, "measurement", by = "arm")
  expect_equal(f$check, "group")
  expect_equal(f$column, "arm")
  expect_equal(f$count, 1L)
  expect_match(hvtiRtemplates:::.identifiability_notice(f), "`arm` has 1 group of fewer than 5 patients", fixed = TRUE)
  expect_equal(nrow(hvtiRtemplates:::.identifiability_check(d, "measurement", by = "arm", small = 3L)), 0L)
})

test_that("nothing found prints nothing, and absent columns are ignored", {
  f <- hvtiRtemplates:::.identifiability_check(identifiability_data(), c("arm", "absent"), age = "absent")
  expect_equal(nrow(f), 0L)
  expect_identical(as.character(hvtiRtemplates:::.identifiability_notice(f)), "")
})

test_that("the notice names columns and counts, never a value, and reaches the run record", {
  old <- hvtiRtemplates:::.run_state$identifiability
  withr::defer(assign("identifiability", old, envir = hvtiRtemplates:::.run_state))
  assign("identifiability", NULL, envir = hvtiRtemplates:::.run_state)
  out <- hvtiRtemplates:::.identifiability_notice(hvtiRtemplates:::.identifiability_check(identifiability_data(), "age"))
  expect_match(out, "Before this goes in a manuscript", fixed = TRUE)
  expect_match(out, "older than 89", fixed = TRUE)
  expect_false(grepl("91|95", out))
  expect_equal(hvtiRtemplates:::.run_state$identifiability$check, c("small", "age"))
})

test_that("every template that calls the check has its chunk", {
  for (q in list(c("dc", "tables"), c("dc", "gfup"), c("ac", NA))) {
    path <- if (is.na(q[[2L]])) template_path(q[[1L]]) else template_path(q[[1L]], q[[2L]])
    expect_true("#| label: identifiability" %in% readLines(path, warn = FALSE))
  }
})

test_that("a rendered dc-tables report carries the callout and the run record's counts", {
  skip_on_cran()
  skip_if_not(quarto::quarto_available())
  root <- migration_study_fixture(NULL, edit_built = function(b) {
    b$rare <- as.integer(seq_len(nrow(b)) <= 2L)
    b
  })
  s <- scaffold_job("dc", "tables", list("^  Symptoms   = c\\(\"nyha_pr\"\\)" = "  Symptoms = c(\"rare\")"), root = root)
  quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
  html <- paste(unlist(lapply(list.files(root, "[.]html$", recursive = TRUE, full.names = TRUE), readLines, warn = FALSE)),
                collapse = "\n")
  expect_match(html, "Before this goes in a manuscript", fixed = TRUE)
  expect_match(html, "Identifiability", fixed = TRUE)
})
