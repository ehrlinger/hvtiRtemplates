# sid-stability, run chunk by chunk from the installed file (helper-rf.R,
# helper-sid.R). Only the tests that fit SID skip on CRAN.

test_that("stab_ari is 1 for the same partition under any labels, and near 0 for an unrelated one", {
  h <- sid_stability_helpers_env()
  a <- rep(1:3, each = 10)
  expect_equal(h$stab_ari(a, a), 1)
  expect_equal(h$stab_ari(a, c("z", "x", "y")[a]), 1)
  expect_lt(abs(h$stab_ari(a, rep(1:3, 10))), 0.1)
})

test_that("stab_best_match lets two refit clusters take one label and leaves a label untaken", {
  h <- sid_stability_helpers_env()
  ref <- c(rep("A", 4), rep("B", 4), rep("C", 2))
  # Refit cluster 1 and 2 split A's patients; 3 holds B and C together.
  draw <- c(1, 1, 2, 2, 3, 3, 3, 3, 3, 3)
  out <- h$stab_best_match(draw, ref)
  expect_identical(out, c(rep("A", 4), rep("B", 6)))
  expect_false("C" %in% out)
})

test_that("stab_best_match breaks a tie by the reference label, not PAM's numbering", {
  h <- sid_stability_helpers_env()
  ref <- c("A", "A", "B", "B")
  # The single refit cluster overlaps A and B equally.
  expect_identical(h$stab_best_match(c(7, 7, 7, 7), ref), rep("A", 4))
  expect_identical(h$stab_best_match(c(2, 2, 2, 2), rev(ref)), rep("A", 4))
})

test_that("stab_jaccard is 0 for a group no refit cluster took", {
  h <- sid_stability_helpers_env()
  ref <- c("A", "A", "B", "B")
  expect_equal(h$stab_jaccard(c("A", "A", "A", "A"), ref, "B"), 0)
  expect_equal(h$stab_jaccard(c("A", "A", "A", "A"), ref, "A"), 0.5)
})

test_that("stab_coassoc is the share of labelings that pair two patients, and stab_pac counts the ambiguous pairs", {
  h <- sid_stability_helpers_env()
  labels <- cbind(c(1, 1, 2, 2), c(1, 1, 1, 2), c(1, 2, 2, 2), c(1, 1, 2, 2))
  co <- h$stab_coassoc(labels)
  expect_equal(diag(co), rep(1, 4))
  expect_equal(co, t(co))
  expect_equal(co[1, 2], 0.75)
  expect_equal(co[2, 3], 0.5)
  expect_equal(co[1, 4], 0)
  v <- co[upper.tri(co)]
  expect_equal(h$stab_pac(co), mean(v > 0.1 & v < 0.9))
  expect_equal(h$stab_pac(co, c(0, 1)), mean(v > 0 & v < 1))
})

test_that("stab_pct keeps a decimal under 1% and rounds halves up", {
  h <- sid_stability_helpers_env()
  expect_identical(h$stab_pct(2 / 369), "0.5%")
  expect_identical(h$stab_pct(9 / 40), "23%")
  expect_identical(h$stab_pct(0), "0%")
  expect_identical(h$stab_pct(NA), "-")
})

test_that("sid-stability refits the planted clusters, agrees with them and writes its handoff", {
  skip_on_cran()
  env <- sid_fit_first()
  sid_clusters_after(env)
  sid_stability_after(env)
  expect_identical(env$seeds, 101:103)
  expect_identical(nrow(env$stab$by_refit), 3L)
  # Three well-separated planted groups: every refit finds them.
  expect_true(all(env$stab$by_refit$ari_groups > 0.9))
  expect_true(all(env$stab$by_group$matched))
  expect_equal(dim(env$co), rep(length(env$.ids), 2L))
  out <- readRDS(env$set_path("estimates", "sid-stability.rds"))
  expect_identical(out$k, 3L)
  expect_identical(nrow(out$by_group), 9L)
  expect_null(out$drop)
  expect_false(any(grepl("^[0-9]+$", rownames(out$coassoc))))
})

test_that("sid-stability fills values from sid-fit's imputation cache and refuses one that no longer matches", {
  skip_on_cran()
  env <- sid_fit_first()
  sid_clusters_after(env)
  sid_stability_after(env)
  expect_false(anyNA(env$x))
  # The cached imputation, with one observed value changed, must not be used.
  path <- file.path(env$CACHE_DIR, "sid-fit-impute-1.rds")
  rec <- readRDS(path)
  imp <- rec$value
  done <- mice::complete(imp, 1)
  first <- which(!is.na(imp$data$b))[1L]
  imp$data$b[first] <- imp$data$b[first] + 100
  rec$value <- imp
  saveRDS(rec, path)
  expect_error(sid_stability_after(env), "does not match the rebuilt cohort")
  expect_true(is.data.frame(done))
})

test_that("DROP_VARS runs a second set of refits and TRACK reports a share per group", {
  skip_on_cran()
  d <- sid_data()
  d$trk <- as.integer(d$truth == 3L)
  env <- sid_fit_first(d)
  sid_clusters_after(env)
  choices <- utils::modifyList(sid_stability_choices, list(DROP_VARS = "e", TRACK = "trk"))
  sid_stability_after(env, choices)
  expect_identical(nrow(env$stab_drop$by_refit), 3L)
  expect_false(anyNA(env$stab$by_group$track[env$stab$by_group$matched]))
  out <- readRDS(env$set_path("estimates", "sid-stability.rds"))
  expect_identical(out$drop$vars, "e")
})

test_that("sid-stability refuses a DROP_VARS that sid-fit did not cluster on, and seeds that include sid-fit's", {
  skip_on_cran()
  env <- sid_fit_first()
  sid_clusters_after(env)
  expect_error(sid_stability_after(env, utils::modifyList(sid_stability_choices, list(DROP_VARS = "zz"))),
               "did not cluster on")
  expect_error(sid_stability_after(env, utils::modifyList(sid_stability_choices, list(SEED_OFFSET = 0))),
               "include sid-fit's own seed")
})
