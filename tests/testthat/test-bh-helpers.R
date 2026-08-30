# The 04.06-bh template is this repo's first caller of boot_clusters() and
# boot_shortfall(), and a render is not a test: the render stops at the
# `bootstrap` chunk whenever no screen output exists, which is every CI run.
# So neither helper is exercised by anything unless it is exercised here.

test_that("boot_clusters() reports union selection over a declared group", {
  skip_if_not_installed("hvtiRbootstrap")

  # A replicate coefficient matrix: rows are replicates, columns are terms, NA
  # where that replicate did not retain the term. This is the shape
  # hzr_bootstrap() returns, and the shape boot_clusters() requires.
  m <- matrix(NA_real_, nrow = 4L, ncol = 3L,
              dimnames = list(NULL, c("age", "ln_age", "bsa")))
  m[c(1L, 2L), "age"]    <- 1
  m[c(2L, 3L), "ln_age"] <- 1
  m[4L, "bsa"]           <- 1

  cl <- hvtiRbootstrap::boot_clusters(m, list(Age = c("age", "ln_age"),
                                              Size = "bsa"))
  expect_s3_class(cl, "data.frame")
  expect_setequal(names(cl), c("cluster", "n_any", "pct_any", "members"))

  # The union is the point. Three of four replicates retained SOME form of age,
  # while no single form reached more than two -- which is exactly the gap a
  # per-variable frequency cannot show.
  expect_identical(cl$n_any[cl$cluster == "Age"], 3L)
  expect_identical(cl$pct_any[cl$cluster == "Age"], 75)
})

test_that("boot_clusters() refuses a cluster naming a term the screen never saw", {
  skip_if_not_installed("hvtiRbootstrap")
  m <- matrix(1, nrow = 2L, ncol = 1L, dimnames = list(NULL, "age"))

  # The failure mode this guards: a cluster vocabulary copied from another
  # study names terms this pool does not contain, and a silent drop would
  # report that cluster's union over the members that happened to match.
  expect_error(hvtiRbootstrap::boot_clusters(m, list(Renal = c("age", "gfr"))),
               "not present in the replicates")
  expect_error(hvtiRbootstrap::boot_clusters(m, list(c("age"))),
               "named list")
})

test_that("boot_shortfall() reports a partial pool and stays silent on a full one", {
  skip_if_not_installed("hvtiRbootstrap")
  full    <- list(n_boot = 500L, n_chunks = 25L)
  partial <- list(n_boot = 200L, n_chunks = 10L)

  expect_null(hvtiRbootstrap::boot_shortfall(full, 25L, 500L))

  msg <- hvtiRbootstrap::boot_shortfall(partial, 25L, 500L)
  expect_true(is.character(msg) && nzchar(msg))
  expect_match(msg, "10 of 25 chunks")
  expect_match(msg, "200 of 500 replicates")
})
