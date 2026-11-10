# The isolation-forest eligibility method, the eligible-but-outside-range table
# and AGE_CAP in vt-fit. Helpers are run from the template's `ood` chunk
# (vt_helpers(), helper-vt.R); the template tests run its chunks on vt_data().

# Two arms on three variables, with one arm B patient far outside arm A in x.
iso_data <- function(n = 240L, seed = 3L) {
  withr::with_seed(seed, {
    d <- data.frame(ID = as.character(seq_len(n)), x = stats::rnorm(n), y = stats::rnorm(n),
                    g = factor(sample(c("u", "v"), n, replace = TRUE)))
  })
  d$x[161] <- 8
  d
}
iso_arm <- rep(c("A", "B"), c(160L, 80L))

test_that("the isolation forest flags a patient far outside the arm and keeps vt_ood's row shape", {
  skip_if_not_installed("isotree")
  h <- vt_helpers()
  d <- iso_data()
  r <- h$vt_elig_isolation(d, c("x", "y", "g"), d$ID, iso_arm, c("A", "B"), cutoff = 0.99, seed = 1L)
  expect_named(r, c("ID", "method", "arm", "nn_id", "distance", "reference", "ratio", "in_distribution", "reason"))
  # Each treated patient is judged once, against the other arm.
  expect_equal(nrow(r), 240L)
  expect_true(all(r$arm != iso_arm[match(r$ID, d$ID)]))
  far <- r[r$ID == "161", ]
  expect_false(far$in_distribution)
  expect_match(far$reason, "isolation score .* above A's 0.99 quantile")
  expect_true(all(r$reason[r$in_distribution] == ""))
  expect_identical(r$in_distribution, !(r$distance > r$reference))
})

test_that("the isolation sensitivity reports the cutoff in use and the 95th and 99.5th beside it", {
  skip_if_not_installed("isotree")
  h <- vt_helpers()
  d <- iso_data()
  r <- h$vt_elig_isolation(d, c("x", "y", "g"), d$ID, iso_arm, c("A", "B"), cutoff = 0.99, seed = 1L)
  s <- attr(r, "sensitivity")
  expect_equal(s$quantile, rep(c(0.95, 0.99, 0.995), 2L))
  expect_equal(s$judged, rep(c(80L, 160L), each = 3L))
  # A higher quantile is a higher line, so it can only flag fewer.
  for (a in c("A", "B")) {
    expect_false(is.unsorted(s$cutoff[s$arm == a]))
    expect_false(is.unsorted(rev(s$flagged[s$arm == a])))
  }
  # The 0.99 row is the line the rows were judged by, and counts the same flags.
  for (a in c("A", "B")) {
    in_use <- s[s$arm == a & s$quantile == 0.99, ]
    expect_equal(in_use$cutoff, unique(r$reference[r$arm == a]))
    expect_equal(in_use$flagged, sum(!r$in_distribution[r$arm == a]))
  }
  # A stricter cutoff moves the line the rows are judged by.
  r95 <- h$vt_elig_isolation(d, c("x", "y", "g"), d$ID, iso_arm, c("A", "B"), cutoff = 0.95, seed = 1L)
  expect_equal(sum(!r95$in_distribution), sum(s$flagged[s$quantile == 0.95]))
  expect_error(h$vt_elig_isolation(d, "x", d$ID, iso_arm, c("A", "B"), cutoff = 99), "ISOLATION_CUTOFF")
})

test_that("an arm's own scores are cross-fitted: no forest scores a patient it was grown on", {
  skip_if_not_installed("isotree")
  h <- vt_helpers()
  d <- iso_data()
  grown <- list()
  fits <- list()
  real <- isotree::isolation.forest
  local_mocked_bindings(isolation.forest = function(data, ...) {
    grown[[length(grown) + 1L]] <<- rownames(data)
    fit <- real(data, ...)
    fits[[length(fits) + 1L]] <<- fit
    fit
  }, .package = "isotree")
  r <- h$vt_elig_isolation(d, c("x", "y", "g"), d$ID, iso_arm, c("A", "B"), seed = 1L)
  # A judged patient is scored as a member is: by ONE fold's forest, the folds dealt as evenly. A mean over
  # all five would be a less noisy score than the arm's own, judged against a line set on the noisier one.
  judged_b <- d[iso_arm == "B", c("x", "y", "g")]
  by_fold <- vapply(fits[1:5], function(f) stats::predict(f, judged_b), numeric(nrow(judged_b)))
  which_fold <- vapply(seq_len(nrow(by_fold)), function(i) {
    hit <- which(abs(by_fold[i, ] - r$distance[r$arm == "A"][i]) < 1e-12)
    if (length(hit) == 1L) hit else NA_integer_
  }, integer(1L))
  expect_false(anyNA(which_fold))
  expect_true(all(tabulate(which_fold, 5L) %in% c(16L, 17L)))
  # Five forests per arm, each grown on that arm's patients alone, leaving out a fifth of them.
  expect_length(grown, 10L)
  for (a in c("A", "B")) {
    members <- rownames(d)[iso_arm == a]
    trained <- grown[if (a == "A") 1:5 else 6:10]
    expect_true(all(vapply(trained, function(g) all(g %in% members), logical(1L))))
    left_out <- lapply(trained, function(g) setdiff(members, g))
    # The folds left out partition the arm: every member is held out by exactly one forest.
    expect_setequal(unlist(left_out), members)
    expect_equal(anyDuplicated(unlist(left_out)), 0L)
    expect_true(all(lengths(left_out) %in% c(floor(length(members) / 5), ceiling(length(members) / 5))))
  }
})

test_that("vt_outside_range lists an eligible patient's values the arm judged against never shows", {
  h <- vt_helpers()
  d <- data.frame(ID = c("a1", "a2", "a3", "b1", "b2", "b3"), x = c(1, 2, 3, 0.5, 2, 9), bin = c(0, 0, 0, 1, 0, 0),
                  g = factor(c("u", "u", "v", "w", "u", "v")), stringsAsFactors = FALSE)
  arm_of <- c("A", "A", "A", "B", "B", "B")
  pairs <- data.frame(ID = c("b1", "b2", "b3"), arm = "A")
  o <- h$vt_outside_range(pairs, d, "ID", arm_of, c("x", "bin", "g"))
  key <- paste(o$ID, o$variable, o$side)
  expect_setequal(key, c("b1 x below", "b3 x above", "b1 bin a level not in the arm", "b1 g a level not in the arm"))
  expect_equal(o$arm_values[o$ID == "b3"], "[1, 3]")
  expect_equal(o$value[o$ID == "b3"], "9")
  # Binary is decided on the whole column: arm A shows only 0 and 1, but 0.5 elsewhere makes the column
  # continuous, so a judged 0.5 sits inside A's range [0, 1] rather than being an unseen level.
  d2 <- data.frame(ID = c("a1", "a2", "b1"), z = c(0, 1, 0.5))
  expect_equal(nrow(h$vt_outside_range(data.frame(ID = "b1", arm = "A"), d2, "ID", c("A", "A", "B"), "z")), 0L)
  # Nobody outside: an empty table with the same columns, never NULL.
  none <- h$vt_outside_range(data.frame(ID = "b2", arm = "A"), d, "ID", arm_of, c("x", "bin", "g"))
  expect_equal(nrow(none), 0L)
  expect_named(none, names(o))
})

test_that("vt-fit judges by gower and isolation together, and any flag excludes", {
  skip_on_cran()
  skip_if_not_installed("isotree")
  # 0.95, not the default 0.99: arm B has about 100 patients, so its 99th percentile is its one or two most
  # unusual scores, mostly noise, and sits above the planted outliers (0.61 to 0.63 against 0.67, measured
  # 2026-11-10). Gower flags them at either setting. That gap is why the sensitivity table exists.
  ch <- utils::modifyList(vt_choices, list(ELIGIBILITY = c("gower", "isolation"), ISOLATION_CUTOFF = 0.95))
  env <- vt_fit_first(choices = ch)
  expect_setequal(unique(env$.elig_rows$method), c("gower", "isolation"))
  expect_false(anyNA(env$.elig$elig_isolation))
  expect_identical(env$.elig$elig, env$.elig$elig_gower & env$.elig$elig_isolation)
  # The planted outliers sit far out in xs, and the arm B forest isolates them.
  planted <- vt_digest(env, which(vt_data()$arm == "A")[1:5])
  expect_false(any(env$.elig$elig_isolation[match(planted, env$.elig$ID)]))
  expect_false(any(env$.elig$elig[match(planted, env$.elig$ID)]))
  expect_setequal(env$.iso_sens$arm, c("A", "B"))
  iso <- env$.elig_rows[env$.elig_rows$method == "isolation" & !env$.elig_rows$in_distribution, ]
  expect_true(all(nzchar(iso$features)))
})

test_that("vt-fit reports eligible patients outside the arm's range, and the handoff keeps them", {
  skip_on_cran()
  d <- vt_data()
  # One arm A patient just past arm B's largest x1 (2.65), inside the pooled range, so Gower keeps them.
  d$x1[which(d$arm == "A")[10]] <- 2.8
  env <- vt_fit_first(data = d)
  id <- vt_digest(env, which(d$arm == "A")[10])
  expect_true(env$.elig$elig[env$.elig$ID == id])
  o <- env$.outside[env$.outside$ID == id & env$.outside$variable == "x1", ]
  expect_equal(o$side, "above")
  expect_equal(o$arm, "B")
  # Only eligible patients are listed.
  expect_true(all(env$.outside$ID %in% env$.elig$ID[env$.elig$elig]))
  # The report counts by variable, arm and side; the arm's range stays in the handoff.
  expect_named(env$.outside_counts, c("variable", "arm", "side", "patients"))
})

test_that("the outside-range table checks the forests' predictors when ELIGIBILITY_VARS leaves one out", {
  skip_on_cran()
  d <- vt_data()
  d$x1[which(d$arm == "A")[10]] <- 2.8
  env <- vt_fit_first(data = d, choices = utils::modifyList(vt_choices, list(ELIGIBILITY_VARS = "g1")))
  id <- vt_digest(env, which(d$arm == "A")[10])
  expect_true(env$.elig$elig[env$.elig$ID == id])
  expect_equal(env$.outside$side[env$.outside$ID == id & env$.outside$variable == "x1"], "above")
})

test_that("AGE_CAP caps the named age in every arm, and refuses an unnamed cap", {
  skip_on_cran()
  d <- vt_data()
  withr::with_seed(5L, d$age <- round(stats::runif(nrow(d), 60, 99)))
  ch <- utils::modifyList(vt_choices, list(AGE_CAP = c(age = 90)))
  env <- vt_fit_first(data = d, choices = ch)
  expect_equal(max(env$.d_read$age), 90)
  expect_equal(sum(env$.d_read$age == 90), sum(d$age >= 90))
  expect_error(vt_fit_first(data = d, choices = utils::modifyList(vt_choices, list(AGE_CAP = 90))),
               "AGE_CAP must be one named number")
  expect_error(vt_fit_first(data = d, choices = utils::modifyList(vt_choices, list(AGE_CAP = c(years = 90)))),
               "AGE_CAP must be one named number")
  expect_error(vt_fit_first(data = d, choices = utils::modifyList(vt_choices, list(AGE_CAP = c(age = Inf)))),
               "AGE_CAP must be one named number")
  # Capping the follow-up time would truncate it with the event left as recorded.
  expect_error(vt_fit_first(data = d, choices = utils::modifyList(vt_choices, list(AGE_CAP = c(time = 2)))),
               "AGE_CAP names time, the ID, arm or outcome")
})

test_that("the isolation forest refuses an arm too small to cross-fit, naming the arm", {
  skip_if_not_installed("isotree")
  h <- vt_helpers()
  d <- data.frame(ID = as.character(1:10), x = 1:10, y = 10:1)
  expect_error(h$vt_elig_isolation(d, c("x", "y"), d$ID, rep(c("A", "B"), c(8L, 2L)), c("A", "B")),
               "Arm B has 2 patient\\(s\\); the isolation forest needs at least 3")
})

test_that("vt-explain caps the age it re-reads, as vt-fit did", {
  skip_on_cran()
  d <- vt_data()
  withr::with_seed(5L, d$age <- round(stats::runif(nrow(d), 60, 99)))
  ch <- utils::modifyList(vt_choices, list(AGE_CAP = c(age = 90)))
  env <- vt_fit_first(data = d, choices = ch, labels = vt_fit_labels_all)
  vt_explain(env, labels = c("setup", "edit-study-choices", "handoff", "explain-data"))
  expect_equal(max(env$.d_all$age), 90)
})

test_that("judged against an arm drawn from the same distribution, the isolation forest flags about the cutoff's share", {
  skip_on_cran()
  skip_if_not_installed("isotree")
  h <- vt_helpers()
  # Two arms of 300 from one distribution. Expected near 10% at the 0.9 cutoff; measured 2026-11-10. A sanity band,
  # not a mutation guard: the single-forest scoring above is what the cross-fit test pins.
  d <- withr::with_seed(11L, data.frame(ID = as.character(1:600), x = stats::rnorm(600), y = stats::rnorm(600),
                                        g = factor(sample(c("u", "v"), 600, replace = TRUE))))
  r <- h$vt_elig_isolation(d, c("x", "y", "g"), d$ID, rep(c("A", "B"), each = 300L), c("A", "B"), cutoff = 0.9,
                           seed = 2L, ntrees = 100L)
  share <- tapply(!r$in_distribution, r$arm, mean)
  expect_true(all(share > 0.05 & share < 0.15), info = paste(round(share, 3), collapse = ", "))
})
