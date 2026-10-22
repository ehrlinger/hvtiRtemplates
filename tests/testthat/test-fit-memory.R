# fake_cgroup_v1() is in helper-run-job.R.
# fake_cgroup_v1() is in helper-run-job.R (Task 1).
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
               "^memory: .*19.2 GiB.*Default.*Small")
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
  skip_if_not(exists(".progress_check_passed", mode = "function"))  # Task 3 defines it and removes this skip
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
  expect_equal(.boostmtree_need_gib(1391, 4771, "continuous", 8, 1000), 22.0, tolerance = 0.01)
  expect_equal(.boostmtree_need_gib(1391, 4771, "continuous", 6, 1000), 16.8, tolerance = 0.01)
  expect_equal(.boostmtree_need_gib(5500, 13900, "ordinal", 8, 1000), 78.4, tolerance = 0.01)
  expect_true(is.na(.boostmtree_need_gib(NA_real_, 1, "ordinal", 8, 1000)))
  expect_error(.boostmtree_need_gib(-1, 1, "ordinal", 8, 1000), "non-negative")
})
