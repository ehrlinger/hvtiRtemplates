# hs-concordance: every patient through every group's hm model, as the
# design in the 2026-09-30 hs-concordance spec describes.

test_that("the fixture fits one hm model per group, in its own set", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- concordance_estate()
  for (g in c("a", "b")) {
    path <- file.path(hvtiRutilities::study_dir("estimates", e$root), paste0("dead-", g), "hm.rds")
    expect_true(file.exists(path), info = g)
    expect_identical(nrow(readRDS(path)$reported$data$frame), sum(e$data$group == g), info = g)
  }
})

test_that("hs-concordance predicts every patient through every model and saves no identifier", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- concordance_estate()
  env <- concordance_run(e$root, concordance_choices(e$data))
  path <- file.path(hvtiRutilities::study_dir("estimates", e$root), "dead-ab", "hs-concordance.rds")
  art <- readRDS(path)
  expect_identical(nrow(art$pred), 2L * nrow(e$data))
  expect_setequal(unique(art$pred$model), c("a", "b"))
  expect_identical(as.vector(table(art$pred$row)), rep(2L, nrow(e$data)))
  expect_identical(names(art$patients), c("row", "group", "age"))
  expect_identical(art$overlap, "none")
  expect_identical(art$time, "iv_dead")
  expect_equal(art$clevel, 0.68268948)
  bytes <- hazard_rds_bytes(path)
  expect_false(any(vapply(e$data$ccfid, function(v) hazard_bytes_hold(bytes, v), logical(1L))))
  lineage <- attr(art, "hvti_provenance")
  expect_identical(sum(grepl("hm.rds$", vapply(lineage$artifacts, `[[`, "", "path"))), 2L)
})

test_that("hs-concordance refuses what would make the comparison meaningless", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- concordance_estate()
  core <- concordance_core
  bad <- function(..., msg) {
    expect_error(concordance_run(e$root, concordance_choices(e$data, ...), core), msg)
  }
  bad(OVERLAP = NULL, msg = "OVERLAP must be one of")
  bad(MODELS = c(a = "dead-a", a = "dead-b"), msg = "must be unique")
  bad(MODELS = c("dead-a", "dead-b"), msg = "needs a name")
  bad(MODELS = c(a = "dead-a", b = "dead-a"), msg = "resolve to the same file")
  bad(MODELS = c(a = "dead-a"), msg = "have no model in MODELS")
  bad(HORIZON = 1e6, msg = "beyond the last observed time of the model for a")
  bad(CARRY = "ccfid", msg = "may not name a patient identifier")
  bad(CARRY = c("age", "group"), msg = "already has")
  other <- file.path(hvtiRutilities::study_dir("estimates", e$root), "dead-b", "hm.rds")
  bad(MODELS = c(a = "dead-a", b = other), msg = "Set CROSS_STUDY")
  bad(MODELS = c(a = "dead-a", b = gsub("/", "\\", other, fixed = TRUE)), msg = "Set CROSS_STUDY")
  bad(TIME = "age", msg = "fitted on time column")
})

test_that("a horizon beyond one model's follow-up names that model alone", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- concordance_estate()
  env <- concordance_run(e$root, concordance_choices(e$data), c("tbl-data", "cohort", "models"))
  last <- vapply(env$models, function(a) max(a$reported$data$frame$iv_dead), numeric(1L))
  h <- mean(last)
  short <- names(which.min(last))
  err <- tryCatch(concordance_run(e$root, concordance_choices(e$data, HORIZON = h), concordance_core),
                  error = conditionMessage)
  expect_match(err, paste0("model for ", short, " \\("))
  expect_no_match(err, paste0("model for ", setdiff(names(last), short)))
})

test_that("a model no patient received is reported, not refused", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- concordance_estate()
  choices <- concordance_choices(e$data[e$data$group == "a", ], WHERE = quote(group == "a"))
  env <- concordance_run(e$root, choices, concordance_core)
  expect_setequal(unique(env$pred$model), c("a", "b"))
})

test_that("the decision calls a choice optimal only when the limits separate it", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- concordance_estate()
  env <- concordance_run(e$root, concordance_choices(e$data), concordance_core)
  n <- nrow(e$data)
  # Patient 1: an exact tie. Patient 2: a near-tie inside the limits.
  # Patient 3: separated. Patient 4: b ineligible, so no choice to make.
  env$pred$fit[env$pred$row %in% 1:4 & env$pred$model == "a"] <- c(0.5, 0.5, 0.9, 0.5)
  env$pred$fit[env$pred$row %in% 1:4 & env$pred$model == "b"] <- c(0.5, 0.5001, 0.2, 0.9)
  env$pred$lower[env$pred$row %in% 1:4] <- env$pred$fit[env$pred$row %in% 1:4] - 0.05
  env$pred$upper[env$pred$row %in% 1:4] <- env$pred$fit[env$pred$row %in% 1:4] + 0.05
  env$d$elig_b <- seq_len(n) != 4L
  before <- env$pred
  # ELIGIBLE is set inside the decision chunk, so the edit is made to its text,
  # as a study author would make it.
  src <- readLines(hazard_template("hs-concordance"), warn = FALSE)
  chunk_of <- function(label) {
    chunk <- src[(match(paste0("#| label: ", label), src) + 1L):length(src)]
    chunk[seq_len(match("```", chunk) - 1L)]
  }
  chunk <- chunk_of("edit-decision")
  edited <- sub("^ELIGIBLE <- list\\(\\)$", 'ELIGIBLE <- list(b = "elig_b")', chunk)
  expect_false(identical(edited, chunk))
  utils::capture.output({
    eval(parse(text = edited), envir = env)
    eval(parse(text = chunk_of("decision")), envir = env)
  })
  dec <- env$decision[1:4, ]
  expect_identical(dec$tie, c(TRUE, FALSE, FALSE, FALSE))
  expect_identical(dec$optimal, rep(NA_character_, 4L) |> replace(3L, "a"))
  expect_identical(dec$best[2:4], c("b", "a", "a"))
  expect_identical(env$pred, before)
  # Every patient is in the best-treatment table, ties and non-choices included.
  expect_identical(sum(env$best_tbl), n)
  expect_equal(unname(colSums(env$best_tbl)[c("(tie)", "(no choice)")]), c(1, 0))
  expect_error({
    eval(parse(text = sub("^ELIGIBLE <- list\\(\\)$", 'ELIGIBLE <- list("elig_b")', chunk)), envir = env)
    eval(parse(text = chunk_of("decision")), envir = env)
  }, "unique name")
})

test_that("deleting the decision leaves a job that saves", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- concordance_estate()
  concordance_run(e$root, concordance_choices(e$data), c(concordance_core, "save"))
  art <- readRDS(file.path(hvtiRutilities::study_dir("estimates", e$root), "dead-ab", "hs-concordance.rds"))
  expect_null(art$decision)
  expect_identical(nrow(art$pred), 2L * nrow(e$data))
})

test_that("a group model without a variance matrix stops the predictions, naming the model (#227)", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- concordance_estate()
  # Model b as a fit that lost its variance matrix: predict() then returns a
  # finite fit with every limit NA.
  path <- file.path(hvtiRutilities::study_dir("estimates", e$root), "dead-b", "hm.rds")
  art <- readRDS(path)
  art$reported$fit$vcov <- NULL
  saveRDS(art, path)
  err <- tryCatch(concordance_run(e$root, concordance_choices(e$data)), error = conditionMessage)
  expect_match(err, "No confidence limits from the model(s) for b:", fixed = TRUE)
  expect_match(err, "no variance matrix", fixed = TRUE)
  expect_no_match(err, "missing value where TRUE/FALSE needed", fixed = TRUE)
})
