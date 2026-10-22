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

test_that("sid-clusters recovers planted clusters at K = 3", {
  skip_on_cran()
  rf_skip_unless_stack(unique(c(rf_template_packages("sid", "fit"), rf_template_packages("sid", "clusters"))))
  env <- sid_fit_first()
  sid_clusters_after(env)
  truth <- sid_data()$truth
  score <- randomForestSRC::sid.perf.metric(factor(truth), factor(env$sid_letters$C3))$normalized_measure
  expect_lt(score, 0.2)
  expect_identical(env$sid_metrics$k, 1:8)
})

test_that("sid-clusters reads sid.rds and never fits", {
  rf_skip_unless_stack(rf_template_packages("sid", "clusters"))
  src <- readLines(template_path("sid", "clusters"), warn = FALSE)
  expect_false(any(grepl("sidClustering(", src, fixed = TRUE)))
  env <- rf_env(sid_data())
  expect_error(rf_run("sid", "clusters", sid_clusters_labels[1:4], env, sid_clusters_choices),
               "Render the sid-fit job in this set first")
})

test_that("sid-clusters writes and registers the cluster letters, and nothing else", {
  skip_on_cran()
  rf_skip_unless_stack(unique(c(rf_template_packages("sid", "fit"), rf_template_packages("sid", "clusters"))))
  env <- sid_fit_first()
  sid_clusters_after(env, utils::modifyList(sid_clusters_choices, list(COLLAPSE = list(Z = c("B", "C")))))
  csv <- file.path(hvtiRutilities::study_dir("datasets", env$.root), "morphology-sid-clusters.csv")
  out <- utils::read.csv(csv)
  expect_identical(names(out), c("ccfid", "C2", "C3", "C4", "C5", "G3"))
  expect_identical(nrow(out), 150L)
  cfg <- hvtiRutilities::study_config(start = env$.root)
  expect_true("clusters_10_morphology_sid" %in% names(cfg$additional_datasets))
  # A second render with letters pinned differently re-registers, and a read
  # returns the new letters.
  # The K = 2 map the first render chose, PAM number -> letter, reversed.
  map <- readRDS(env$set_path("estimates", "sid-clusters.rds"))$letters$pm2
  flip <- stats::setNames(rev(unname(map)), names(map))
  sid_clusters_after(env, utils::modifyList(sid_clusters_choices, list(OVERRIDES = list(pm2 = flip))))
  again <- read_job_data(hvtiRutilities::study_config(start = env$.root), join = "clusters_10_morphology_sid")$data
  expect_false(identical(again$c2[again$ccfid == out$ccfid[1]], out$C2[1]))
})

test_that("K = NULL renders the metrics and skips what needs K; a final render or a K outside K_RANGE stops", {
  skip_on_cran()
  rf_skip_unless_stack(unique(c(rf_template_packages("sid", "fit"), rf_template_packages("sid", "clusters"))))
  env <- sid_fit_first()
  # modifyList() would drop an element set to NULL, so K = NULL is rebuilt with c().
  no_k <- c(sid_clusters_choices[setdiff(names(sid_clusters_choices), "K")], list(K = NULL))
  sid_clusters_after(env, no_k)
  expect_false(is.null(env$sid_metrics))
  expect_null(env$sid_mds)
  expect_null(readRDS(env$set_path("estimates", "sid-clusters.rds"))$clusters)
  withr::with_envvar(c(HVTI_TEMPLATE_STRICT = "true"),
                     expect_error(rf_run("sid", "clusters", sid_clusters_labels[c(2:4)], env, no_k), "set K"))
  expect_error(sid_clusters_after(env, utils::modifyList(sid_clusters_choices, list(K = 9L))), "K_RANGE")
})

test_that("a small cohort caps the metrics at n - 1 and refuses a K_RANGE it cannot hold", {
  skip_on_cran()
  rf_skip_unless_stack(unique(c(rf_template_packages("sid", "fit"), rf_template_packages("sid", "clusters"))))
  env <- sid_fit_first(sid_data(n_per = 4L))  # 12 patients
  sid_clusters_after(env, utils::modifyList(sid_clusters_choices, list(K_RANGE = 2:9, K_METRICS_MAX = 15, MIN_SIZE = 1)))
  expect_identical(env$sid_metrics$k, 1:11)
  expect_error(sid_clusters_after(env, utils::modifyList(sid_clusters_choices, list(K_RANGE = 2:12))), "only 12 patients")
})

test_that("sid-clusters refuses a registered name that belongs to another file", {
  skip_on_cran()
  rf_skip_unless_stack(unique(c(rf_template_packages("sid", "fit"), rf_template_packages("sid", "clusters"))))
  env <- sid_fit_first()
  # Another set already holds the name, as a set whose name differs only in case would.
  dd <- hvtiRutilities::study_dir("datasets", env$.root)
  utils::write.csv(data.frame(ccfid = 1:150, C2 = "A"), file.path(dd, "other-clusters.csv"), row.names = FALSE)
  utils::capture.output(suppressMessages(hvtiRutilities::register_data(
    env$.root, built = "other-clusters.csv", dataset = "clusters_10_morphology_sid", role = "named",
    population = "x", kind = "ancillary", key = "ccfid"
  )))
  expect_error(sid_clusters_after(env), "already registered to other-clusters.csv")
})

test_that("the clusters element vt reads holds one digest-keyed letter per patient, and no raw ID", {
  skip_on_cran()
  rf_skip_unless_stack(unique(c(rf_template_packages("sid", "fit"), rf_template_packages("sid", "clusters"))))
  env <- sid_fit_first()
  sid_clusters_after(env)
  h <- readRDS(env$set_path("estimates", "sid-clusters.rds"))
  key <- hvtiRtemplates:::.study_id_key(env$.root)
  expect_identical(names(h$clusters), c("id", "cluster"))
  expect_setequal(h$clusters$id, hvtiRtemplates:::.id_digest(seq_len(150L), key))
  expect_identical(h$clusters$cluster, as.character(env$sid_letters$C3[match(h$clusters$id, rownames(env$sid$dist))]))
  expect_identical(h$id_key, hvtiRtemplates:::.id_key_fingerprint(key))
})

test_that("a cluster under MIN_SIZE at K warns", {
  skip_on_cran()
  rf_skip_unless_stack(unique(c(rf_template_packages("sid", "fit"), rf_template_packages("sid", "clusters"))))
  env <- sid_fit_first(sid_data(n_per = 4L))  # 12 patients, so every cluster is under 20
  expect_warning(sid_clusters_after(env), "fewer than 20 patients")
})

test_that("a later job joins the registered clusters, one per patient", {
  skip_on_cran()
  rf_skip_unless_stack(unique(c(rf_template_packages("sid", "fit"), rf_template_packages("sid", "clusters"))))
  env <- sid_fit_first()
  sid_clusters_after(env)
  cfg <- hvtiRutilities::study_config(start = env$.root)
  long <- read_job_data(cfg, join = "clusters_10_morphology_sid")
  expect_identical(nrow(long$data), 150L)
  expect_true(all(c("c2", "c3") %in% tolower(names(long$data))))
  expect_error(read_job_data(cfg, join = "clusters_10_morphology_sid", one_row_per_patient = TRUE), "REDUCE")
  one <- read_job_data(cfg, join = "clusters_10_morphology_sid", reduce = list(rule = "first", by = "ccfid"),
                       one_row_per_patient = TRUE)
  expect_identical(nrow(one$data), 150L)
  expect_identical(anyDuplicated(one$data$ccfid), 0L)
})
