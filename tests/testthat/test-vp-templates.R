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

test_that("vp-fit imputes a missing predictor by default and keeps the patient", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  data <- vp_data()
  data$x1[1:7] <- NA
  env <- rf_env(data)
  rf_run("vp", "fit", vp_data_labels, env, vp_choices)
  expect_identical(nrow(env$d), 200L)
  expect_false(anyNA(env$d[vp_choices$PREDICTORS]))
  expect_identical(env$.cohort$n, 200L)
  expect_identical(env$.cohort$n_imputed[["x1"]], 7L)
  expect_identical(env$.cohort$na_action, "na.impute")
})

test_that("vp-fit with NA_ACTION = na.omit drops incomplete patients as before, and counts them", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  data <- vp_data()
  data$x1[1:7] <- NA
  env <- rf_env(data)
  rf_run("vp", "fit", vp_data_labels, env, utils::modifyList(vp_choices, list(NA_ACTION = "na.omit")))
  expect_identical(nrow(env$d), 193L)
  expect_identical(env$.cohort$n, 193L)
  expect_identical(env$.cohort$n_dropped, 7L)
})

test_that("vp-fit drops a patient missing the outcome, and imputes without it", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  data <- vp_data()
  data$time[1:3] <- NA
  data$x1[4:9] <- NA
  env <- rf_env(data)
  rec <- new.env()
  testthat::local_mocked_bindings(impute = vp_mock_impute(rec), .package = "randomForestSRC")
  rf_run("vp", "fit", vp_data_labels, env, vp_choices)
  expect_identical(env$.cohort$n_outcome_missing, 3L)
  expect_identical(nrow(env$d), 197L)
  # The imputation was handed the predictors and nothing else: no outcome column.
  expect_identical(rec$seen, vp_choices$PREDICTORS)
  expect_false(any(c("time", "event") %in% rec$seen))
})

test_that("vp-fit stops on a patient with no observed predictor", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  data <- vp_data()
  data[5, vp_choices$PREDICTORS] <- NA
  data$x1[10:12] <- NA  # something to impute, so the imputation runs
  expect_error(rf_run("vp", "fit", vp_data_labels, rf_env(data), vp_choices), "cannot be imputed")
})

test_that("vp-fit refuses to impute a predictor missing in most patients", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  data <- vp_data()
  data$x2[1:150] <- NA
  expect_error(rf_run("vp", "fit", vp_data_labels, rf_env(data), vp_choices), "x2 \\(75%\\)")
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
  env
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
  out <- vp_judge_fn()$vp_judge(cov)
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
  out <- vp_judge_fn()$vp_judge(cov)
  expect_identical(out$selected, c(TRUE, FALSE, FALSE, FALSE))
  expect_identical(unique(out$bar[out$kind == "categorical"]), 0.25)
  expect_identical(unique(out$bar_from[out$kind == "categorical"]), "categorical")
})

test_that("vp_judge selects nothing when no noise was tested, and says so", {
  cov <- vp_cov(
    variable = c("x_real", "noise1_x"), kind = c("continuous", "continuous"),
    noise = c(FALSE, TRUE), tested = c(TRUE, FALSE), z = c(2, NA)
  )
  out <- vp_judge_fn()$vp_judge(cov)
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
  out <- vp_judge_fn()$vp_judge(cov)
  expect_identical(out$selected, c(FALSE, FALSE, FALSE, FALSE))
  expect_identical(out$bar_from[1:2], c("no usable noise bar", "no usable noise bar"))
})

test_that("vp_judge drops varpro_coverage()'s own bar, so one bar remains", {
  cov <- vp_cov(
    variable = c("x_real", "noise1_x"), kind = c("continuous", "continuous"),
    noise = c(FALSE, TRUE), tested = c(TRUE, TRUE), z = c(2, 0.3)
  )
  cov$noise_cut <- 0
  cov$selected <- TRUE
  out <- vp_judge_fn()$vp_judge(cov)
  expect_false("noise_cut" %in% names(out))
  expect_identical(out$selected, c(TRUE, FALSE))
})

test_that("vp_judge ignores a tested noise row whose z is NA", {
  cov <- vp_cov(
    variable = c("x_real", "noise1_x", "noise2_x"), kind = rep("continuous", 3),
    noise = c(FALSE, TRUE, TRUE), tested = c(TRUE, TRUE, TRUE), z = c(2, NA, 0.4)
  )
  out <- vp_judge_fn()$vp_judge(cov)
  expect_identical(unique(out$bar), 0.4)
})

test_that("vp-fit's coverage call muffles the empty-noise warning, and both fits go through it", {
  lines <- readLines(template_path("vp", "fit"), warn = FALSE)
  at <- grep("varpro_coverage\\(f, by = \"variable\"", lines)
  expect_length(at, 1L)
  expect_match(paste(lines[max(1L, at - 3L):at], collapse = "\n"), "withCallingHandlers", fixed = TRUE)
  expect_match(paste(lines[at:min(length(lines), at + 4L)], collapse = "\n"), "no noise variable was tested", fixed = TRUE)
  expect_length(grep("varpro_coverage\\((fit|fr),", lines), 0L)
  expect_length(grep("vp_judge\\(vp_coverage\\((fit|fr),", lines), 2L)
})

test_that("vp_vote counts a selection over the refits that tested the variable, not over REPEATS", {
  vote <- vp_judge_fn()$vp_vote
  stab <- rbind(
    data.frame(r = 1:20, variable = "a", tested = 1:20 <= 3, selected = 1:20 <= 3),
    data.frame(r = 1:20, variable = "b", tested = TRUE, selected = 1:20 <= 3)
  )
  v <- vote(stab, repeats = 20, min_tested_share = 0.5)
  a <- v[v$variable == "a", ]
  b <- v[v$variable == "b", ]
  expect_equal(a$share_selected, 1)
  expect_false(a$examined)
  expect_equal(b$share_selected, 0.15)
  expect_true(b$examined)
})

test_that("vp_vote gives NA, not 0, to a variable no refit tested", {
  vote <- vp_judge_fn()$vp_vote
  stab <- data.frame(r = 1:4, variable = "z", tested = FALSE, selected = FALSE)
  expect_true(is.na(vote(stab, repeats = 4, min_tested_share = 0.5)$share_selected))
})

test_that("vp-fit hands on only variables the refits examined, and names the rest", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- vp_fit_first()
  h <- readRDS(env$set_path("estimates", "vp.rds"))
  expect_identical(h$selected, env$.freq$variable[env$.freq$examined & (env$.freq$share_selected >= 0.5) %in% TRUE])
})

test_that("vp-fit holds the full fit to MAX_UNTESTED and leaves the refits to the stability table", {
  lines <- readLines(template_path("vp", "fit"), warn = FALSE)
  calls <- grep("vp_judge\\(vp_coverage\\((fit|fr),", lines, value = TRUE)
  expect_match(calls[1], "max_untested = MAX_UNTESTED", fixed = TRUE)
  expect_no_match(calls[2], "max_untested", fixed = TRUE)
  expect_true("MAX_UNTESTED <- 0.1" %in% rf_chunk(lines, "edit-study-choices"))
})

test_that("vp-fit's figure takes its bar and selection from the table", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- rf_env(vp_data())
  rf_run("vp", "fit", c(vp_data_labels, "noise", "judge", "fit", "tbl-coverage", "fig-varpro"), env, vp_choices)
  imp <- env$.gv$imp
  at <- match(imp$kind, env$cov$kind)
  expect_false(anyNA(at))
  bar <- env$cov$bar[at]
  expect_identical(imp$noise_cut, ifelse(is.na(bar), 0, bar))
  expect_identical(imp$selected, !imp$noise & imp$tested & (imp$z > bar) %in% TRUE)
  expect_s3_class(ggplot2::ggplot_build(env$.fig), "ggplot_built")
})

test_that("vp-fit's screened figure drops the noise and the untested, and keeps each row's bar and selection", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- rf_env(vp_data())
  rf_run("vp", "fit", c(vp_data_labels, "noise", "judge", "fit", "tbl-coverage", "fig-varpro", "fig-varpro-screened"),
         env, vp_choices)
  full <- env$.gv$imp
  keep <- full[!full$noise & full$tested, ]
  imp <- env$.gvs$imp
  expect_setequal(as.character(imp$variable), as.character(keep$variable))
  expect_setequal(levels(imp$variable), as.character(keep$variable))
  expect_setequal(as.character(env$.gvs$stats$variable), as.character(keep$variable))
  expect_identical(imp$selected, keep$selected)
  expect_identical(imp$noise_cut, keep$noise_cut)
  expect_s3_class(ggplot2::ggplot_build(env$.fig), "ggplot_built")
  expect_no_match(env$.fig$labels$caption, "Orange boxes", fixed = TRUE)
  expect_no_match(env$.fig$labels$caption, "Open boxes", fixed = TRUE)
})

test_that("FIGURES can keep vp-fit's original importance figure without the screened one", {
  # FIGURES keeps a figure whose name starts with an entry, so no vp-fit stem may start with another.
  stems <- regmatches(readLines(template_path("vp", "fit"), warn = FALSE),
                      regexpr("(?<=save_figure\\(\\.fig, \")vp-fit-[a-z-]+", readLines(template_path("vp", "fit"), warn = FALSE),
                              perl = TRUE))
  expect_true("vp-fit-screened" %in% stems)
  for (s in stems) expect_identical(stems[startsWith(stems, s)], s)
})

test_that("vp-fit's screened figure says so, and draws nothing, when no real variable was tested", {
  lines <- rf_chunk(readLines(template_path("vp", "fit"), warn = FALSE), "fig-varpro-screened")
  imp <- data.frame(variable = factor(c("a", "noise1_a")), z = c(0, 0.5), selected = FALSE, tested = c(FALSE, TRUE),
                    noise = c(FALSE, TRUE), kind = "continuous", noise_cut = 0.5, noise_ref = "continuous")
  env <- list2env(list(.gv = list(imp = imp, stats = data.frame(variable = imp$variable)), saved = character()))
  env$save_figure <- function(plot, name, ...) env$saved <- c(env$saved, name)
  out <- capture.output(eval(parse(text = lines), envir = env))
  expect_match(paste(out, collapse = "\n"), "No real variable was tested", fixed = TRUE)
  expect_length(env$saved, 0L)
})

test_that("vp-fit's figure holds categorical variables to the table's bar when categorical noise all scores 0", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  lines <- rf_chunk(readLines(template_path("vp", "fit"), warn = FALSE), "fig-varpro")
  from <- grep("^\\.at <- ", lines)
  to <- grep("^\\.fig <- plot", lines) - 1L
  imp <- data.frame(variable = c("a", "b", "n1", "n2"), kind = c("categorical", "continuous", "categorical", "continuous"),
                    z = c(0.5, 0.5, 0, 0.9), noise = c(FALSE, FALSE, TRUE, TRUE), tested = TRUE,
                    noise_cut = c(0, 0.9, 0, 0.9), noise_ref = c("categorical", "continuous", "categorical", "continuous"),
                    selected = c(TRUE, FALSE, FALSE, FALSE))
  env <- list2env(list(.gv = list(imp = imp), cov = data.frame(
    kind = c("categorical", "continuous"), bar = c(0.9, 0.9), bar_from = c("continuous (fallback)", "continuous")
  )))
  eval(parse(text = lines[from:to]), envir = env)
  # gg_varpro() alone would select "a" against a bar of 0; the table's fallback does not.
  expect_identical(env$.gv$imp$noise_cut, rep(0.9, 4))
  expect_identical(env$.gv$imp$selected, rep(FALSE, 4))
  expect_identical(env$.gv$imp$noise_ref[1], "continuous")
  # With no usable bar nothing is selected, and the bar still draws.
  env$.gv$imp <- imp
  env$cov$bar <- NA_real_
  env$cov$bar_from <- "no usable noise bar"
  eval(parse(text = lines[from:to]), envir = env)
  expect_identical(env$.gv$imp$noise_cut, rep(0, 4))
  expect_identical(env$.gv$imp$selected, rep(FALSE, 4))
  # The caption says so, in the words of the table. Built from ggRandomForests' own caption, so a change there fails here.
  env$.fig <- ggplot2::ggplot() + ggplot2::labs(caption = ggRandomForests:::.varpro_noise_caption(env$.gv$imp))
  eval(parse(text = grep("^\\.fig\\$labels\\$caption", lines, value = TRUE)), envir = env)
  expect_match(env$.fig$labels$caption, "categorical: no usable noise bar, nothing selected", fixed = TRUE)
  expect_no_match(env$.fig$labels$caption, "no noise tested", fixed = TRUE)
})

test_that("vp-fit judges a factor by its best level, as MAX_UNTESTED does, not by its pooled levels", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  labels <- c(vp_data_labels, "noise", "judge", "fit", "tbl-coverage", "tbl-funnel")
  env <- rf_env(vp_data())
  rf_run("vp", "fit", labels, env, utils::modifyList(vp_choices, list(TRIM = 0.3)))
  set.seed(1)
  pooled <- suppressWarnings(ggRandomForests::varpro_coverage(env$fit, by = "variable", trim = 0.3,
                                                              max.tree = env$fit$rf$ntree, noise = "^noise"))
  cov <- env$cov
  gap <- pooled$variable[pooled$tested & !cov$tested[match(pooled$variable, cov$variable)]]
  # The case at issue: its levels' trees together clear TRIM, and no single level does.
  expect_true("g1" %in% gap)
  expect_false(any(cov$selected[cov$variable %in% gap]))
  expect_true(all(cov$coverage[cov$variable %in% gap] < 0.3))
  # The stop and the table now count the same variables: one more untested than allowed stops, exactly that many passes.
  real <- cov[!cov$noise, ]
  untested <- sum(!real$tested) / nrow(real)
  stop_env <- rf_env(vp_data())
  expect_error(rf_run("vp", "fit", labels, stop_env, utils::modifyList(vp_choices, list(TRIM = 0.3, MAX_UNTESTED = untested - 0.01))),
               "real variables are untested")
  pass_env <- rf_env(vp_data())
  expect_no_error(rf_run("vp", "fit", labels, pass_env, utils::modifyList(vp_choices, list(TRIM = 0.3, MAX_UNTESTED = untested))))
})

test_that("vp-fit stops when more candidates went untested than MAX_UNTESTED allows", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- rf_env(vp_data())
  # A trim of 0.49 leaves at least one candidate untested on a cohort this small; a share of 0 tolerates none.
  choices <- utils::modifyList(vp_choices, list(TRIM = 0.49, MAX_UNTESTED = 0))
  expect_error(rf_run("vp", "fit", c(vp_data_labels, "noise", "judge", "fit", "tbl-coverage"), env, choices),
               "real variables are untested")
})

test_that("vp-fit refuses a SUBSAMPLE that is not a share", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- rf_env(vp_data())
  choices <- utils::modifyList(vp_choices, list(SUBSAMPLE = 1.5))
  expect_error(rf_run("vp", "fit", c(vp_data_labels, "noise"), env, choices), "SUBSAMPLE must be a share")
})

test_that("vp-fit refuses a survival EVENT coded 1 and 2", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  d <- vp_data()
  d$event <- d$event + 1L
  env <- rf_env(d)
  expect_error(rf_run("vp", "fit", vp_data_labels, env, vp_choices), "must be coded 0 and 1")
})

test_that("every varpro() call in vp-fit runs on one core", {
  # options(rf.cores) limits randomForestSRC's threads, not varPro's own
  # workers, which read `cores =` or mc.cores.
  lines <- readLines(template_path("vp", "fit"), warn = FALSE)
  # Comments mention varpro() in prose; only code lines are calls.
  src <- paste(lines[!grepl("^\\s*#", lines)], collapse = "\n")
  # A call spans several lines, so each is read from varpro( to its seed, which comes last.
  calls <- regmatches(src, gregexpr("(?s)(?<![_[:alnum:]])varpro\\(.*?seed = ", src, perl = TRUE))[[1L]]
  # The full fit and the stability refit.
  expect_length(calls, 2L)
  expect_true(all(grepl("cores = 1L", calls, fixed = TRUE)))
  expect_match(src, "options(rf.cores = 1L, mc.cores = 1L)", fixed = TRUE)
})

test_that("both varpro() calls in vp-fit carry the exploration settings, and the defaults are them", {
  lines <- readLines(template_path("vp", "fit"), warn = FALSE)
  src <- paste(lines[!grepl("^\\s*#", lines)], collapse = "\n")
  calls <- regmatches(src, gregexpr("(?s)(?<![_[:alnum:]])varpro\\(.*?seed = ", src, perl = TRUE))[[1L]]
  expect_length(calls, 2L)
  for (arg in c("split.weight = SPLIT_WEIGHT", "sparse = SPARSE", "mtry = .mtry", "nodesize.external = .nodesize_external,",
                "max.tree = .max_tree", "max.rules.tree = MAX_RULES_TREE")) {
    expect_true(all(grepl(arg, calls, fixed = TRUE)), info = arg)
  }
  choices <- rf_chunk(lines, "edit-study-choices")
  for (default in c("NTREE <- 500", "MTRY <- NULL", "NODESIZE_EXTERNAL <- NULL", "SPLIT_WEIGHT <- FALSE", "SPARSE <- FALSE")) {
    expect_true(default %in% choices, info = default)
  }
  # The larger setting and the parsimonious screen stay one uncomment away, and
  # take effect: their lines sit below the assignments they override.
  options <- list(
    "# NTREE <- 1000; MAX_TREE <- 1000; MAX_RULES_TREE <- 300" = list(NTREE = 1000, MAX_TREE = 1000, MAX_RULES_TREE = 300),
    "# SPLIT_WEIGHT <- TRUE; SPARSE <- TRUE; MTRY <- Inf; NVAR <- 30" = list(SPLIT_WEIGHT = TRUE, SPARSE = TRUE, MTRY = Inf, NVAR = 30)
  )
  for (line in names(options)) {
    at <- which(choices == line)
    expect_length(at, 1L)
    env <- new.env()
    eval(parse(text = replace(choices, at, sub("^# ", "", line))), envir = env)
    expect_identical(mget(names(options[[line]]), envir = env), options[[line]], info = line)
  }
  # The figure is scored on every tree, as the coverage table is.
  expect_match(src, "gg_varpro(fit, max.tree = fit$rf$ntree, trim = TRIM, noise = \"^noise\")", fixed = TRUE)
  expect_match(src, "varpro_coverage(f, by = \"variable\", trim = TRIM, max.tree = f$rf$ntree,", fixed = TRUE)
})

test_that("vp-fit hands varPro a lowered mtry and a survival leaf of about two events", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- rf_env(vp_data())
  rf_run("vp", "fit", c(vp_data_labels, "noise", "judge", "fit"), env, vp_choices)
  # Five candidates and 20 noise columns: ceiling(sqrt(25)) is 5, where varPro alone would use every column.
  expect_equal(env$.mtry, 5)
  expect_equal(env$fit$rf$mtry, 5)
  events <- sum(env$d_noise$event == 1)
  expect_identical(env$vp_nodesize_external(env$d_noise), max(10, round(2 * nrow(env$d_noise) / events)))
  # The rule sampling settings reach the fit: 150 trees capped at the 50 grown.
  expect_equal(env$fit$max.tree, 50)
  expect_equal(env$fit$max.rules.tree, 150)
  # The rule follows the patients a refit is given: every censored patient and five events.
  few <- rbind(env$d_noise[env$d_noise$event == 0, ], utils::head(env$d_noise[env$d_noise$event == 1, ], 5L))
  expect_identical(env$vp_nodesize_external(few), max(10, round(2 * nrow(few) / sum(few$event == 1))))
  expect_gt(env$vp_nodesize_external(few), 10)
  env$NODESIZE_EXTERNAL <- 25
  expect_identical(env$vp_nodesize_external(few), 25)
  # A classification screen grows no survival forest, so it passes nothing.
  env$.survival <- FALSE
  expect_null(env$vp_nodesize_external(few))
})

test_that("changing NODESIZE_EXTERNAL makes both vp-fit caches stale, and REFIT refits them", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  # Run in the global environment, as a render runs its chunks. There cache_fit()
  # keys a helper by its body and not the values it reads, so a leaf size read
  # inside vp_nodesize_external() went unseen. A child environment hides that.
  g <- globalenv()
  before <- ls(g, all.names = TRUE)
  withr::defer(rm(list = setdiff(ls(g, all.names = TRUE), before), envir = g))
  data <- vp_data()
  data$ccfid <- seq_len(nrow(data))
  g$.root <- rf_study(data, environment())
  labels <- c(vp_data_labels, "noise", "judge", "fit", "tbl-coverage", "tbl-stability")
  choices <- utils::modifyList(vp_choices, list(NTREE = 20, REPEATS = 1))
  run <- function(extra = list()) {
    g$.provenance_data <- list()
    rf_run("vp", "fit", labels, g, utils::modifyList(choices, extra))
  }
  run()
  files <- file.path(g$CACHE_DIR, c("vp-fit.rds", "vp-repeat-01.rds"))
  stamps <- file.mtime(files)
  Sys.sleep(1.1)  # so a rewrite would show in the modification time
  expect_error(run(list(NODESIZE_EXTERNAL = 25)), "stale")
  run(list(NODESIZE_EXTERNAL = 25, REFIT = TRUE))
  expect_identical(g$.nodesize_external, 25)
  expect_true(all(file.mtime(files) > stamps))
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
  expect_named(h, c("fit", "coverage", "selected", "family", "not_examined", "not_examined_refits"))
  expect_identical(h$not_examined, as.character(env$.real$variable[!env$.real$tested]))
  # With refits, the selection handed on is the refits' majority vote, among the variables they examined.
  expect_identical(h$selected, env$.freq$variable[env$.freq$examined & (env$.freq$share_selected >= 0.5) %in% TRUE])
  expect_identical(h$family, "survival")
  expect_s3_class(h$fit, "varpro")
  expect_false(is.null(attr(h, "hvti_provenance")))
  expect_setequal(unique(env$.stab$r), 1:2)
})

test_that("vp-fit never hands on a variable the refits did not examine", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  # A trim of 0.3 tests some candidates in only some refits, and a share of 1 asks every refit to have tested one before its
  # vote counts. A low SELECT_SHARE would then keep a variable tested once and selected there, were the gate not in place.
  choices <- utils::modifyList(vp_choices, list(TRIM = 0.3, MAX_UNTESTED = 1, REPEATS = 3, MIN_TESTED_SHARE = 1, SELECT_SHARE = 0.1))
  env <- vp_fit_first(choices = choices)
  h <- readRDS(env$set_path("estimates", "vp.rds"))
  freq <- env$.freq
  would_pass <- freq$variable[!freq$examined & (freq$share_selected >= 0.1) %in% TRUE]
  skip_if(!length(would_pass), "no unexamined variable was selected in the refits that tested it, so there is nothing to gate")
  expect_identical(h$not_examined_refits, as.character(freq$variable[!freq$examined]))
  expect_true(all(would_pass %in% h$not_examined_refits))
  expect_false(any(h$not_examined_refits %in% h$selected))
})

test_that("SELECT_SHARE = NA, or REPEATS = 0, hands on the full fit's selection", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  for (extra in list(list(SELECT_SHARE = NA), list(REPEATS = 0))) {
    env <- vp_fit_first(choices = utils::modifyList(vp_choices, extra))
    h <- readRDS(env$set_path("estimates", "vp.rds"))
    expect_identical(h$selected, env$.real$variable[env$.real$selected])
  }
})

test_that("SELECT_SHARE must be NA or a share in (0, 1]", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  for (bad in list(0, 1.5, NaN, "half", c(0.5, 0.6))) {
    expect_error(vp_fit_first(choices = utils::modifyList(vp_choices, list(SELECT_SHARE = bad))), "SELECT_SHARE")
  }
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
  expect_true(all(again$.freq$share_tested >= 0 & again$.freq$share_tested <= 1))
  expect_true(all(again$.freq$share_selected >= 0 & again$.freq$share_selected <= 1, na.rm = TRUE))
  expect_equal(again$.freq$share_tested * 3, round(again$.freq$share_tested * 3))
})

test_that("REPEATS = 0 skips the stability check", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- vp_fit_first(choices = utils::modifyList(vp_choices, list(REPEATS = 0)))
  expect_identical(nrow(env$.stab), 0L)
  expect_false(any(grepl("^vp-repeat-", list.files(env$CACHE_DIR))))
})

vp_explain_labels <- c("setup", "edit-study-choices", "screen", "tbl-data", "select", "dependence-varpro")

test_that("no vp-explain line calls varpro()", {
  src <- readLines(template_path("vp", "explain"), warn = FALSE)
  # gg_partial_varpro( is allowed; a bare varpro( fit is not.
  expect_false(any(grepl("(^|[^_[:alnum:]])varpro\\(", src)))
})

test_that("vp-explain stops when no vp-fit has run in its set", {
  rf_skip_unless_stack(rf_template_packages("vp", "explain"))
  env <- rf_env(vp_data())
  expect_error(rf_run("vp", "explain", c("setup", "edit-study-choices", "screen"), env), "Render the vp-fit job")
})

test_that("vp-explain names a selection the saved full fit did not test, and stops when nothing is left", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "explain"))
  # A trim of 0.49 leaves a candidate untested on a cohort this small, as a refit vote can hand one on.
  fit <- vp_fit_first(choices = utils::modifyList(vp_choices, list(TRIM = 0.49, MAX_UNTESTED = 1)))
  untested <- as.character(fit$.real$variable[!fit$.real$tested])
  skip_if(!length(untested), "every candidate was tested")
  env <- new.env(parent = globalenv())
  env$.root <- fit$.root
  expect_error(
    rf_run("vp", "explain", vp_explain_labels, env,
           list(HORIZON = 1, SEED = 1, SAVE_FIGURES = FALSE, PARTIAL_VARS = untested[1])),
    "the screen did not examine"
  )
})

test_that("vp-explain draws the saved selection, tested variables only", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "explain"))
  fit <- vp_fit_first()
  env <- new.env(parent = globalenv())
  env$.root <- fit$.root
  rf_run("vp", "explain", vp_explain_labels, env, list(HORIZON = 1, SEED = 1, SAVE_FIGURES = FALSE))
  h <- readRDS(fit$set_path("estimates", "vp.rds"))
  expect_setequal(env$sel, h$selected)
  expect_true(all(env$sel %in% h$coverage$variable[h$coverage$tested]))
  expect_true(file.exists(file.path(env$CACHE_DIR, "vp-partial.rds")))
})

test_that("vp-explain refuses a horizon past the longest follow-up", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "explain"))
  fit <- vp_fit_first()
  env <- new.env(parent = globalenv())
  env$.root <- fit$.root
  expect_error(rf_run("vp", "explain", vp_explain_labels, env, list(HORIZON = 1e6, SEED = 1, SAVE_FIGURES = FALSE)),
               "longest follow-up")
})

test_that("vp-fit and vp-explain keyed on MRN save no MRN in any file", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "explain"))
  data <- rf_mrn_data(n = 60L)
  choices <- list(TIME = "iv_dead", EVENT = "dead", RESPONSE = NULL, PREDICTORS = c("age", "x1", "grp"),
                  NTREE = 25, REPEATS = 1, SEED = 1, SAVE_FIGURES = FALSE,
                  MAX_UNTESTED = 0.5)  # 60 patients is far smaller than the 0.1 default is set for.
  fit <- vp_fit_first(data, choices)
  # The ID fell back to MRN, and the job read it.
  expect_identical(attr(fit$job_data$record, "selection")$id, "mrn")
  expect_identical(rf_files_holding(fit$CACHE_DIR, data$MRN), character())
  # On 60 patients the screen may select nothing, and vp-explain would then stop
  # before writing its cache; draw the first tested variable instead, so the
  # partial cache exists to be searched.
  h <- readRDS(fit$set_path("estimates", "vp.rds"))
  tested <- h$coverage$variable[!h$coverage$noise & h$coverage$tested]
  expect_gt(length(tested), 0L)
  env <- new.env(parent = globalenv())
  env$.root <- fit$.root
  rf_run("vp", "explain", vp_explain_labels, env,
         list(PARTIAL_VARS = tested[[1L]], HORIZON = 1, SEED = 1, SAVE_FIGURES = FALSE))
  expect_true(file.exists(file.path(fit$CACHE_DIR, "vp-partial.rds")))
  expect_identical(rf_files_holding(fit$CACHE_DIR, data$MRN), character())
  # The search finds what is there: every MRN in the data as the job read it.
  expect_true(rf_bytes_hold_any(serialize(fit$job_data$data, NULL), data$MRN))
})

# vp-dependence ---------------------------------------------------------------

test_that("vpd_parent reads varPro's own term map, and refuses a fit without one", {
  env <- vpd_helpers_env()
  x <- data.frame(fs = 1, fs.1 = 0)
  attr(x, "xvar.map") <- c(fs = "fs", fs.1 = "f")
  expect_identical(env$vpd_parent(list(x = x)), c(fs = "fs", fs.1 = "f"))
  expect_error(env$vpd_parent(list(x = data.frame(a = 1))), "xvar.map")
})

test_that("vpd_square pads to square and zeroes links within one factor", {
  env <- vpd_helpers_env()
  m <- matrix(c(0, 9, 0.5,
                8, 0, 0.2), nrow = 2, byrow = TRUE,
              dimnames = list(c("g1u", "g1v"), c("g1u", "g1v", "a")))
  sq <- env$vpd_square(m, c(g1u = "g1", g1v = "g1", a = "a"))
  expect_identical(dim(sq), c(3L, 3L))
  expect_identical(rownames(sq), colnames(sq))
  expect_equal(sq["g1u", "g1v"], 0)
  expect_equal(sq["g1v", "g1u"], 0)
  expect_equal(sq["g1u", "a"], 0.5)
  expect_equal(sq["a", "g1u"], 0)
})

test_that("vpd_square follows the term map through a name collision", {
  env <- vpd_helpers_env()
  # A factor f with levels s, t, u beside a numeric fs: varPro 3.3.0 names
  # f's s-level column fs.1, and it belongs to f.
  map <- c(fs = "fs", fs.1 = "f", ft = "f", fu = "f")
  m <- matrix(1, 4, 4, dimnames = list(names(map), names(map)))
  sq <- env$vpd_square(m, map)
  expect_equal(sq["fs", "fs.1"], 1)   # a real link between two variables survives
  expect_equal(sq["fs.1", "fs"], 1)
  expect_equal(sq["fs.1", "ft"], 0)   # a link between two levels of f is removed
  expect_equal(sq["fu", "fs.1"], 0)
})

test_that("vpd_bar takes the largest noise entry in a row or a column", {
  env <- vpd_helpers_env()
  nm <- c("a", "c", "noise1_a")
  m <- matrix(0, 3, 3, dimnames = list(nm, nm))
  m["a", "c"] <- 2.1
  m["noise1_a", "c"] <- 0.3   # noise released, real predictor
  m["a", "noise1_a"] <- 0.4   # real released, noise predictor
  b <- env$vpd_bar(m, startsWith(nm, "noise"), fixed = 0.25)
  expect_equal(b$bar, 0.4)    # the column direction counts
  expect_identical(b$from, "noise")
  m["a", "noise1_a"] <- 0
  expect_equal(env$vpd_bar(m, startsWith(nm, "noise"), fixed = 0.25)$bar, 0.3)  # and the row direction
})

test_that("vpd_bar falls back to the fixed threshold when every noise entry is 0", {
  env <- vpd_helpers_env()
  nm <- c("a", "c", "noise1_a")
  m <- matrix(0, 3, 3, dimnames = list(nm, nm))
  m["a", "c"] <- 2.1
  b <- env$vpd_bar(m, startsWith(nm, "noise"), fixed = 0.25)
  expect_equal(b$bar, 0.25)
  expect_identical(b$from, "fixed (fallback)")
})

test_that("vp-dependence keeps the noise and the outcome in the lasso step", {
  src <- readLines(template_path("vp", "dependence"), warn = FALSE)
  # Calls with arguments only: the narration and comments name the function as get.beta.entropy().
  calls <- grep("get\\.beta\\.entropy\\([^)]", src, value = TRUE)
  expect_gt(length(calls), 0L)
  expect_true(all(grepl("pre.filter = FALSE", calls, fixed = TRUE)))
})

test_that("vp-dependence runs on one core", {
  src <- readLines(template_path("vp", "dependence"), warn = FALSE)
  expect_true(any(grepl("options(rf.cores = 1L, mc.cores = 1L)", src, fixed = TRUE)))
  # Calls with arguments only: the narration and comments name the function as get.beta.entropy().
  calls <- grep("get\\.beta\\.entropy\\([^)]", src, value = TRUE)
  expect_true(all(grepl("papply = lapply", calls, fixed = TRUE)))
})

test_that("vp-dependence finds a planted dependence above the noise bar", {
  skip_on_cran()
  vp33_skip_unless_stack(c(rf_template_packages("vp", "dependence"), "ggraph"))
  # 100 trees: at 30 a noise entry reached 1.69 against the planted 2.3 (spec section 8).
  env <- vpd_first(choices = utils::modifyList(vpd_choices, list(NTREE = 100)))
  expect_identical(env$bar$from, "noise")
  expect_gt(env$beta["a", "c"], env$bar$bar)
  expect_gt(env$beta["c", "a"], env$bar$bar)
  expect_true(any(env$gg$edges$variable_from == "a" & env$gg$edges$variable_to == "c"))
  expect_false(any(grepl("^noise", c(env$gg$edges$variable_from, env$gg$edges$variable_to))))
})

test_that("vp-dependence saves one handoff with its lineage", {
  skip_on_cran()
  vp33_skip_unless_stack(c(rf_template_packages("vp", "dependence"), "ggraph"))
  env <- vpd_first()
  path <- env$set_path("estimates", "dependence.rds")
  h <- readRDS(path)
  expect_named(h, c("fit", "beta", "bar", "bar_from", "edges", "signal", "stability", "not_examined"))
  expect_s3_class(h$fit, "uvarpro")
  expect_null(h$stability)
  # The fixture's every variable has a release rule, so nothing is handed on as unexamined.
  expect_identical(h$not_examined, character())
  # The package's handoff reader accepts it: the lineage is complete.
  expect_no_error(hvtiRtemplates:::.read_handoff(path, "dependence", env$.cfg, "the vp-dependence job"))
})

test_that("vp-dependence traces a colliding encoded column to its factor", {
  skip_on_cran()
  vp33_skip_unless_stack(c(rf_template_packages("vp", "dependence"), "ggraph"))
  d <- vpd_data()
  d$f <- factor(withr::with_seed(3, sample(c("s", "t", "u"), nrow(d), replace = TRUE)))
  d$fs <- withr::with_seed(4, stats::rnorm(nrow(d)))
  # At 30 trees the three-level f takes the rules and fs gets none, which a MAX_UNTESTED share would stop on. This test
  # is about the term map, which covers every column whether or not it was released, so the gate is set to report.
  env <- vpd_first(d, c(utils::modifyList(vpd_choices, list(VARIABLES = c("a", "c", "f", "fs"))), list(MAX_UNTESTED = NULL)))
  # Asserted on varPro's own record, so it holds whatever spelling a later
  # varPro chooses: every encoded column of f maps to f, and fs stays fs.
  f_terms <- names(env$.parent)[env$.parent == "f"]
  expect_gt(length(f_terms), 1L)
  expect_identical(unname(env$.parent["fs"]), "fs")
  in_beta <- intersect(f_terms, rownames(env$beta))
  expect_true(all(env$beta[in_beta, in_beta] == 0))
})

test_that("vp-dependence keys its caches on the engines beneath varPro", {
  skip_on_cran()
  vp33_skip_unless_stack(c(rf_template_packages("vp", "dependence"), "ggraph"))
  env <- vpd_first(choices = utils::modifyList(vpd_choices, list(REPEATS = 1)))
  # The key records the version of every package named in packages =, so an
  # update to the forest or the lasso engine invalidates the cache.
  key_names <- function(file) {
    key <- readRDS(file.path(env$CACHE_DIR, file))$key
    paste(deparse(key), collapse = " ")
  }
  for (file in c("vp-dependence.rds", "vp-dependence-repeat-01.rds")) {
    expect_match(key_names(file), "randomForestSRC", fixed = TRUE, info = file)
  }
  for (file in c("vp-dependence-beta.rds", "vp-dependence-repeat-01-beta.rds")) {
    expect_match(key_names(file), "glmnet", fixed = TRUE, info = file)
  }
})

test_that("vp-dependence refuses an ORDINAL variable it was not given", {
  vp33_skip_unless_stack(c(rf_template_packages("vp", "dependence"), "ggraph"))
  env <- rf_env(vpd_data())
  expect_error(rf_run("vp", "dependence", c("setup", "edit-study-choices", "tbl-data"), env,
                      utils::modifyList(vpd_choices, list(ORDINAL = "zz"))),
               "ORDINAL names variable")
})

test_that("raising REPEATS in vp-dependence computes only the new refit", {
  skip_on_cran()
  vp33_skip_unless_stack(c(rf_template_packages("vp", "dependence"), "ggraph"))
  env <- vpd_first(choices = utils::modifyList(vpd_choices, list(REPEATS = 2)))
  # cache_fit() writes a provenance file beside each .rds, so only the .rds are counted.
  files <- list.files(env$CACHE_DIR, "^vp-dependence-repeat-.*[.]rds$", full.names = TRUE)
  expect_length(files, 4L)  # a forest and a matrix per refit
  before <- file.mtime(files)
  rf_run("vp", "dependence", vpd_labels, env, utils::modifyList(vpd_choices, list(REPEATS = 3)))
  expect_identical(file.mtime(files), before)
  expect_length(list.files(env$CACHE_DIR, "^vp-dependence-repeat-.*[.]rds$"), 6L)
  h <- readRDS(env$set_path("estimates", "dependence.rds"))
  expect_length(h$stability$bars, 3L)
  expect_true(all(h$stability$edges$share >= 0 & h$stability$edges$share <= 1))
})

test_that("REPEATS = 0 skips the dependence stability check", {
  skip_on_cran()
  vp33_skip_unless_stack(c(rf_template_packages("vp", "dependence"), "ggraph"))
  env <- vpd_first()
  expect_length(list.files(env$CACHE_DIR, "^vp-dependence-repeat-"), 0L)
  expect_null(readRDS(env$set_path("estimates", "dependence.rds"))$stability)
})

test_that("vpd_coverage counts each variable's release rules through varPro's term map", {
  vp33_skip_unless_stack("varPro")
  env <- vpd_helpers_env()
  d <- vpd_data()
  d$noise1_a <- withr::with_seed(7, sample(d$a))
  withr::local_options(rf.cores = 1L)
  fit <- varPro::uvarpro(d, ntree = 10, seed = -1)
  cols <- names(vpd_data())
  cov <- env$vpd_coverage(fit, cols)
  expect_identical(cov$variable, cols)
  # Every rule except those releasing the noise column, counted without the map: a numeric column keeps its name.
  expect_identical(sum(cov$rules), nrow(fit$results) - sum(colnames(fit$x)[fit$results$variable] == "noise1_a"))
  expect_identical(cov$state, ifelse(cov$rules > 0L, "examined", "not examined"))
  # fs is a factor, split into 0/1 columns, and its rules are counted to fs.
  expect_gt(cov$rules[cov$variable == "fs"], 0L)
})

test_that("vpd_edge_share counts an edge over the refits that examined both its ends", {
  env <- vpd_helpers_env()
  runs <- list(
    list(edges = "a -> c", examined = c("a", "c")),
    list(edges = "a -> c", examined = c("a", "b", "c")),
    list(edges = character(), examined = c("a", "b")),
    list(edges = character(), examined = c("b", "c"))
  )
  s <- env$vpd_edge_share(runs)
  expect_identical(s$from, "a")
  expect_identical(s$to, "c")
  expect_equal(s$share, 1)
  expect_identical(s$refits, 2L)
  # A refit that examined both ends and drew no edge counts against it.
  s <- env$vpd_edge_share(c(runs, list(list(edges = character(), examined = c("a", "c")))))
  expect_equal(s$share, 2 / 3)
  expect_identical(nrow(env$vpd_edge_share(list(list(edges = character(), examined = "a")))), 0L)
})

test_that("both uvarpro() calls in vp-dependence carry the rule limits, and the defaults are the measured ones", {
  lines <- readLines(template_path("vp", "dependence"), warn = FALSE)
  # Code only: the narration names uvarpro() in prose.
  open <- grep("^```\\{r", lines)
  code <- unlist(lapply(open, function(at) {
    end <- at + which(lines[(at + 1L):length(lines)] == "```")[1L]
    lines[(at + 1L):(end - 1L)]
  }))
  src <- paste(code[!grepl("^\\s*#", code)], collapse = "\n")
  calls <- regmatches(src, gregexpr("(?s)(?<![_[:alnum:]])uvarpro\\(.*?seed = ", src, perl = TRUE))[[1L]]
  # The full fit and the stability refit.
  expect_length(calls, 2L)
  for (arg in c("max.tree = min(MAX_TREE, NTREE)", "max.rules.tree = MAX_RULES_TREE")) {
    expect_true(all(grepl(arg, calls, fixed = TRUE)), info = arg)
  }
  choices <- rf_chunk(lines, "edit-study-choices")
  for (default in c("MAX_TREE <- 500", "MAX_RULES_TREE <- 20", "MAX_UNTESTED <- NULL")) {
    expect_true(default %in% choices, info = default)
  }
})

test_that("changing MAX_RULES_TREE makes both vp-dependence caches stale, and REFIT refits them", {
  skip_on_cran()
  vp33_skip_unless_stack(c(rf_template_packages("vp", "dependence"), "ggraph"))
  # Run in the global environment, as a render runs its chunks, as vp-fit's
  # NODESIZE_EXTERNAL test does.
  g <- globalenv()
  before <- ls(g, all.names = TRUE)
  withr::defer(rm(list = setdiff(ls(g, all.names = TRUE), before), envir = g))
  data <- vpd_data()
  data$ccfid <- seq_len(nrow(data))
  g$.root <- rf_study(data, environment())
  choices <- utils::modifyList(vpd_choices, list(REPEATS = 1))
  run <- function(extra = list()) {
    g$.provenance_data <- list()
    rf_run("vp", "dependence", vpd_labels, g, utils::modifyList(choices, extra))
  }
  run()
  files <- file.path(g$CACHE_DIR, c("vp-dependence.rds", "vp-dependence-repeat-01.rds"))
  stamps <- file.mtime(files)
  Sys.sleep(1.1)  # so a rewrite would show in the modification time
  expect_error(run(list(MAX_RULES_TREE = 10)), "stale")
  run(list(MAX_RULES_TREE = 10, REFIT = TRUE))
  expect_true(all(file.mtime(files) > stamps))
})

test_that("vp-dependence stops on an unexamined variable when MAX_UNTESTED is set, and by default hands it on", {
  skip_on_cran()
  vp33_skip_unless_stack(c(rf_template_packages("vp", "dependence"), "ggraph"))
  # Five trees and two rules a tree leave b and x2 without a release rule on this cohort.
  few <- utils::modifyList(vpd_choices, list(MAX_TREE = 5, MAX_RULES_TREE = 2))
  env <- rf_env(vpd_data())
  err <- expect_error(rf_run("vp", "dependence", c(vpd_labels[seq_len(which(vpd_labels == "coverage-gate"))]), env,
                             utils::modifyList(few, list(MAX_UNTESTED = 0))), "MAX_UNTESTED")
  expect_match(conditionMessage(err), "x2", fixed = TRUE)
  expect_match(conditionMessage(err), "MAX_TREE", fixed = TRUE)
  # The shipped default, NULL, reports and renders: `few` leaves MAX_UNTESTED to the template.
  env <- vpd_first(choices = few)
  expect_null(env$MAX_UNTESTED)
  h <- readRDS(env$set_path("estimates", "dependence.rds"))
  expect_true("x2" %in% h$not_examined)
  expect_identical(h$not_examined, env$.coverage$variable[env$.coverage$rules == 0L])
})

test_that("vp-dependence's default rule limits examine every variable where varPro's left two unexamined", {
  skip_on_cran()
  vp33_skip_unless_stack(c(rf_template_packages("vp", "dependence"), "ggraph"))
  # The template's own NTREE, NOISE_N and rule limits on the fixture shape. Which
  # variable misses is chance: over SEED = 1 to 30, varPro's 200 trees left a
  # real variable without a rule at 23 seeds and the default 500 at 7. SEED = 3
  # is one where 200 trees leave b and x2 out and 500 cover them, so this test
  # fails if the default falls back to 200 (dev/vp/uvarpro-coverage.R).
  env <- rf_env(vpd_data())
  rf_run("vp", "dependence", c("setup", "edit-study-choices", "tbl-data", "tbl-missing", "noise", "dependence-helpers"),
         env, list(VARIABLES = c("a", "b", "x2", "fs", "c"), OUTCOME = NULL, ORDINAL = NULL, SAVE_FIGURES = FALSE, SEED = 3))
  expect_identical(c(env$NTREE, env$NOISE_N), c(500, 20))
  # The fit chunk's own uvarpro() call, without the lasso that follows it.
  find <- function(e) {
    if (!is.call(e)) return(list())
    if (identical(e[[1L]], as.name("uvarpro"))) return(list(e))
    unlist(lapply(as.list(e)[-1L], find), recursive = FALSE)
  }
  fit_chunk <- rf_chunk(readLines(template_path("vp", "dependence"), warn = FALSE), "fit")
  call <- unlist(lapply(parse(text = fit_chunk), find), recursive = FALSE)
  expect_length(call, 1L)
  set.seed(abs(env$SEED))
  fit <- eval(call[[1L]], env)
  cov <- env$vpd_coverage(fit, env$.cols)
  expect_identical(cov$variable[cov$state != "examined"], character())
})

# vp-individual ---------------------------------------------------------------

test_that("no vp-individual line fits varPro", {
  src <- readLines(template_path("vp", "individual"), warn = FALSE)
  expect_false(any(grepl("(^|[^_[:alnum:].])varpro\\(", src)))
})

test_that("vp-individual stops when no vp-fit has run in its set", {
  vp33_skip_unless_stack(rf_template_packages("vp", "individual"))
  env <- rf_env(vp_data())
  expect_error(rf_run("vp", "individual", c("setup", "edit-study-choices", "screen"), env), "Render the vp-fit job")
})

test_that("vpi_coverage lists an all-NA term and draws it not", {
  env <- vpi_helpers_env()
  grad <- data.frame(xs = c(1, -2, NA), x1 = NA_real_, noise1_xs = NA_real_)
  screen <- data.frame(variable = c("xs", "x1", "noise1_xs"), noise = c(FALSE, FALSE, TRUE),
                       tested = c(TRUE, TRUE, FALSE), selected = c(TRUE, FALSE, FALSE))
  cov <- env$vpi_coverage(grad, c(xs = "xs", x1 = "x1", noise1_xs = "noise1_xs"), screen)
  expect_identical(cov$drawn[cov$term == "x1"], FALSE)
  expect_equal(cov$share_na[cov$term == "x1"], 1)
  expect_equal(cov$median_abs[cov$term == "xs"], 1.5)
  ref <- env$vpi_noise_ref(cov)
  expect_true(is.na(ref$value))
  expect_match(ref$text, "no noise reference")
})

test_that("vpi_coverage marks the handoff's selection, not the full fit's", {
  env <- vpi_helpers_env()
  # vp-fit's refit vote can differ from the full fit's own selection both ways.
  grad <- data.frame(age = c(1, 2), x1 = c(0.5, -1))
  screen <- data.frame(variable = c("age", "x1"), noise = FALSE, tested = TRUE, selected = c(FALSE, TRUE))
  cov <- env$vpi_coverage(grad, c(age = "age", x1 = "x1"), screen, selected = "age")
  expect_identical(cov$selected, c(TRUE, FALSE))
  # Without a handoff selection it falls back to the screen's own.
  expect_identical(env$vpi_coverage(grad, c(age = "age", x1 = "x1"), screen)$selected, c(FALSE, TRUE))
})

test_that("vpi_coverage gives each predictor one of the three states", {
  e <- vpi_helpers_env()
  cov <- data.frame(variable = c("s", "e", "n"), noise = FALSE, tested = c(TRUE, TRUE, FALSE))
  grad <- data.frame(s = c(0.1, 0.2), e = c(0.1, 0.1), n = c(NA, NA))
  out <- e$vpi_coverage(grad, c(s = "s", e = "e", n = "n"), cov, selected = "s")
  expect_identical(out$state, c("selected", "examined, not selected", "not examined"))
})

test_that("vpi_coverage keeps a predictor ivarpro() returned no column for", {
  env <- vpi_helpers_env()
  # With nvar = 1, varPro 3.3.0 kept only x1 in xvar.names and ivarpro()
  # returned only x1, though fit$x held x1, x2 and x3: x2 and x3 are absent, not NA.
  grad <- data.frame(x1 = c(0.5, -1))
  screen <- data.frame(variable = c("x1", "x2", "x3"), noise = FALSE, tested = c(TRUE, FALSE, FALSE),
                       selected = c(TRUE, FALSE, FALSE))
  cov <- env$vpi_coverage(grad, c(x1 = "x1", x2 = "x2", x3 = "x3"), screen)
  expect_identical(cov$term, c("x1", "x2", "x3"))
  expect_identical(cov$gradients, c("computed", "removed before gradients", "removed before gradients"))
  expect_identical(cov$drawn, c(TRUE, FALSE, FALSE))
  expect_equal(cov$share_na[cov$term == "x2"], 1)
})

test_that("vp-individual draws one target of a multiclass screen, with its plotting data", {
  skip_on_cran()
  vp33_skip_unless_stack(rf_template_packages("vp", "individual"))
  d <- vp_data()
  d$cls <- factor(ifelse(d$xs > 0.5, "c", ifelse(d$xs < -0.5, "a", "b")))
  ch <- utils::modifyList(vp_outcome(vp_choices, NULL, NULL, "cls"),
                          list(PREDICTORS = c("xs", "x1", "x2"), SPLIT_WEIGHT = FALSE, NVAR = 50, REPEATS = 0))
  fit <- vp_fit_first(d, ch)
  expect_error(vpi_run(fit, list(SHOW = "xs", TARGET = NULL, SEED = 1, SAVE_FIGURES = FALSE)), "Name one in TARGET")
  env <- vpi_run(fit, list(SHOW = "xs", TARGET = "c", SEED = 1, SAVE_FIGURES = FALSE))
  expect_false(is.null(env$.idata))
  expect_true(env$.target_col %in% names(env$.idata))
  expect_gt(nrow(env$.bee), 0L)
  expect_true(all(is.finite(env$.bee$value)))
})

test_that("vp-individual names the class a two-class screen's gradients explain", {
  skip_on_cran()
  vp33_skip_unless_stack(rf_template_packages("vp", "individual"))
  # A 0/1 outcome: ivarpro() explains the first class, 0, so a rising event risk
  # has a falling gradient, and the report must say which class it shows.
  ch <- utils::modifyList(vp_outcome(vp_choices, NULL, NULL, "event"),
                          list(PREDICTORS = c("xs", "x1", "x2"), SPLIT_WEIGHT = FALSE, NVAR = 50, REPEATS = 0))
  fit <- vp_fit_first(vp_data(), ch)
  out <- utils::capture.output(env <- vpi_run(fit, list(SHOW = "xs", SEED = 1, SAVE_FIGURES = FALSE)))
  expect_identical(env$.target, "0")
  expect_identical(env$.target_label, "P(class 0)")
  expect_true(any(grepl("predicted probability of class 0", out, fixed = TRUE)))
  expect_true(any(grepl("sign reversed", out, fixed = TRUE)))
  # .fig is the last gradient page, whose y axis is the gradient.
  expect_identical(ggplot2::get_labs(env$.fig)$y, "Local gradient of P(class 0)")
})

test_that("vp-individual gives the planted signal larger gradients than the nulls", {
  skip_on_cran()
  vp33_skip_unless_stack(rf_template_packages("vp", "individual"))
  # 500 trees: with the default mtry, 50 trees on 200 patients left xs no rule ivarpro() could release.
  fit <- vp_fit_first(choices = utils::modifyList(vp_choices, list(NTREE = 500, REPEATS = 0)))
  env <- vpi_run(fit, list(SHOW = c("xs", "x1", "x2"), SEED = 1, SAVE_FIGURES = FALSE))
  cov <- env$icov
  xs <- cov$median_abs[cov$term == "xs"]
  nulls <- cov$median_abs[cov$term %in% c("x1", "x2") & is.finite(cov$median_abs)]
  expect_true(is.finite(xs))
  expect_true(all(xs > nulls))
  h <- readRDS(fit$set_path("estimates", "individual.rds"))
  expect_named(h, c("ivarpro", "coverage"))
})

test_that("vp-dependence and vp-individual keyed on MRN save no MRN in any file", {
  skip_on_cran()
  vp33_skip_unless_stack(c(rf_template_packages("vp", "individual"), "ggraph"))
  data <- rf_mrn_data(n = 60L)
  dep <- vpd_first(data, list(VARIABLES = c("age", "x1", "grp"), OUTCOME = NULL, ORDINAL = NULL, NOISE_N = 2,
                              NTREE = 25, REPEATS = 1, SEED = 1, SAVE_FIGURES = FALSE))
  expect_identical(attr(dep$job_data$record, "selection")$id, "mrn")
  expect_true(file.exists(dep$set_path("estimates", "dependence.rds")))
  expect_identical(rf_files_holding(dep$CACHE_DIR, data$MRN), character())
  # ivarpro() releases a predictor only through rules holding enough patients,
  # and on the 60 above none of the three got a gradient, so the job stopped
  # before writing individual.rds. 120 patients and two noise columns give the
  # rules room; all three are shown, so whichever got gradients is drawn.
  data <- rf_mrn_data(n = 120L)
  fit <- vp_fit_first(data, list(TIME = "iv_dead", EVENT = "dead", RESPONSE = NULL, PREDICTORS = c("age", "x1", "grp"),
                                 NOISE_N = 2, NTREE = 50, REPEATS = 0, SEED = 1, SAVE_FIGURES = FALSE,
                                 SPLIT_WEIGHT = FALSE, NVAR = 50))
  vpi_run(fit, list(SHOW = c("age", "x1", "grp"), SEED = 1, SAVE_FIGURES = FALSE))
  expect_true(file.exists(fit$set_path("estimates", "individual.rds")))
  expect_identical(rf_files_holding(fit$CACHE_DIR, data$MRN), character())
  # The search finds what is there: every MRN in the data as the job read it.
  expect_true(rf_bytes_hold_any(serialize(fit$job_data$data, NULL), data$MRN))
})

test_that("vp-dependence imputes a missing variable by default, and leaves OUTCOME out of the imputation", {
  skip_on_cran()
  vp33_skip_unless_stack(rf_template_packages("vp", "dependence"))
  data <- vpd_data()
  data$b[1:9] <- NA
  env <- rf_env(data)
  rf_run("vp", "dependence", c("setup", "edit-study-choices", "tbl-data", "tbl-missing"), env, vpd_choices)
  expect_identical(nrow(env$d), 200L)
  expect_false(anyNA(env$d[vpd_choices$VARIABLES]))
  expect_identical(env$.cohort$n_imputed[["b"]], 9L)
})

test_that("vp-dependence hands the imputation the variables only, and drops a patient missing OUTCOME", {
  skip_on_cran()
  vp33_skip_unless_stack(rf_template_packages("vp", "dependence"))
  data <- vpd_data()
  data$x2[1:3] <- NA
  data$b[4:9] <- NA
  choices <- utils::modifyList(vpd_choices, list(VARIABLES = c("a", "b", "fs", "c")))
  choices <- c(choices[setdiff(names(choices), "OUTCOME")], list(OUTCOME = "x2"))
  env <- rf_env(data)
  rec <- new.env()
  testthat::local_mocked_bindings(impute = vp_mock_impute(rec), .package = "randomForestSRC")
  rf_run("vp", "dependence", c("setup", "edit-study-choices", "tbl-data", "tbl-missing"), env, choices)
  expect_identical(env$.cohort$n_outcome_missing, 3L)
  expect_identical(nrow(env$d), 197L)
  expect_identical(rec$seen, c("a", "b", "fs", "c"))
  expect_false("x2" %in% rec$seen)
})

test_that("vp-dependence stops on a patient with no observed variable", {
  skip_on_cran()
  vp33_skip_unless_stack(rf_template_packages("vp", "dependence"))
  data <- vpd_data()
  data[5, vpd_choices$VARIABLES] <- NA
  data$b[10:12] <- NA  # something to impute, so the imputation runs
  expect_error(rf_run("vp", "dependence", c("setup", "edit-study-choices", "tbl-data", "tbl-missing"),
                      rf_env(data), vpd_choices), "cannot be imputed")
})

test_that("vp-dependence with NA_ACTION = na.omit drops incomplete patients as before", {
  vp33_skip_unless_stack(rf_template_packages("vp", "dependence"))
  data <- vpd_data()
  data$b[1:9] <- NA
  env <- rf_env(data)
  rf_run("vp", "dependence", c("setup", "edit-study-choices", "tbl-data", "tbl-missing"), env,
         utils::modifyList(vpd_choices, list(NA_ACTION = "na.omit")))
  expect_identical(nrow(env$d), 191L)
  expect_identical(env$.cohort$n_dropped, 9L)
})
