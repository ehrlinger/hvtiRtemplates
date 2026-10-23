# fake_cgroup_v1() is in helper-run-job.R.
test_that("the v1 limit is read under the memory controller", {
  cg <- fake_cgroup_v1(19.2)
  m <- .cgroup_memory(cg$proc, cg$sys)
  expect_equal(m$limit_gib, 19.2, tolerance = 1e-6)
  expect_identical(m$source, "cgroup v1")
})

test_that("an unlimited leaf beneath a capped parent takes the parent's cap", {
  cg <- fake_cgroup_v1(NA, parent_gib = 76.8, usage_gib = 40, peak_gib = 50)
  m <- .cgroup_memory(cg$proc, cg$sys)
  expect_equal(m$limit_gib, 76.8, tolerance = 1e-6)
  expect_identical(m$source, "cgroup v1")
  expect_equal(m$usage_gib, 40, tolerance = 1e-6)
})

test_that("a v2 memory.max of 'max' all the way up reads as no cgroup limit", {
  d <- withr::local_tempdir()
  writeLines("0::/user.slice/s", file.path(d, "cgroup"))
  dir.create(file.path(d, "sys", "user.slice", "s"), recursive = TRUE)
  writeLines("max", file.path(d, "sys", "user.slice", "s", "memory.max"))
  m <- .cgroup_memory(file.path(d, "cgroup"), file.path(d, "sys"))
  expect_identical(m$source, "physical")
})

test_that("the profile named is the smallest whose cap holds the need", {
  expect_identical(.profile_for(25), "Small")    # the cap holds 90 percent of 38.4
  expect_identical(.profile_for(40), "Medium")
  expect_identical(.profile_for(80), "Large")
  expect_identical(.profile_for(500), "none")
})

test_that("COMMENCE at 8 cores is refused in a Default session and passes in Medium (failure 4)", {
  need <- .boostmtree_need_gib(patients = 1391, visits = 4771, family = "continuous", cores = 8, m = 1000)
  cg <- fake_cgroup_v1(19.2)
  expect_error(guard_memory(need, "a boostmtree fit", cores = 8, proc = cg$proc, sys = cg$sys),
               "^memory: .*19.2 GiB.*Default.*Medium")
  cg <- fake_cgroup_v1(76.8)
  expect_silent(guard_memory(need, "a boostmtree fit", cores = 8, proc = cg$proc, sys = cg$sys))
})

test_that("Penny's ordinal fit at 8 cores is refused in a Medium session (failure 5)", {
  need <- .boostmtree_need_gib(patients = 5500, visits = 13900, family = "ordinal", cores = 8, m = 1000)
  cg <- fake_cgroup_v1(76.8)
  expect_error(guard_memory(need, "a boostmtree fit", cores = 8, proc = cg$proc, sys = cg$sys),
               "^memory: .*76.8 GiB.*Medium")
})

test_that("a need of 0 (a cached rerender) passes and records the memory check", {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "x.run.progress")
  .progress_begin(f, "fit")
  withr::defer(.progress_finish())
  cg <- fake_cgroup_v1(19.2)
  guard_memory(0, "x", proc = cg$proc, sys = cg$sys)
  expect_true("memory" %in% yaml::read_yaml(f)$checks)
})

test_that("the refusal names the CORES that would fit this session", {
  cg <- fake_cgroup_v1(19.2)
  fit <- function(k) .boostmtree_need_gib(1391, 4771, "continuous", k, 1000)
  expect_error(guard_memory(fit(8), "x", cores = 8, cores_fit = fit, proc = cg$proc, sys = cg$sys),
               "CORES <- [0-9]+")
})

test_that("an NA need cannot be estimated and passes", {
  cg <- fake_cgroup_v1(19.2)
  expect_silent(guard_memory(NA_real_, "x", proc = cg$proc, sys = cg$sys))
})

test_that("the estimates sit where the calibration says", {
  expect_equal(.boostmtree_need_gib(1391, 4771, "continuous", 8, 1000), 37.5, tolerance = 0.01)
  expect_equal(.boostmtree_need_gib(1391, 4771, "continuous", 3, 1000), 14.7, tolerance = 0.01)
  expect_equal(.boostmtree_need_gib(5500, 13900, "ordinal", 8, 1000), 78.4, tolerance = 0.01)
  expect_true(is.na(.boostmtree_need_gib(NA_real_, 1, "ordinal", 8, 1000)))
  expect_error(.boostmtree_need_gib(-1, 1, "ordinal", 8, 1000), "non-negative")
})

test_that("with no progress file active, guard_memory and a passed check leave no state behind", {
  rm(list = ls(.progress_state, all.names = TRUE), envir = .progress_state)
  cg <- fake_cgroup_v1(19.2)
  guard_memory(4, "x", proc = cg$proc, sys = cg$sys)
  .progress_check_passed("render_r")
  expect_length(ls(.progress_state, all.names = TRUE), 0L)
})

test_that("a cgroup path holding ':' is read whole", {
  d <- withr::local_tempdir()
  writeLines("7:memory:/rstudio/a:b", file.path(d, "cgroup"))
  leaf <- file.path(d, "sys", "memory", "rstudio", "a:b")
  dir.create(leaf, recursive = TRUE)
  writeLines(format(round(19.2 * 1024^3), scientific = FALSE), file.path(leaf, "memory.limit_in_bytes"))
  m <- .cgroup_memory(file.path(d, "cgroup"), file.path(d, "sys"))
  expect_equal(m$limit_gib, 19.2, tolerance = 1e-6)
  expect_identical(m$source, "cgroup v1")
})

test_that("a refusal on physical memory says no cgroup limit was found", {
  d <- withr::local_tempdir()
  expect_error(guard_memory(1e6, "this fit", proc = file.path(d, "none"), sys = file.path(d, "none")),
               "^memory: .*GiB \\(physical memory: no cgroup limit found\\)")
})

test_that("guard_memory refuses arguments of the wrong shape, plainly", {
  cg <- fake_cgroup_v1(19.2)
  g <- function(...) guard_memory(proc = cg$proc, sys = cg$sys, ...)
  expect_error(g(c(1, 2), "x"), "need_gib")
  expect_error(g("1", "x"), "need_gib")
  expect_error(g(1, c("a", "b")), "why")
  expect_error(g(1, 3), "why")
  expect_error(g(1, NA_character_), "why")
  for (bad in list(0, NA, 8.5, -2, c(2, 4), "8")) expect_error(g(1, "x", cores = bad), "cores", label = deparse(bad))
  expect_silent(g(NA_real_, "x", cores = 8))
  expect_silent(g(1, "x", cores = NULL))
  fit <- function(k) .boostmtree_need_gib(1391, 4771, "continuous", k, 1000)
  expect_error(g(fit(8), "x", cores = 8, cores_fit = fit), "with 8 cores.*CORES <- [0-9]+")  # 8 (double) coerced, used as a count
})

test_that("a cores_fit that returns NA never names CORES <- NA", {
  cg <- fake_cgroup_v1(19.2)
  err <- expect_error(guard_memory(100, "x", cores = 8, cores_fit = function(k) NA_real_, proc = cg$proc, sys = cg$sys),
                      "^memory: ")
  expect_no_match(conditionMessage(err), "CORES <- NA", fixed = TRUE)
})

test_that(".cache_would_fit() follows cache_fit()'s own decision, against a real cache", {
  dir <- withr::local_tempdir()
  a <- 2
  # No file: cache_fit() computes.
  expect_true(.cache_would_fit("f", quote(a * 3), seed = 7, dir = dir))
  # The file is written by the inline form the template used before; the quoted form must read the same key.
  suppressMessages(hvtiRutilities::cache_fit("f", a * 3, seed = 7, dir = dir))
  code <- quote(a * 3)
  expect_false(.cache_would_fit("f", code, seed = 7, dir = dir, refit = FALSE))
  expect_false(.cache_would_fit("f", code, seed = 7, dir = dir, refit = TRUE))   # a matching key loads, REFIT or not
  expect_message(hvtiRutilities::cache_fit("f", code, seed = 7, dir = dir, refit = TRUE), "loaded")
  # A changed input: stale. cache_fit() stops without REFIT and recomputes with it.
  a <- 5
  expect_false(.cache_would_fit("f", code, seed = 7, dir = dir, refit = FALSE))
  expect_true(.cache_would_fit("f", code, seed = 7, dir = dir, refit = TRUE))
  expect_true(.cache_would_fit("f", code, seed = 8, dir = withr::local_tempdir(), refit = TRUE))
  # An unkeyed file recomputes under REFIT.
  saveRDS(1, file.path(dir, "g.rds"))
  expect_true(.cache_would_fit("g", code, dir = dir, refit = TRUE))
  expect_false(.cache_would_fit("g", code, dir = dir, refit = FALSE))
})
