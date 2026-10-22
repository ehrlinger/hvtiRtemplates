test_that("vt-fit reads the cohort and resolves the predictors", {
  skip_on_cran()
  env <- vt_fit_first()
  expect_setequal(env$.predictors, c("xs", "x1", "g1"))
  expect_equal(sum(env$.no_arm), 10L)
  expect_equal(sum(env$.treated), 290L)
})

test_that("the predictor contract refuses the arm, the outcome and the ID", {
  skip_on_cran()
  for (leak in c("arm", "time", "event", "ccfid")) {
    ch <- utils::modifyList(vt_choices, list(PREDICTORS = c("xs", leak)))
    expect_error(vt_fit_first(choices = ch), "PREDICTORS", info = leak)
  }
})

test_that("an arm with fewer than 2 patients stops, naming the arm and its counts", {
  skip_on_cran()
  d <- vt_data()
  d$arm[which(d$arm == "B")[-1L]] <- "A"
  expect_error(vt_fit_first(data = d), "B has 1 patient\\(s\\)")
})

test_that("na.omit that leaves an arm with 1 patient stops, naming the arm", {
  skip_on_cran()
  d <- vt_data()
  b <- which(d$arm == "B")
  d$x1[b[-1L]] <- NA
  ch <- utils::modifyList(vt_choices, list(NA_ACTION = "na.omit"))
  expect_error(vt_fit_first(data = d, choices = ch), "B has 1 patient\\(s\\)")
})

test_that("a treated patient with no status reports the missing outcome", {
  skip_on_cran()
  d <- vt_data()
  d$event[which(d$arm == "A")[1L]] <- NA
  expect_error(vt_fit_first(data = d), "no outcome")
})

test_that("an ARM value in neither ARMS nor NO_ARM stops", {
  skip_on_cran()
  d <- vt_data()
  d$arm[1L] <- "C"
  expect_error(vt_fit_first(data = d), "neither in ARMS nor NO_ARM")
})

test_that("patient IDs are digested on read", {
  skip_on_cran()
  env <- vt_fit_first()
  expect_identical(env$d[[env$ID]][1:3],
                   hvtiRtemplates:::.id_digest(1:3, hvtiRtemplates:::.study_id_key(env$.root)))
})

test_that("EXCLUDE drops post-treatment columns", {
  skip_on_cran()
  ch <- utils::modifyList(vt_choices, list(EXCLUDE = "x1"))
  expect_setequal(vt_fit_first(choices = ch)$.predictors, c("xs", "g1"))
})

test_that("na.omit drops and counts patients missing a predictor", {
  skip_on_cran()
  d <- vt_data()
  d$x1[1:3] <- NA
  env <- vt_fit_first(data = d, choices = utils::modifyList(vt_choices, list(NA_ACTION = "na.omit")))
  expect_equal(nrow(env$d), 297L)
})

test_that("with stacked imputations only IMPUTATION_USE reaches the job", {
  skip_on_cran()
  d1 <- vt_data()
  d1$imp <- 1L
  d2 <- vt_data()
  d2$imp <- 2L
  d2$xs <- d2$xs + 100
  ch <- utils::modifyList(vt_choices, list(IMPUTATION = "imp", IMPUTATION_USE = 2L))
  env <- vt_fit_first(data = rbind(d1, d2), choices = ch)
  expect_equal(nrow(env$d), 300L)
  expect_gt(min(env$d$xs), 90)
})

test_that("vt_ood flags a patient beyond the arm's largest nearest-neighbour gap", {
  h <- vt_helpers()
  # Arm A at 0, 1, 2 (largest within-arm gap 1); arm B at 2.5 and 10.
  x <- c(a1 = 0, a2 = 1, a3 = 2, b1 = 2.5, b2 = 10)
  dm <- as.matrix(stats::dist(x))
  arm <- c("A", "A", "A", "B", "B")
  r <- h$vt_ood(dm, names(x), arm, c("A", "B"))
  b <- r[r$arm == "A" & r$ID %in% c("b1", "b2"), ]
  expect_equal(b$in_distribution[b$ID == "b1"], TRUE)
  expect_equal(b$in_distribution[b$ID == "b2"], FALSE)
  expect_match(b$reason[b$ID == "b2"], "A")
})

test_that("a distance exactly at the reference is in distribution (strict >)", {
  h <- vt_helpers()
  x <- c(a1 = 0, a2 = 1, b1 = 2)  # b1's distance to arm A is 1, the reference is 1
  r <- h$vt_ood(as.matrix(stats::dist(x)), names(x), c("A", "A", "B"), c("A", "B"))
  expect_true(r$in_distribution[r$ID == "b1" & r$arm == "A"])
})

test_that("a no-arm row must pass against both arms", {
  h <- vt_helpers()
  x <- c(a1 = 0, a2 = 1, b1 = 20, b2 = 21, n1 = 0.5)
  r <- h$vt_ood(as.matrix(stats::dist(x)), names(x), c("A", "A", "B", "B", NA), c("A", "B"))
  r$method <- "gower"  # aggregate() drops rows whose group is NA, as the caller's method never is
  n1 <- r[r$ID == "n1", ]
  expect_setequal(n1$arm, c("A", "B"))
  expect_false(all(n1$in_distribution))
  expect_false(h$vt_combine(r, "any")$elig[h$vt_combine(r, "any")$ID == "n1"])
})

test_that("a patient with no distance to an arm is out of distribution, not NA", {
  h <- vt_helpers()
  dm <- as.matrix(stats::dist(c(a1 = 0, a2 = 1, b1 = 0.5)))
  dm["b1", c("a1", "a2")] <- dm[c("a1", "a2"), "b1"] <- NA
  r <- h$vt_ood(dm, rownames(dm), c("A", "A", "B"), c("A", "B"))
  b1 <- r[r$ID == "b1" & r$arm == "A", ]
  expect_false(b1$in_distribution)
  expect_match(b1$reason, "no comparable")
  expect_false(anyNA(r$in_distribution))
})

test_that("Gower on a patient missing every predictor gives a flag", {
  skip_if_not_installed("cluster")
  h <- vt_helpers()
  d <- data.frame(ID = as.character(1:5), x = c(0, 1, 2, 1.5, NA), g = factor(c("u", "v", "u", "v", NA)))
  r <- h$vt_ood(h$vt_elig_gower(d, c("x", "g"), "ID"), d$ID, c("A", "A", "A", "B", "B"), c("A", "B"))
  expect_false(r$in_distribution[r$ID == "5" & r$arm == "A"])
})

test_that("methods combine by any and all, with one row shape", {
  h <- vt_helpers()
  base <- data.frame(ID = c("p1", "p2", "p3"), method = NA, arm = "A", nn_id = "q", distance = 1,
                     reference = 1, ratio = 1, in_distribution = TRUE, reason = "")
  g <- transform(base, method = "gower", in_distribution = c(FALSE, TRUE, TRUE))
  s <- transform(base, method = "sid", in_distribution = c(TRUE, FALSE, TRUE))
  expect_identical(names(g), names(s))
  any_ <- h$vt_combine(rbind(g, s), "any")
  all_ <- h$vt_combine(rbind(g, s), "all")
  expect_equal(any_$elig[order(any_$ID)], c(FALSE, FALSE, TRUE))
  expect_equal(all_$elig[order(all_$ID)], c(TRUE, TRUE, TRUE))
})

test_that("the sid method uses a set's distance and refuses a missing patient", {
  h <- vt_helpers()
  ids <- c("1", "2", "3")
  path <- withr::local_tempfile(fileext = ".rds")
  saveRDS(list(dist = stats::dist(c(`1` = 0, `2` = 1, `3` = 2))), path)
  m <- h$vt_elig_sid(path, ids, cfg = NULL, read = function(p) list(value = readRDS(p)))
  expect_equal(dimnames(m)[[1]], ids)
  expect_false(is.null(attr(m, "read")))
  expect_error(h$vt_elig_sid(path, c(ids, "4"), cfg = NULL, read = function(p) list(value = readRDS(p))),
               "1 patient")
})

test_that("the sid method checks the key fingerprint of a set", {
  h <- vt_helpers()
  ids <- c("1", "2", "3")
  key <- strrep("a", 64)
  path <- withr::local_tempfile(fileext = ".rds")
  saveRDS(1, path)
  d <- stats::dist(c(`1` = 0, `2` = 1, `3` = 2))
  stub <- function(fp) function(p) list(value = list(dist = d, id_key = fp))
  expect_error(h$vt_elig_sid(path, ids, cfg = NULL, key = key, read = stub("0000000000000000")),
               "different study key")
  m <- h$vt_elig_sid(path, ids, cfg = NULL, key = key, read = stub(hvtiRtemplates:::.id_key_fingerprint(key)))
  expect_equal(dimnames(m)[[1]], ids)
})

test_that("the propensity sensitivity renders with missing predictors under na.impute", {
  skip_on_cran()
  d <- vt_data()
  d$x1[c(20, 40, 60)] <- NA
  env <- vt_fit_first(data = d)
  expect_false(anyNA(env$.elig$elig_propensity))
})

test_that("vt-fit flags the planted outliers against arm B", {
  skip_on_cran()
  env <- vt_fit_first()
  flagged <- env$.elig$ID[!env$.elig$elig_gower]
  expect_true(all(vt_digest(env, which(vt_data()$arm == "A")[1:5]) %in% flagged))
})

test_that("vt_rmst integrates a step curve to the horizon and takes the difference in ARMS order", {
  h <- vt_helpers()
  curves <- data.frame(ID = "p", arm_of_curve = rep(c("A", "B"), each = 3),
                       time = rep(c(1, 2, 3), 2), surv = c(0.9, 0.8, 0.7, 0.5, 0.5, 0.5))
  r <- h$vt_rmst(curves, horizon = 2, arms = c("A", "B"), followup = c(A = 5, B = 5))
  expect_equal(r$rmst_A, 1 * 1 + 1 * 0.9)
  expect_equal(r$rmst_B, 1 * 1 + 1 * 0.5)
  expect_equal(r$diff, r$rmst_A - r$rmst_B)
  expect_equal(r$risk_A, 1 - 0.8)
})

test_that("a horizon beyond either arm's follow-up stops", {
  h <- vt_helpers()
  curves <- data.frame(ID = "p", arm_of_curve = c("A", "B"), time = 1, surv = 0.9)
  expect_error(h$vt_rmst(curves, horizon = 6, arms = c("A", "B"), followup = c(A = 8, B = 5)),
               "HORIZON.*B")
})

test_that("vt_curves keys by ID, whatever the row order", {
  skip_on_cran()
  env <- vt_fit_first(labels = c(vt_fit_labels, "fit", "curves-helper", "curves"))
  shuffled <- env$d[rev(seq_len(nrow(env$d))), ]
  again <- env$vt_curves(env$.forests, env$.train_ids, shuffled, env$ID, env$ARM, env$ARMS,
                         no_arm = rev(env$.no_arm), seed = -abs(env$SEED))
  key <- function(x) x[order(x$ID, x$arm_of_curve, x$time), ]
  expect_equal(key(again)$surv, key(env$.curves)$surv)
})

test_that("a patient's own-arm curve is out of bag", {
  skip_on_cran()
  env <- vt_fit_first(labels = c(vt_fit_labels, "fit", "curves-helper", "curves"))
  forest_a <- env$.forests[["A"]]
  first <- env$d[[env$ID]][env$d[[env$ARM]] %in% "A"][1]
  own <- env$.curves[env$.curves$ID == first & env$.curves$arm_of_curve == "A", "surv"]
  expect_equal(own, unname(forest_a$survival.oob[1, ]))
})

test_that("the twin difference recovers the planted effect", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_fit_labels_all)
  r <- merge(env$.rmst, data.frame(ID = vt_digest(env, vt_data()$ccfid), xs = vt_data()$xs))
  r <- r[r$elig, ]
  expect_gt(stats::median(r$diff[r$xs > 1]), 0)
  expect_lt(stats::median(r$diff[r$xs < -1]), 0)
})

test_that("vt-fit saves one handoff with every element", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_fit_labels_all)
  h <- readRDS(env$set_path("estimates", "vt.rds"))
  expect_named(h, c("rmst", "curves", "forests", "eligibility", "predictors", "settings"))
  expect_true(all(c("elig", "elig_gower", "elig_propensity", "elig_none", "diff", "log_rr") %in% names(h$rmst)))
  expect_false(is.null(attr(h, "hvti_provenance")))
  expect_setequal(h$settings$performance$arm, c("A", "B"))
  expect_true(all(c("events", "c_index", "lower") %in% names(h$settings$performance)))
})

test_that("curves are reproducible when predictors are missing under na.impute", {
  skip_on_cran()
  d <- vt_data()
  d$x1[c(which(d$arm == "B")[1:6], which(is.na(d$arm))[1:3])] <- NA
  labs <- c(vt_fit_labels, "fit", "curves-helper", "curves")
  one <- vt_fit_first(data = d, labels = labs)
  two <- vt_fit_first(data = d, labels = labs)
  expect_identical(one$.curves$surv, two$.curves$surv)
  # Two fresh runs share an RNG history, so they can agree with no seed at all.
  # Re-run only `curves` from a different global RNG state: the same SEED must still
  # give the same curves, and a different SEED must give different ones.
  curves_at <- function(seed, rng) {
    set.seed(rng)
    one$SEED <- seed
    rf_run("vt", "fit", "curves", one, vt_choices)  # nolint: object_usage_linter.
    one$.curves$surv
  }
  expect_identical(curves_at(1L, 100L), curves_at(1L, 200L))
  expect_false(identical(curves_at(1L, 100L), curves_at(2L, 100L)))
})

test_that("the saved handoff carries no patient ID and no captured environment", {
  skip_on_cran()
  d <- vt_data()
  d$ccfid <- 7350000000 + d$ccfid
  env <- vt_fit_first(data = d, labels = vt_fit_labels_all)
  h <- readRDS(env$set_path("estimates", "vt.rds"))
  # rfsrc 3.9.0 keeps no $formula or $terms; the formula is stored in $call.
  f <- h$forests[[1]]
  expect_identical(environment(f$call$formula), globalenv())
  expect_identical(environment(h$eligibility$ps$meta$formula), globalenv())
  # The propensity forest keeps its own call; its formula must not capture the job environment either.
  pf <- h$eligibility$ps$models$forest
  expect_identical(environment(pf$call$formula), globalenv())
  held <- rf_files_holding(dirname(env$set_path("estimates", "vt.rds")), as.character(d$ccfid))
  expect_identical(held, character())
})

test_that("vt-explain reads vt.rds and never grows a forest", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_fit_labels_all)
  vt_explain(env)
  expect_true(all(c("gower", "propensity", "none") %in% env$.sens$rule))
  # The eligibility mask is `.eligible`; `.in` is setup's source path and must stay free for provenance.
  expect_type(env$.eligible, "logical")
  expect_false(exists(".in", envir = env, inherits = FALSE) && is.logical(env$.in))
  src <- readLines(template_path("vt", "explain"), warn = FALSE)
  expect_false(any(grepl("rfsrc(", src, fixed = TRUE)))
})

test_that("vt-explain stops naming the file when no fit has run", {
  skip_on_cran()
  env <- rf_env(vt_data())
  expect_error(vt_explain(env, c("setup", "edit-study-choices", "handoff"), list()), "vt.rds")
})

test_that("vt-explain reads the fit's own selection, stacked imputations included", {
  skip_on_cran()
  d1 <- vt_data()
  d1$imp <- 1L
  d2 <- vt_data()
  d2$imp <- 2L
  d2$x1 <- d2$x1 + 100
  env <- vt_fit_first(data = rbind(d1, d2), labels = vt_fit_labels_all,
                      choices = utils::modifyList(vt_choices, list(IMPUTATION = "imp", IMPUTATION_USE = 2L)))
  vt_explain(env, vt_explain_labels_all, list(STRATIFY = "x1", BOOT = 0L, GAIN_MIN = 0, SAVE_FIGURES = FALSE))
  expect_equal(nrow(env$.d_all), 300L)
  expect_gt(min(env$.strata$stratum |> as.numeric()), 90)
  # The stacked rows of imputation 1 are gone: x1 is the shifted one.
  expect_gt(min(env$.d_all$x1), 90)
})

test_that("overlap weights are 1 - e on the first arm and e on the second", {
  src <- readLines(template_path("vt", "explain"), warn = FALSE)
  env <- new.env()
  eval(parse(text = rf_chunk(src, "overlap-weights")), envir = env)  # nolint: object_usage_linter.
  ps <- data.frame(id = c("p", "q", "r"), arm = c("A", "B", "A"), prob_t = c(0.8, 0.3, 0.1))
  expect_equal(env$vt_overlap_weights(ps, c("r", "p", "q"), "id", "arm", c("A", "B")), c(0.9, 0.2, 0.3))
})

test_that("the stratifier joins sid-clusters on the ID digest", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_fit_labels_all)
  sid_dir <- file.path(dirname(dirname(env$set_path("estimates", "vt.rds"))), "dead-sid")
  dir.create(sid_dir, recursive = TRUE)
  key <- hvtiRtemplates:::.study_id_key(env$.root)
  saveRDS(list(clusters = data.frame(id = factor(vt_digest(env, factor(vt_data()$ccfid))),
                                     cluster = ifelse(vt_data()$xs > 0, "hi", "lo")),
               id_key = hvtiRtemplates:::.id_key_fingerprint(key)),
          file.path(sid_dir, "sid-clusters.rds"))
  vt_explain(env, vt_explain_labels_all,
             list(STRATIFY = list(set = "dead-sid"), BOOT = 0L, GAIN_MIN = 0, SAVE_FIGURES = FALSE,
                  .vt_read_sid = function(p) {
                    list(value = readRDS(p), lineage = list(data = list(), artifacts = list()), record = list(path = p))
                  }))
  expect_setequal(unique(env$.strata$stratum), c("hi", "lo"))
  expect_equal(sum(is.na(merge(env$r, env$.strata, by = "ID", all.x = TRUE)$stratum)), 0L)
})

test_that("a rare factor level does not abort the bootstrap", {
  skip_on_cran()
  d <- vt_data()
  d$rare <- factor(ifelse(seq_len(nrow(d)) %in% c(3, 150), "yes", "no"))
  env <- vt_fit_first(data = d, labels = vt_fit_labels_all,
                      choices = utils::modifyList(vt_choices, list(PREDICTORS = c("xs", "x1", "g1", "rare"))))
  vt_explain(env, vt_explain_labels_all, list(STRATIFY = NULL, BOOT = 50L, GAIN_MIN = 0, SAVE_FIGURES = FALSE))
  row <- env$.betas[startsWith(env$.betas$variable, "rare"), ]
  expect_match(row$variable, "yes vs no")
  expect_gt(row$unestimable, 0L)
})

test_that("BOOT = 0 skips the intervals and the betas still render", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_fit_labels_all)
  vt_explain(env, vt_explain_labels_all)
  expect_true(all(is.na(env$.betas$lower)))
  expect_true(all(is.finite(env$.betas$beta)))
})

# A sid-clusters fixture for the stratifier tests; `clusters` and `id_key` are overridable.
vt_sid_fixture <- function(env, clusters, id_key = NULL) {
  sid_dir <- file.path(dirname(dirname(env$set_path("estimates", "vt.rds"))), "dead-sid")
  dir.create(sid_dir, recursive = TRUE, showWarnings = FALSE)
  key <- hvtiRtemplates:::.study_id_key(env$.root)
  saveRDS(list(clusters = clusters, id_key = id_key %||% hvtiRtemplates:::.id_key_fingerprint(key)),
          file.path(sid_dir, "sid-clusters.rds"))
}
vt_sid_reader <- function(p) {
  list(value = readRDS(p), lineage = list(data = list(), artifacts = list()), record = list(path = p))
}
vt_strat_choices <- function(column = NULL) {
  list(STRATIFY = list(set = "dead-sid", column = column), BOOT = 0L, GAIN_MIN = 0, SAVE_FIGURES = FALSE,
       .vt_read_sid = vt_sid_reader)
}

test_that("sid-clusters digested under another study key stop the stratifier", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_fit_labels_all)
  d <- vt_data()
  vt_sid_fixture(env, data.frame(id = vt_digest(env, factor(d$ccfid)), cluster = "a"), id_key = "0000000000000000")
  expect_error(vt_explain(env, vt_explain_labels_all, vt_strat_choices()), "different study key")
})

test_that("a sid set with no clusters stops the stratifier", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_fit_labels_all)
  vt_sid_fixture(env, NULL)
  expect_error(vt_explain(env, vt_explain_labels_all, vt_strat_choices()), "set K in sid-clusters")
})

test_that("a stratifier column the set lacks stops and names what it has", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_fit_labels_all)
  d <- vt_data()
  vt_sid_fixture(env, data.frame(id = vt_digest(env, factor(d$ccfid)), cluster = "a"))
  expect_error(vt_explain(env, vt_explain_labels_all, vt_strat_choices("group")), 'no column "group".*id, cluster')
})

test_that("a stratum cell under 5 patients shows no median but keeps its n", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_fit_labels_all)
  d <- vt_data()
  tiny <- which(d$arm == "B")[1:3]
  vt_sid_fixture(env, data.frame(id = vt_digest(env, factor(d$ccfid)), cluster = ifelse(seq_len(nrow(d)) %in% tiny, "tiny", "big")))
  vt_explain(env, vt_explain_labels_all, vt_strat_choices())
  cell <- env$.st[env$.st$stratum == "tiny" & env$.st$arm == "B", ]
  expect_equal(nrow(cell), 1L)
  expect_true(is.na(cell$median))
  expect_false(is.na(cell$n))
  expect_lt(cell$n, 5L)
})

test_that("tbl-benefit honours GAIN_MIN and splits the no-arm patients between the arms", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_fit_labels_all)
  vt_explain(env, vt_explain_labels_all, list(STRATIFY = NULL, BOOT = 0L, GAIN_MIN = 1e6, SAVE_FIGURES = FALSE))
  expect_equal(nrow(env$.benefit), 0L)
  env2 <- vt_fit_first(labels = vt_fit_labels_all)
  vt_explain(env2, vt_explain_labels_all, list(STRATIFY = NULL, BOOT = 0L, GAIN_MIN = 0, SAVE_FIGURES = FALSE))
  expect_equal(sum(table(env2$.future$favours)), sum(env2$.eligible & env2$r$arm == "none"))
})

test_that("VP_SET reads a vp-fit screen's selected set, minus EXCLUDE", {
  skip_on_cran()
  screen <- list(selected = c("xs", "x1"), coverage = data.frame(variable = c("xs", "x1", "g1")))
  env <- vt_with_screen(screen, utils::modifyList(vt_choices, list(VP_SET = "dead-vp", EXCLUDE = "x1")))
  expect_equal(env$.predictors, "xs")
})

test_that("a screen that saw the arm is refused", {
  skip_on_cran()
  screen <- list(selected = "xs", coverage = data.frame(variable = c("xs", "arm")))
  expect_error(vt_with_screen(screen, utils::modifyList(vt_choices, list(VP_SET = "dead-vp"))), "treatment-blind")
})

# Keyed on an MRN (no ccfid, so read_job_data() falls back to it): the job
# digests it, and no file it writes holds one.
test_that("no MRN reaches any file vt-fit or vt-explain generates", {
  skip_on_cran()
  d <- vt_data()
  # Realistic ten-digit values: a short one such as 00000001 reads as the number 1,
  # whose double bytes sit in every .rds, so the scan would flag a file that holds no ID.
  d$MRN <- sprintf("73%08d", d$ccfid)
  d$ccfid <- NULL
  env <- vt_fit_first(data = d, labels = vt_fit_labels_all, choices = utils::modifyList(vt_choices, list(ID = "ccfid")))
  vt_explain(env, vt_explain_labels_all)
  # Only what the jobs wrote: the set's estimates. The fixture's input dataset
  # under datasets/ holds the MRNs on purpose.
  set_dir <- dirname(env$set_path("estimates", "vt.rds"))
  expect_identical(rf_files_holding(set_dir, d$MRN), character())  # nolint: object_usage_linter.
})

test_that("vt-fit and vt-explain render end to end", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if(is.null(quarto::quarto_path()), "Quarto is not installed")
  # nolint start: object_usage_linter.
  rf_skip_unless_stack(unique(c(rf_template_packages("vt", "fit"), rf_template_packages("vt", "explain"))))
  # nolint end
  out <- vt_render_fixture()
  expect_true(all(file.exists(out$outputs)))
})

test_that("a level carried only by the rest of the arm still shows, at 0% for the other group", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_fit_labels_all)
  vt_explain(env, vt_explain_labels_all)
  expect_gt(nrow(env$.benefit), 0L)
  env$.d_all$g1 <- as.character(env$.d_all$g1)
  env$.d_all$g1[!env$.d_all[[env$.vt$settings$id]] %in% env$.benefit$ID] <- "z"
  vt_explain(env, "tbl-benefit")
  z <- env$.ben_tab[env$.ben_tab$variable == "g1: z", ]
  expect_gt(nrow(z), 0L)
  expect_true(all(z$other_arm_favoured == "0%"))
  expect_false(any(is.na(env$.ben_tab$other_arm_favoured)))
})

test_that("vt-explain stops when the dataset changed since vt-fit ran, though the manifest verifies", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_fit_labels_all)
  dd <- hvtiRutilities::study_dir("datasets", env$.root)
  f <- file.path(dd, "cohort.rds")
  d <- readRDS(f)
  d$x1[1L] <- d$x1[1L] + 1
  saveRDS(d, f)
  # Re-register the changed file, so the manifest agrees with it and only vt-explain's own lineage check can object.
  withr::with_dir(env$.root, utils::capture.output(suppressMessages(hvtiRutilities::update_manifest())))
  expect_error(hvtiRutilities::verify_manifest(file.path(env$.root, "manifest.yaml")), NA)
  expect_error(vt_explain(env, c("setup", "edit-study-choices", "handoff", "explain-data")),
               "The dataset changed since vt-fit ran")
})
