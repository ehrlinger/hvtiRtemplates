# The sid templates, run chunk by chunk from the installed files (helper-rf.R,
# helper-sid.R). Only tests that fit SID skip on CRAN.

test_that("sid_align_labels keeps a parent's letter on its largest child", {
  h <- sid_helpers_env()
  # K = 2: cluster 1 has 6 patients, cluster 2 has 4. K = 3 splits cluster 1
  # into 4 + 2; the 4 keep the parent's letter, the 2 take a fresh one.
  mat <- data.frame(pm2 = c(1, 1, 1, 1, 1, 1, 2, 2, 2, 2), pm3 = c(3, 3, 3, 3, 1, 1, 2, 2, 2, 2))
  out <- h$sid_align_labels(mat)
  expect_identical(colnames(out), c("pm2", "pm3"))
  expect_identical(out[, "pm2"], rep(c("A", "B"), c(6, 4)))
  expect_identical(out[, "pm3"], c(rep("A", 4), "C", "C", rep("B", 4)))
})

test_that("sid_align_labels does not depend on how PAM numbered its clusters", {
  h <- sid_helpers_env()
  mat <- data.frame(pm2 = c(1, 1, 1, 1, 1, 1, 2, 2, 2, 2), pm3 = c(3, 3, 3, 3, 1, 1, 2, 2, 2, 2))
  renumbered <- data.frame(pm2 = 3 - mat$pm2, pm3 = c(`1` = 2, `2` = 3, `3` = 1)[as.character(mat$pm3)])
  expect_identical(unname(h$sid_align_labels(renumbered)), unname(h$sid_align_labels(mat)))
})

test_that("sid_align_labels applies an override and rejects an unknown cluster id", {
  h <- sid_helpers_env()
  mat <- data.frame(pm2 = c(1, 1, 1, 2, 2), pm3 = c(1, 1, 3, 2, 2))
  out <- h$sid_align_labels(mat, overrides = list(pm2 = c("1" = "B", "2" = "A")))
  expect_identical(out[, "pm2"], c("B", "B", "B", "A", "A"))
  expect_error(h$sid_align_labels(mat, overrides = list(pm2 = c("7" = "B"))), "unknown cluster id")
})

test_that("sid_align_labels never gives two clusters one letter when an override takes it", {
  h <- sid_helpers_env()
  # Found in review: an override gives cluster 1 at K = 3 the letter "B", which
  # the lineage rule would otherwise hand to cluster 2, the child of B.
  mat <- data.frame(pm2 = c(1, 1, 1, 1, 2, 2), pm3 = c(1, 1, 3, 3, 2, 2))
  out <- h$sid_align_labels(mat, overrides = list(pm3 = c("1" = "B")))
  pm3 <- tapply(out[, "pm3"], mat$pm3, unique)
  expect_identical(anyDuplicated(unlist(pm3)), 0L)
  expect_error(h$sid_align_labels(mat, overrides = list(pm3 = c("1" = "B", "2" = "B"))), "one letter to two")
})

test_that("sid_align_labels gives the same letters when several parents split, however PAM numbered them", {
  h <- sid_helpers_env()
  # Found in review (Codex, #394): two parents each produce a fresh child at
  # K = 4, with no size ties; the order of PAM's numbers decided D and E.
  mat <- data.frame(pm2 = c(rep(1, 20), rep(2, 19)), pm3 = c(rep(1, 20), rep(2, 16), rep(3, 3)),
                    pm4 = c(rep(1, 12), rep(2, 8), rep(3, 10), rep(4, 6), rep(1, 3)))
  other <- mat
  other$pm4 <- c(`1` = 4, `2` = 3, `3` = 2, `4` = 1)[as.character(mat$pm4)]
  expect_identical(h$sid_align_labels(other), h$sid_align_labels(mat))
})

test_that("sid_align_labels orders equal-sized clusters by their first patient, not PAM's number", {
  h <- sid_helpers_env()
  one <- h$sid_align_labels(data.frame(pm2 = c(1, 1, 2, 2)))
  two <- h$sid_align_labels(data.frame(pm2 = c(2, 2, 1, 1)))
  expect_identical(one, two)
  expect_identical(one[, "pm2"], c("A", "A", "B", "B"))
})

test_that("sid_mds_signs breaks a tie between equally distant patients by row name", {
  h <- sid_helpers_env()
  xy <- cbind(c(-1, 1), c(2, -2))
  rownames(xy) <- c("p2", "p1")
  expect_identical(h$sid_mds_signs(xy[2:1, ]), h$sid_mds_signs(xy)[2:1, ])
  expect_identical(unname(h$sid_mds_signs(xy)["p1", ]), c(1, 2))
})

test_that("sid_dataset_name keeps sets apart whose names split differently at an underscore", {
  h <- sid_helpers_env()
  expect_false(identical(h$sid_dataset_name("a_b", "c"), h$sid_dataset_name("a", "b_c")))
  expect_match(h$sid_dataset_name("Morphology", "sid"), "^[a-z][a-z0-9_]*$")
})

test_that("sid_align_labels stops when the letter pool runs out", {
  h <- sid_helpers_env()
  mat <- data.frame(pm3 = c(1, 2, 3))
  expect_error(h$sid_align_labels(mat, pool = c("A", "B")), "Letter pool exhausted")
})

test_that("sid_collapse maps letters, keeps unmapped ones and rejects a bad map", {
  h <- sid_helpers_env()
  x <- c("A", "C", "D", "B", "E")
  expect_identical(h$sid_collapse(x, list(Z = c("C", "D", "E"))), c("A", "Z", "Z", "B", "Z"))
  expect_error(h$sid_collapse(x, list(Z = c("C", "Q"))), "not a cluster at K: Q")
  expect_error(h$sid_collapse(x, list(Y = "C", Z = "C")), "mapped more than once: C")
})

test_that("sid_mds_signs gives the same picture under row order and sign flips", {
  h <- sid_helpers_env()
  xy <- cbind(c(1, -3, 2, 0.5), c(-0.2, 0.1, 0.4, -2))
  ref <- h$sid_mds_signs(xy)
  expect_true(ref[2, 1] > 0)  # the largest |x| on axis 1 is row 2, made positive
  expect_true(ref[4, 2] > 0)
  perm <- c(3, 1, 4, 2)
  expect_identical(h$sid_mds_signs(xy[perm, ]), ref[perm, ])
  expect_identical(h$sid_mds_signs(-xy), ref)
})

test_that("sid-fit imputes, fits and saves the handoff", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("sid", "fit"))
  env <- sid_fit_first()
  h <- readRDS(env$set_path("estimates", "sid.rds"))
  expect_identical(names(h), c("dist", "id_key", "vars", "dropped", "reduced", "settings"))
  expect_identical(dim(h$dist), c(150L, 150L))
  expect_false(anyNA(h$dist))
  key <- hvtiRtemplates:::.study_id_key(env$.root)
  expect_identical(rownames(h$dist), hvtiRtemplates:::.id_digest(seq_len(150L), key))
  expect_identical(h$id_key, hvtiRtemplates:::.id_key_fingerprint(key))
  expect_false(is.null(attr(h, "hvti_provenance")$selection))
})

test_that("sid-fit imputes by forest, and pools M imputations into one mean distance", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("sid", "fit"))
  forest <- readRDS(sid_fit_first(choices = utils::modifyList(sid_fit_choices, list(IMPUTE = "forest")))$set_path(
    "estimates", "sid.rds"
  ))
  expect_false(anyNA(forest$dist))
  env <- sid_fit_first(choices = utils::modifyList(sid_fit_choices, list(M = 2)))
  expect_length(env$sid_fits, 2L)
  pooled <- readRDS(env$set_path("estimates", "sid.rds"))$dist
  expect_equal(unname(pooled), unname((env$sid_fits[[1]]$dist + env$sid_fits[[2]]$dist) / 2))
  expect_identical(nrow(env$sid_agreement), 2L)
  # IMPUTE is checked where it is used, in the impute chunk (the fifth).
  bad <- rf_env(sid_data())
  expect_error(rf_run("sid", "fit", sid_fit_labels[1:5], bad, utils::modifyList(sid_fit_choices, list(IMPUTE = "x"))),
               "IMPUTE")
})

test_that("sid-fit drops a variable over MAX_MISSING and says so", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("sid", "fit"))
  d <- sid_data()
  d$e[1:80] <- NA
  env <- sid_fit_first(d)
  expect_identical(env$sid_dropped$variable, "e")
  expect_false("e" %in% env$sid_vars)
})

test_that("sid-fit refuses an ID or an absent column in VARS", {
  rf_skip_unless_stack(rf_template_packages("sid", "fit"))
  for (vars in list(c("a", "ccfid"), c("a", "nope"))) {
    env <- rf_env(sid_data())
    expect_error(
      rf_run("sid", "fit", sid_fit_labels[1:3], env, utils::modifyList(sid_fit_choices, list(VARS = vars))),
      "VARS"
    )
  }
})

test_that("the seed reproduces a reduce = TRUE fit", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("sid", "fit"))
  # Six noise columns make the reduce step's choice of variables depend on the
  # generator. Without them the planted groups settle the reduced set whatever
  # the incoming state, and this test cannot go red (measured by mutation).
  d <- sid_data()
  withr::with_seed(5L, for (i in 1:6) d[[paste0("n", i)]] <- stats::rnorm(nrow(d)))
  choices <- utils::modifyList(sid_fit_choices, list(SID_REDUCE = TRUE, VARS = c(sid_fit_choices$VARS, paste0("n", 1:6))))
  # Each throwaway study draws its own ID key, so the digest dimnames differ
  # by design; the numbers must not. The incoming generator states differ too,
  # so only the job's own seeding can make the two agree.
  set.seed(1)
  one <- readRDS(sid_fit_first(d, choices)$set_path("estimates", "sid.rds"))$dist
  set.seed(3)
  two <- readRDS(sid_fit_first(d, choices)$set_path("estimates", "sid.rds"))$dist
  expect_identical(unname(one), unname(two))
})
