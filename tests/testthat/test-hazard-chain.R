# The hazard chain reads its data through read_job_data(). hz and ac choose the
# rows; hm, hp and hs rebuild hz's rows from the selection its hand-off records
# and stop when their own settings differ. dev/specs/2026-09-29-template-data-contract-design.md.

# What each downstream job reads, and where its data chunk takes the selection from.
downstream_reads <- list(hm = "hz.rds", hp = c("ac.rds", "hz.rds"), `hs-setup` = "hm.rds")

test_that("the hazard test data is fixed and leaves the session's random numbers alone", {
  withr::local_seed(1)
  before <- .Random.seed
  expect_identical(hazard_data(), hazard_data())
  expect_identical(.Random.seed, before)
})

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

# ---- #177: the counts are typed once, in hz, and checked downstream ----------

test_that("hm, hp and hs take their counts from upstream and declare none of their own", {
  for (prefix in names(hazard_cohort_gates)) {
    src <- readLines(hazard_template(prefix), warn = FALSE)
    expect_false(any(grepl("^EXPECTED\\s*<-", src)), info = prefix)
    expect_false(any(grepl("assert_cohort(", src, fixed = TRUE)), info = prefix)
    expect_true(any(grepl("hvtiRtemplates:::.check_upstream_cohort(d, ", src, fixed = TRUE)), info = prefix)
  }
})

test_that("a downstream job passes on the upstream counts and stops on others, naming both", {
  data <- hazard_data()
  root <- hazard_study(data)
  lineage <- hazard_lineage(root, where = quote(age >= 18))
  cc <- hvtiRutilities::cohort_counts(data[data$age >= 18, ], event = "dead", time = "iv_dead")
  expect_identical(lineage$cohort, cc)
  hazard_upstream(root, lineage)
  for (prefix in names(hazard_cohort_gates)) {
    env <- expect_no_error(hazard_cohort_gate(prefix, root))
    if (prefix != "hp") expect_identical(env$cc, cc, info = prefix)
  }
  # Same rows, but upstream counted one more event: the data changed under it.
  lineage$cohort$n_events <- cc$n_events + 1L
  lineage$cohort$n_censored <- cc$n_censored - 1L
  hazard_upstream(root, lineage)
  for (prefix in names(hazard_cohort_gates)) {
    err <- expect_error(hazard_cohort_gate(prefix, root), info = prefix)
    msg <- conditionMessage(err)
    expect_match(msg, paste0("The upstream job \\(", if (prefix == "hs-setup") "hm" else "hz", "\\.rds\\)"), info = prefix)
    expect_match(msg, sprintf("counted N=%d / events=%d / censored=%d", cc$n, cc$n_events + 1L, cc$n_censored - 1L),
                 fixed = TRUE, info = prefix)
    expect_match(msg, sprintf("this job counts N=%d / events=%d / censored=%d", cc$n, cc$n_events, cc$n_censored),
                 fixed = TRUE, info = prefix)
  }
})

test_that("a downstream job stops on an upstream fit that records no counts", {
  root <- hazard_study()
  lineage <- hazard_lineage(root)
  lineage$cohort <- list(n = lineage$cohort$n)
  hazard_upstream(root, lineage)
  for (prefix in names(hazard_cohort_gates)) {
    expect_error(hazard_cohort_gate(prefix, root), "records no cohort counts", info = prefix)
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

test_that("hp names an ac.rds saved before the data contract, rather than calling the rows different", {
  root <- hazard_study()
  lineage <- hazard_lineage(root)
  hazard_upstream(root, lineage)
  ac <- lineage
  ac$selection <- NULL
  hazard_save(list(overall = data.frame(time = 1)), ac, hazard_set_path(root, "ac.rds"))
  err <- expect_error(hazard_downstream("hp", root), "ac\\.rds.*predates the data contract")
  expect_match(conditionMessage(err), "Rerun the ac job with the current template")
  expect_no_match(conditionMessage(err), "read different data")
})

# ---- #203: no saved hazard object carries a patient identifier --------------

test_that("ac, hz, hm and hs keyed on MRN save no MRN anywhere in their files", {
  skip_if_not_installed("TemporalHazard", minimum_version = "1.2.8")
  skip_if_not_installed("hvtiRlifetables", minimum_version = "0.1.2")
  skip_if_not_installed("numDeriv")
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  withr::local_package("hvtiRlifetables")
  data <- hazard_data(id = "MRN")
  root <- hazard_study(data)
  env <- hazard_chain_run(root, data)
  # The ID fell back to MRN, which the data read names in lower case, and the jobs read it.
  expect_identical(attr(env$job_data$record, "selection")$id, "mrn")
  expect_true("mrn" %in% names(env$d))
  for (file in c("ac.rds", "hz.rds", "hm.rds", "hs.rds")) {
    expect_false(hazard_file_holds_any(root, file, data$MRN), info = file)
  }
  # The search finds what is there: every MRN in the data as the jobs read it.
  expect_true(all(vapply(data$MRN, function(v) hazard_bytes_hold(serialize(env$d, NULL), v), logical(1L))))
  # hm's model still carries what hs predicts from.
  expect_true(all(c("iv_dead", "dead", "x1", "age") %in% names(readRDS(hazard_set_path(root, "hm.rds"))$reported$data$frame)))
})

test_that("hm saves no MRN when its chunks run outside the global environment", {
  skip_if_not_installed("TemporalHazard", minimum_version = "1.2.8")
  skip_if_not_installed("hvtiRlifetables", minimum_version = "0.1.2")
  skip_if_not_installed("numDeriv")
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  withr::local_package("hvtiRlifetables")
  data <- hazard_data(id = "MRN")
  root <- hazard_study(data)
  # A chunk environment that is not the global one is serialized in full, with
  # every object in it, `d` and its MRN column included, unless hm's fit does
  # not refer to it.
  env <- hazard_chain_run(root, data, hm_env = new.env(parent = globalenv()))
  expect_true("mrn" %in% names(env$d))
  expect_false(hazard_file_holds_any(root, "hm.rds", data$MRN))
})

test_that("hz's convergence table keeps its rows when a fit leaves a field out", {
  # A multiphase fit carries no iteration count (#168); a missing field must
  # show as "not reported", not change the row count and stop the render.
  src <- readLines(template_path("hz"), warn = FALSE)
  at <- which(trimws(src) == "#| label: tbl-convergence")
  chunk <- parse(text = src[(at + 1L):(at + which(src[(at + 1L):length(src)] == "```")[1L] - 1L)])
  env <- new.env(parent = globalenv())
  env$fit_det <- list(fit = list(objective = -10, converged = TRUE, rcond = 0.1, pd = TRUE))
  out <- as.character(eval(chunk, env))
  expect_identical(sum(grepl("not reported", out, fixed = TRUE)), 2L)
  expect_identical(sum(grepl("evaluations", out, fixed = TRUE)), 2L)
  env$fit_det$fit$counts <- c("function" = 6L, gradient = 1L)
  out <- as.character(eval(chunk, env))
  expect_false(any(grepl("not reported", out, fixed = TRUE)))
})
