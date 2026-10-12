# lp-mirror: the mirrored propensity histogram, read from a saved
# lm-propensity_binary bundle. The design is
# dev/specs/2026-10-11-lp-mirror-template-design.md; its section 7 lists what
# these tests cover. All data are synthetic.

test_that("lp-mirror is a graphs template that add_job() scaffolds by its full name", {
  tl <- template_list()
  row <- tl[tl$name == "lp.mirror", ]
  expect_identical(nrow(row), 1L)
  expect_identical(row$folder, "graphs")
  expect_identical(row$call, "add_job(\"lp.mirror\", subject = \"treatment\", type = \"propensity\")")
  root <- lm_study()
  job <- add_job("lp.mirror", "treatment", "propensity", dir = root)
  expect_identical(basename(job), "lp.mirror.treatment.propensity.qmd")
  expect_identical(normalizePath(dirname(job)), normalizePath(hvtiRutilities::study_dir("graphs", root)))
  src <- readLines(job, warn = FALSE)
  expect_identical(grep("^SUBJECT\\s+<- ", src, value = TRUE), "SUBJECT <- \"treatment\"")
  expect_identical(grep("^TYPE\\s+<- ", src, value = TRUE), "TYPE    <- \"propensity\"")
})

test_that("the job's package guards ask for the versions DESCRIPTION suggests", {
  src <- readLines(template_path("lp", "mirror"), warn = FALSE)
  suggests <- gsub("\\s+", " ", utils::packageDescription("hvtiRtemplates")$Suggests)
  for (pkg in c("hvtiRpropensity", "hvtiPlotR")) {
    minimum <- sub(paste0(".*", pkg, " \\(>= ([0-9.]+)\\).*"), "\\1", suggests)
    guard <- regmatches(src, regexpr(paste0("packageVersion[(]\"", pkg, "\"[)] < \"[0-9.]+\""), src))
    expect_length(guard, 1L)
    expect_identical(sub('.*< "([0-9.]+)"$', "\\1", guard), minimum, info = pkg)
    expect_true(any(grepl(paste0(pkg, " >= ", minimum), src, fixed = TRUE)), info = pkg)
  }
})

test_that("the job reads the bundle from its own set, or another through MODEL_SET, and never refits", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- lp_fixture()
  testthat::local_mocked_bindings(
    ps_logistic = function(...) stop("lp-mirror refitted the model", call. = FALSE),
    .package = "hvtiRpropensity"
  )
  env <- lm_eval_job(s$job)
  expect_identical(env$MODEL_PATH, s$bundle)
  expect_identical(nrow(env$scores), 120L)
  expect_named(env$scores, c("id", "score", "group", "weight", "matched"))
  # The bundle moved to a set of its own is found through MODEL_SET.
  other <- file.path(hvtiRutilities::study_dir("estimates", s$root), "treatment-propensity")
  dir.create(other)
  file.rename(s$bundle, file.path(other, "lm-propensity_binary.rds"))
  expect_error(lm_eval_job(s$job), "^Saved model not found: .*outcome-analysis.*set MODEL_FILE and MODEL_SET")
  src <- readLines(s$job, warn = FALSE)
  writeLines(sub("^MODEL_SET <- NULL$", "MODEL_SET <- \"treatment-propensity\"", src), s$job)
  env <- lm_eval_job(s$job)
  expect_identical(normalizePath(env$MODEL_PATH), normalizePath(file.path(other, "lm-propensity_binary.rds")))
  # Neither setting can reach outside the study's estimates.
  writeLines(sub("^MODEL_SET <- NULL$", "MODEL_SET <- \"../treatment-propensity\"", src), s$job)
  expect_error(lm_eval_job(s$job), "^MODEL_SET must be NULL or one set name")
  writeLines(sub("^MODEL_FILE <- .*$", "MODEL_FILE <- \"../x/lm-propensity_binary.rds\"", src), s$job)
  expect_error(lm_eval_job(s$job), "^MODEL_FILE must name one [.]rds file")
  # A bundle without its matching weight is not one this job can draw.
  writeLines(sub("^MODEL_SET <- NULL$", "MODEL_SET <- \"treatment-propensity\"", src), s$job)
  bundle <- readRDS(file.path(other, "lm-propensity_binary.rds"))
  bundle$data$mt_wt <- NULL
  saveRDS(bundle, file.path(other, "lm-propensity_binary.rds"))
  expect_error(lm_eval_job(s$job), "is not a binary propensity model with its patients, treatment, score and matching weight")
})

test_that("a bundle without lineage, or built from data that changed since, stops with the job to rerun", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- lp_fixture()
  bundle <- readRDS(s$bundle)
  lineage <- attr(bundle, "hvti_provenance")
  resave <- function(value) {
    attr(bundle, "hvti_provenance") <- value
    saveRDS(bundle, s$bundle)
  }
  resave(NULL)
  expect_error(lm_eval_job(s$job), "no complete hvti_provenance lineage. Rebuild it by rendering the lm-propensity_binary job")
  no_data <- lineage
  no_data$data <- list()
  resave(no_data)
  expect_error(lm_eval_job(s$job), "no source data lineage. Rebuild it by rendering the lm-propensity_binary job")
  resave(lineage[setdiff(names(lineage), "selection")])
  expect_error(lm_eval_job(s$job), "Render the lm-propensity_binary job again with the current template")
  # The same counts on other patients: the data changed since the bundle was saved.
  changed <- lineage
  changed$selection$key_hash <- strrep("0", 64L)
  resave(changed)
  expect_error(lm_eval_job(s$job), "The data changed since the upstream job ran")
})

test_that("the groups are labeled by the bundle's declared levels, treated first, unless GROUP_LABELS says", {
  h <- lp_helpers()
  meta <- list(treatment_levels = c("control", "treated"), treated_level = "treated")
  expect_identical(h$mirror_groups(meta), list(levels = c("treated", "control"), labels = c("treated", "control")))
  # Named by level, in either order.
  expect_identical(h$mirror_groups(meta, c(control = "Surgical", treated = "Transcatheter"))$labels,
                   c("Transcatheter", "Surgical"))
  expect_identical(h$mirror_groups(meta, c(treated = "Transcatheter", control = "Surgical"))$labels,
                   c("Transcatheter", "Surgical"))
  expect_error(h$mirror_groups(meta, c("Surgical", "Transcatheter")),
               "^GROUP_LABELS must be NULL or two labels named by the treatment levels, such as c[(]control")
  expect_error(h$mirror_groups(meta, c(control = "a", other = "b")), "^GROUP_LABELS must be NULL")
  # A bundle saved before hvtiRpropensity 0.1.10 declares no levels.
  expect_error(h$mirror_groups(list(treatment_levels = NULL, treated_level = NULL)),
               "does not declare two treatment levels")
  # The job reads them from the saved bundle.
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- lp_fixture("GROUP_LABELS <- c(control = \"Surgical\", treated = \"Transcatheter\")")
  env <- lm_eval_job(s$job)
  expect_identical(env$groups, list(levels = c("treated", "control"), labels = c("Transcatheter", "Surgical")))
})

lp_scores <- function() {
  i <- seq_len(40L)
  data.frame(id = paste0("p", i), score = (i - 0.5) / 40, group = rep(c("treated", "control"), 20L),
             weight = 0.25 + (i %% 4L) / 4, matched = as.integer(i %% 3L != 0L))
}

test_that("the treated bars are above the axis and the y-limits are symmetric, from the tallest bar", {
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  h <- lp_helpers()
  groups <- list(levels = c("treated", "control"), labels = c("Treated", "Control"))
  mh <- h$mirror_hist(lp_scores(), "unmatched", groups, 5)
  expect_true(all(mh$data$y[mh$data$group == "Treated"] >= 0))
  expect_true(all(mh$data$y[mh$data$group == "Control"] <= 0))
  # Only the all-patient bars: an unmatched figure has no matched layer.
  expect_setequal(unique(mh$data$layer), "Before")
  top <- max(abs(mh$data$y))
  expect_identical(h$mirror_limit(mh$data$y), top + max(1, ceiling(0.1 * top)))
  expect_identical(h$mirror_limit(c(3, -12)), 14)
  expect_identical(h$mirror_limit(numeric()), 1)
  p <- h$mirror_figure(mh, "unmatched")
  limits <- ggplot2::layer_scales(p)$y$get_limits()
  expect_identical(limits, c(-h$mirror_limit(mh$data$y), h$mirror_limit(mh$data$y)))
  # A tall treated side and a short control side, past the point where the
  # padding is one patient: the limits still match.
  tall <- lp_scores()[rep(seq_len(40L), 12L), ]
  tall$group[tall$group == "control"][seq_len(200L)] <- "treated"
  mh <- h$mirror_hist(tall, "unmatched", groups, 5)
  expect_gt(max(abs(mh$data$y)), 10)
  limits <- ggplot2::layer_scales(h$mirror_figure(mh, "unmatched"))$y$get_limits()
  expect_identical(limits, c(-h$mirror_limit(mh$data$y), h$mirror_limit(mh$data$y)))
})

test_that("the weighted bars are the sum of the matching weights in each group and bin", {
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  h <- lp_helpers()
  s <- lp_scores()
  groups <- list(levels = c("treated", "control"), labels = c("Treated", "Control"))
  mh <- h$mirror_hist(s, "weighted", groups, 10)
  bins <- cut(100 * s$score, seq(0, 100, 10), right = TRUE, include.lowest = TRUE)
  for (g in groups$levels) {
    label <- groups$labels[groups$levels == g]
    want <- tapply(s$weight[s$group == g], bins[s$group == g], sum)
    want[is.na(want)] <- 0
    got <- mh$data$y[mh$data$layer == "Weighted" & mh$data$group == label]
    expect_equal(abs(got), as.numeric(want), info = g)
  }
  counts <- h$mirror_counts(mh, "weighted")
  expect_identical(counts$patients, c(20L, 20L))
  expect_equal(counts$weighted, c(sum(s$weight[s$group == "treated"]), sum(s$weight[s$group == "control"])))
})

test_that("the job saves the unmatched and weighted figures, with a count table under each", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- lp_fixture()
  env <- lm_eval_job(s$job)
  graphs <- file.path(hvtiRutilities::study_dir("graphs", s$root), "outcome-analysis")
  expect_setequal(list.files(graphs), c("lp-mirror-unmatched.png", "lp-mirror-unmatched.pdf",
                                        "lp-mirror-weighted.png", "lp-mirror-weighted.pdf"))
  d <- lp_data()
  n <- c(sum(d$treatment == "treated"), sum(d$treatment == "control"))
  expect_identical(env$mirror_counts(env$mh_unmatched, "unmatched")$patients, n)
  expect_identical(env$mirror_counts(env$mh_weighted, "weighted")$patients, n)
  expect_named(env$mirror_counts(env$mh_unmatched, "unmatched"), c("group", "patients"))
})

test_that("the match flag joins by ID digest, counts both kinds of miss, and stops on another cohort", {
  h <- lp_helpers()
  bundle_ids <- paste0("d", 1:10)
  # Patients 9 and 10 have no flag; the dataset has two patients with no score.
  out <- h$mirror_join(bundle_ids, c(paste0("d", 1:8), "x1", "x2"), c(1, 0, 1, 1, 0, 1, 1, 1, 1, 1))
  expect_identical(out$matched, c(1L, 0L, 1L, 1L, 0L, 1L, 1L, 1L, 0L, 0L))
  expect_identical(out$counts$patients, c(2L, 2L))
  # Fewer than half the scored patients in the dataset: another cohort, or another identifier.
  expect_error(h$mirror_join(bundle_ids, c("d1", "d2", paste0("x", 1:8)), rep(1, 10)),
               "^Only 2 of the 10 patients the scores were computed for are in the dataset read for MATCH")
  expect_error(h$mirror_join(bundle_ids, c("d1", "d1"), c(1, 1)), "holds a patient more than once")
  # A dataset row with no score and no flag is not a flagged patient, so it is not counted as one.
  out <- h$mirror_join(bundle_ids, c(paste0("d", 1:10), "x1", "x2"), c(rep(1, 10L), 1, NA))
  expect_identical(out$counts$patients, c(0L, 1L))
})

test_that("a MATCH flag not coded 0 and 1, or with no 1 among the scored patients, stops naming MATCH", {
  h <- lp_helpers()
  bundle_ids <- paste0("d", 1:10)
  ids <- paste0("d", 1:10)
  e <- expect_error(h$mirror_join(bundle_ids, ids, rep(c("Y", "N"), 5L)), "^MATCH must be coded 0 and 1")
  expect_error(h$mirror_join(bundle_ids, ids, rep(c(1, 2), 5L)), "^MATCH must be coded 0 and 1")
  expect_error(h$mirror_join(bundle_ids, ids, rep(0, 10L)), "^MATCH flags no scored patient")
  # The message counts distinct values and shows none of them.
  expect_match(conditionMessage(e), "2 distinct values")
  expect_false(grepl("Y", conditionMessage(e), fixed = TRUE))
  # A logical column is 1 and 0, and blanks are not a value.
  out <- h$mirror_join(bundle_ids, ids, c(rep(c(TRUE, FALSE), 4L), NA, TRUE))
  expect_identical(out$matched, c(rep(c(1L, 0L), 4L), 0L, 1L))
})

test_that("an NA identifier on both sides of the join is not a pair", {
  h <- lp_helpers()
  out <- h$mirror_join(c(paste0("d", 1:9), NA), c(paste0("d", 1:9), NA, "x1"), rep(1, 11L))
  expect_identical(out$matched, c(rep(1L, 9L), 0L))
  expect_identical(out$counts$patients[1L], 1L)
})

test_that("MATCH must name a column of the dataset, not a formula term", {
  local_child_chunks()
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  for (bad in c(".", "nope")) {
    s <- lp_fixture(sprintf("MATCH <- \"%s\"", bad))
    expect_error(lm_eval_job(s$job), paste0("^MATCH names a column this dataset does not have: ", bad,
                                            "[.] Change MATCH in edit-study-choices[.]"))
  }
})

test_that("a score, weight or group the figures cannot draw stops the job, with counts only", {
  local_child_chunks()
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- lp_fixture()
  bundle <- readRDS(s$bundle)
  meta <- bundle$meta
  saved <- bundle
  bundle$data[[meta$weight_col]][5L] <- NA
  saveRDS(bundle, s$bundle)
  expect_error(lm_eval_job(s$job), "^The saved bundle holds 1 patient with a missing matching weight")
  bundle <- saved
  bundle$data[[meta$treatment_col]] <- as.character(bundle$data[[meta$treatment_col]])
  bundle$data[[meta$treatment_col]][7:8] <- "other"
  saveRDS(bundle, s$bundle)
  expect_error(lm_eval_job(s$job), "2 patients in a group the bundle does not declare")
})

test_that("a mirrored histogram whose hvtiPlotR draws the groups the other way up stops", {
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  h <- lp_helpers()
  groups <- list(levels = c("treated", "control"), labels = c("Treated", "Control"))
  real <- hvtiPlotR::hv_mirror_hist
  testthat::local_mocked_bindings(
    hv_mirror_hist = function(...) {
      mh <- real(...)
      mh$data$y <- -mh$data$y
      mh
    },
    .package = "hvtiPlotR"
  )
  expect_error(h$mirror_hist(lp_scores(), "unmatched", groups, 5), "hvtiPlotR.*orientation")
})

test_that("with MATCH the job joins the flag through the study key and keeps no identifier", {
  local_child_chunks()
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- lp_fixture("MATCH <- \"match\"")
  env <- lm_eval_job(s$job)
  d <- lp_data()
  expect_identical(env$scores$matched, d$match)
  expect_identical(env$.join$counts$patients, c(0L, 0L))
  expect_identical(env$mirror_counts(env$mh_matched, "matched")$matched,
                   c(sum(d$match[d$treatment == "treated"]), sum(d$match[d$treatment == "control"])))
  graphs <- file.path(hvtiRutilities::study_dir("graphs", s$root), "outcome-analysis")
  expect_true(all(file.exists(file.path(graphs, c("lp-mirror-matched.png", "lp-mirror-matched.pdf")))))
  # The scores hold the study-keyed digest, never the identifier.
  expect_false(any(as.character(d$ccfid) %in% env$scores$id))
  # A dataset keyed on another identifier stops by name.
  src <- readLines(s$job, warn = FALSE)
  writeLines(sub("^ID <- .*$", "ID <- \"id\"", src), s$job)
  expect_error(lm_eval_job(s$job), "identifies patients by `id`, the bundle by `ccfid`")
})

test_that("without MATCH the job draws no matched figure and joins nothing", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- lp_fixture()
  env <- lm_eval_job(s$job)
  expect_null(env$.join)
  expect_false(exists("mh_matched", envir = env, inherits = FALSE))
  expect_false(exists("match_data", envir = env, inherits = FALSE))
  expect_true(all(env$scores$matched == 0L))
  graphs <- file.path(hvtiRutilities::study_dir("graphs", s$root), "outcome-analysis")
  expect_true(all(file.exists(file.path(graphs, c("lp-mirror-unmatched.png", "lp-mirror-weighted.png")))))
  expect_false(any(file.exists(file.path(graphs, c("lp-mirror-matched.png", "lp-mirror-matched.pdf")))))
})

test_that("a scored patient with no flag is drawn as unmatched and counted, never dropped", {
  local_child_chunks()
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- lp_fixture(c("MATCH <- \"match\"", "DATASET <- \"match_file\""))
  d <- lp_data()
  # 100 of the 120 scored patients are in the file, 5 of them with the flag blank,
  # and the file holds 7 patients with no score.
  flag <- d$match[1:100]
  flag[c(3, 40, 41, 77, 100)] <- NA
  lp_register_match(s$root, 1:100, foreign = 7L, flag = flag)
  env <- lm_eval_job(s$job)
  expect_identical(env$.join$counts$patients, c(25L, 7L))
  expect_identical(env$scores$matched, c(ifelse(is.na(flag), 0L, flag), rep(0L, 20L)))
  # Every scored patient is still in the figure's data.
  counts <- env$mirror_counts(env$mh_matched, "matched")
  expect_identical(sum(counts$patients), 120L)
  expect_identical(sum(counts$matched), sum(flag == 1L, na.rm = TRUE))
  expect_identical(env$.join$counts$count,
                   c("Patients with a score and no match flag", "Patients with a match flag and no score"))
})

test_that("the job stops, saying why, when fewer than half the scored patients are in the MATCH dataset", {
  local_child_chunks()
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- lp_fixture(c("MATCH <- \"match\"", "DATASET <- \"match_file\""))
  lp_register_match(s$root, 1:59, foreign = 61L)
  expect_error(lm_eval_job(s$job), "^Only 59 of the 120 patients the scores were computed for are in the dataset read for MATCH")
  expect_error(lm_eval_job(s$job), "not the cohort the scores came from, or its ID does not identify patients")
  # Exactly half is enough.
  half <- lp_fixture(c("MATCH <- \"match\"", "DATASET <- \"match_file\""))
  lp_register_match(half$root, 1:60, foreign = 60L)
  expect_identical(lm_eval_job(half$job)$.join$counts$patients, c(60L, 60L))
})

test_that("the join reports counts only: no identifier, raw or digested, is printed or kept in an output", {
  local_child_chunks()
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- lp_fixture(c("MATCH <- \"match\"", "DATASET <- \"match_file\""))
  lp_register_match(s$root, 1:100, foreign = 7L)
  # What the job's asis chunks would print: the child chunks they knit, and the
  # tables those chunks draw.
  printed <- character()
  testthat::local_mocked_bindings(
    knit_child = function(text, envir, ...) {
      printed <<- c(printed, text)
      for (line in grep("^knitr::kable", text, value = TRUE)) {
        printed <<- c(printed, utils::capture.output(print(eval(parse(text = line), envir = envir))))
      }
      ""
    },
    .package = "knitr"
  )
  env <- lm_eval_job(s$job)
  expect_gt(length(printed), 0L)
  # The fixture's own identifiers, as whole tokens: a pattern such as 91[0-9]{5}
  # also matched a file size in the provenance on Windows, with no patient in it.
  ids <- c(lp_data()$ccfid, 9200000L + seq_len(7L))
  id_token <- paste0("(?<![A-Za-z0-9])(", paste(ids, collapse = "|"), ")(?![A-Za-z0-9])")
  digests <- env$scores$id
  expect_false(any(grepl(id_token, printed, perl = TRUE)))
  expect_false(any(vapply(digests, function(x) any(grepl(x, printed, fixed = TRUE)), logical(1L))))
  # The join result and every table built from it hold counts and nothing else.
  expect_named(env$.join, c("matched", "counts"))
  expect_named(env$.join$counts, c("count", "patients"))
  expect_false(is.null(env$match_data$provenance))
  outputs <- list(env$.join$counts, env$mirror_counts(env$mh_matched, "matched"), env$.provenance_data,
                  env$.provenance_artifacts)
  text <- paste(vapply(outputs, function(x) paste(unlist(rapply(x, as.character, how = "list")), collapse = " "),
                       character(1L)), collapse = " ")
  expect_false(grepl(id_token, text, perl = TRUE))
  expect_false(any(vapply(digests, function(x) grepl(x, text, fixed = TRUE), logical(1L))))
})

test_that("the job renders two figures without MATCH and three with it, naming no patient", {
  skip_on_cran()
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  for (match in c(FALSE, TRUE)) {
    s <- lp_fixture(if (match) "MATCH <- \"match\"" else character())
    quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
    html <- paste(readLines(sub("[.]qmd$", ".html", s$job), warn = FALSE), collapse = "\n")
    figures <- c("lp-mirror-unmatched", "lp-mirror-weighted", if (match) "lp-mirror-matched")
    graphs <- file.path(hvtiRutilities::study_dir("graphs", s$root), "outcome-analysis")
    expect_setequal(sub("[.]png$", "", list.files(graphs, "[.]png$")), figures)
    expect_setequal(sub("[.]pdf$", "", list.files(graphs, "[.]pdf$")), figures)
    shown <- unique(regmatches(html, gregexpr("id=\"fig-mirror-[a-z]+\"", html))[[1L]])
    expect_setequal(shown, paste0("id=\"fig-", sub("^lp-", "", figures), "\""))
    # No patient identifier, raw or digested, appears in the report.
    d <- lp_data()
    key <- hvtiRtemplates:::.study_id_key(s$root)
    # Embedded images and fonts are base64 data URIs, whose text can spell any short digit run by chance:
    # on Linux one held "91000033", which contains a fixture ID. They carry no patient data, so they are
    # dropped before the scan, and an ID counts only as a whole token. The provenance JSON is not a data
    # URI, so it is still scanned.
    text <- gsub("data:[A-Za-z0-9.+/-]+(;[^,\"')]*)?,[^\"') ]*", "", html, perl = TRUE)
    for (id in c(as.character(d$ccfid), hvtiRtemplates:::.id_digest(d$ccfid, key))) {
      at <- regexpr(paste0("(?<![A-Za-z0-9])", id, "(?![A-Za-z0-9])"), text, perl = TRUE)[[1L]]
      # On a hit, show the text around it, so a CI failure says where it came from.
      expect_false(at > 0L, info = if (at > 0L) substring(text, max(1L, at - 120L), at + 120L) else id)
    }
    payload <- hvtiRtemplates:::.extract_provenance(html, managed = TRUE)
    expect_identical(payload$mirror$model_file, "lm-propensity_binary.rds")
    expect_identical(payload$mirror$model_set, "outcome-analysis")
    expect_false(is.null(payload$analysis))
    if (match) {
      expect_identical(payload$mirror$match, "match")
      expect_identical(unlist(payload$mirror$join), c(no_flag = 0L, no_score = 0L))
      expect_true("match" %in% vapply(payload$data, function(r) r$role, character(1L)))
    }
  }
})
