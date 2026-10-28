test_that("add_job() scaffolds dt into the study's 00_datasets folder", {
  root <- bd_study()
  job <- add_job("dt", "study", "check", dir = root)
  expect_identical(basename(dirname(job)), "00_datasets")
  expect_identical(basename(job), "dt.study.check.qmd")
  lines <- readLines(job, warn = FALSE)
  expect_true(any(lines == "SUBJECT <- \"study\""))
  expect_true(any(lines == "TYPE    <- \"check\""))
})

test_that("dt stops with a plain message when bd has not written the working file", {
  dt_skip()
  s <- dt_study()
  expect_error(dt_run(s$root, dt_choices(DATASET_ID = "not_built")),
               "bd has not written datasets/not_built.rds. Render the bd job with this DATASET_ID first.", fixed = TRUE)
})

test_that("a rebuild of the declared dataset is compared against its registered version", {
  dt_skip()
  s <- dt_study()
  env <- dt_run(s$root)
  expect_match(env$.rebuild_state, "^A rebuild of the study dataset: study_cohort.rds against its registered version ")
  # Nothing changed since registering, so every column reads identical.
  expect_true(all(env$.comparison$verdict == "identical"))
  rows <- attr(env$.comparison, "rows")
  expect_identical(c(length(rows$only_oracle), length(rows$only_r)), c(0L, 0L))
})

test_that("the rebuild comparison reports values, not shape, against the registered version", {
  dt_skip()
  s <- dt_study()
  dt_rebuild(s$root, function(d) {
    d$dead <- 1L - d$dead
    d$iv_dead <- d$iv_dead + 1
    d$ccfid[[1L]] <- "PTSWAP001"
    d
  })
  # HVTI_DATA = "working" makes read_built() serve the working file unless told not to;
  # the baseline must still be the registered version, or every column reads identical.
  withr::local_envvar(HVTI_DATA = "working")
  env <- dt_run(s$root)
  cmp <- as.data.frame(env$.comparison)
  rows <- attr(env$.comparison, "rows")
  # Same shape: as many rows and the same columns. A shape-only comparison calls this unchanged.
  expect_identical(rows$n_oracle, rows$n_r)
  # Every row in both differs in the event indicator and the follow-up interval.
  changed <- cmp[cmp$variable %in% c("dead", "iv_dead"), ]
  expect_identical(changed$verdict, c("differs", "differs"))
  expect_identical(changed$n_differ, rep(rows$n_common, 2L))
  expect_true(all(cmp$verdict[!cmp$variable %in% c("dead", "iv_dead")] == "identical"))
  # One patient swapped for another: one row on each side.
  expect_length(rows$only_oracle, 1L)
  expect_identical(rows$only_r, "PTSWAP001")
})

test_that("a comparison build is compared against the declared dataset and says it is a comparison build", {
  dt_skip()
  m <- bd_master()
  root <- bd_study()
  # The study's dataset, registered as legacy; then a rebuild beside it under another DATASET_ID.
  bd_run(root, utils::modifyList(dt_bd_choices(m, TRUE), list(DATASET_ID = "legacy")))
  rebuild <- dt_bd_choices(m, FALSE)
  rebuild$DATASET_ID <- "study_rebuild"
  # Assigned, not merged with modifyList(), which would merge the two lists of rules.
  rebuild$EXCLUDE <- list(age < 50 ~ "Under 50")
  bd_run(root, rebuild)
  expect_identical(hvtiRutilities::study_config(root)$built, "legacy.rds")
  env <- dt_run(root, dt_choices(DATASET_ID = "study_rebuild"))
  expect_match(env$.rebuild_state, "^A comparison build: study_rebuild.rds is not the study dataset\\.")
  expect_match(env$.rebuild_state, "dataset legacy.rds, registered as legacy_[0-9]{8}[.]parquet")
  # Every section checks the new file, and the comparison is the new file against the declared one.
  rebuilt <- readRDS(dt_working(root, "study_rebuild"))
  expect_identical(nrow(env$d), nrow(rebuilt))
  rows <- attr(env$.comparison, "rows")
  expect_identical(rows$n_r, nrow(rebuilt))
  expect_identical(rows$n_oracle, nrow(readRDS(dt_working(root, "legacy"))))
  expect_identical(length(rows$only_oracle), sum(m$data$age >= 40 & m$data$age < 50, na.rm = TRUE))
  expect_length(rows$only_r, 0L)
})

test_that("with nothing registered there is no comparison, and the report says so", {
  dt_skip()
  # bd without REGISTER declares the working file: read_built() would serve that very file.
  s <- dt_study(register = FALSE)
  expect_identical(hvtiRutilities::study_config(s$root, require_data = FALSE)$built, "study_cohort.rds")
  env <- dt_run(s$root)
  expect_null(env$.comparison)
  expect_identical(env$.rebuild_state,
                   "Nothing is registered for this study yet, so there is no version to compare this build against.")
})

test_that("the cross-tab, follow-up and named-check sections report counts", {
  dt_skip()
  s <- dt_study()
  dt_rebuild(s$root, function(d) {
    d$iv_dead[1:3] <- c(0, -1, NA)
    d
  })
  env <- dt_run(s$root, labels = c("setup", "edit-study-choices", "check-choices", "read-working", "crosstabs",
                                   "followup", "tbl-checks"))
  out <- paste(env$.stdout, collapse = "\n")
  expect_match(out, "### dead by sex", fixed = TRUE)
  expect_match(out, "row(s) look suspicious, listed in the console", fixed = TRUE)
  expect_identical(env$.checked$label, "Follow-up of zero or less")
  expect_identical(env$.checked$n, 2L)
  expect_identical(env$.checked$n_missing, 1L)
  # A missing value is a level of its own in a cross-tab.
  expect_true(all(c("dead", "sex", "Frequency", "Small") %in% names(env$.tab)))
})
