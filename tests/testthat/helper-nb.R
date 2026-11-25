# nb-boostmtree is run here chunk by chunk, as the rf and hazard templates are.

nb_template <- function(name = "nb.boostmtree") {
  templates <- template_list()
  hit <- which(templates$name == name)
  if (length(hit) != 1L) stop("template '", name, "' found ", length(hit), " times", call. = FALSE)
  templates$file[[hit]]
}

# Evaluate chunks `labels` in `env`; `choices` overwrite edit-study-choices.
nb_run <- function(labels, env, choices = list(), template = "nb.boostmtree") {
  src <- readLines(nb_template(template), warn = FALSE)
  # "set" is the old name of the setup chunk, and a list that names both runs it once.
  for (label in unique(vapply(labels, setup_label, ""))) {  # nolint: object_usage_linter.
    at <- which(trimws(src) == paste0("#| label: ", label))
    if (length(at) != 1L) stop("chunk '", label, "' found ", length(at), " times", call. = FALSE)
    end <- at + which(src[(at + 1L):length(src)] == "```")[1L]
    code <- src[(at + 1L):(end - 1L)]
    if (identical(label, "setup")) {
      eval_setup_chunk(code, env)  # nolint: object_usage_linter.
    } else {
      withCallingHandlers(
        suppressMessages(eval(parse(text = code), envir = env)),
        warning = function(w) if (nb_small_cohort_notice(w)) invokeRestart("muffleWarning")
      )
    }
    if (identical(label, "edit-study-choices")) list2env(choices, envir = env)
  }
  invisible(env)
}
nb_fit_run <- function(labels, env, choices = list()) nb_run(labels, env, choices, "nb.boostmtree_fit")
nb_explain_run <- function(labels, env, choices = list()) nb_run(labels, env, choices, "nb.boostmtree_explain")
nb_bundle_path <- function(root) file.path(hvtiRutilities::study_dir("estimates", root), "lvef-boost", "nb-boostmtree_fit.rds")
nb_set_dir <- function(root) file.path(hvtiRutilities::study_dir("estimates", root), "lvef-boost")

# ggBoostedTrees (since #46) warns when some subjects were never out of bag by
# m.opt, since their fitted trajectory is the starting value rather than a
# prediction. On nb_data()'s 40 patients a few always are, so the notice is true
# of the test cohort and says nothing about the template. It is muffled by its
# message and nothing else, as the rf tests muffle their drawing notices, and a
# study still sees it in its report.
nb_small_cohort_notice <- function(w) {
  grepl("^gg_boost_trajectory: [0-9]+ of [0-9]+ subject\\(s\\) were never out of bag by m\\.opt",
        conditionMessage(w))
}

# A small longitudinal cohort: 40 patients, 3 to 6 visits each, a continuous
# response that drifts with time and age. `id` names the ID column: "ccfid",
# or "MRN" to exercise the fallback that keeps MRN as the job's ID. IDs are
# ten digits, so a byte search cannot match one by chance.
nb_data <- function(n = 40L, id = "ccfid") {
  withr::local_seed(20261001)
  visits <- sample(3:6, n, replace = TRUE)
  pid <- rep(4730000000 + seq_len(n), visits)
  age <- rep(round(stats::runif(n, 30, 80)), visits)
  female <- rep(stats::rbinom(n, 1L, 0.4), visits)
  # Visit times are drawn without replacement, so no patient has two visits at
  # one time and the cohort is unique on KEY <- c(ID, TIME).
  iv_echo <- unlist(lapply(visits, function(k) sort(sample(0:800, k)) / 100))
  d <- data.frame(id = pid, iv_echo = iv_echo, age = age, female = female, grp = rep(sample(c("a", "b"), n, TRUE), visits))
  d$lvef <- 55 - 0.8 * d$iv_echo + 0.1 * (d$age - 55) - 2 * d$female + stats::rnorm(nrow(d), 0, 2)
  names(d)[[1L]] <- id
  d
}

# One response per family the template offers, beside the continuous lvef.
nb_family_data <- function() {
  d <- nb_data()
  d$lvef_bin <- as.integer(d$lvef > stats::median(d$lvef))
  d$lvef_ord <- cut(d$lvef, stats::quantile(d$lvef, c(0, 1 / 3, 2 / 3, 1)), include.lowest = TRUE, labels = FALSE)
  d$lvef_nom <- c("low", "mid", "high")[d$lvef_ord]
  d
}
nb_families <- list(continuous = "lvef", binary = "lvef_bin", ordinal = "lvef_ord", nominal = "lvef_nom")

nb_study <- function(data = nb_data(), .local_envir = parent.frame()) {
  root <- withr::local_tempdir("nb-study-", .local_envir = .local_envir)
  suppressMessages(hvtiRutilities::study_setup(
    root, study = "nb test", study_tracker_id = 9L,
    adopt = TRUE, cleanup = FALSE, renv = FALSE
  ))
  utils::write.csv(data, file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"), row.names = FALSE)
  suppressWarnings(suppressMessages(hvtiRutilities::register_data(root = root, file = "built.csv")))
  normalizePath(root)
}

# A chunk environment for `root`, parented on globalenv as a render's is.
nb_env <- function(root, parent = globalenv()) {
  env <- new.env(parent = parent)
  env$.root <- root
  env$.provenance_data <- list()
  env$study_config <- hvtiRutilities::study_config
  # The setup chunk attaches these; bound here instead, so a test does not attach a package for the rest of the run.
  env$cache_fit <- hvtiRutilities::cache_fit
  if (requireNamespace("boostmtree", quietly = TRUE)) {
    env$boostmtree <- boostmtree::boostmtree
    env$vimp.boostmtree <- boostmtree::vimp.boostmtree
    env$boostmtree.control <- boostmtree::boostmtree.control
    # partial.plot() is most of a chunk test's time, and nearly all of that is
    # its grid of 25 values per continuous covariate. Five still draws a curve,
    # and a factor is evaluated at its levels whatever n.points says. The
    # rendered job in test-nb-boostmtree.R keeps the template's own call.
    env$partial.plot <- function(object, ...) boostmtree::partial.plot(object, ..., n.points = 5)
  }
  if (requireNamespace("ggBoostedTrees", quietly = TRUE)) {
    for (f in c("gg_boost_error", "gg_boost_path", "gg_boost_calibration", "gg_boost_vimp", "gg_boost_effect",
                "gg_boost_trajectory", "boost_shadow")) {
      assign(f, getExportedValue("ggBoostedTrees", f), envir = env)
    }
  }
  env
}

# The setup chunk without the lines that need a study or attach packages: what
# is left is the version floors.
nb_setup_code <- function(template = "nb.boostmtree") {
  src <- readLines(nb_template(template), warn = FALSE)
  at <- which(trimws(src) == "#| label: setup")
  end <- at + which(src[(at + 1L):length(src)] == "```")[1L]
  setup <- src[(at + 1L):(end - 1L)]
  setup[!grepl("^\\.in <-|^\\.job|^\\.root <-|^set_path <-|library\\(", setup)]
}

# The real packages are installed, so the mocked version is the only thing that
# can trip each floor.
nb_mocked_setup <- function(pkg, version, template = "nb.boostmtree") {
  setup <- nb_setup_code(template)
  env <- new.env(parent = globalenv())
  testthat::local_mocked_bindings(
    packageVersion = function(p, ...) if (identical(p, pkg)) package_version(version) else package_version("99.0.0"),
    .package = "utils"
  )
  eval(parse(text = setup), envir = env)
}

# On CI a missing or too-old stack stops the suite instead of skipping it: boostmtree 2.0.8 reaches CI only through
# the Remotes pin, and a skip would let every nb test go quiet unnoticed.
nb_skip_unless_stack <- function() {
  floors <- c(boostmtree = "2.0.13", ggBoostedTrees = "0.10.3")
  for (pkg in names(floors)) {
    ok <- requireNamespace(pkg, quietly = TRUE) && utils::packageVersion(pkg) >= floors[[pkg]]
    if (ok) next
    msg <- paste0(pkg, " >= ", floors[[pkg]], " is required for the nb-boostmtree tests")
    if (identical(Sys.getenv("CI"), "true")) stop(msg, call. = FALSE)
    testthat::skip(msg)
  }
}

# Every environment reachable from `x` that is not the global, base or a package's. Used to see what a fit carries.
nb_reachable_envs <- function(x) {
  seen <- list()
  walk <- function(o) {
    if (is.environment(o)) {
      if (identical(o, globalenv()) || identical(o, baseenv()) || identical(o, emptyenv()) || isNamespace(o) ||
            nzchar(environmentName(o))) return(invisible())
      if (any(vapply(seen, identical, logical(1L), o))) return(invisible())
      seen[[length(seen) + 1L]] <<- o
      for (n in setdiff(ls(o, all.names = TRUE), "...")) walk(get(n, o))
      walk(parent.env(o))
      return(invisible())
    }
    if (is.function(o)) walk(environment(o))
    if (is.list(o) || is.pairlist(o)) for (i in seq_along(o)) walk(o[[i]])
    if (is.language(o)) walk(attr(o, ".Environment"))
    for (a in setdiff(names(attributes(o)), c("names", "dim", "dimnames", "class"))) walk(attr(o, a))
    invisible()
  }
  walk(x)
  seen
}

# M is five boosting steps: enough for every chunk to draw, and the fit and
# partial.plot() both cost in proportion to it. CORES is at most 2, because
# R CMD check sets _R_CHECK_LIMIT_CORES_ and parallel then refuses the
# template's 4; Windows, which cannot fork, gets 1 so boostmtree does not warn.
nb_cores <- if (.Platform$OS.type == "windows") 1L else 2L
nb_choices <- function(...) {
  utils::modifyList(list(RESPONSE = "lvef", M = 5, SEED = 7, CORES = nb_cores), list(...))
}

# The fit helpers below live here, not in the test file, so object_usage_linter
# resolves nb_env and nb_run from the same file.

# TRUE when `bytes` hold `value` as text or as R's big-endian double.
nb_bytes_hold <- function(bytes, value) {
  patterns <- list(charToRaw(format(value, scientific = FALSE)), writeBin(as.double(value), raw(), endian = "big"))
  any(vapply(patterns, function(p) length(grepRaw(p, bytes, fixed = TRUE)) > 0L, logical(1L)))
}
nb_file_bytes <- function(path) {
  con <- gzfile(path, "rb")
  on.exit(close(con))
  pieces <- list()
  repeat {
    piece <- readBin(con, "raw", n = 1e7)
    if (!length(piece)) break
    pieces[[length(pieces) + 1L]] <- piece
  }
  do.call(c, pieces)
}
nb_fit_in <- function(root, parent = globalenv(), choices = nb_choices(), template = "nb.boostmtree_fit") {
  env <- nb_env(root, parent)
  utils::capture.output(nb_run(c("setup", "edit-study-choices", "tbl-data", "fit", "save"), env, choices, template))
  env
}

# A cohort keyed on a study's own randid that also carries a ccfid column, ten
# digits like the rest, so a byte search cannot match one by chance.
nb_randid_data <- function() {
  d <- nb_data(id = "randid")
  d$ccfid <- 5810000000 + match(d$randid, unique(d$randid))
  d
}
nb_randid_choices <- function(...) nb_choices(ID = "randid", KEY = c("randid", "iv_echo"), ...)

# The files under `root` that hold any of `values`, leaving out the input
# dataset, its registered copy and the study key, as the MRN test does.
nb_files_holding <- function(root, values) {
  datasets <- basename(hvtiRutilities::study_dir("datasets", root))
  inputs <- c(file.path(datasets, c("built.csv", "built.parquet")), file.path(".hvti", "id_key"))
  files <- setdiff(list.files(root, recursive = TRUE, all.files = TRUE), inputs)
  Filter(function(f) {
    bytes <- nb_file_bytes(file.path(root, f))
    any(vapply(values, function(v) nb_bytes_hold(bytes, v), logical(1L)))
  }, files)
}

nb_explain_choices <- function(...) utils::modifyList(list(N_VIMP = 3, SEED = 11, CORES = nb_cores), list(...))

# Fit in `root` with `fit_choices`, then run explain chunks `labels` in a fresh environment.
nb_explain_in <- function(root, labels = c("setup", "edit-study-choices", "fit", "tbl-data", "fig-importance",
                                           "importance-runs"),
                          choices = nb_explain_choices(), fit_choices = nb_choices(), fit = TRUE) {
  if (fit) nb_fit_in(root, choices = fit_choices)
  env <- nb_env(root)
  utils::capture.output(nb_explain_run(labels, env, choices))
  env
}

# Rewrite the one line of `job` matching `from`.
nb_set_choice <- function(job, from, to) {
  txt <- readLines(job)
  hit <- grep(from, txt)
  stopifnot(length(hit) == 1L)
  txt[hit] <- to
  writeLines(txt, job)
}

# Render `job` and return what it printed. On failure, fail with Quarto's own
# stderr (#493): the quarto package once lost it while formatting its error with
# cli, so the console streams are captured here and the condition chain is read
# too. Each render gets its own TMPDIR, so renders run in parallel share no
# Quarto temporary files.
nb_render <- function(job) {
  withr::local_envvar(TMPDIR = withr::local_tempdir("nb-render-tmp-"))
  out <- withr::local_tempfile(fileext = ".out")
  err <- withr::local_tempfile(fileext = ".err")
  con_out <- file(out, "w")
  con_err <- file(err, "w")
  sink(con_out)
  sink(con_err, type = "message")
  result <- tryCatch({
    render_job(job, quiet = FALSE)
    NULL
  }, error = function(e) e, finally = {
    sink(type = "message")
    sink()
    close(con_out)
    close(con_err)
  })
  printed <- c(readLines(out, warn = FALSE), readLines(err, warn = FALSE))
  if (!is.null(result)) {
    chain <- character()
    e <- result
    while (!is.null(e)) {
      if (is.character(e$stderr)) chain <- c(chain, e$stderr)
      e <- e$parent
    }
    message <- tryCatch(conditionMessage(result), error = function(x) "<the error message could not be formatted>")
    testthat::fail(paste(c(paste("render_job() failed:", message), "--- stderr on the condition chain ---", chain,
                           "--- console, last 80 lines ---", utils::tail(printed, 80L)), collapse = "\n"))
    return(invisible(printed))
  }
  printed
}
