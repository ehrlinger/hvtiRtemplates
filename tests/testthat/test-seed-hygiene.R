# Every random call in a shipped template is seeded where it runs, and every
# randomForestSRC-family call carries a negative `seed =`. The rule and its
# evidence are in helper-seed-hygiene.R.

test_that("every random call in a shipped template is seeded", {
  dir <- system.file("templates", package = "hvtiRtemplates")
  expect_true(nzchar(dir))
  # The scan must reach the forest jobs, or a clean result proves nothing.
  expect_true(all(c("30_analyses/rfc-fit.qmd", "30_analyses/rfs-explain.qmd") %in%
                    list.files(dir, pattern = "[.]qmd$", recursive = TRUE)))
  expect_identical(seed_hygiene_scan(dir), character(0))
})

test_that("the seed check catches what it exists to catch", {
  check <- function(...) seed_violations(c(...), "x.qmd")
  # Unseeded, and the forest's own seed missing.
  expect_match(check("f <- rfsrc(y ~ ., d)"), "x.qmd:1: rfsrc\\(\\) needs a negative", all = FALSE)
  expect_match(check("f <- rfsrc(y ~ ., d)"), "x.qmd:1: rfsrc\\(\\) is not seeded", all = FALSE)
  # set.seed() alone leaves rfsrc() drawing its own seed from R's generator.
  expect_match(check("set.seed(1)", "f <- rfsrc(y ~ ., d)"), "needs a negative")
  # A positive seed is not the form randomForestSRC takes as its own.
  expect_match(check("set.seed(1)", "f <- rfsrc(y ~ ., d, seed = SEED)"), "needs a negative")
  # cache_fit() without a seed does not seed the call it wraps.
  expect_match(check("v <- cache_fit('v', varpro(m, d, seed = -abs(S)))"), "varpro\\(\\) is not seeded")
  # A seed too far up, or in another chunk, has been spent by the time it runs.
  expect_match(check("set.seed(1)", "", "", "", "i <- sample(n)"), "x.qmd:5: sample\\(\\) is not seeded")
  expect_match(check("i <- sample(n)", "set.seed(1)"), "sample\\(\\) is not seeded")
  # Namespaced calls are seen too.
  expect_match(check("x <- stats::runif(3)"), "runif\\(\\) is not seeded")

  # The forms the templates use pass.
  expect_identical(check("f <- cache_fit('f', rfsrc(y ~ ., d, seed = -abs(SEED)), seed = SEED)"), character(0))
  expect_identical(check("set.seed(s)", "f <- rfsrc(y ~ ., d, seed = -abs(s))"), character(0))
  expect_identical(check("p <- withr::with_seed(SEED, sample(ids, 10))"), character(0))
  expect_identical(check("m <- mice(d, seed = 2026)"), character(0))
  # A call named in a comment or a string is not a call.
  expect_identical(check("# f <- rfsrc(y ~ ., d)", "msg <- 'rfsrc(y ~ ., d)'"), character(0))
  expect_match(check("x <- ("), "does not parse")
})
