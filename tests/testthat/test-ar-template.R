# The ar template scaffolds, and an ar job renders end to end against a
# finished hz job. Spec section 7.

test_that("ar scaffolds into documents with one SUBJECT and one TYPE line", {
  root <- hazard_study()
  job <- suppressMessages(add_job("ar", "dead", "question", dir = root))
  expect_match(job, "/(50_)?documents/ar\\.dead\\.question\\.qmd$")
  src <- readLines(job)
  expect_length(grep("^SUBJECT\\s+<- ", src), 1L)
  expect_length(grep("^TYPE\\s+<- ", src), 1L)
  expect_gte(length(grep("EDIT:", src)), 2L)
})

test_that("an ar job renders against a finished hz job", {
  skip_on_cran()
  skip_if_not_installed("TemporalHazard")
  skip_if(Sys.which("quarto") == "", "quarto is not installed")
  dat <- hazard_data()
  root <- hazard_study(dat)
  hz <- suppressMessages(add_job("hz", "dead", "hz", dir = root))
  # Stand in for a finished job: set the one choice an unedited hz stops on, the
  # expected counts, then remove the marker word only. Truncating a line at the
  # marker would leave a one-line HTML comment unclosed.
  cc <- hvtiRutilities::cohort_counts(dat, event = "dead", time = "iv_dead")
  src <- readLines(hz)
  gate <- grep("^EXPECTED <- ", src)
  expect_length(gate, 1L)
  src[gate] <- sprintf("EXPECTED <- list(n = %dL, n_events = %dL, n_censored = %dL)", cc$n, cc$n_events, cc$n_censored)
  writeLines(gsub("EDIT:", "", src, fixed = TRUE), hz)
  render_job(hz)
  ar <- suppressMessages(add_job("ar", "dead", "question", dir = root))
  a <- gsub("hz.dead_pa.hz", "hz.dead.hz", readLines(ar), fixed = TRUE)
  writeLines(gsub("EDIT:", "", a, fixed = TRUE), ar)
  ar_paste_methods(ar)
  render_job(ar)
  html <- readLines(sub("[.]qmd$", ".html", ar), warn = FALSE)
  expect_true(any(grepl("Item 1", html, fixed = TRUE)))
  expect_false(any(grepl("callout-warning", html, fixed = TRUE)))
})
