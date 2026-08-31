# The 04.05-bh template is this repo's first caller of boot_clusters() and
# boot_shortfall(), and a render is not a test: the render stops at the `load`
# chunk whenever no bootstrap output exists, which is every CI run. So the two
# helpers the template leans on are exercised here against synthetic input.
#
# hvtiRbootstrap is declared in Suggests, not Imports -- these tests are the
# only thing in the package that calls it, and the templates that use it are
# shipped data rather than package source. Suggests means it may legitimately
# be absent, so these skip rather than fail. That is also why the templates are
# excluded from object_usage_linter: their OTHER study dependencies, such as
# TemporalHazard, are in no DESCRIPTION field at all.

test_that("boot_clusters() counts a replicate once when it selects two forms", {
  skip_if_not_installed("hvtiRbootstrap")
  set.seed(1)
  n <- 200L

  # `a` and `a2` stand in for two forms of one concept. Replicates split
  # between them, so NEITHER reaches a high individual frequency -- which is
  # precisely the understatement the cluster view exists to correct.
  m <- matrix(NA_real_, nrow = n, ncol = 3L,
              dimnames = list(NULL, c("a", "a2", "b")))
  pick <- rep(c(TRUE, FALSE), length.out = n)
  m[pick, "a"] <- rnorm(sum(pick))
  m[!pick, "a2"] <- rnorm(sum(!pick))
  m[seq_len(20L), "b"] <- rnorm(20L)

  cl <- hvtiRbootstrap::boot_clusters(m, list(A = c("a", "a2"), B = "b"))

  expect_true(is.data.frame(cl))
  expect_setequal(cl$cluster, c("A", "B"))

  # Every replicate selected one form or the other, so the cluster is at 100%
  # while each member sits at 50%. n_any is NOT the sum of the members.
  expect_identical(cl$n_any[cl$cluster == "A"], n)
  expect_identical(cl$pct_any[cl$cluster == "A"], 100)
  expect_identical(cl$n_any[cl$cluster == "B"], 20L)
})

test_that("boot_clusters() refuses a cluster naming a term not in the pool", {
  skip_if_not_installed("hvtiRbootstrap")
  m <- matrix(c(1, NA, 2, 3), nrow = 2L, dimnames = list(NULL, c("a", "b")))
  # A typo here would otherwise group nothing and report an honest-looking 0%.
  expect_error(hvtiRbootstrap::boot_clusters(m, list(A = c("a", "typo"))),
               "typo")
})

test_that("boot_shortfall() reports a partial pool and stays silent on a full one", {
  skip_if_not_installed("hvtiRbootstrap")
  full    <- list(n_boot = 500L, n_chunks = 25L)
  partial <- list(n_boot = 200L, n_chunks = 10L)
  expect_null(hvtiRbootstrap::boot_shortfall(full, 25L, 500L))
  msg <- hvtiRbootstrap::boot_shortfall(partial, 25L, 500L)
  expect_true(is.character(msg) && nzchar(msg))
  # Both shortfalls named, not just the chunk count: a chunk that ran short is
  # not a missing chunk, and counting chunks alone would call that complete.
  expect_match(msg, "10 of 25 chunks")
  expect_match(msg, "200 of 500 replicates")
})
