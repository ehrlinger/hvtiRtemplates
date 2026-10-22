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
  D <- as.matrix(stats::dist(x))
  arm <- c("A", "A", "A", "B", "B")
  r <- h$vt_ood(D, names(x), arm, c("A", "B"))
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
  D <- as.matrix(stats::dist(c(a1 = 0, a2 = 1, b1 = 0.5)))
  D["b1", c("a1", "a2")] <- D[c("a1", "a2"), "b1"] <- NA
  r <- h$vt_ood(D, rownames(D), c("A", "A", "B"), c("A", "B"))
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
  d <- vt_data(); d$x1[c(20, 40, 60)] <- NA
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
  again <- env$vt_curves(env$.forests, env$.train_ids, shuffled, env$ID, env$ARM, env$ARMS, no_arm = rev(env$.no_arm))
  key <- function(x) x[order(x$ID, x$arm_of_curve, x$time), ]
  expect_equal(key(again)$surv, key(env$.curves)$surv)
})

test_that("a patient's own-arm curve is out of bag", {
  skip_on_cran()
  env <- vt_fit_first(labels = c(vt_fit_labels, "fit", "curves-helper", "curves"))
  fA <- env$.forests[["A"]]
  first <- env$d[[env$ID]][env$d[[env$ARM]] %in% "A"][1]
  own <- env$.curves[env$.curves$ID == first & env$.curves$arm_of_curve == "A", "surv"]
  expect_equal(own, unname(fA$survival.oob[1, ]))
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
})
