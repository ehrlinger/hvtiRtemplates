# The vp templates, run chunk by chunk from the installed files (helper-rf.R,
# helper-vp.R). Only tests that fit varPro skip on CRAN.

vp_data_labels <- c("setup", "edit-study-choices", "tbl-data", "tbl-missing")

test_that("vp-fit draws half its noise from each kind of candidate", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- rf_env(vp_data())
  rf_run("vp", "fit", c(vp_data_labels, "noise"), env, vp_choices)
  noise <- grep("^noise", names(env$d_noise), value = TRUE)
  src <- sub("^noise[0-9]+_", "", noise)
  expect_length(noise, 20L)
  expect_identical(sum(src %in% c("fs", "g1")), 10L)
  # A permuted copy keeps its source's values and loses their order.
  for (i in seq_along(noise)) {
    expect_identical(sort(as.character(env$d_noise[[noise[i]]])), sort(as.character(env$d[[src[i]]])))
    # A continuous column of 200 draws keeps its order after a permutation
    # only if sample() was skipped.
    if (src[i] %in% c("xs", "x1", "x2")) expect_false(identical(env$d_noise[[noise[i]]], env$d[[src[i]]]))
  }
})

test_that("vp-fit refuses an outcome named both ways, or neither", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  both <- vp_outcome(vp_choices, TIME = "time", EVENT = "event", RESPONSE = "event")
  neither <- vp_outcome(vp_choices, TIME = NULL, EVENT = NULL, RESPONSE = NULL)
  for (choices in list(both, neither)) {
    env <- rf_env(vp_data())
    expect_error(rf_run("vp", "fit", vp_data_labels, env, choices), "either TIME and EVENT")
  }
})

test_that("vp-fit screens a 0/1 RESPONSE as classification", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  choices <- vp_outcome(vp_choices, TIME = NULL, EVENT = NULL, RESPONSE = "event")
  env <- rf_env(vp_data())
  rf_run("vp", "fit", vp_data_labels, env, choices)
  expect_identical(env$.family, "classification")
  expect_true(is.factor(env$d$event))
  expect_identical(env$.analysis$outcome$kind, "classification")
})

test_that("vp-fit drops incomplete patients before the fit, and counts them", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  data <- vp_data()
  data$x1[1:7] <- NA
  env <- rf_env(data)
  rf_run("vp", "fit", vp_data_labels, env, vp_choices)
  expect_identical(nrow(env$d), 193L)
  expect_identical(env$.cohort$n, 193L)
  expect_match(utils::tail(env$.missing_values$Missing, 1L), "7 dropped")
})

test_that("vp-fit refuses a candidate whose name could be taken for noise", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  data <- vp_data()
  data$noise_x <- data$x1
  choices <- utils::modifyList(vp_choices, list(PREDICTORS = c("xs", "noise_x")))
  env <- rf_env(data)
  expect_error(rf_run("vp", "fit", c(vp_data_labels, "noise"), env, choices), "start with \"noise\"")
})

# vp_judge() on hand-built tables: no fit, so these run on CRAN too.
vp_judge_fn <- function() {
  env <- new.env(parent = globalenv())
  src <- readLines(template_path("vp", "fit"), warn = FALSE)
  eval(parse(text = rf_chunk(src, "judge")), envir = env)  # nolint: object_usage_linter.
  env$vp_judge
}
vp_cov <- function(variable, kind, noise, tested, z) {
  data.frame(variable = variable, kind = kind, noise = noise, tested = tested, z = z)
}

test_that("vp_judge falls back to the continuous bar when tested categorical noise all scores zero", {
  cov <- vp_cov(
    variable = c("x_real", "f_null", "noise1_x", "noise2_f", "noise3_f"),
    kind = c("continuous", "categorical", "continuous", "categorical", "categorical"),
    noise = c(FALSE, FALSE, TRUE, TRUE, TRUE),
    tested = c(TRUE, TRUE, TRUE, TRUE, FALSE),
    z = c(0.9, 0.2, 0.3, 0, NA)
  )
  out <- vp_judge_fn()(cov)
  expect_identical(out$selected, c(TRUE, FALSE, FALSE, FALSE, FALSE))
  expect_identical(out$bar[out$variable == "f_null"], 0.3)
  expect_identical(out$bar_from[out$variable == "f_null"], "continuous (fallback)")
})

test_that("vp_judge keeps a categorical bar that tested noise set above zero", {
  cov <- vp_cov(
    variable = c("f_real", "f_null", "noise1_x", "noise2_f"),
    kind = c("categorical", "categorical", "continuous", "categorical"),
    noise = c(FALSE, FALSE, TRUE, TRUE),
    tested = c(TRUE, TRUE, TRUE, TRUE),
    z = c(0.5, 0.2, 0.9, 0.25)
  )
  out <- vp_judge_fn()(cov)
  expect_identical(out$selected, c(TRUE, FALSE, FALSE, FALSE))
  expect_identical(unique(out$bar[out$kind == "categorical"]), 0.25)
  expect_identical(unique(out$bar_from[out$kind == "categorical"]), "categorical")
})

test_that("vp_judge selects nothing when no noise was tested, and says so", {
  cov <- vp_cov(
    variable = c("x_real", "noise1_x"), kind = c("continuous", "continuous"),
    noise = c(FALSE, TRUE), tested = c(TRUE, FALSE), z = c(2, NA)
  )
  out <- vp_judge_fn()(cov)
  expect_identical(out$selected, c(FALSE, FALSE))
  expect_identical(out$bar_from, c("no usable noise bar", "no usable noise bar"))
})

test_that("vp_judge borrows no bar from noise that scored zero", {
  # Only categorical noise was tested, and it scored 0: neither kind has a
  # usable bar, so a categorical z of 0.05 is not selected through a
  # "fallback" that is 0 again.
  cov <- vp_cov(
    variable = c("x_real", "f_null", "noise1_x", "noise2_f"),
    kind = c("continuous", "categorical", "continuous", "categorical"),
    noise = c(FALSE, FALSE, TRUE, TRUE),
    tested = c(TRUE, TRUE, FALSE, TRUE),
    z = c(2, 0.05, NA, 0)
  )
  out <- vp_judge_fn()(cov)
  expect_identical(out$selected, c(FALSE, FALSE, FALSE, FALSE))
  expect_identical(out$bar_from[1:2], c("no usable noise bar", "no usable noise bar"))
})

test_that("every varpro() call in vp-fit runs on one core", {
  # options(rf.cores) limits randomForestSRC's threads, not varPro's own
  # workers, which read `cores =` or mc.cores.
  lines <- readLines(template_path("vp", "fit"), warn = FALSE)
  # Comments mention varpro() in prose; only code lines are calls.
  src <- paste(lines[!grepl("^\\s*#", lines)], collapse = "\n")
  calls <- regmatches(src, gregexpr("(?<![_[:alnum:]])varpro\\([^\n]*", src, perl = TRUE))[[1L]]
  # The full fit and the stability refit.
  expect_length(calls, 2L)
  expect_true(all(grepl("cores = 1L", calls, fixed = TRUE)))
  expect_match(src, "options(rf.cores = 1L, mc.cores = 1L)", fixed = TRUE)
})

test_that("vp-fit selects a planted signal", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- vp_fit_first()
  real <- env$.real[env$.real$tested, ]
  expect_true(all(c("xs", "fs") %in% env$.real$variable[env$.real$selected]))
  expect_setequal(utils::head(real$variable[order(-real$z)], 2L), c("xs", "fs"))
  # Every noise column reached the coverage table, so the bars rest on all of them.
  expect_identical(sum(env$cov$noise), 20L)
})

test_that("vp-fit saves one handoff: the fit, its judged coverage, the selection and the family", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- vp_fit_first()
  h <- readRDS(env$set_path("estimates", "vp.rds"))
  expect_named(h, c("fit", "coverage", "selected", "family"))
  expect_identical(h$selected, env$.real$variable[env$.real$selected])
  expect_identical(h$family, "survival")
  expect_s3_class(h$fit, "varpro")
  expect_false(is.null(attr(h, "hvti_provenance")))
  expect_setequal(unique(env$.stab$r), 1:2)
})

test_that("raising REPEATS computes only the new repeat", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- vp_fit_first()
  first <- file.path(env$CACHE_DIR, "vp-repeat-01.rds")
  stamp <- file.mtime(first)
  expect_false(file.exists(file.path(env$CACHE_DIR, "vp-repeat-03.rds")))
  Sys.sleep(1.1)  # so a rewrite would show in the modification time
  again <- new.env(parent = globalenv())
  again$.root <- env$.root
  again$.provenance_data <- list()
  rf_run("vp", "fit", vp_fit_labels, again, utils::modifyList(vp_choices, list(REPEATS = 3)))
  expect_identical(file.mtime(first), stamp)
  expect_true(file.exists(file.path(env$CACHE_DIR, "vp-repeat-03.rds")))
  expect_setequal(unique(again$.stab$r), 1:3)
})

test_that("REPEATS = 0 skips the stability check", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- vp_fit_first(choices = utils::modifyList(vp_choices, list(REPEATS = 0)))
  expect_identical(nrow(env$.stab), 0L)
  expect_false(any(grepl("^vp-repeat-", list.files(env$CACHE_DIR))))
})
