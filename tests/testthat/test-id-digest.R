# Saved models keep a study-keyed digest of each patient ID, never the ID (#203).

# TRUE when `bytes` hold `value` as text or as R's big-endian integer or double encoding.
bytes_hold <- function(bytes, value) {
  patterns <- list(charToRaw(as.character(value)))
  if (is.numeric(value)) {
    patterns <- c(patterns, list(writeBin(as.double(value), raw(), endian = "big")))
    if (value == trunc(value) && abs(value) < .Machine$integer.max) {
      patterns <- c(patterns, list(writeBin(as.integer(value), raw(), endian = "big")))
    }
  }
  any(vapply(patterns, function(p) length(grepRaw(p, bytes, fixed = TRUE)) > 0L, logical(1L)))
}

rds_bytes <- function(path) {
  con <- gzfile(path, "rb")
  on.exit(close(con))
  readBin(con, "raw", n = 1e8)
}

test_that("the study key is made once, kept private, and reused", {
  root <- withr::local_tempdir("id-key-")
  path <- file.path(root, ".hvti", "id_key")
  expect_false(file.exists(path))
  key <- hvtiRtemplates:::.study_id_key(root)
  expect_true(file.exists(path))
  expect_match(key, "^[0-9a-f]{64}$")
  if (.Platform$OS.type == "unix") expect_identical(format(file.mode(path)), "640")
  before <- file.info(path)$mtime
  expect_identical(hvtiRtemplates:::.study_id_key(root), key)
  expect_identical(file.info(path)$mtime, before)
  # Another study has its own key, so the same patient digests differently there.
  expect_false(identical(hvtiRtemplates:::.study_id_key(withr::local_tempdir("id-key-")), key))
  writeLines("not a key", path)
  expect_error(hvtiRtemplates:::.study_id_key(root), "cannot be read or is not a key")
})

test_that("the same ID gives the same digest, and a missing ID stays missing", {
  root <- withr::local_tempdir("id-key-")
  ids <- c(73500001, NA, 73500002, 73500001)
  first <- hvtiRtemplates:::.id_digest(ids, hvtiRtemplates:::.study_id_key(root))
  second <- hvtiRtemplates:::.id_digest(ids, hvtiRtemplates:::.study_id_key(root))
  expect_identical(first, second)
  expect_identical(first[[1L]], first[[4L]])
  expect_true(is.na(first[[2L]]))
  expect_match(first[-2L], "^[0-9a-f]{64}$")
  expect_identical(first[[1L]], digest::hmac(hvtiRtemplates:::.study_id_key(root), "73500001", "sha256"))
  # An ID read as a double in one dataset and an integer in another is the same patient.
  key <- hvtiRtemplates:::.study_id_key(root)
  expect_identical(hvtiRtemplates:::.id_digest(1e5, key), hvtiRtemplates:::.id_digest(100000L, key))
  expect_identical(hvtiRtemplates:::.id_digest(factor("A12"), key), hvtiRtemplates:::.id_digest("A12", key))
})

test_that("every lm fit template saves digested IDs and a model that still scores", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.7")
  d <- lm_mi_data()
  common <- list(PREDICTORS = c("age", "female"), ID = "id", IMPUTATION = "imp")
  cases <- list(
    binary = list(OUTCOME = "outcome", OUTCOME_LEVELS = c("none", "event"), EVENT_LEVEL = "event"),
    ordinal = list(OUTCOME = "ordinal", OUTCOME_LEVELS = c("low", "middle", "high")),
    nominal = list(OUTCOME = "nominal", OUTCOME_LEVELS = c("reference", "level_b", "level_c"),
                   REFERENCE_LEVEL = "reference"),
    propensity_binary = list(TREATMENT = "treatment", TREATMENT_LEVELS = c("control", "treated"),
                             TREATED_LEVEL = "treated"),
    propensity_ordinal = list(TREATMENT = "treatment_ordinal", TREATMENT_LEVELS = c("low", "middle", "high")),
    propensity_nominal = list(TREATMENT = "treatment_nominal", TREATMENT_LEVELS = c("reference", "level_b", "level_c"),
                              REFERENCE_LEVEL = "reference"),
    balancing_count = list(OUTCOME = "count", DISTRIBUTION = "poisson", N_STRATA = 5L)
  )
  for (qualifier in names(cases)) {
    env <- new.env(parent = globalenv())
    env$d <- d
    env$.root <- withr::local_tempdir("lm-root-")
    env$set_path <- function(kind, file) tempfile(fileext = file)
    lm_run(qualifier, c("edit-study-choices", "fit", "save"), env, c(common, cases[[qualifier]]))
    saved <- readRDS(env$MODEL_PATH)
    key <- hvtiRtemplates:::.study_id_key(env$.root)
    expect_true(isTRUE(saved$meta$id_digest), info = qualifier)
    expect_null(env$fit$meta$id_digest, info = qualifier)
    expect_identical(env$fit$data$id, d$id[d$imp == 1L], info = qualifier)
    expect_identical(saved$data$id, hvtiRtemplates:::.id_digest(env$fit$data$id, key), info = qualifier)
    # No copy of the data anywhere in the bundle, the fitted models' own included, keeps a raw ID.
    frames <- list()
    collect <- function(x) {
      if (is.data.frame(x)) frames[[length(frames) + 1L]] <<- x else if (is.list(x)) lapply(x, collect)
      invisible(NULL)
    }
    collect(unclass(saved))
    ids <- unlist(lapply(frames, function(f) if ("id" %in% names(f)) as.character(f$id)))
    expect_true(length(ids) > 0L, info = qualifier)
    expect_true(all(grepl("^[0-9a-f]{64}$", ids)), info = qualifier)
    # The models themselves are untouched, so the saved bundle scores new patients as the fit did.
    expect_equal(stats::predict(saved$models[[1L]], newdata = lm_data()),
                 stats::predict(env$fit$models[[1L]], newdata = lm_data()), info = qualifier)
  }
})

test_that("a rendered lm-binary keyed on MRN saves no MRN anywhere in the file", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.7")
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  d <- lm_data()
  d$MRN <- 73500000L + d$ccfid
  d$ccfid <- NULL
  d$id <- NULL
  out <- lm_render_fixture("binary", data = d)
  path <- file.path(hvtiRutilities::study_dir("estimates", out$root), "outcome-analysis", "lm-binary.rds")
  expect_true(file.exists(path))
  saved <- readRDS(path)
  # The ID fell back to MRN, which the data read names in lower case.
  expect_identical(saved$meta$id_col, "mrn")
  expect_true(isTRUE(saved$meta$id_digest))
  bytes <- rds_bytes(path)
  expect_false(any(vapply(d$MRN, function(v) bytes_hold(bytes, v), logical(1L))))
  # The search finds what is there: the digests in this file, and MRNs in serialized data.
  key <- hvtiRtemplates:::.study_id_key(out$root)
  expect_true(bytes_hold(bytes, hvtiRtemplates:::.id_digest(d$MRN[[1L]], key)))
  expect_true(all(vapply(d$MRN, function(v) bytes_hold(serialize(d, NULL), v), logical(1L))))
  expect_true(all(vapply(as.numeric(d$MRN), function(v) bytes_hold(serialize(as.numeric(d$MRN), NULL), v), logical(1L))))
  expect_true(bytes_hold(serialize(as.character(d$MRN), NULL), d$MRN[[1L]]))
  # The key stays in the study, never beside the package.
  expect_true(file.exists(file.path(out$root, ".hvti", "id_key")))
})
