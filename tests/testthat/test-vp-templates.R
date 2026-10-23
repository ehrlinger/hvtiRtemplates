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

test_that("vp_judge drops varpro_coverage()'s own bar, so one bar remains", {
  cov <- vp_cov(
    variable = c("x_real", "noise1_x"), kind = c("continuous", "continuous"),
    noise = c(FALSE, TRUE), tested = c(TRUE, TRUE), z = c(2, 0.3)
  )
  cov$noise_cut <- 0
  cov$selected <- TRUE
  out <- vp_judge_fn()(cov)
  expect_false("noise_cut" %in% names(out))
  expect_identical(out$selected, c(TRUE, FALSE))
})

test_that("vp_judge ignores a tested noise row whose z is NA", {
  cov <- vp_cov(
    variable = c("x_real", "noise1_x", "noise2_x"), kind = rep("continuous", 3),
    noise = c(FALSE, TRUE, TRUE), tested = c(TRUE, TRUE, TRUE), z = c(2, NA, 0.4)
  )
  out <- vp_judge_fn()(cov)
  expect_identical(unique(out$bar), 0.4)
})

test_that("both varpro_coverage() calls in vp-fit muffle the empty-noise warning", {
  lines <- readLines(template_path("vp", "fit"), warn = FALSE)
  at <- grep("varpro_coverage\\(fit|varpro_coverage\\(fr", lines)
  expect_length(at, 2L)
  for (i in at) {
    before <- paste(lines[max(1L, i - 3L):i], collapse = "\n")
    expect_match(before, "withCallingHandlers", fixed = TRUE)
    after <- paste(lines[i:min(length(lines), i + 4L)], collapse = "\n")
    expect_match(after, "no noise variable was tested", fixed = TRUE)
  }
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
  expect_true(all(again$.freq$share_tested >= 0 & again$.freq$share_selected <= 1))
  expect_equal(again$.freq$share_selected * 3, round(again$.freq$share_selected * 3))
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
                  NTREE = 25, REPEATS = 1, SEED = 1, SAVE_FIGURES = FALSE)
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
  rf_skip_unless_stack(c(rf_template_packages("vp", "dependence"), "ggraph"))
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
  rf_skip_unless_stack(c(rf_template_packages("vp", "dependence"), "ggraph"))
  env <- vpd_first()
  path <- env$set_path("estimates", "dependence.rds")
  h <- readRDS(path)
  expect_named(h, c("fit", "beta", "bar", "bar_from", "edges", "signal", "stability"))
  expect_s3_class(h$fit, "uvarpro")
  expect_null(h$stability)
  # The package's handoff reader accepts it: the lineage is complete.
  expect_no_error(hvtiRtemplates:::.read_handoff(path, "dependence", env$.cfg, "the vp-dependence job"))
})

test_that("vp-dependence traces a colliding encoded column to its factor", {
  skip_on_cran()
  rf_skip_unless_stack(c(rf_template_packages("vp", "dependence"), "ggraph"))
  d <- vpd_data()
  d$f <- factor(withr::with_seed(3, sample(c("s", "t", "u"), nrow(d), replace = TRUE)))
  d$fs <- withr::with_seed(4, stats::rnorm(nrow(d)))
  env <- vpd_first(d, utils::modifyList(vpd_choices, list(VARIABLES = c("a", "c", "f", "fs"))))
  # Asserted on varPro's own record, so it holds whatever spelling a later
  # varPro chooses: every encoded column of f maps to f, and fs stays fs.
  f_terms <- names(env$.parent)[env$.parent == "f"]
  expect_gt(length(f_terms), 1L)
  expect_identical(unname(env$.parent["fs"]), "fs")
  in_beta <- intersect(f_terms, rownames(env$beta))
  expect_true(all(env$beta[in_beta, in_beta] == 0))
})

test_that("vp-dependence refuses an ORDINAL variable it was not given", {
  rf_skip_unless_stack(rf_template_packages("vp", "dependence"))
  env <- rf_env(vpd_data())
  expect_error(rf_run("vp", "dependence", c("setup", "edit-study-choices", "tbl-data"), env,
                      utils::modifyList(vpd_choices, list(ORDINAL = "zz"))),
               "ORDINAL names variable")
})

test_that("raising REPEATS in vp-dependence computes only the new refit", {
  skip_on_cran()
  rf_skip_unless_stack(c(rf_template_packages("vp", "dependence"), "ggraph"))
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
  rf_skip_unless_stack(c(rf_template_packages("vp", "dependence"), "ggraph"))
  env <- vpd_first()
  expect_length(list.files(env$CACHE_DIR, "^vp-dependence-repeat-"), 0L)
  expect_null(readRDS(env$set_path("estimates", "dependence.rds"))$stability)
})

# vp-individual ---------------------------------------------------------------

test_that("no vp-individual line fits varPro", {
  src <- readLines(template_path("vp", "individual"), warn = FALSE)
  expect_false(any(grepl("(^|[^_[:alnum:].])varpro\\(", src)))
})

test_that("vp-individual stops when no vp-fit has run in its set", {
  rf_skip_unless_stack(rf_template_packages("vp", "individual"))
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
  rf_skip_unless_stack(rf_template_packages("vp", "individual"))
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

test_that("vp-individual gives the planted signal larger gradients than the nulls", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "individual"))
  fit <- vp_fit_first(choices = utils::modifyList(vp_choices, list(SPLIT_WEIGHT = FALSE, NVAR = 50)))
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
  rf_skip_unless_stack(c(rf_template_packages("vp", "individual"), "ggraph"))
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
