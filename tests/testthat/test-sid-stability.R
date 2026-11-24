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
  expect_false(anyNA(env$x_m[[1L]]))
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
               "include sid-fit's own forest seed")
})

test_that("a refit that loses a group reports where its patients went", {
  skip_on_cran()
  env <- sid_fit_first()
  sid_clusters_after(env)
  sid_stability_after(env)
  # Every refit, at K, gives the patients of reported group C the label its group A patients carry.
  pm <- paste0("pm", env$K)
  lost <- lapply(env$refits, function(m) {
    a_label <- as.integer(names(which.max(table(m[env$ref_letter == "A", pm]))))
    m[env$ref_letter == "C", pm] <- a_label
    m
  })
  env$stab <- env$summarize_refits(lost)
  expect_false(any(env$stab$by_group$matched[env$stab$by_group$group == "C"]))
  expect_identical(colnames(env$stab$mapped), names(lost))
  src <- readLines(template_path("sid", "stability"), warn = FALSE)
  eval(parse(text = rf_chunk(src, "tbl-lost")), envir = env)  # nolint: object_usage_linter.
  expect_identical(env$.lost$Group, "C")
  expect_identical(env$.lost[["to A"]], "100%")
})

test_that("sid-stability refuses clusters rendered on an earlier sid.rds", {
  skip_on_cran()
  env <- sid_fit_first()
  sid_clusters_after(env)
  # A sid-fit rerun leaves new bytes in sid.rds while sid-clusters still holds the old checksum.
  path <- env$set_path("estimates", "sid.rds")
  saveRDS(utils::modifyList(readRDS(path), list(rerun = TRUE)), path)
  expect_error(sid_stability_after(env), "earlier sid.rds")
})

test_that("sid-stability refuses an imputation cache whose imputed values changed", {
  skip_on_cran()
  env <- sid_fit_first()
  sid_clusters_after(env)
  # Only an imputed cell moves: every observed value still agrees, so the fingerprint must catch it.
  path <- file.path(env$set_path("estimates", "sid.rds") |> dirname(), "sid-fit-impute-1.rds")
  rec <- readRDS(path)
  rec$value$imp$a[1, 1] <- rec$value$imp$a[1, 1] + 50
  saveRDS(rec, path)
  expect_error(sid_stability_after(env), "differ from the completed data")
})

test_that("with M = 2 a refit at sid-fit's seed rebuilds the reported clusters, and refits seed M forests apart", {
  skip_on_cran()
  env <- sid_fit_first(choices = utils::modifyList(sid_fit_choices, list(M = 2)))
  sid_clusters_after(env)
  sid_stability_after(env)
  expect_length(env$x_m, 2L)
  expect_identical(env$seeds, c(101L, 103L, 105L))
  # The refit code, run at sid-fit's own seed, must give sid-clusters' solution at every K:
  # the same M forests, the same averaging, the same PAM.
  e <- new.env(parent = env)
  e$refit_x <- env$x_m
  e$refit_ntree <- env$.s$ntree
  e$refit_reduce <- env$.s$sid_reduce
  e$refit_k <- env$.k_range
  e$refit_seed <- as.integer(env$.s$seed)
  lab <- eval(env$.refit_code, e)
  for (i in seq_along(env$.k_range)) {
    expect_equal(env$stab_ari(lab[, i], env$ref_pam[[as.character(env$.k_range[i])]]), 1,
                 info = paste("K =", env$.k_range[i]))
  }
})

# ---- #623: agreement with a reference assignment ------------------------------------------------

test_that("with a REFERENCE in sid-clusters, the refits are also measured against it, beside the rerun's own (#623)", {
  skip_on_cran()
  d <- sid_data()
  env <- sid_fit_first(d)
  # The reference moves ten patients of the first planted group into the second and leaves two unassigned,
  # so it is not the rerun's own solution and the two agreements must differ.
  grp <- c("Q", "R", "S")[d$truth]
  grp[1:10] <- "R"
  grp[149:150] <- NA
  sid_register_reference(env, grp)
  expect_warning(sid_clusters_after(env, utils::modifyList(sid_clusters_choices,
                                                           list(REFERENCE = list(dataset = "published", col = "grp")))),
                 "2 patients clustered here have no group in `published`")
  saved <- readRDS(env$set_path("estimates", "sid-clusters.rds"))
  # sid-clusters hands on each patient's reference group, by digest, NA where the reference has none.
  expect_identical(saved$clusters$reference, grp[match(env$sid_letters$ccfid, seq_along(grp))])
  sid_stability_after(env)
  expect_false(is.null(env$stab_ref))
  expect_setequal(unique(env$stab_ref$by_group$group), c("Q", "R", "S"))
  expect_identical(env$ref_assigned, 148L)
  # The refits recover the planted groups, which agree with the rerun better than with the moved reference.
  expect_true(all(env$stab_ref$by_refit$ari_groups < env$stab$by_refit$ari_groups))
  expect_true(all(env$stab_ref$by_refit$ari_groups > 0.7))
  # Group Q lost ten patients in the reference, so its overlap with every refit is below 1.
  q <- env$stab_ref$by_group[env$stab_ref$by_group$group == "Q", ]
  expect_true(all(q$jaccard < 1 & q$jaccard > 0.7))
  out <- readRDS(env$set_path("estimates", "sid-stability.rds"))
  expect_identical(out$reference$dataset, "published")
  expect_identical(out$reference$assigned, 148L)
  expect_identical(nrow(out$reference$by_group), 9L)
  # The reference dataset's digest is in the lineage this job records.
  sha <- vapply(env$.provenance_data, function(p) p$sha256, "")
  expect_true(any(vapply(env$.cl_read$lineage$data, function(p) p$sha256 %in% sha, NA)))
  expect_gt(length(unique(sha)), length(unique(vapply(env$.sid_read$lineage$data, function(p) p$sha256, ""))))
})

test_that("a REFERENCE with COLLAPSE measures the refits against the reference's collapsed groups", {
  skip_on_cran()
  d <- sid_data()
  env <- sid_fit_first(d)
  sid_register_reference(env, c("Q", "R", "S")[d$truth])
  sid_clusters_after(env, utils::modifyList(sid_clusters_choices,
                                            list(REFERENCE = list(dataset = "published", col = "grp"),
                                                 COLLAPSE = list(Z = c("Q", "R")))))
  sid_stability_after(env)
  expect_setequal(unique(env$stab_ref$by_group$group), c("S", "Z"))
  expect_true(all(env$stab_ref$by_refit$ari_groups > 0.9))
})

test_that("an older sid-clusters.rds, with no reference or PAM metric, refits as before", {
  skip_on_cran()
  env <- sid_fit_first()
  sid_clusters_after(env)
  path <- env$set_path("estimates", "sid-clusters.rds")
  old <- readRDS(path)
  old$pam_on <- NULL
  old$clusters$reference <- NULL
  saveRDS(old, path)
  sid_stability_after(env)
  expect_null(env$stab_ref)
  expect_identical(env$pam_on, "sid")
  expect_true(all(env$stab$by_refit$ari_groups > 0.9))
  expect_null(readRDS(env$set_path("estimates", "sid-stability.rds"))$reference)
})

# ---- #624: TRACK a level of a coded column ------------------------------------------------------

test_that("TRACK takes a level of a coded column and names it, and still takes a 0/1 column (#624)", {
  skip_on_cran()
  d <- sid_data()
  d$grade <- c(1L, 2L, 3L)[d$truth]
  d$trk <- as.integer(d$truth == 3L)
  env <- sid_fit_first(d)
  sid_clusters_after(env)
  sid_stability_after(env, utils::modifyList(sid_stability_choices, list(TRACK = list(var = "grade", level = 3))))
  expect_identical(env$track, as.integer(env$cohort$grade == 3L))
  expect_identical(env$.track_label, "grade = 3")
  tbl <- env$tbl_stability(env$stab)
  expect_true("grade = 3, reported" %in% names(tbl))
  # The binary form, as a study copy written before levels existed sets it.
  sid_stability_after(env, utils::modifyList(sid_stability_choices, list(TRACK = "trk")))
  expect_identical(env$.track_label, "trk")
  expect_identical(env$track, env$cohort$trk)
  bad <- function(track) sid_stability_after(env, utils::modifyList(sid_stability_choices, list(TRACK = track)))
  expect_error(bad(list(var = "grade", level = 7)), "TRACK's level, 7, is not a value of grade")
  expect_error(bad(list(var = "grade")), "TRACK must be NULL, a 0/1 column name")
  expect_error(bad("grade"), "a 0/1 or TRUE/FALSE column")
})

# ---- #622: progress through the refits ----------------------------------------------------------

test_that("the refits report done/total to the job's progress, counting only refits that fit (#622)", {
  skip_on_cran()
  env <- sid_fit_first()
  sid_clusters_after(env)
  labels <- sid_stability_labels
  before <- labels[seq_len(match("refits", labels) - 1L)]
  steps <- list()
  record <- function(unit) function(step, total) steps[[length(steps) + 1L]] <<- c(unit = unit, step = step, total = total)
  rf_skip_unless_stack(rf_template_packages("sid", "stability"))
  withr::local_pdf(NULL)
  rf_run("sid", "stability", before, env, sid_stability_choices)
  env$.job$progress <- record
  rf_run("sid", "stability", "refits", env, sid_stability_choices)
  expect_identical(vapply(steps, function(s) s[["step"]], ""), c("1", "2", "3"))
  expect_true(all(vapply(steps, function(s) s[["total"]] == "3" && s[["unit"]] == "refit", NA)))
  # Raising REPEATS reuses the three cached refits: only the two new ones count.
  steps <- list()
  env$REPEATS <- 5
  rf_run("sid", "stability", "refits", env)
  expect_identical(vapply(steps, function(s) s[["step"]], ""), c("1", "2"))
  expect_true(all(vapply(steps, function(s) s[["total"]] == "2", NA)))
})

# ---- #629: PAM on the profile distance ----------------------------------------------------------

test_that("sid-stability refits with the PAM metric sid-clusters used, and the profile metric rebuilds its solution (#629)", {
  skip_on_cran()
  env <- sid_fit_first()
  sid_clusters_after(env, utils::modifyList(sid_clusters_choices, list(PAM_ON = "profile")))
  expect_identical(readRDS(env$set_path("estimates", "sid-clusters.rds"))$pam_on, "profile")
  # PAM on the matrix itself: each patient's row of dissimilarities is a point.
  expect_identical(env$sid_pam$pm3$clustering, cluster::pam(env$sid$dist, 3L)$clustering)
  sid_stability_after(env)
  expect_identical(env$pam_on, "profile")
  e <- new.env(parent = env)
  e$refit_x <- env$x_m
  e$refit_ntree <- env$.s$ntree
  e$refit_reduce <- env$.s$sid_reduce
  e$refit_k <- env$.k_range
  e$refit_seed <- as.integer(env$.s$seed)
  lab <- eval(env$.refit_pam, e)
  for (i in seq_along(env$.k_range)) {
    expect_equal(env$stab_ari(lab[, i], env$ref_pam[[as.character(env$.k_range[i])]]), 1,
                 info = paste("K =", env$.k_range[i]))
  }
  expect_identical(readRDS(env$set_path("estimates", "sid-stability.rds"))$settings$pam_on, "profile")
})

test_that("the default refit code is unchanged, so refits cached before PAM_ON existed still load", {
  # cache_fit() keys on the code, so any change to the default's text would make every cached refit stale.
  src <- readLines(template_path("sid", "stability"), warn = FALSE)
  env <- new.env(parent = globalenv())
  env$pam_on <- "sid"
  chunk <- rf_chunk(src, "refits")
  eval(parse(text = chunk[grep("^\\.refit_code <- ", chunk):(grep("^run_refits <- ", chunk) - 1L)]), envir = env)
  expect_snapshot(cat(deparse(env$.refit_code), sep = "\n"))
})
