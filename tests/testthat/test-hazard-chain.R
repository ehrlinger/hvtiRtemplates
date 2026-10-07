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

test_that("a downstream job stops on saved counts that are not whole and non-negative", {
  # as.integer() truncates, so a saved n of 3.7 used to pass against a count of 3.
  root <- hazard_study()
  lineage <- hazard_lineage(root)
  bad <- list(fraction = lineage$cohort$n + 0.7, infinite = Inf, negative = -1)
  for (kind in names(bad)) {
    broken <- lineage
    broken$cohort$n <- bad[[kind]]
    hazard_upstream(root, broken)
    for (prefix in names(hazard_cohort_gates)) {
      expect_error(hazard_cohort_gate(prefix, root), "not whole, non-negative numbers \\(n\\)",
                   info = paste(prefix, kind))
    }
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
  skip_on_cran()
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
  skip_on_cran()
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

# ---- hz's fits, run as a render runs them --------------------------------------

test_that("hz passes hazard() no control element it ignores (#172)", {
  skip_if_not_installed("TemporalHazard", minimum_version = "1.2.8")
  skip_if_not_installed("numDeriv")
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  env <- hz_fit_run()
  expect_true(all(c("fit_det", "probe_ll", "fit_nc") %in% ls(env)))
  expect_false(any(grepl("with no effect", env$.warnings, fixed = TRUE)))
})

test_that("hz's start probes move only the free parameters (#169)", {
  skip_if_not_installed("TemporalHazard", minimum_version = "1.2.8")
  withr::local_package("TemporalHazard")
  env <- hz_probe_env()
  held <- c("late.log_tau", "late.gamma", "late.alpha")
  expect_identical(env$theta_names[!env$free], held)
  at <- match(held, env$theta_names)
  expect_identical(unname(env$probes[, at]), matrix(env$theta0[at], 3L, length(at), byrow = TRUE))
  # Every free position does move, so the probes still test the starting point.
  free_cols <- env$probes[, env$free, drop = FALSE]
  expect_true(all(apply(free_cols, 2L, function(x) length(unique(x)) == 3L)))
})

test_that("hz's start probes hold every shape a fixed = \"shapes\" phase fixes (#169)", {
  # hzr_phase() expands the "shapes" shorthand into the phase's shape names when
  # the phase is built (since at least TemporalHazard 1.2.8, the floor hz checks),
  # so `held` sees names, never the literal. Raised by Codex on #256; this holds
  # that expansion to account should it ever stop.
  skip_if_not_installed("TemporalHazard", minimum_version = "1.2.8")
  withr::local_package("TemporalHazard")
  env <- hz_probe_env()
  env$phases <- list(
    early = hzr_phase("cdf", t_half = 1, nu = 1, m = 1, fixed = "shapes"),
    late  = hzr_phase("g3", tau = 1, gamma = 1, alpha = 1, eta = 1, fixed = "shapes")
  )
  env$theta_names <- hzr_theta_names(env$phases)
  utils::capture.output(hazard_run("hz", "edit-multistart", env))
  expect_identical(env$theta_names[env$free], c("early.log_mu", "late.log_mu"))
  held <- env$theta_names[!env$free]
  at <- match(held, env$theta_names)
  expect_identical(unname(env$probes[, at]), matrix(env$theta0[at], 3L, length(at), byrow = TRUE))
})

test_that("hz stops on a start probe that moves a fixed parameter (#169)", {
  skip_if_not_installed("TemporalHazard", minimum_version = "1.2.8")
  withr::local_package("TemporalHazard")
  env <- hz_probe_env()
  # The probes as they stood before #169, moving every position.
  src <- readLines(hazard_template("hz"), warn = FALSE)
  at <- which(trimws(src) == "#| label: edit-multistart")
  chunk <- src[(at + 1L):(at + which(src[(at + 1L):length(src)] == "```")[1L] - 1L)]
  edited <- sub("^probes <- .*$", "probes <- rbind(theta0, theta0 + 0.5, theta0 - 0.5)", chunk)
  expect_false(identical(edited, chunk))
  expect_error(eval(parse(text = edited), env),
               "A probe moves a fixed parameter \\(late\\.log_tau, late\\.gamma, late\\.alpha\\)")
})

# ---- #175: a time of zero or below stops ac and hz at the cohort ---------------

test_that("ac stops on times of zero or below, counting each and naming the fix (#175)", {
  withr::local_package("hvtiRutilities")
  expect_time_guard("ac")
})

test_that("hz stops on times of zero or below, counting each and naming the fix (#175)", {
  skip_if_not_installed("TemporalHazard", minimum_version = "1.2.8")
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  expect_time_guard("hz")
})

test_that("hm's stage 1 holds every shape of each phase (rollup review, 1.2.6)", {
  # make_phases(TRUE) read names(ph$par), a field an hzr_phase does not have,
  # so stage 1 held nothing beyond hz's own fixed set and fitted stage 2's model.
  skip_if_not_installed("TemporalHazard", minimum_version = "1.2.8")
  withr::local_package("TemporalHazard")
  src <- readLines(hazard_template("hm"), warn = FALSE)
  at <- grep("^make_phases <- function", src)
  end <- at + match("}", src[-seq_len(at)])
  env <- new.env()
  env$hz_art <- list(phases = list(
    early = hzr_phase("cdf", t_half = 1, nu = 1, m = 1),
    late  = hzr_phase("g3", tau = 1, gamma = 1, alpha = 1, eta = 1, fixed = c("tau", "gamma", "alpha")),
    derived = hzr_phase("g3", tau = 1, gamma = 1, eta = 1, constraint = "alpha_gamma_eta"),
    flat = hzr_phase("constant")
  ))
  eval(parse(text = src[at:end]), env)
  held <- env$make_phases(TRUE)
  expect_setequal(held$early$fixed, c("t_half", "nu", "m"))
  expect_setequal(held$late$fixed, c("tau", "gamma", "alpha", "eta"))
  # A shape a constraint derives is computed, and may not be named in `fixed`.
  expect_setequal(held$derived$fixed, c("tau", "gamma", "eta"))
  expect_length(held$flat$fixed, 0L)
  # Stage 2 is hz's phases as they are.
  expect_identical(env$make_phases(FALSE), env$hz_art$phases)
})
