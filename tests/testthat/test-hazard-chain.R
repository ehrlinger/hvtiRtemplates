# The hazard chain reads its data through read_job_data(). hz and ac choose the
# rows; hm, hp and hs rebuild hz's rows from the selection its hand-off records
# and stop when their own settings differ. dev/specs/2026-09-29-template-data-contract-design.md.

# What each downstream job reads, and where its data chunk takes the selection from.
downstream_reads <- list(hm = "hz.rds", hp = c("ac.rds", "hz.rds"), hs = "hm.rds")

test_that("hm, hp and hs rebuild hz's rows and take its TIME and EVENT", {
  data <- hazard_data()
  root <- hazard_study(data)
  hazard_upstream(root, hazard_lineage(root, where = quote(age >= 18), time = "iv_dead", event = "dead"))
  for (prefix in names(downstream_reads)) {
    env <- hazard_downstream(prefix, root)
    expect_identical(env$d$ccfid, data$ccfid[data$age >= 18], info = prefix)
    expect_identical(env$TIME, "iv_dead", info = prefix)
    expect_identical(env$EVENT, "dead", info = prefix)
    expect_identical(attr(env$job_data$record, "selection")$where, "age >= 18", info = prefix)
  }
})

test_that("a downstream WHERE, TIME or EVENT that differs from hz's stops the job, naming both", {
  root <- hazard_study()
  hazard_upstream(root, hazard_lineage(root, where = quote(age >= 18)))
  for (prefix in names(downstream_reads)) {
    expect_error(hazard_downstream(prefix, root, list(WHERE = quote(age >= 65))),
                 "WHERE here \\(age >= 65\\) differs from the upstream job's \\(age >= 18\\)", info = prefix)
    expect_error(hazard_downstream(prefix, root, list(TIME = "iv_other")),
                 "TIME here \\(iv_other\\) differs from the upstream job's \\(iv_dead\\)", info = prefix)
    expect_error(hazard_downstream(prefix, root, list(EVENT = "other")),
                 "EVENT here \\(other\\) differs from the upstream job's \\(dead\\)", info = prefix)
    # Set to the upstream value, a setting only confirms it.
    expect_silent(hazard_downstream(prefix, root, list(WHERE = quote(age >= 18), TIME = "iv_dead")))
  }
})

test_that("a downstream job stops on an upstream fit saved before the data contract", {
  root <- hazard_study()
  lineage <- hazard_lineage(root)
  lineage$selection <- NULL
  hazard_upstream(root, lineage)
  for (prefix in names(downstream_reads)) {
    expect_error(hazard_downstream(prefix, root), "predates the data contract", info = prefix)
  }
})

test_that("hp stops when ac and hz chose different rows", {
  root <- hazard_study()
  lineage <- hazard_lineage(root)
  hazard_upstream(root, lineage)
  # Only the rows differ: the cohort counts alone are stopped by an earlier check.
  ac <- hazard_lineage(root, where = quote(age >= 18))
  ac$cohort <- lineage$cohort
  hazard_save(list(overall = data.frame(time = 1)), ac, hazard_set_path(root, "ac.rds"))
  expect_error(hazard_downstream("hp", root), "ac and hz handoffs read different data")
})

# ---- #203: no saved hazard object carries a patient identifier --------------

# TRUE when `bytes` hold `value` as text or as R's big-endian integer or double encoding.
hazard_bytes_hold <- function(bytes, value) {
  patterns <- list(charToRaw(as.character(value)), writeBin(as.double(value), raw(), endian = "big"),
                   writeBin(as.integer(value), raw(), endian = "big"))
  any(vapply(patterns, function(p) length(grepRaw(p, bytes, fixed = TRUE)) > 0L, logical(1L)))
}

hazard_rds_bytes <- function(path) {
  con <- gzfile(path, "rb")
  on.exit(close(con))
  readBin(con, "raw", n = 1e8)
}

test_that("hz, hm and hs keyed on MRN save no MRN anywhere in their files", {
  skip_if_not_installed("TemporalHazard", minimum_version = "1.2.8")
  skip_if_not_installed("hvtiRlifetables", minimum_version = "0.1.2")
  skip_if_not_installed("numDeriv")
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  withr::local_package("hvtiRlifetables")
  data <- hazard_data(id = "MRN")
  root <- hazard_study(data)
  cc <- hvtiRutilities::cohort_counts(data, event = "dead", time = "iv_dead")
  expected <- list(n = cc$n, n_events = cc$n_events, n_censored = cc$n_censored)
  # A render evaluates every chunk in the global environment, which a saved fit
  # refers to by reference only. So these run there too, and are removed after.
  env <- globalenv()
  before <- ls(env, all.names = TRUE)
  withr::defer(rm(list = setdiff(ls(env, all.names = TRUE), before), envir = env))
  list2env(as.list(hazard_env(root), all.names = TRUE), envir = env)
  # TemporalHazard's own notes on a synthetic fit (an ignored control, a
  # Hessian that is not positive-definite) are about the fit, not the file.
  suppressWarnings(utils::capture.output({
    hazard_run("hz", c("set", "edit-study-choices"), env, list(EXPECTED = expected))
    hazard_run("hz", c("data", "cohort", "phases", "edit-start", "edit-response", "response-check", "guard",
                       "fit-deterministic", "noconserve", "save"), env)
    hazard_run("hm", c("set", "edit-study-choices"), env, list(EXPECTED = expected, DECILE_TIME = 3))
    env$COVARIATES <- list(early = "x1", late = c("x1", "age"))
    hazard_run("hm", c("read-upstream", "data", "cohort", "audit", "phases", "edit-fit", "edit-reported",
                       "calibration", "save"), env)
    hazard_run("hs", c("set", "edit-study-choices"), env,
               list(EXPECTED = expected, HORIZONS = c(1, 2), VINTAGE = "table2023"))
    hazard_run("hs", c("read-upstream", "data", "cohort", "model", "horizons", "predict", "expected",
                       "edit-obs-vs-exp", "save"), env)
  }))
  # The ID fell back to MRN, which the data read names in lower case, and the jobs read it.
  expect_identical(attr(env$job_data$record, "selection")$id, "mrn")
  expect_true("mrn" %in% names(env$d))
  for (file in c("hz.rds", "hm.rds", "hs.rds")) {
    bytes <- hazard_rds_bytes(hazard_set_path(root, file))
    expect_false(any(vapply(data$MRN, function(v) hazard_bytes_hold(bytes, v), logical(1L))), info = file)
  }
  # The search finds what is there: every MRN in the data as the jobs read it.
  expect_true(all(vapply(data$MRN, function(v) hazard_bytes_hold(serialize(env$d, NULL), v), logical(1L))))
  # hm's model still carries what hs predicts from.
  expect_true(all(c("iv_dead", "dead", "x1", "age") %in% names(readRDS(hazard_set_path(root, "hm.rds"))$reported$data$frame)))
})
