# sid-fit's IMPUTE = "none" (#643), SID_ARGS (#644) and the reason for its randomForestSRC floor (#646).

# sid_data() with its few missing values removed: data completed upstream, as a rerun would supply them.
sid_complete_data <- function() {
  d <- sid_data()  # nolint: object_usage_linter.
  d[stats::complete.cases(d), ]
}

# The fit chunk's `.sid_code`, built from the template's own lines with `sid_args` spliced in.
sid_fit_code <- function(sid_args) {
  src <- readLines(template_path("sid", "fit"), warn = FALSE)  # nolint: object_usage_linter.
  from <- grep("^\\.sid_code <- bquote\\(", src)
  to <- grep("^}, splice = TRUE\\)$", src)
  stopifnot(length(from) == 1L, length(to) == 1L)
  env <- new.env(parent = globalenv())
  env$SID_ARGS <- sid_args
  eval(parse(text = src[from:to]), envir = env)
  env$.sid_code
}

# The block the fit chunk cached before SID_ARGS existed, verbatim. A study's existing caches are keyed on it.
sid_fit_code_before <- quote({
  o <- sidClustering(d_complete[[m]], method = "sid", ntree = NTREE, reduce = SID_REDUCE, seed = -abs(s))
  if (is.null(o$dist)) {
    stop("sidClustering() failed on imputation ", m, " (it returned no distance). Look above for the message ",
         "randomForestSRC gave, and check the clustering variables for a constant or near-empty factor.", call. = FALSE)
  }
  o[c("dist", "outcome.names")]
})

test_that("with SID_ARGS = list(), the cached call is the one sid-fit made before SID_ARGS", {
  code <- sid_fit_code(list())
  expect_identical(code, sid_fit_code_before)
  # The text cache_fit() keys on, byte for byte.
  text <- hvtiRutilities:::.cache_code_text(code)
  expect_identical(text, hvtiRutilities:::.cache_code_text(sid_fit_code_before))
  expect_snapshot(cat(text))
})

test_that("SID_ARGS is written into the cached call by value, so each argument changes the key", {
  text <- hvtiRutilities:::.cache_code_text(sid_fit_code(list(dist.sharpen = FALSE, ntree.reduce = 200)))
  expect_match(text, "seed = -abs(s), dist.sharpen = FALSE, ntree.reduce = 200)", fixed = TRUE)
})

test_that("a sid-fit cache from before SID_ARGS still loads under the default list()", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("sid", "fit"))  # nolint: object_usage_linter.
  env <- sid_fit_first()  # nolint: object_usage_linter.
  # The block from before SID_ARGS, run where the job ran it: a key that differed would stop as stale.
  run <- new.env(parent = env)
  run$m <- 1L
  run$s <- env$SEED
  run$code <- sid_fit_code_before
  expect_message(
    eval(quote(hvtiRutilities::cache_fit("sid-fit-1", code, seed = s, dir = CACHE_DIR, refit = FALSE)), run),
    "loaded 'sid-fit-1' from cache"
  )
  h <- readRDS(env$set_path("estimates", "sid.rds"))
  expect_identical(h$settings$sid_args, list())
})

test_that("SID_ARGS reaches sidClustering(), the cache key and the handoff", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("sid", "fit"))  # nolint: object_usage_linter.
  args <- list(dist.sharpen = FALSE)
  env <- sid_fit_first(choices = utils::modifyList(sid_fit_choices, list(SID_ARGS = args)))  # nolint: object_usage_linter.
  h <- readRDS(env$set_path("estimates", "sid.rds"))
  expect_identical(h$settings$sid_args, args)
  expect_match(readRDS(file.path(env$CACHE_DIR, "sid-fit-1.rds"))$key$code, "dist.sharpen = FALSE", fixed = TRUE)
  # dist.sharpen = FALSE leaves the distance unsharpened, so it differs from the default fit's.
  default <- readRDS(sid_fit_first()$set_path("estimates", "sid.rds"))$dist  # nolint: object_usage_linter.
  expect_false(isTRUE(all.equal(unname(h$dist), unname(default))))
})

test_that("SID_ARGS refuses the arguments the job sets, unknown ones and unnamed ones", {
  rf_skip_unless_stack(rf_template_packages("sid", "fit"))  # nolint: object_usage_linter.
  cases <- list(
    list(args = list(ntree = 10), msg = "sets itself: ntree"),
    list(args = list(seed = -1, k = 3), msg = "sets itself: seed, k"),
    list(args = list(na.action = "na.impute"), msg = "sets itself: na.action"),
    list(args = list(case.wt = rep(1, 10)), msg = "patient-level data: case.wt"),
    list(args = list(x.no.sid = data.frame(z = 1)), msg = "patient-level data: x.no.sid"),
    list(args = list(nodesise = 5), msg = "neither sidClustering\\(\\) nor rfsrc\\(\\) takes: nodesise"),
    list(args = list(TRUE), msg = "each named once"),
    list(args = list(fast = TRUE, fast = FALSE), msg = "each named once"),
    list(args = c(fast = TRUE), msg = "must be list\\(\\)")
  )
  for (case in cases) {
    env <- rf_env(sid_complete_data())  # nolint: object_usage_linter.
    choices <- utils::modifyList(sid_fit_choices, list(SID_ARGS = case$args, IMPUTE = "none"))  # nolint: object_usage_linter.
    expect_error(rf_run("sid", "fit", sid_fit_labels[1:6], env, choices), case$msg)  # nolint: object_usage_linter.
    # Refused before any forest is grown, so nothing is cached.
    expect_false(file.exists(file.path(env$CACHE_DIR, "sid-fit-1.rds")))
  }
})

test_that("IMPUTE = \"none\" fits complete data as supplied, imputes nothing and records it", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("sid", "fit"))  # nolint: object_usage_linter.
  d <- sid_complete_data()
  choices <- utils::modifyList(sid_fit_choices, list(IMPUTE = "none"))  # nolint: object_usage_linter.
  out <- utils::capture.output(env <- sid_fit_first(d, choices))  # nolint: object_usage_linter.
  expect_true(any(grepl("complete as supplied", out, fixed = TRUE)))
  expect_false(any(grepl("Values imputed", out, fixed = TRUE)))
  expect_false(file.exists(file.path(env$CACHE_DIR, "sid-fit-impute-1.rds")))
  expect_identical(env$d_complete[[1L]], env$d[env$sid_vars])
  h <- readRDS(env$set_path("estimates", "sid.rds"))
  expect_identical(h$settings$impute, "none")
  expect_identical(dim(h$dist), rep(nrow(d), 2L))
})

test_that("IMPUTE = \"none\" stops on a missing value, naming the variables, and needs M = 1", {
  rf_skip_unless_stack(rf_template_packages("sid", "fit"))  # nolint: object_usage_linter.
  env <- rf_env(sid_data())  # nolint: object_usage_linter.
  choices <- utils::modifyList(sid_fit_choices, list(IMPUTE = "none"))  # nolint: object_usage_linter.
  expect_error(rf_run("sid", "fit", sid_fit_labels[1:5], env, choices),  # nolint: object_usage_linter.
               "missing values: a \\(5\\), f \\(3\\)")
  env <- rf_env(sid_complete_data())  # nolint: object_usage_linter.
  expect_error(rf_run("sid", "fit", sid_fit_labels[1:5], env, utils::modifyList(choices, list(M = 2))),  # nolint: object_usage_linter.
               "needs M = 1")
})

test_that("sid-fit says why it needs randomForestSRC 3.7.0, next to the check", {
  src <- readLines(template_path("sid", "fit"), warn = FALSE)  # nolint: object_usage_linter.
  at <- grep('packageVersion("randomForestSRC") < "3.7.0"', src, fixed = TRUE)
  expect_length(at, 1L)
  above <- paste(src[seq(max(1L, at - 8L), at - 1L)], collapse = " ")
  expect_match(above, "copied the floor")
  expect_match(above, "3.7.0 changed survival prediction", fixed = TRUE)
})

test_that("sid-fit renders with IMPUTE = \"none\" on complete data and a non-empty SID_ARGS", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  rf_skip_unless_stack(rf_template_packages("sid", "fit"))  # nolint: object_usage_linter.
  root <- tempfile("sid-study-")
  withr::defer(unlink(root, recursive = TRUE))
  suppressMessages(hvtiRutilities::study_setup(root, study = "Synthetic sid study", study_tracker_id = 42L, renv = FALSE))
  d <- sid_complete_data()
  d <- cbind(ccfid = seq_len(nrow(d)), d[c("a", "b", "c", "e", "f")])
  utils::write.csv(d, file.path(root, "00_datasets", "built.csv"), row.names = FALSE)
  suppressMessages(hvtiRutilities::register_data(root = root, file = "built.csv", role = "study", population = "Synthetic cohort"))
  fit <- add_job("sid", "morph", "sid", root = root, qualifier = "fit")
  sid_edit_job(fit, c('VARS <- c("a", "b", "c", "e", "f")', "NTREE <- 200", "SID_REDUCE <- FALSE",  # nolint: object_usage_linter.
                      'IMPUTE <- "none"', "SID_ARGS <- list(dist.sharpen = FALSE)"))
  quarto::quarto_render(fit, execute_dir = dirname(fit), quiet = TRUE)
  html <- sub("[.]qmd$", ".html", fit)
  expect_true(file.exists(html))
  raw <- paste(readLines(html, warn = FALSE), collapse = "\n")
  # The code is folded into the page too, so the printed lines are read from the chunk output alone, and the
  # table row from the page with every <pre> block removed.
  printed <- regmatches(raw, gregexpr("(?s)cell-output-stdout\">\\s*<pre><code>.*?</code>", raw, perl = TRUE))[[1L]]
  printed <- paste(printed, collapse = "\n")
  expect_match(printed, "the clustering variables were complete as supplied", fixed = TRUE)
  expect_no_match(printed, "Values imputed", fixed = TRUE)
  expect_match(gsub("(?s)<pre[^>]*>.*?</pre>", "", raw, perl = TRUE), "none: complete as supplied", fixed = TRUE)
  prov <- hvtiRtemplates:::.extract_provenance(raw)
  expect_identical(prov$sid$impute, "none")
  expect_identical(prov$sid$sid_args$dist.sharpen, "FALSE")
  saved <- list.files(root, "^sid[.]rds$", recursive = TRUE, full.names = TRUE)
  expect_length(saved, 1L)
  h <- readRDS(saved)
  expect_identical(h$settings$sid_args, list(dist.sharpen = FALSE))
})

test_that("sid-stability refits with sid-fit's SID_ARGS, in both refit calls and in the refits it ran", {
  skip_on_cran()
  rf_skip_unless_stack(unique(c(rf_template_packages("sid", "fit"), rf_template_packages("sid", "stability"))))
  args <- list(dist.sharpen = FALSE)
  env <- sid_fit_first(choices = utils::modifyList(sid_fit_choices, list(SID_ARGS = args)))  # nolint: object_usage_linter.
  sid_clusters_after(env)  # nolint: object_usage_linter.
  sid_stability_after(env)  # nolint: object_usage_linter.
  expect_identical(env$.sid_args, args)
  # The refits that ran were cached under code that hands the argument on.
  refits <- list.files(env$CACHE_DIR, "^sid-stability-.*[.]rds$", full.names = TRUE)
  expect_gt(length(refits), 0L)
  for (f in refits) expect_match(readRDS(f)$key$code, "dist.sharpen = FALSE", fixed = TRUE, info = basename(f))
  # Both refit calls, the SID metric's and the profile metric's, pass it to sidClustering().
  for (code in list(env$.refit_code, env$.refit_code_profile)) {
    seen <- new.env()
    seen$args <- list()
    e <- new.env(parent = env)
    e$sidClustering <- function(x, ...) {
      seen$args <- c(seen$args, list(list(...)))
      list(dist = as.matrix(stats::dist(seq_len(nrow(x)))))
    }
    e$refit_x <- env$x_m
    e$refit_ntree <- env$.s$ntree
    e$refit_reduce <- env$.s$sid_reduce
    e$refit_k <- env$.k_range
    e$refit_seed <- 1L
    eval(code, e)
    expect_length(seen$args, length(env$x_m))
    for (a in seen$args) expect_identical(a$dist.sharpen, FALSE)
  }
})
