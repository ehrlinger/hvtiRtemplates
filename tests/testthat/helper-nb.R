# nb-boostmtree is run here chunk by chunk, as the rf and hazard templates are.

nb_template <- function() {
  templates <- template_list()
  hit <- which(templates$name == "nb-boostmtree")
  if (length(hit) != 1L) stop("template 'nb-boostmtree' found ", length(hit), " times", call. = FALSE)
  templates$file[[hit]]
}

# Evaluate chunks `labels` in `env`; `choices` overwrite edit-study-choices.
nb_run <- function(labels, env, choices = list()) {
  src <- readLines(nb_template(), warn = FALSE)
  for (label in labels) {
    at <- which(trimws(src) == paste0("#| label: ", label))
    if (length(at) != 1L) stop("chunk '", label, "' found ", length(at), " times", call. = FALSE)
    end <- at + which(src[(at + 1L):length(src)] == "```")[1L]
    suppressMessages(eval(parse(text = src[(at + 1L):(end - 1L)]), envir = env))
    if (identical(label, "edit-study-choices")) list2env(choices, envir = env)
  }
  invisible(env)
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
  suppressMessages(hvtiRutilities::study_setup(root, study = "nb test", study_tracker_id = 9L, adopt = TRUE))
  utils::write.csv(data, file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"), row.names = FALSE)
  suppressWarnings(suppressMessages(hvtiRutilities::register_data(root, built = "built.csv")))
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
    # partial.plot() is most of a chunk test's time, and nearly all of that is
    # its grid of 25 values per continuous covariate. Five still draws a curve,
    # and a factor is evaluated at its levels whatever n.points says. The
    # rendered job in test-nb-boostmtree.R keeps the template's own call.
    env$partial.plot <- function(object, ...) boostmtree::partial.plot(object, ..., n.points = 5)
  }
  if (requireNamespace("ggBoostedTrees", quietly = TRUE)) {
    for (f in c("gg_boost_error", "gg_boost_path", "gg_boost_calibration", "gg_boost_vimp", "gg_boost_effect",
                "gg_boost_trajectory")) {
      assign(f, getExportedValue("ggBoostedTrees", f), envir = env)
    }
  }
  env
}

# The setup chunk without the lines that need a study or attach packages.
nb_setup_code <- function() {
  src <- readLines(nb_template(), warn = FALSE)
  at <- which(trimws(src) == "#| label: setup")
  end <- at + which(src[(at + 1L):length(src)] == "```")[1L]
  setup <- src[(at + 1L):(end - 1L)]
  setup[!grepl("find_study_root|list.files|library\\(", setup)]
}

# The real packages are installed, so the mocked version is the only thing that
# can trip each floor.
nb_mocked_setup <- function(pkg, version) {
  setup <- nb_setup_code()
  env <- new.env(parent = globalenv())
  testthat::local_mocked_bindings(
    packageVersion = function(p, ...) if (identical(p, pkg)) package_version(version) else package_version("99.0.0"),
    .package = "utils"
  )
  eval(parse(text = setup), envir = env)
}

nb_skip_unless_stack <- function() {
  testthat::skip_if_not_installed("boostmtree", minimum_version = "2.0.2")
  testthat::skip_if_not_installed("ggBoostedTrees", minimum_version = "0.9.0")
}

# M is five boosting steps: enough for every chunk to draw, and the fit and
# partial.plot() both cost in proportion to it.
nb_choices <- function(...) {
  utils::modifyList(list(RESPONSE = "lvef", M = 5, SEED = 7), list(...))
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
nb_fit_in <- function(root, parent = globalenv(), choices = nb_choices()) {
  env <- nb_env(root, parent)
  utils::capture.output(nb_run(c("set", "edit-study-choices", "tbl-data", "fit", "save"), env, choices))
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
