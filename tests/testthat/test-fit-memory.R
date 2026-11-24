# fake_cgroup_v1() is in helper-run-job.R.
# The estimate depends on the installed boostmtree; every test here reads the 2.0.13 calibration unless it names
# a version, so the result does not move with the library the suite runs against.
local_mocked_bindings(.boostmtree_version = function() "2.0.13")
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

test_that("a 2,000-patient continuous fit at 8 cores and M = 500 is refused in Default and names Small", {
  # Measured on 2.0.13 at 18.3 GiB (#601), which a 19.2 GiB Default session cannot hold.
  need <- .boostmtree_need_gib(patients = 2000, visits = 16300, family = "continuous", cores = 8, m = 500)
  cg <- fake_cgroup_v1(19.2)
  expect_error(guard_memory(need, "a boostmtree fit", cores = 8, proc = cg$proc, sys = cg$sys),
               "^memory: .*19.2 GiB.*Default.*Small")
  cg <- fake_cgroup_v1(38.4)
  expect_silent(guard_memory(need, "a boostmtree fit", cores = 8, proc = cg$proc, sys = cg$sys))
})

test_that("COMMENCE at 8 cores and M = 500 passes in Default on 2.0.13 (failure 4 was 2.0.8's memory)", {
  need <- .boostmtree_need_gib(patients = 1391, visits = 4771, family = "continuous", cores = 8, m = 500)
  cg <- fake_cgroup_v1(19.2)
  expect_silent(guard_memory(need, "a boostmtree fit", cores = 8, proc = cg$proc, sys = cg$sys))
})

test_that("every continuous 2.0.13 peak measured for #601 sits at least 25% under its estimate", {
  # patients, visits, cores, M, peak GiB (the harnesses' MiB / 1024): R/fit-memory.R has the source of each row.
  peaks <- rbind(c(1000, 8202, 4, 10, 1.983), c(1000, 8202, 8, 10, 3.209), c(2000, 16300, 8, 10, 6.778),
                 c(4000, 32137, 4, 10, 10.612), c(1000, 8202, 4, 10, 2.581), c(2000, 16300, 8, 10, 8.272),
                 c(1000, 8202, 4, 500, 4.155), c(1000, 8202, 4, 500, 5.021),
                 c(2000, 16300, 8, 500, 17.088), c(2000, 16300, 8, 500, 18.325), c(1391, 4771, 8, 10, 3.729),
                 c(1391, 4771, 8, 500, 9.160))
  for (i in seq_len(nrow(peaks))) {
    r <- peaks[i, ]
    need <- .boostmtree_need_gib(r[1], r[2], "continuous", r[3], r[4])
    expect_gte(need, 1.25 * r[5], label = paste(r, collapse = " "))
  }
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
  fit <- function(k) .boostmtree_need_gib(2000, 16300, "continuous", k, 500)
  expect_error(guard_memory(fit(8), "x", cores = 8, cores_fit = fit, proc = cg$proc, sys = cg$sys),
               "CORES <- 2\\b")
})

test_that("an NA need cannot be estimated and passes", {
  cg <- fake_cgroup_v1(19.2)
  expect_silent(guard_memory(NA_real_, "x", proc = cg$proc, sys = cg$sys))
})

test_that("below 2.0.13 the estimate is the 2.0.8 calibration, unchanged", {
  # nb-boostmtree.qmd still accepts 2.0.8. COMMENCE on 2.0.8 (1,391 / 4,771 / continuous / 8 cores / M = 1000)
  # was killed in Default; the 2.0.8 estimate keeps it out, the 2.0.13 one would let it in.
  old <- .boostmtree_need_gib(1391, 4771, "continuous", 8, 1000, version = "2.0.8")
  expect_equal(old, 1 + 8 * 2.6 * 1.391^1.7, tolerance = 1e-6)
  expect_gt(old, 0.9 * 19.2)
  expect_lt(.boostmtree_need_gib(1391, 4771, "continuous", 8, 1000, version = "2.0.13"), 0.9 * 19.2)
  expect_equal(.boostmtree_need_gib(5500, 13900, "ordinal", 8, 1000, version = "2.0.12"),
               1 + 8 * 0.5 * 5.5^1.7 + 0.35e-3 * 1000 * 13.9, tolerance = 1e-6)
  expect_equal(.boostmtree_need_gib(1391, 4771, "binary", 8, 1000, version = "2.0.8"), old, tolerance = 1e-6)
  # A version that cannot be read takes the 2.0.8 path, the larger estimate.
  expect_equal(.boostmtree_need_gib(1391, 4771, "continuous", 8, 1000, version = NA_character_), old,
               tolerance = 1e-6)
})

test_that("the estimates sit where the calibration says", {
  expect_equal(.boostmtree_need_gib(1391, 4771, "continuous", 8, 500), 12.5, tolerance = 0.01)
  expect_equal(.boostmtree_need_gib(1391, 4771, "continuous", 3, 1000), 6.7, tolerance = 0.01)
  expect_equal(.boostmtree_need_gib(2000, 16300, "continuous", 8, 500), 27.9, tolerance = 0.01)
  expect_equal(.boostmtree_need_gib(5500, 13900, "ordinal", 8, 1000), 78.4, tolerance = 0.01)
  # Growth is the larger of per core x visits and visits squared: the second binds with many visits on few cores.
  expect_equal(.boostmtree_need_gib(4000, 32137, "continuous", 4, 500),
               1 + 4 * 0.56 * 4^1.7 + 9.1e-5 * 500 * 32.137^2, tolerance = 1e-6)
  # An unmeasured family takes the larger coefficient and the larger growth, doubled.
  expect_equal(.boostmtree_need_gib(1391, 4771, "binary", 8, 500),
               2 * .boostmtree_need_gib(1391, 4771, "continuous", 8, 500), tolerance = 1e-6)
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
  skip_on_os("windows") # no file name there can hold ':'
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
  fit <- function(k) .boostmtree_need_gib(2000, 16300, "continuous", k, 500)
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
