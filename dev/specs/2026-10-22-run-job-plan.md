# run_job Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One command, `hvti run <job>` in a terminal or `run_job(<job>)` in R, that refuses every
2026-10-22 failure up front with a plain reason and the exact fix, and explains in plain words any
failure it could not foresee.

**Architecture:** There are four layers, each a small file.
- Pure check functions return a common `check` record (`R/preflight.R`, `R/fit-memory.R`).
- `run_job()` runs the pre-submit checks, calls `submit_job()`, then waits for the in-render checks
  (`render_r`, `memory`), which record themselves in `.run.progress` (`R/run-job.R`).
- `job_status()` gains a diagnosis read from the log and `.run.yml` (`R/diagnose.R`).
- A POSIX `sh` script, `inst/bin/hvti`, picks the lock's R before any R starts.

The snapshot guard is two separate pull requests, in hvtiRutilities and then hvtiR (tasks 11–12).

**Tech Stack:** R (base, `jsonlite`, `yaml`, `ps`, already in Imports), testthat 3e with
`local_mocked_bindings()`, POSIX `sh`.

**Spec:** `dev/specs/2026-10-22-run-job-design.md`. Section numbers below (§) refer to it.

## Global Constraints

- No new Imports. `jsonlite`, `yaml` and `ps` are already in `DESCRIPTION`.
- Roxygen is Rd markup (`\code{}`, `\strong{}`), not markdown. Run `devtools::document()` and commit
  `man/` and `NAMESPACE` with the source.
- Lines ≤ 135 characters (`.lintr`).
- Every check result is a `check` record: `list(name = <chr>, ok = <lgl>, message = <chr|NULL>,
  fix = <chr|NULL>, note = <chr|NULL>)`. `message` and `fix` are non-NULL exactly when `ok` is FALSE.
- Check names are fixed: `r_version`, `packages`, `run_state`, `quarto`, `render_r`, `memory`. A
  refusal's text begins with `<name>: `.
- Nothing calls base `getRversion()`, `R.home()` or reads `/proc` or `/sys` directly inside a check.
  The checks go through `.session_r()`, `.r_home()` and the `proc`/`sys` arguments, so tests can mock
  them. Base functions cannot be mocked.
- Every test runs in `withr::local_tempdir()`, with fixture lockfiles, cgroup trees and `/opt/R`
  trees. No test touches a study share or needs Workbench. Shell-script tests carry
  `skip_on_os("windows")`.
- The implementing pull request adds `news/<branch>.md` and does not touch `Version:` or `NEWS.md`
  (AGENTS.md, "Bump when you name a version"). This spec-and-plan PR ships nothing (`dev/` is in
  `.Rbuildignore`), so it carries no fragment.
- Copilot's quota is exhausted, so run `/code-review` locally before opening the implementation PR
  and say so in its body.

---

## File structure

| file | responsibility |
|---|---|
| `R/preflight.R` (new) | the `check` record, `.session_r()`, `.r_home()`, lockfile reading, checks `r_version`, `packages`, `quarto`, `run_state`, `render_r`, and `.report_checks()` |
| `R/fit-memory.R` (new) | `.cgroup_memory()`, `.workbench_profiles`, `.boostmtree_need_gib()`, exported `guard_memory()` |
| `R/run-job.R` (new) | exported `run_job()`, `.expected_checks()`, `.wait_for_checks()`, exported `install_hvti()` |
| `R/diagnose.R` (new) | `.diagnose_failure()` |
| `R/job-progress.R` (modify) | `mem_gib` and `checks` in each write, `.progress_check_passed()` |
| `R/background-job.R` (modify) | export `HVTI_RUN_R` to the runner, record the memory peak, print memory and diagnosis in `job_status()` |
| `R/job-setup.R` (modify) | call `.check_render_r()` |
| `inst/bin/hvti` (new) | the shell command |
| `inst/templates/30_analyses/nb-boostmtree.qmd` (modify) | `guard_memory()` in the fit chunk, the CORES comment pointing at `R/fit-memory.R` |
| `tests/testthat/test-preflight.R`, `test-fit-memory.R`, `test-run-job.R`, `test-diagnose.R`, `test-hvti-command.R` (new) | one file per unit |
| `tests/testthat/fixtures-diagnose/*.log` (new) | logs cut from 2026-10-22, with no data in them |

Before Task 1, confirm the nb-boostmtree template's path with
`ls inst/templates/*/nb-boostmtree*.qmd` and use what it prints wherever this plan names it.

---

### Task 1: the check record, lockfile reading, `r_version` and `packages`

Implements §4.1 and §4.2, failures 1 and 3.

**Files:**
- Create: `R/preflight.R`
- Create: `tests/testthat/helper-run-job.R` (fixtures every later task's tests use; testthat loads
  `helper-*.R` before any filtered run, so `devtools::test(filter = ...)` sees them)
- Modify: `tests/testthat/test-background-job.R` (move `status_job()` from lines 1–6 into the helper)
- Test: `tests/testthat/test-preflight.R`

**Interfaces:**
- Produces: `.check(name, ok, message = NULL, fix = NULL, note = NULL)` returns a `check` record.
  `.session_r()` and `.r_home()` wrap `getRversion()` and `R.home("bin")`. `.lock_read(root)` returns
  the parsed lock, a list, or NULL when there is none. `.lock_r_version(root)` returns a chr(1) or NA.
  `.check_r_version(root)` and `.check_packages(path, root)` return `check` records.
  `.job_packages(path)` returns a character vector.

- [ ] **Step 0: Write the shared fixtures** in `tests/testthat/helper-run-job.R`, and delete
  `status_job()` from the top of `test-background-job.R`, so it is defined once:

```r
# A set-up study (so .find_study_root() accepts it, which needs _study.yml) with a renv.lock.
lock_study <- function(r = "4.5.3", pkgs = list(quarto = "1.4.4", knitr = "1.48"), env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  invisible(hvtiRutilities::study_setup(root, "Example", 1L, renv = FALSE))
  lock <- list(R = list(Version = r, Repositories = list()),
               Packages = lapply(names(pkgs), function(p) list(Package = p, Version = pkgs[[p]])))
  names(lock$Packages) <- names(pkgs)
  jsonlite::write_json(lock, file.path(root, "renv.lock"), auto_unbox = TRUE, pretty = TRUE)
  dir.create(file.path(root, "analyses"), showWarnings = FALSE)
  root
}

status_job <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  job <- file.path(dir, "nb.boostmtree.x.boost.qmd")
  writeLines("---\ntitle: x\n---", job)
  job
}

# A cgroup v1 tree: the session's leaf under the memory controller, optionally beneath a capped parent.
fake_cgroup_v1 <- function(limit_gib, usage_gib = 1, peak_gib = 2, parent_gib = NULL, env = parent.frame()) {
  d <- withr::local_tempdir(.local_envir = env)
  proc <- file.path(d, "cgroup")
  writeLines(c("12:cpu,cpuacct:/rstudio/s1", "7:memory:/rstudio/s1", "1:name=systemd:/x"), proc)
  b <- function(g) if (is.na(g)) "9223372036854771712" else format(round(g * 1024^3), scientific = FALSE)
  put <- function(dir, lim, use, peak) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    writeLines(b(lim), file.path(dir, "memory.limit_in_bytes"))
    writeLines(b(use), file.path(dir, "memory.usage_in_bytes"))
    writeLines(b(peak), file.path(dir, "memory.max_usage_in_bytes"))
  }
  put(file.path(d, "sys", "memory", "rstudio", "s1"), limit_gib, usage_gib, peak_gib)
  if (!is.null(parent_gib)) put(file.path(d, "sys", "memory", "rstudio"), parent_gib, usage_gib, peak_gib)
  list(proc = proc, sys = file.path(d, "sys"))
}
```

- [ ] **Step 1: Write the failing tests**

```r
test_that("r_version refuses a session R whose major.minor differs from the lock's (failure 1)", {
  root <- lock_study(r = "4.5.3")
  testthat::local_mocked_bindings(.session_r = function() numeric_version("4.6.1"))
  ck <- .check_r_version(root)
  expect_false(ck$ok)
  expect_match(ck$message, "^r_version: .*4[.]5[.]3.*4[.]6[.]1")
  expect_match(ck$fix, "hvti run", fixed = TRUE)
  expect_match(ck$fix, "/opt/R/4.5.3/bin/R", fixed = TRUE)
})

test_that("r_version passes a patch difference with a note", {
  root <- lock_study(r = "4.5.1")
  testthat::local_mocked_bindings(.session_r = function() numeric_version("4.5.3"))
  ck <- .check_r_version(root)
  expect_true(ck$ok)
  expect_match(ck$note, "4.5.1", fixed = TRUE)
})

test_that("r_version passes a study with no lock", {
  root <- withr::local_tempdir()
  expect_true(.check_r_version(root)$ok)
})

test_that("packages refuses a needed package missing from the lock (failure 3)", {
  root <- lock_study(pkgs = list(knitr = "1.48"))
  job <- file.path(root, "analyses", "x.qmd")
  writeLines(c("```{r}", "#| label: setup", "library(knitr)", "```"), job)
  testthat::local_mocked_bindings(.installed_version = function(p) "1.4.4")
  ck <- .check_packages(job, root)
  expect_false(ck$ok)
  expect_match(ck$message, "^packages: .*quarto.*not recorded in renv.lock")
  expect_match(ck$fix, "hvtiR::update()", fixed = TRUE)
})

test_that("packages refuses a locked package missing from the library", {
  root <- lock_study()
  job <- file.path(root, "analyses", "x.qmd")
  writeLines(c("```{r}", "#| label: setup", "library(knitr)", "```"), job)
  testthat::local_mocked_bindings(.installed_version = function(p) if (p == "quarto") NA_character_ else "1.48")
  ck <- .check_packages(job, root)
  expect_false(ck$ok)
  expect_match(ck$fix, 'renv::restore(packages = "quarto")', fixed = TRUE)
})

test_that("packages refuses a version that differs between library and lock", {
  root <- lock_study(pkgs = list(quarto = "1.4.4", knitr = "1.48"))
  job <- file.path(root, "analyses", "x.qmd")
  writeLines(c("```{r}", "#| label: setup", "library(knitr)", "```"), job)
  testthat::local_mocked_bindings(.installed_version = function(p) if (p == "knitr") "1.50" else "1.4.4",
                                  .always_needed = function() c("quarto", "knitr"))
  ck <- .check_packages(job, root)
  expect_false(ck$ok)
  expect_match(ck$message, "knitr 1.50 installed, 1.48 locked", fixed = TRUE)
})

test_that("drift in a package the job does not load is a note, not a refusal", {
  root <- lock_study(pkgs = list(quarto = "1.4.4", knitr = "1.48", sf = "1.0"))
  job <- file.path(root, "analyses", "x.qmd")
  writeLines(c("```{r}", "#| label: setup", "library(knitr)", "```"), job)
  testthat::local_mocked_bindings(.installed_version = function(p) if (p == "sf") "1.1" else
                                    c(quarto = "1.4.4", knitr = "1.48")[[p]],
                                  .always_needed = function() c("quarto", "knitr"))
  ck <- .check_packages(job, root)
  expect_true(ck$ok)
  expect_match(ck$note, "sf", fixed = TRUE)
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "preflight")'`
Expected: FAIL, `could not find function ".check_r_version"`.

- [ ] **Step 3: Write the implementation**

```r
# The checks run_job() makes, each returning one record so the report and the tests read them the
# same way. Design: dev/specs/2026-10-22-run-job-design.md.
.check <- function(name, ok, message = NULL, fix = NULL, note = NULL) {
  list(name = name, ok = ok, message = if (!ok) paste0(name, ": ", message), fix = fix, note = note)
}

# Wrapped so tests can stand in for them; base functions cannot be mocked.
.session_r <- function() getRversion()
.r_home <- function() R.home("bin")
.installed_version <- function(p) {
  tryCatch(as.character(utils::packageVersion(p)), error = function(e) NA_character_)
}
.always_needed <- function() c("quarto", "knitr", "rmarkdown", "hvtiRtemplates", "hvtiRutilities")

.lock_read <- function(root) {
  f <- file.path(root, "renv.lock")
  if (!file.exists(f)) return(NULL)
  jsonlite::read_json(f, simplifyVector = FALSE)
}

.lock_r_version <- function(root) {
  v <- .lock_read(root)$R$Version
  if (is.character(v) && length(v) == 1L) v else NA_character_
}

.minor <- function(v) paste(unlist(numeric_version(v))[1:2], collapse = ".")

# renv keeps one library per major.minor, so only that has to agree.
.check_r_version <- function(root) {
  lock <- .lock_r_version(root)
  have <- as.character(.session_r())
  if (is.na(lock)) return(.check("r_version", TRUE))
  if (.minor(lock) != .minor(have)) {
    return(.check("r_version", FALSE,
                  sprintf("this study's renv.lock records R %s, but this session is R %s, so it would use a different package library.",
                          lock, have),
                  sprintf("Run it from a terminal with `hvti run <job>`, or start R %s (/opt/R/%s/bin/R).", lock, lock)))
  }
  .check("r_version", TRUE, note = if (lock != have) sprintf("renv.lock records R %s; this session is %s (same library).", lock, have))
}

# What the job's own setup chunk loads, read the way .template_packages() reads a template.
.job_packages <- function(path) {
  pk <- tryCatch(.template_packages(path)$package, error = function(e) character())
  unique(c(pk, .always_needed()))
}

.check_packages <- function(path, root) {
  lock <- .lock_read(root)
  if (is.null(lock)) return(.check("packages", TRUE, note = "no renv.lock; packages not checked."))
  locked <- vapply(lock$Packages, function(p) p$Version, "")
  need <- .job_packages(path)
  have <- vapply(need, .installed_version, "")
  bad <- character(); fix <- character()
  for (p in need) {
    l <- if (p %in% names(locked)) locked[[p]] else NA_character_
    h <- have[[p]]
    if (is.na(h) && is.na(l)) {
      bad <- c(bad, sprintf("%s is neither installed nor recorded in renv.lock", p))
      fix <- c(fix, "hvtiR::update()")
    } else if (is.na(l)) {
      bad <- c(bad, sprintf("%s %s is installed but not recorded in renv.lock", p, h))
      fix <- c(fix, "hvtiR::update()")
    } else if (is.na(h)) {
      bad <- c(bad, sprintf("%s %s is recorded in renv.lock but not installed", p, l))
      fix <- c(fix, sprintf('renv::restore(packages = "%s")', p))
    } else if (h != l) {
      bad <- c(bad, sprintf("%s %s installed, %s locked", p, h, l))
      fix <- c(fix, if (numeric_version(h) > numeric_version(l)) "hvtiR::update()" else sprintf('renv::restore(packages = "%s")', p))
    }
  }
  other <- setdiff(names(locked), need)
  drift <- other[vapply(other, function(p) !identical(.installed_version(p), locked[[p]]), NA)]
  note <- if (length(drift)) sprintf("%d package(s) this job does not load differ from renv.lock: %s.",
                                      length(drift), paste(drift, collapse = ", "))
  if (length(bad)) return(.check("packages", FALSE, paste0(paste(bad, collapse = "; "), "."),
                                 paste(unique(fix), collapse = "\n"), note))
  .check("packages", TRUE, note = note)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "preflight")'`
Expected: PASS, 0 failures.

- [ ] **Step 5: Mutation check**

Change `.minor(lock) != .minor(have)` to `lock != have` and confirm the patch-difference test goes
red. Then delete the `is.na(l)` branch and confirm the failure-3 test goes red. Revert both.

- [ ] **Step 6: Commit**

```bash
git add R/preflight.R tests/testthat/test-preflight.R
git commit -m "feat(run_job): r_version and packages checks against renv.lock"
```

---

### Task 2: cgroup memory, the profile table, and `guard_memory()`

Implements §5.2, failures 4 and 5.

**Files:**
- Create: `R/fit-memory.R`
- Test: `tests/testthat/test-fit-memory.R`

**Interfaces:**
- Produces: `.cgroup_memory(proc = "/proc/self/cgroup", sys = "/sys/fs/cgroup")` returns
  `list(limit_gib, usage_gib, peak_gib, source)`, any element possibly NA, with `source` one of
  `"cgroup v1"`, `"cgroup v2"` or `"physical"`. `.workbench_profiles` is a data.frame with columns
  `profile` and `cap_gib`. `.profile_for(need_gib)` returns chr(1). `.boostmtree_need_gib(patients,
  visits, family, cores, m)` returns a numeric GiB value. `guard_memory(need_gib, why, cores = NULL,
  cores_fit = NULL, proc =, sys =)` returns the limit invisibly, or stops with the `memory:` refusal.
  `.progress_check_passed("memory")` is called on a pass; Task 3 defines it, and until then use
  `if (exists(".progress_check_passed")) .progress_check_passed("memory")`.

- [ ] **Step 1: Write the failing tests**

```r
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
  expect_identical(.profile_for(25), "Small")    # 25 <= 0.9 * 38.4
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "fit-memory")'`
Expected: FAIL, `could not find function ".cgroup_memory"`.

- [ ] **Step 3: Write the cgroup reader, the profile table and the guard**

```r
# Workbench enforces about 1.2 times the profile's memory (measured 2026-10-22).
.workbench_profiles <- data.frame(profile = c("Default", "Small", "Medium", "Large"),
                                  cap_gib = c(19.2, 38.4, 76.8, 153.6))

.profile_for <- function(need_gib) {
  i <- which(.workbench_profiles$cap_gib * 0.9 >= need_gib)[1L]
  if (is.na(i)) "none" else .workbench_profiles$profile[i]
}

.read_bytes_gib <- function(f) {
  if (!file.exists(f)) return(NA_real_)
  x <- trimws(readLines(f, n = 1L, warn = FALSE))
  v <- suppressWarnings(as.numeric(x))
  # v1 writes a value near 2^63 for "no limit"; v2 writes "max".
  if (is.na(v) || v > 2^60) NA_real_ else v / 1024^3
}

# A detached job counts against its submitting session's cgroup, so this is the cap the fit will hit.
# An unlimited leaf can sit beneath a capped ancestor, so the binding cap is the smallest finite one
# from the leaf up to the controller's root; usage and peak are read at that same cgroup.
.cgroup_memory <- function(proc = "/proc/self/cgroup", sys = "/sys/fs/cgroup") {
  lines <- if (file.exists(proc)) readLines(proc, warn = FALSE) else character()
  parts <- strsplit(lines, ":", fixed = TRUE)
  v1 <- Filter(function(p) length(p) >= 3L && "memory" %in% strsplit(p[2L], ",", fixed = TRUE)[[1L]], parts)
  v2 <- Filter(function(p) length(p) >= 3L && p[1L] == "0" && p[2L] == "", parts)
  spec <- if (length(v1)) {
    list(base = file.path(sys, "memory"), rel = v1[[1L]][3L], source = "cgroup v1",
         files = c("memory.limit_in_bytes", "memory.usage_in_bytes", "memory.max_usage_in_bytes"))
  } else if (length(v2)) {
    list(base = sys, rel = v2[[1L]][3L], source = "cgroup v2", files = c("memory.max", "memory.current", "memory.peak"))
  }
  out <- list(limit_gib = NA_real_, usage_gib = NA_real_, peak_gib = NA_real_, source = "physical")
  if (!is.null(spec)) {
    segs <- strsplit(sub("^/", "", spec$rel), "/", fixed = TRUE)[[1L]]
    for (i in rev(seq_len(length(segs) + 1L) - 1L)) {   # leaf first, then each ancestor, then the root
      d <- do.call(file.path, as.list(c(spec$base, segs[seq_len(i)])))
      lim <- .read_bytes_gib(file.path(d, spec$files[1L]))
      if (!is.na(lim) && (is.na(out$limit_gib) || lim < out$limit_gib)) {
        out <- list(limit_gib = lim, usage_gib = .read_bytes_gib(file.path(d, spec$files[2L])),
                    peak_gib = .read_bytes_gib(file.path(d, spec$files[3L])), source = spec$source)
      }
    }
  }
  if (is.na(out$limit_gib)) {
    out$limit_gib <- tryCatch(as.numeric(ps::ps_system_memory()$total) / 1024^3, error = function(e) NA_real_)
    out$source <- "physical"
  }
  out
}
```

`guard_memory()` with roxygen. It is `@export`, with `@return` and `\donttest{}` examples per the
Cookbook. Its `@details` say the v1 peak is the session's:

```r
guard_memory <- function(need_gib, why, cores = NULL, cores_fit = NULL,
                         proc = "/proc/self/cgroup", sys = "/sys/fs/cgroup") {
  m <- .cgroup_memory(proc, sys)
  # Recorded so job_status() can name the right profile if the fit dies anyway (spec section 6).
  .progress_state$mem_need_gib <- round(need_gib, 1)
  if (is.na(m$limit_gib) || need_gib <= 0.9 * m$limit_gib) {
    if (exists(".progress_check_passed", mode = "function")) .progress_check_passed("memory")
    return(invisible(m$limit_gib))
  }
  here <- .workbench_profiles$profile[match(TRUE, abs(.workbench_profiles$cap_gib - m$limit_gib) < 0.5)]
  where <- if (is.na(here)) sprintf("%.1f GiB", m$limit_gib) else sprintf("%.1f GiB (Workbench \"%s\")", m$limit_gib, here)
  to <- .profile_for(need_gib)
  k <- if (is.function(cores_fit) && !is.null(cores)) {
    ok <- Filter(function(k) cores_fit(k) <= 0.9 * m$limit_gib, seq_len(cores - 1L))
    if (length(ok)) max(unlist(ok))
  }
  stop(sprintf("memory: %s needs about %.0f GiB%s and this session is capped at %s. %s%s",
               why, need_gib, if (!is.null(cores)) sprintf(" with %d cores", cores) else "", where,
               if (to == "none") "No Workbench profile holds it: reduce CORES or the data." else
                 sprintf("Start a \"%s\" session (%.1f GiB) or larger.", to,
                         .workbench_profiles$cap_gib[.workbench_profiles$profile == to]),
               if (!is.null(k)) sprintf(" Or set CORES <- %d to fit in this one.", k) else ""),
       call. = FALSE)
}
```

- [ ] **Step 4: Calibrate `.boostmtree_need_gib()`.** This step is a decision for John.

Form: `need = base + cores * worker`, with `worker = a * family_factor * (visits / 1000)^p`, plus
the per-step growth from the CORES comment, `0.35e-3 GiB * m * visits / 1000` for an ordinal
response. The constraints, each a test in Step 1:
- COMMENCE (1,391 / 4,771 / continuous / 8 cores, boostmtree 2.0.8): need > 0.9 × 19.2, because it
  was killed there, and ≤ 0.9 × 76.8, because it ran in Medium.
- Penny's fit (5,500 / 13,900 / ordinal / 8 cores, 2.0.8): need > 0.9 × 76.8, because it was killed
  at iteration 2.
- Add the Large pass test (≤ 0.9 × 153.6) **only after** Penny's Large run, started 2026-10-22 13:26
  on lri-r03, records its peak. Until then that bound is unknown, and the comment says so.

Write the coefficients and a comment giving each data point's source and date. The 2.0.4 rows of
the template's CORES table are older numbers: 2.0.8's workers need about a third of 2.0.4's memory.
Use them for the shape `p` only, not the level. Present the chosen coefficients and margin to John
before committing.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "fit-memory")'`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
Rscript -e 'devtools::document()'
git add R/fit-memory.R tests/testthat/test-fit-memory.R man/guard_memory.Rd NAMESPACE
git commit -m "feat(guard_memory): refuse a fit the session's memory cap cannot hold"
```

---

### Task 3: progress records the checks and memory, and the runner records the peak

Implements §5.3, the progress half, and §6, peak tracking.

**Files:**
- Modify: `R/job-progress.R` (`.progress_write()` and the state it reads)
- Modify: `R/background-job.R` (`.runner_lines()`, `job_status()` printing)
- Test: `tests/testthat/test-job-progress.R`, `tests/testthat/test-background-job.R`

**Interfaces:**
- Consumes: `.cgroup_memory()` (Task 2).
- Produces: `.progress_check_passed(name)` appends to `.progress_state$checks` and writes.
  Progress records now carry `checks` (character) and `mem_gib` (numeric). `.run.yml` carries
  `mem_peak_gib` and `mem_limit_gib` when they are known. `job_status()` prints
  `  memory: <peak> of <limit> GiB (peak)` when both are present.

- [ ] **Step 1: Write the failing tests**

```r
test_that("a passed check is recorded in the progress file", {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "x.run.progress")
  .progress_begin(f, c("setup", "fit"))
  withr::defer(.progress_finish())
  .progress_check_passed("render_r")
  expect_identical(yaml::read_yaml(f)$checks, "render_r")
})

test_that("each progress write records the session's memory use", {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "x.run.progress")
  testthat::local_mocked_bindings(.cgroup_memory = function(...) list(limit_gib = 76.8, usage_gib = 41.5,
                                                                      peak_gib = 50, source = "cgroup v1"))
  .progress_begin(f, c("setup"))
  withr::defer(.progress_finish())
  expect_equal(yaml::read_yaml(f)$mem_gib, 41.5)
})

test_that("job_status prints the recorded peak against the limit", {
  job <- status_job()
  .write_status(.run_files(job)$status, state = "failed", exit_code = 1L, pid = 999999L,
                mem_peak_gib = 76.7, mem_limit_gib = 76.8)
  expect_output(job_status(job), "memory: 76.7 of 76.8 GiB (peak)", fixed = TRUE)
})

test_that("the runner records the cgroup peak at its end", {
  lines <- .runner_lines("/s/a.qmd", "/s/a.run.yml", FALSE, "TRUE")
  expect_true(any(grepl("hvtiRtemplates:::.cgroup_memory()", lines, fixed = TRUE)))
  expect_true(any(grepl("mem_peak_gib", lines, fixed = TRUE)))
})
```

- [ ] **Step 2: Run them to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "job-progress|background-job")'`
Expected: FAIL on the four new tests.

- [ ] **Step 3: Implement**

In `.progress_write()`, add two fields to `rec`, after `done = s$done`:

```r
              checks = s$checks, mem_need_gib = s$mem_need_gib,
              mem_gib = tryCatch(round(.cgroup_memory()$usage_gib, 1), error = function(e) NULL)
```

Add, after `.progress_finish()`:

```r
# An in-render check that passed; run_job() waits for these (dev/specs/2026-10-22-run-job-design.md, 5.3).
.progress_check_passed <- function(name) {
  .progress_state$checks <- unique(c(.progress_state$checks, name))
  .progress_write()
}
```

Reset `.progress_state$checks <- NULL` and `.progress_state$mem_need_gib <- NULL` in
`.progress_begin()`. `.progress_view()` keeps every field it reads, so `job_status()`'s
`st$progress$mem_need_gib` needs no change there.

In `.runner_lines()`, replace the final `put(...)` line with one that adds the memory fields. The
runner already runs the package to render, so `:::` is available there:

```r
    paste0("mem <- tryCatch(hvtiRtemplates:::.cgroup_memory(), error = function(e) list())"),
    paste0("put(c(list(state = if (ok) 'finished' else 'failed', exit_code = if (ok) 0L else 1L), base, ",
           "list(ended = stamp(ended), elapsed_s = round(as.numeric(difftime(ended, started, units = 'secs')))), ",
           "Filter(function(v) length(v) == 1L && !is.na(v), list(mem_peak_gib = round(mem$peak_gib, 1), ",
           "mem_limit_gib = round(mem$limit_gib, 1)))))"),
```

In `job_status()`, after `cat(basename(path), ...)`:

```r
    if (is.numeric(st$mem_peak_gib) && is.numeric(st$mem_limit_gib)) {
      cat(sprintf("  memory: %.1f of %.1f GiB (peak)\n", st$mem_peak_gib, st$mem_limit_gib))
    }
```

- [ ] **Step 4: Run the tests to verify they pass, including the whole progress and background suites**

Run: `Rscript -e 'devtools::test(filter = "job-progress|background-job")'`
Expected: PASS, with no existing test changed.

- [ ] **Step 5: Commit**

```bash
git add R/job-progress.R R/background-job.R tests/testthat/test-job-progress.R tests/testthat/test-background-job.R
git commit -m "feat(job_status): record passed checks, memory use and the run's memory peak"
```

---

### Task 4: `render_r` in the render, and `HVTI_RUN_R` from `submit_job()`

Implements §5.1, failure 2.

**Files:**
- Modify: `R/preflight.R` (add `.check_render_r()`)
- Modify: `R/background-job.R` (`.submit_job()` command line)
- Modify: `R/job-setup.R` (call it)
- Test: `tests/testthat/test-preflight.R`, `tests/testthat/test-background-job.R`

**Interfaces:**
- Consumes: `.check()`, `.r_home()` (Task 1), `.progress_check_passed()` (Task 3).
- Produces: `.check_render_r(expected = Sys.getenv("HVTI_RUN_R"))` returns a `check` record.
  `.job_setup()` stops with its message when `ok` is FALSE.

- [ ] **Step 1: Write the failing tests**

```r
test_that("render_r refuses a render on an R other than the submitter's (failure 2)", {
  testthat::local_mocked_bindings(.r_home = function() "/usr/lib/R/bin")
  ck <- .check_render_r(expected = "/opt/R/4.5.3/lib/R/bin")
  expect_false(ck$ok)
  expect_match(ck$message, "^render_r: .*/usr/lib/R/bin.*/opt/R/4.5.3")
  expect_match(ck$fix, "QUARTO_R", fixed = TRUE)
})

test_that("render_r is skipped when nothing was submitted", {
  expect_true(.check_render_r(expected = "")$ok)
})

test_that("submit_job exports HVTI_RUN_R to the runner", {
  captured <- NULL
  testthat::local_mocked_bindings(system = function(cmd, ...) captured <<- cmd, .package = "base")
  # If base::system cannot be mocked in this testthat version, wrap the call as .launch(cmd) in
  # background-job.R and mock that instead; the assertion is unchanged.
  job <- status_job()
  .submit_job(job, FALSE, "TRUE", dirname(job))
  expect_match(captured, "HVTI_RUN_R=", fixed = TRUE)
})
```

- [ ] **Step 2: Run them to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "preflight|background-job")'`
Expected: FAIL on the three new tests.

- [ ] **Step 3: Implement**

In `R/preflight.R`:

```r
# Quarto starts its own R for knitr; QUARTO_R or the PATH can point it at another one.
.check_render_r <- function(expected = Sys.getenv("HVTI_RUN_R")) {
  if (!nzchar(expected)) return(.check("render_r", TRUE))
  have <- normalizePath(.r_home(), mustWork = FALSE)
  want <- normalizePath(expected, mustWork = FALSE)
  if (identical(have, want)) return(.check("render_r", TRUE))
  .check("render_r", FALSE,
         sprintf("Quarto ran this render on %s, not the R that submitted it, %s.", have, want),
         "A QUARTO_R setting is overriding it: remove QUARTO_R from ~/.Renviron or the study's .Renviron.")
}
```

In `.submit_job()`, change `cmd` so the runner's environment carries the submitting R:

```r
  cmd <- sprintf("cd %s && HVTI_RUN_R=%s exec %snohup %s %s > %s 2>&1 < /dev/null",
                 shQuote(root), shQuote(R.home("bin")), setsid, shQuote(rscript), shQuote(files$runner), shQuote(files$log))
```

In `.job_setup()`, after `.check_job_name(...)`:

```r
  ck <- .check_render_r()
  if (!ck$ok) stop(ck$message, "\n", ck$fix, call. = FALSE)
```

and after `progress <- .progress_install(...)`, add `.progress_check_passed("render_r")`.

- [ ] **Step 4: Run the tests, including the setup suite that runs real setup chunks**

Run: `Rscript -e 'devtools::test(filter = "preflight|background-job|job-setup")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/preflight.R R/background-job.R R/job-setup.R tests/testthat/test-preflight.R tests/testthat/test-background-job.R
git commit -m "feat(render_r): stop a render that Quarto started on another R"
```

---

### Task 5: `run_state` and `quarto` checks

Implements §4.3 and §4.4, failures 6 and 2 (the pre-submit half).

**Files:**
- Modify: `R/preflight.R`
- Test: `tests/testthat/test-preflight.R`

**Interfaces:**
- Consumes: `job_status()`, `.run_files()`. `cancel_job(path, other_host = "abandon")` and the `marker`
  field in `.run.yml` come from `feat/cancel-job`: run `grep -n other_host R/background-job.R` on `origin/main` first.
- Produces: `.check_run_state(path)` and `.check_quarto()` return `check` records.

- [ ] **Step 1: Write the failing tests**

```r
test_that("run_state refuses a run recorded on another host and names it (failure 6)", {
  job <- status_job()
  .write_status(.run_files(job)$status, state = "running", pid = 1L, host = "lri-r06", started = .stamp())
  ck <- .check_run_state(job)
  expect_false(ck$ok)
  expect_match(ck$message, "lri-r06", fixed = TRUE)
})

test_that("a stale other-host run is called probably dead, with the abandon call", {
  job <- status_job()
  .write_status(.run_files(job)$status, state = "running", pid = 1L, host = "lri-r06", started = .stamp())
  testthat::local_mocked_bindings(job_status = function(path, quiet) list(state = "running", host = "lri-r06",
                                                                          progress = list(stale = TRUE)))
  ck <- .check_run_state(job)
  expect_match(ck$message, "probably", fixed = TRUE)
  expect_match(ck$fix, "cancel_job(", fixed = TRUE)
})

test_that("the abandon fix tells the user to confirm on that host first, by marker", {
  job <- status_job()
  testthat::local_mocked_bindings(job_status = function(path, quiet) list(state = "running", host = "lri-r06",
                                                                          marker = "hvti-abc123",
                                                                          progress = list(stale = TRUE)))
  ck <- .check_run_state(job)
  expect_match(ck$fix, "ps eww -u $USER | grep hvti-abc123", fixed = TRUE)
  expect_lt(regexpr("grep", ck$fix, fixed = TRUE), regexpr("cancel_job(", ck$fix, fixed = TRUE))
})

test_that("a lock directory older than ten minutes is refused by name", {
  job <- status_job()
  lock <- .run_files(job)$lock
  dir.create(lock)
  Sys.setFileTime(lock, Sys.time() - 3600)
  ck <- .check_run_state(job)
  expect_false(ck$ok)
  expect_match(ck$message, basename(lock), fixed = TRUE)
})

test_that("finished, failed and vanished runs pass", {
  job <- status_job()
  .write_status(.run_files(job)$status, state = "failed", exit_code = 1L, pid = 999999L)
  expect_true(.check_run_state(job)$ok)
})

test_that("quarto refuses a QUARTO_R that names another R", {
  withr::local_envvar(QUARTO_R = "/usr/lib/R/bin")
  testthat::local_mocked_bindings(.r_home = function() "/opt/R/4.5.3/lib/R/bin", .quarto_found = function() TRUE)
  ck <- .check_quarto()
  expect_false(ck$ok)
  expect_match(ck$message, "^quarto: QUARTO_R")
})
```

- [ ] **Step 2: Run them to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "preflight")'`
Expected: FAIL on the five new tests.

- [ ] **Step 3: Implement**

```r
.quarto_found <- function() {
  requireNamespace("quarto", quietly = TRUE) && !is.null(tryCatch(quarto::quarto_path(), error = function(e) NULL))
}

.check_quarto <- function() {
  if (!.quarto_found()) {
    return(.check("quarto", FALSE, "the Quarto command line tool cannot be found.",
                  "Ask the server administrator; on lri it ships with Workbench."))
  }
  q <- Sys.getenv("QUARTO_R")
  if (nzchar(q) && !identical(normalizePath(q, mustWork = FALSE), normalizePath(.r_home(), mustWork = FALSE))) {
    return(.check("quarto", FALSE, sprintf("QUARTO_R is set to %s, so Quarto would render on that R, not this one (%s).",
                                           q, .r_home()),
                  "Remove QUARTO_R from ~/.Renviron or the study's .Renviron."))
  }
  .check("quarto", TRUE)
}
```

```r
.check_run_state <- function(path) {
  files <- .run_files(path)
  if (dir.exists(files$lock)) {
    age <- difftime(Sys.time(), file.info(files$lock)$mtime, units = "mins")
    if (!is.na(age) && age > 10) {
      return(.check("run_state", FALSE,
                    sprintf("%s is %.0f minutes old; a submit that crashed left it.", basename(files$lock), age),
                    sprintf("Delete the directory %s, then run again.", files$lock)))
    }
  }
  st <- job_status(path, quiet = TRUE)
  here <- Sys.info()[["nodename"]]
  if (identical(st$state, "running") && is.character(st$host) && !identical(st$host, here)) {
    stale <- isTRUE(st$progress$stale)
    # Stale progress is not proof: Quarto's knitr runs in a session of its own and can outlive the
    # Workbench session, so the fix confirms on that host before abandoning (spec section 6).
    confirm <- if (is.character(st$marker)) {
      sprintf("On %s, confirm nothing is left with `ps eww -u $USER | grep %s`. ", st$host, st$marker)
    } else {
      sprintf("From a session on %s, confirm with `hvti status` that nothing is left. ", st$host)
    }
    abandon <- if (exists("cancel_job", mode = "function") && "other_host" %in% names(formals(cancel_job))) {
      sprintf('%sOnly then run cancel_job("%s", other_host = "abandon") here.', confirm, path)
    } else {
      sprintf("If that session is gone, delete %s and %s, then run again.", files$status, files$progress)
    }
    return(.check("run_state", FALSE,
                  sprintf("this job is recorded running on host %s%s.", st$host,
                          if (stale) ", but its progress has not moved for over 30 minutes, so it is probably dead" else ""),
                  paste0(if (!stale) sprintf("Check it from a session on %s with `hvti status`. ", st$host), abandon)))
  }
  if (st$state %in% c("running", "submitted")) {
    return(.check("run_state", FALSE, sprintf("this job is already %s.", st$state),
                  "Follow it with `hvti status <job>`, or stop it with `hvti cancel <job>`."))
  }
  .check("run_state", TRUE)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "preflight")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/preflight.R tests/testthat/test-preflight.R
git commit -m "feat(run_job): run_state and quarto checks"
```

---

### Task 6: `run_job()`, the report, and the wait

Implements §2 and §5.3.

**Files:**
- Create: `R/run-job.R`
- Test: `tests/testthat/test-run-job.R`

**Interfaces:**
- Consumes: all `.check_*()` functions, `submit_job()`, `job_status()`, `.find_study_root()`.
- Produces: `run_job(path, final = FALSE, wait = 300)` (exported) returns the status invisibly.
  `.report_checks(checks)` prints a line per check and returns TRUE when all passed.
  `.expected_checks(path)` returns `c("render_r")` or `c("render_r", "memory")`.
  `.wait_for_checks(path, expected, wait, poll = 5)` returns the status.

- [ ] **Step 1: Write the failing tests**

```r
test_that("run_job refuses before submitting when any check fails, and lists every failure", {
  root <- lock_study(r = "4.5.3")
  job <- file.path(root, "analyses", "x.qmd")
  writeLines("---\ntitle: x\n---", job)
  submitted <- FALSE
  testthat::local_mocked_bindings(.session_r = function() numeric_version("4.6.1"),
                                  .check_packages = function(...) .check("packages", FALSE, "quarto missing.", "hvtiR::update()"),
                                  .check_quarto = function() .check("quarto", TRUE),
                                  submit_job = function(...) submitted <<- TRUE)
  expect_error(expect_output(run_job(job), "r_version.*\n.*packages"), "refused")
  expect_false(submitted)
})

test_that("the memory check is expected only where the job calls guard_memory()", {
  root <- withr::local_tempdir()
  j <- file.path(root, "a.qmd")
  writeLines("x <- 1", j)
  expect_identical(.expected_checks(j), "render_r")
  writeLines("guard_memory(need, 'fit')", j)
  expect_identical(.expected_checks(j), c("render_r", "memory"))
})

test_that("the wait returns once every expected check is recorded", {
  testthat::local_mocked_bindings(job_status = function(path, quiet) list(state = "running", pid = 1L, host = "h",
                                                                          progress = list(checks = c("render_r", "memory"))))
  st <- .wait_for_checks("x.qmd", c("render_r", "memory"), wait = 1, poll = 0)
  expect_identical(st$state, "running")
})

test_that("the wait returns on failure, printing the diagnosis", {
  testthat::local_mocked_bindings(job_status = function(path, quiet = FALSE) {
    if (!quiet) cat("x.qmd: failed\n  why: memory: ...\n")
    list(state = "failed")
  })
  expect_output(.wait_for_checks("x.qmd", "render_r", wait = 1, poll = 0), "why: memory")
})

test_that("a render that finishes between polls is reported finished, not running or starting", {
  testthat::local_mocked_bindings(job_status = function(path, quiet = FALSE) {
    if (!quiet) cat("x.qmd: finished in 40 s\n")
    list(state = "finished", progress = list(checks = "render_r"))
  })
  out <- capture.output(st <- .wait_for_checks("x.qmd", c("render_r", "memory"), wait = 60, poll = 0))
  expect_identical(st$state, "finished")
  expect_match(out, "finished", all = FALSE)
  expect_false(any(grepl("still starting|checks passed", out)))
})

test_that("the wait times out with a pointer to hvti status", {
  testthat::local_mocked_bindings(job_status = function(path, quiet) list(state = "running", progress = list()))
  expect_output(.wait_for_checks("x.qmd", "render_r", wait = 0, poll = 0), "still starting", fixed = TRUE)
})
```

- [ ] **Step 2: Run them to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "run-job")'`
Expected: FAIL, `could not find function "run_job"`.

- [ ] **Step 3: Implement**

```r
.report_checks <- function(checks) {
  for (ck in checks) {
    cat(if (ck$ok) "  ok    " else "  FAIL  ", ck$name, "\n", sep = "")
    if (!ck$ok) cat("        ", ck$message, "\n        fix: ", gsub("\n", "\n             ", ck$fix), "\n", sep = "")
    if (!is.null(ck$note)) cat("        note: ", ck$note, "\n", sep = "")
  }
  all(vapply(checks, `[[`, NA, "ok"))
}

.expected_checks <- function(path) {
  c("render_r", if (any(grepl("guard_memory(", readLines(path, warn = FALSE), fixed = TRUE))) "memory")
}

.wait_for_checks <- function(path, expected, wait, poll = 5) {
  deadline <- Sys.time() + wait
  repeat {
    st <- job_status(path, quiet = TRUE)
    # Finished, failed or gone: say so at once, whatever the check markers show.
    if (st$state %in% c("finished", "failed", "vanished", "cancelled")) return(invisible(job_status(path)))
    if (all(expected %in% st$progress$checks)) {
      cat(sprintf("checks passed; running (process %s on %s). Follow it with `hvti status %s`.\n",
                  st$pid, st$host, basename(path)))
      return(invisible(st))
    }
    if (Sys.time() >= deadline) {
      cat(sprintf("still starting; follow it with `hvti status %s`.\n", basename(path)))
      return(invisible(st))
    }
    Sys.sleep(poll)
  }
}
```

`run_job()`, with roxygen. Give it `@description` in the house voice for a study author,
`@return`, and an `@examples` block in `\dontrun{}`, as `submit_job()`'s has, because it starts a
real render:

```r
run_job <- function(path, final = FALSE, wait = 300) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path) || dir.exists(path)) {
    stop("run_job(): `path` must be an existing job file.", call. = FALSE)
  }
  path <- normalizePath(path, winslash = "/")
  root <- .find_study_root(dirname(path))
  cat("Checking ", basename(path), "\n", sep = "")
  checks <- list(.check_r_version(root), .check_packages(path, root), .check_quarto(), .check_run_state(path))
  if (!.report_checks(checks)) stop("run_job(): refused; fix the checks marked FAIL above and run again.", call. = FALSE)
  submit_job(path, final = final)
  if (wait <= 0) return(invisible(job_status(path, quiet = TRUE)))
  .wait_for_checks(path, .expected_checks(path), wait)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "run-job")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/run-job.R tests/testthat/test-run-job.R man/run_job.Rd NAMESPACE
git commit -m "feat(run_job): preflight, submit, and wait for the render's own checks"
```

---

### Task 7: diagnosis in `job_status()`

Implements §6, failure 7.

**Files:**
- Create: `R/diagnose.R`, plus `tests/testthat/fixtures-diagnose/{oom-workers,no-package,quitting,guard,unknown}.log`
- Modify: `R/background-job.R` (`job_status()` prints `  why:` and `  fix:`, and returns `st$diagnosis`)
- Test: `tests/testthat/test-diagnose.R`

**Interfaces:**
- Consumes: the `mem_peak_gib` and `mem_limit_gib` fields (Task 3), `.profile_for()` (Task 2).
- Produces: `.diagnose_failure(log_lines, st)` returns `list(reason = chr, fix = chr)`.

The fixture logs are cut from the 2026-10-22 runs and contain **no data values, IDs or paths
under `/studies/`**. Write them by hand from the signatures: COMMENCE's `worker result(s) were not
delivered`, `there is no package called 'boostmtree'`, a `Quitting from nb.x.qmd:212-240 [fit]`
followed by `Error in ...`, and a `memory: ...` guard refusal.

- [ ] **Step 1: Write the failing tests**

```r
fx <- function(name) readLines(test_path("fixtures-diagnose", paste0(name, ".log")))

test_that("killed workers with the peak at the cap read as memory, and the fix uses the recorded need (failures 4-5)", {
  d <- .diagnose_failure(fx("oom-workers"), list(mem_peak_gib = 19.1, mem_limit_gib = 19.2,
                                                 progress = list(mem_need_gib = 30)))
  expect_match(d$reason, "ran out of memory: peak 19.1 of a 19.2 GiB cap", fixed = TRUE)
  expect_match(d$fix, "Medium", fixed = TRUE)   # .profile_for(30)
})

test_that("with no recorded need, the fix asks for a larger session than this one", {
  d <- .diagnose_failure(fx("oom-workers"), list(mem_peak_gib = 19.1, mem_limit_gib = 19.2))
  expect_match(d$fix, "larger than this one (19.2 GiB)", fixed = TRUE)
})

test_that("the same signature without a recorded peak is hedged", {
  d <- .diagnose_failure(fx("oom-workers"), list())
  expect_match(d$reason, "^probably memory", ignore.case = TRUE)
})

test_that("a missing package reads as the wrong R or library", {
  d <- .diagnose_failure(fx("no-package"), list())
  expect_match(d$reason, "boostmtree", fixed = TRUE)
  expect_match(d$fix, "hvti run", fixed = TRUE)
})

test_that("Quitting from names the chunk and quotes the error", {
  d <- .diagnose_failure(fx("quitting"), list())
  expect_match(d$reason, "chunk `fit`", fixed = TRUE)
  expect_match(d$fix, "^Error", ignore.case = FALSE)
})

test_that("a check's own refusal is passed through verbatim", {
  d <- .diagnose_failure(fx("guard"), list())
  expect_match(d$reason, "^memory: ")
})

test_that("an unknown failure shows the last 20 log lines", {
  d <- .diagnose_failure(fx("unknown"), list())
  expect_match(d$reason, "no known cause", fixed = TRUE)
  expect_lte(length(strsplit(d$fix, "\n")[[1]]), 20L)
})

test_that("job_status prints why and fix for a failed run", {
  job <- status_job()
  file.copy(test_path("fixtures-diagnose", "no-package.log"), .run_files(job)$log, overwrite = TRUE)
  .write_status(.run_files(job)$status, state = "failed", exit_code = 1L, pid = 999999L)
  expect_output(job_status(job), "why: .*boostmtree")
})
```

- [ ] **Step 2: Run them to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "diagnose")'`
Expected: FAIL, `could not find function ".diagnose_failure"`.

- [ ] **Step 3: Implement**

```r
# Known ways a render dies, matched in order; the first that matches explains it.
.diagnose_failure <- function(log, st) {
  hit <- function(p) grep(p, log, perl = TRUE)
  g <- hit("^(r_version|packages|run_state|quarto|render_r|memory): ")
  if (length(g)) return(list(reason = log[g[1L]], fix = if (length(log) > g[1L]) log[g[1L] + 1L] else ""))
  if (length(hit("worker result\\(s\\) were not delivered|^Killed|exit status 137"))) {
    peak <- st$mem_peak_gib; lim <- st$mem_limit_gib
    if (is.numeric(peak) && is.numeric(lim) && peak >= 0.95 * lim) {
      need <- st$progress$mem_need_gib
      to <- if (is.numeric(need)) .profile_for(need) else "none"
      fix <- if (to != "none") {
        sprintf("Start a \"%s\" session or larger (this fit was estimated at %.0f GiB), or lower CORES.", to, need)
      } else {
        sprintf("Start a Workbench session larger than this one (%.1f GiB), or lower CORES.", lim)
      }
      return(list(reason = sprintf("the session ran out of memory: peak %.1f of a %.1f GiB cap.", peak, lim), fix = fix))
    }
    return(list(reason = "probably memory: forked workers were killed, and this run recorded no memory peak.",
                fix = "Start a larger Workbench session, or lower CORES, and run again."))
  }
  m <- regmatches(log, regexpr("there is no package called .[A-Za-z0-9.]+.", log))
  if (length(m)) {
    return(list(reason = sprintf("the render ran on an R or library that lacks a package (%s).", m[1L]),
                fix = "Run it with `hvti run <job>`, which starts the study's R; if it still fails, fix what run_job's packages check reports."))
  }
  q <- hit("^Quitting from .*\\[[^]]+\\]")
  if (length(q)) {
    label <- sub("^.*\\[([^]]+)\\].*$", "\\1", log[q[1L]])
    lines <- sub("^Quitting from [^:]*:([0-9-]+).*$", "\\1", log[q[1L]])
    err <- grep("^Error", log[-seq_len(q[1L])], value = TRUE)
    return(list(reason = sprintf("the job stopped in chunk `%s`, lines %s.", label, lines),
                fix = if (length(err)) err[1L] else "See the log for the error."))
  }
  list(reason = "no known cause; the end of the log follows.", fix = paste(utils::tail(log, 20L), collapse = "\n"))
}
```

In `job_status()`, after the memory line from Task 3:

```r
    if (st$state %in% c("failed", "vanished") && file.exists(files$log)) {
      st$diagnosis <- tryCatch(.diagnose_failure(readLines(files$log, warn = FALSE), st), error = function(e) NULL)
      if (!is.null(st$diagnosis)) cat("  why: ", st$diagnosis$reason, "\n  fix: ", st$diagnosis$fix, "\n", sep = "")
    }
```

Compute `st$diagnosis` before the `if (!isTRUE(quiet))` block, so the returned list carries it even
when `quiet = TRUE`, and only print inside the block. Document it in `job_status()`'s `@return`.

- [ ] **Step 4: Mutation check.** Swap the order of the memory and missing-package branches, and
  confirm no test goes red. Two fixtures matching each other's branch would mean the order is
  untested, so add a fixture carrying both signatures, assert that the guard or memory branch wins,
  and confirm the swap now goes red.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "diagnose|background-job")'`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add R/diagnose.R R/background-job.R tests/testthat/test-diagnose.R tests/testthat/fixtures-diagnose man/job_status.Rd
git commit -m "feat(job_status): say in plain words why a run failed, and the fix"
```

---

### Task 8: wire `guard_memory()` into nb-boostmtree

Implements §5.2, the template half.

**Files:**
- Modify: `inst/templates/30_analyses/nb-boostmtree.qmd` (CORES comment, fit chunk)
- Test: the existing nb-boostmtree template tests (`grep -ln "nb-boostmtree" tests/testthat/test-*.R`)

**Interfaces:**
- Consumes: `guard_memory()`, `.boostmtree_need_gib()` (Task 2). The cache-hit handshake (a need of
  0 records `memory`) is tested in Task 2; this task's test checks the call is unconditional.

- [ ] **Step 1: Write the failing test** in the nb template test file, using that file's helpers:

```r
test_that("the nb-boostmtree fit chunk guards memory before cache_fit()", {
  tpl <- readLines(template_path("nb.boostmtree"))
  fit <- grep("guard_memory(", tpl, fixed = TRUE)
  cache <- grep("cache_fit(", tpl, fixed = TRUE)
  expect_length(fit, 1L)
  expect_lt(fit, min(cache[cache > fit]))
  # Not inside an if (): a cached rerender must still record the check run_job() waits for.
  expect_match(tpl[fit], "^hvtiRtemplates::guard_memory\\(")
})
```

- [ ] **Step 2: Run it to verify it fails.** Run: `Rscript -e 'devtools::test(filter = "nb")'`.
  Expected: FAIL.

- [ ] **Step 3: Edit the template.** Immediately before the fit's `cache_fit()` call, and after
  `guard_long_fit()` if present, add one unconditional call. A cached rerender needs no memory, so it
  passes a need of 0, which still records `memory` and lets `run_job()`'s wait complete:

```r
# Refuses here, in the first minutes of the render, a fit this session's memory cannot hold, and
# names the Workbench profile to start. The numbers behind the estimate are in hvtiRtemplates'
# R/fit-memory.R, measured on the server. A cached fit is only loaded, so it needs nothing.
.need <- function(k) hvtiRtemplates:::.boostmtree_need_gib(length(unique(d[[ID]])), nrow(d), FAMILY, k, M)
.fitting <- !file.exists(file.path(CACHE_DIR, "nb-boostmtree-fit.rds")) || isTRUE(REFIT)
hvtiRtemplates::guard_memory(if (.fitting) .need(CORES) else 0, "this boostmtree fit",
                             cores = CORES, cores_fit = .need)
```

Use the template's own names for the data frame, ID column, family, M and cache file. Read the fit
chunk first and substitute them, because the names above are illustrative of the shape only. Replace
the CORES comment's table with one sentence pointing at `R/fit-memory.R` and `?guard_memory`. Keep
the `EDIT:` marker and the advice about speed levelling off.

- [ ] **Step 4: Run the template's tests, including its end-to-end render**

Run: `NOT_CRAN=true Rscript -e 'devtools::test(filter = "nb")'`
Expected: PASS. The small synthetic cohort's need is far under any limit, so the guard passes and
records `memory`.

- [ ] **Step 5: Commit**

```bash
git add inst/templates/30_analyses/nb-boostmtree.qmd tests/testthat/test-nb*.R
git commit -m "feat(nb-boostmtree): guard the fit's memory before it starts"
```

---

### Task 9: the `hvti` command and `install_hvti()`

Implements §3, failures 1 and 8.

**Files:**
- Create: `inst/bin/hvti`
- Modify: `R/run-job.R` (add `install_hvti()`)
- Test: `tests/testthat/test-hvti-command.R`

**Interfaces:**
- Produces: `hvti run|status|cancel <job> [--final]`; `.hvti_main(args)` (internal), which takes
  `c(cmd, path, final)` and returns the process exit status, 0L or 1L; and `install_hvti(dir = "~/bin")`
  (exported), which returns the installed path invisibly. `hvti run` exits 1 when a check refuses or
  the render fails or vanishes during the wait, so `hvti run job && next` stops there.

- [ ] **Step 1: Write the failing tests**

```r
hvti <- function() system.file("bin", "hvti", package = "hvtiRtemplates")

fake_r <- function(ver) {
  top <- withr::local_tempdir(.local_envir = parent.frame())
  bin <- file.path(top, ver, "bin")
  dir.create(bin, recursive = TRUE)
  log <- file.path(top, "args.txt")
  # printf, not echo: sh's echo interprets backslashes, which would corrupt the path being checked.
  writeLines(c("#!/bin/sh", sprintf('printf "%%s\\n" "$PWD" > %s; for a in "$@"; do printf "%%s\\n" "$a" >> %s; done', log, log)),
             file.path(bin, "Rscript"))
  Sys.chmod(file.path(bin, "Rscript"), "755")
  list(top = top, log = log)
}

test_that("hvti run starts the lock's R from the study root, passing the path as data (failures 1 and 8)", {
  skip_on_os("windows")
  root <- lock_study(r = "4.5.3")
  odd <- file.path(root, "analyses", "we\"ird\\dir")   # a quote and a backslash in a directory name
  dir.create(odd)
  job <- file.path(odd, "x.qmd"); writeLines("x", job)
  r <- fake_r("4.5.3")
  out <- system2(hvti(), c("run", shQuote(job), "--final"), env = paste0("HVTI_R_ROOT=", r$top), stdout = TRUE, stderr = TRUE)
  got <- readLines(r$log)
  expect_identical(normalizePath(got[1]), normalizePath(root))
  expect_identical(got[2], "-e")
  expect_identical(got[3], "quit(status = hvtiRtemplates:::.hvti_main(commandArgs(TRUE)))")
  expect_identical(got[c(4, 6)], c("run", "TRUE"))
  expect_identical(normalizePath(got[5]), normalizePath(job))   # pwd may keep a symlinked tempdir logical
})

test_that(".hvti_main exits nonzero when the launch fails or is refused, zero when it runs (C11)", {
  testthat::local_mocked_bindings(run_job = function(path, final) invisible(list(state = "failed")))
  expect_identical(.hvti_main(c("run", "x.qmd", "FALSE")), 1L)
  testthat::local_mocked_bindings(run_job = function(path, final) stop("run_job(): refused; fix the checks"))
  expect_identical(suppressMessages(.hvti_main(c("run", "x.qmd", "FALSE"))), 1L)
  testthat::local_mocked_bindings(run_job = function(path, final) invisible(list(state = "running")))
  expect_identical(.hvti_main(c("run", "x.qmd", "FALSE")), 0L)
})

test_that(".hvti_main passes the path through unchanged, quotes and backslashes included", {
  seen <- NULL
  testthat::local_mocked_bindings(run_job = function(path, final) { seen <<- list(path, final); list(state = "running") })
  .hvti_main(c("run", "/s/we\"ird\\dir/x.qmd", "TRUE"))
  expect_identical(seen, list("/s/we\"ird\\dir/x.qmd", TRUE))
})

test_that("hvti refuses, naming the version, when the lock's R is not installed", {
  skip_on_os("windows")
  root <- lock_study(r = "4.5.3")
  job <- file.path(root, "analyses", "x.qmd"); writeLines("x", job)
  r <- fake_r("4.6.1")
  out <- suppressWarnings(system2(hvti(), c("run", job), env = paste0("HVTI_R_ROOT=", r$top), stdout = TRUE, stderr = TRUE))
  expect_match(paste(out, collapse = "\n"), "R 4.5.3")
  expect_false(is.null(attr(out, "status")))
})

test_that("hvti refuses a job outside any study", {
  skip_on_os("windows")
  d <- withr::local_tempdir(); job <- file.path(d, "x.qmd"); writeLines("x", job)
  out <- suppressWarnings(system2(hvti(), c("run", job), stdout = TRUE, stderr = TRUE))
  expect_match(paste(out, collapse = "\n"), "renv.lock")
})

test_that("install_hvti copies the script, not a symlink", {
  skip_on_os("windows")
  d <- withr::local_tempdir()
  p <- install_hvti(d)
  expect_false(nzchar(Sys.readlink(p)))
  expect_true(file.access(p, 1L) == 0L)
})
```

- [ ] **Step 2: Run them to verify they fail**

Run: `Rscript -e 'devtools::test(filter = "hvti-command")'`
Expected: FAIL. `system.file()` returns `""`.

- [ ] **Step 3: Write `inst/bin/hvti`**

```sh
#!/bin/sh
# hvti: run an hvtiR job on the R its study's renv.lock records. hvti-version: 1
# Design: hvtiRtemplates dev/specs/2026-10-22-run-job-design.md, section 3.
usage() { echo "usage: hvti run|status|cancel <job.qmd> [--final]" >&2; exit 2; }
[ $# -ge 2 ] || usage
cmd=$1; job=$2; final=FALSE
[ "${3:-}" = "--final" ] && final=TRUE
[ -f "$job" ] || { echo "hvti: no such job file: $job" >&2; exit 1; }
jobdir=$(cd "$(dirname "$job")" && pwd) || exit 1
jobpath="$jobdir/$(basename "$job")"
root=$jobdir
while [ ! -f "$root/renv.lock" ]; do
  [ "$root" = "/" ] && { echo "hvti: $job is not inside a study (no renv.lock above it)." >&2; exit 1; }
  root=$(dirname "$root")
done
ver=$(tr -d '\n' < "$root/renv.lock" | sed -n 's/.*"R"[[:space:]]*:[[:space:]]*{[^}]*"Version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -n "$ver" ] || { echo "hvti: $root/renv.lock records no R version." >&2; exit 1; }
for top in "${HVTI_R_ROOT:-}" /opt/R; do
  [ -n "$top" ] && [ -x "$top/$ver/bin/Rscript" ] && { rscript="$top/$ver/bin/Rscript"; break; }
done
if [ -z "${rscript:-}" ]; then
  echo "hvti: this study needs R $ver, which is not installed here. Installed: $(ls /opt/R 2>/dev/null | tr '\n' ' ')" >&2
  exit 1
fi
case $cmd in run|status|cancel) ;; *) usage ;; esac
# The job path reaches R as an argument, never as R source: a fixed expression reads it with
# commandArgs(), so no directory name can change what R runs. .hvti_main() returns the exit status.
cd "$root" && exec "$rscript" -e 'quit(status = hvtiRtemplates:::.hvti_main(commandArgs(TRUE)))' "$cmd" "$jobpath" "$final"
```

The fake Rscript in the test logs `$PWD` and then each argument, so its lines are the root, `-e`,
the fixed expression, the command, the path and `final`. Make the file executable and keep the bit in git: `chmod 755 inst/bin/hvti` and
`git update-index --chmod=+x inst/bin/hvti`. `R CMD build` keeps the mode.

- [ ] **Step 4: Add `.hvti_main()` and `install_hvti()` to `R/run-job.R`.** `.hvti_main()` is
  internal; `install_hvti()` is exported with roxygen, `@return`, and an example that installs into
  `tempdir()`:

```r
# hvti's whole R side. The path arrives as data (commandArgs), never as source. Exit 1 on a refusal,
# or a launch that failed or vanished during the wait, so a shell `&&` chain stops there.
.hvti_main <- function(args) {
  cmd <- args[1L]; path <- args[2L]; final <- identical(args[3L], "TRUE")
  st <- tryCatch(switch(cmd,
                        run = run_job(path, final = final),
                        status = job_status(path),
                        cancel = cancel_job(path)),
                 error = function(e) { message(conditionMessage(e)); NULL })
  if (is.null(st)) return(1L)
  if (identical(cmd, "run") && isTRUE(st$state %in% c("failed", "vanished", "cancelled"))) 1L else 0L
}
```


```r
install_hvti <- function(dir = "~/bin") {
  dir <- path.expand(dir)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  to <- file.path(dir, "hvti")
  # A copy, not a symlink: the library path changes with the R version, which is what hvti exists to survive.
  if (!file.copy(system.file("bin", "hvti", package = "hvtiRtemplates"), to, overwrite = TRUE)) {
    stop("install_hvti(): could not write ", to, ".", call. = FALSE)
  }
  Sys.chmod(to, "755")
  on_path <- normalizePath(dir) %in% normalizePath(strsplit(Sys.getenv("PATH"), ":", fixed = TRUE)[[1]], mustWork = FALSE)
  if (!on_path) message("Add it to your PATH: echo 'export PATH=\"", dir, ":$PATH\"' >> ~/.profile")
  invisible(to)
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::install(quick = TRUE, quiet = TRUE); devtools::test(filter = "hvti-command")'`
Expected: PASS. Per memory `render-tests-need-a-private-library`, install into a private library
with `R CMD INSTALL -l` and `R_LIBS` rather than the shared one when other sessions are active.

- [ ] **Step 6: Update the Windows skip count in `AGENTS.md`.** Four new `skip_on_os("windows")`
  calls take Windows from `SKIP 3` to `SKIP 7`. Edit the `R-CMD-check.yaml` row's numbers and the
  sentence listing the deliberate skips, and say why.

- [ ] **Step 7: Commit**

```bash
git add inst/bin/hvti R/run-job.R tests/testthat/test-hvti-command.R man/install_hvti.Rd NAMESPACE AGENTS.md
git commit -m "feat(hvti): a terminal command that starts the study's R and runs the job"
```

---

### Task 10: documentation, news, full gates

**Files:**
- Modify: `inst/templates/README.md` (a short "Running a long job" section: `install_hvti()` once,
  then `hvti run`, `hvti status`, what the checks mean)
- Create: `news/<branch>.md`

- [ ] **Step 1:** Write the README section in the house voice (apply `ehrlinger-writing`). It
  covers the three commands, the six check names with one line each, and that a refusal's `fix:`
  line is the thing to run.
- [ ] **Step 2:** Write the news fragment. Bullets only, no heading, covering `run_job()`,
  `hvti`/`install_hvti()`, `guard_memory()`, `job_status()`'s diagnosis and memory peak, and
  nb-boostmtree's guard.
- [ ] **Step 3:** Run `Rscript -e 'devtools::document()'`, then `NOT_CRAN=true Rscript -e 'devtools::test()'`.
  Expected: 0 failures. Read the `SKIP` count; any skip beyond the known ones is a defect.
- [ ] **Step 4:** Run `Rscript -e 'devtools::check()'`. Expected: 0 errors, 0 warnings, 0 notes.
  `lintr::lint_package()` is clean.
- [ ] **Step 5:** Run `/code-review` locally and fix what it finds.
- [ ] **Step 6:** Commit, push the branch, and open the PR against `main`. Its body maps each
  2026-10-22 failure to its check and test, copied from spec §8, and says `/code-review` stood in
  for Copilot.

---

### Task 11: snapshot guard in hvtiRutilities (separate repository and PR)

Implements §7, failure 1b. Work in `~/Documents/GitHub/hvtiRutilities` on a branch from
`origin/main`, following that repository's `AGENTS.md`. **It enforces 80-character lines and has an
explicit pkgdown reference index**, unlike this repository.

**Files:**
- Create: `R/snapshot-guard.R`
- Modify: `R/study_need.R` (`.need_snapshot()`), `R/study_setup.R` (the snapshot at line ~300)
- Test: `tests/testthat/test-snapshot-guard.R`

**Interfaces:**
- Produces: `.guard_snapshot(root, r_upgrade = FALSE, session = getRversion(),
  installed = function(p) ...)`. It returns invisibly or stops. It is exported as `guard_snapshot()`
  so hvtiR can call it, and goes in the pkgdown reference index.

- [ ] **Step 1: Write the failing tests**

```r
snap_root <- function(r = "4.5.3", pkgs = c(boostmtree = "2.0.8", ggBoostedTrees = "0.10.0")) {
  root <- withr::local_tempdir(.local_envir = parent.frame())
  lock <- list(R = list(Version = r),
               Packages = lapply(names(pkgs), function(p) list(Package = p, Version = pkgs[[p]])))
  names(lock$Packages) <- names(pkgs)
  jsonlite::write_json(lock, file.path(root, "renv.lock"), auto_unbox = TRUE)
  root
}

test_that("a snapshot from another R major.minor is refused, naming both (failure 1b)", {
  root <- snap_root("4.5.3")
  expect_error(guard_snapshot(root, session = numeric_version("4.6.1")), "4[.]5[.]3.*4[.]6[.]1")
})

test_that("r_upgrade = TRUE still refuses while a locked package is missing from the new library", {
  root <- snap_root("4.5.3")
  expect_error(guard_snapshot(root, r_upgrade = TRUE, session = numeric_version("4.6.1"),
                              installed = function(p) if (p == "boostmtree") NA_character_ else "0.10.0"),
               "boostmtree.*renv::restore")
})

test_that("r_upgrade = TRUE passes once every locked package is installed", {
  root <- snap_root("4.5.3")
  expect_silent(guard_snapshot(root, r_upgrade = TRUE, session = numeric_version("4.6.1"),
                               installed = function(p) "1.0"))
})

test_that("a patch difference, or no lock, passes", {
  expect_silent(guard_snapshot(snap_root("4.5.1"), session = numeric_version("4.5.3")))
  expect_silent(guard_snapshot(withr::local_tempdir(), session = numeric_version("4.6.1")))
})

test_that(".need_snapshot() never calls renv::snapshot from a mismatched R", {
  root <- snap_root("4.5.3")
  called <- FALSE
  local_mocked_bindings(snapshot = function(...) called <<- TRUE, .package = "renv")
  local_mocked_bindings(.session_r = function() numeric_version("4.6.1"))
  expect_error(.need_snapshot(root))
  expect_false(called)
})
```

- [ ] **Step 2: Run them to verify they fail.** Run: `Rscript -e 'devtools::test(filter = "snapshot-guard")'`.

- [ ] **Step 3: Implement**

```r
.session_r <- function() getRversion()

guard_snapshot <- function(root, r_upgrade = FALSE, session = .session_r(),
                           installed = function(p) {
                             tryCatch(as.character(utils::packageVersion(p)),
                                      error = function(e) NA_character_)
                           }) {
  f <- file.path(root, "renv.lock")
  if (!file.exists(f)) return(invisible(TRUE))
  lock <- jsonlite::read_json(f, simplifyVector = FALSE)
  want <- lock$R$Version
  if (!is.character(want)) return(invisible(TRUE))
  mm <- function(v) paste(unlist(numeric_version(v))[1:2], collapse = ".")
  have <- as.character(session)
  if (mm(want) == mm(have)) return(invisible(TRUE))
  if (!isTRUE(r_upgrade)) {
    stop("renv.lock records R ", want, " but this is R ", have,
         "; a snapshot now would record the wrong R and drop packages ",
         "this R's library lacks. Start R ", want, " (/opt/R/", want,
         "/bin/R), or pass r_upgrade = TRUE to move the study to R ",
         have, " on purpose.", call. = FALSE)
  }
  pk <- names(lock$Packages)
  missing <- pk[is.na(vapply(pk, installed, ""))]
  if (length(missing)) {
    stop("Moving to R ", have, " would drop ", paste(missing, collapse = ", "),
         " from renv.lock. Install them first: renv::restore(packages = c(",
         paste0('"', missing, '"', collapse = ", "), ")).", call. = FALSE)
  }
  invisible(TRUE)
}
```

Call `guard_snapshot(root, r_upgrade)` first in `.need_snapshot()` and before the snapshot in
`study_setup()`. Thread an `r_upgrade = FALSE` argument through the exported callers that reach
them, documented in Rd. Wrap lines to 80 characters.

- [ ] **Step 4:** Run `devtools::test()` and `devtools::check()`, and get 0/0/0.
- [ ] **Step 5:** Add a news fragment per that repository's convention, run `/code-review`, and open
  a PR against `main`. John merges, and the patch bump follows that repository's release step.

---

### Task 12: snapshot guard in hvtiR (separate repository and PR, after Task 11 is released)

**Files:**
- Modify: `hvtiR/R/setup.R` near line 663, the string that runs `renv::snapshot(project = ...)` in
  the study. Modify `DESCRIPTION`, raising the `hvtiRutilities` floor to the release carrying
  `guard_snapshot()`, in hvtiR's own bump.
- Test: `hvtiR/tests/testthat/test-setup.R` (or the file covering `run_in_study()`)

- [ ] **Step 1: Write the failing test.** The command string `setup()` builds for the study must
  call `hvtiRutilities::guard_snapshot(<root>, r_upgrade = <bool>)` before `renv::snapshot(`:

```r
test_that("the study snapshot is guarded by guard_snapshot() first", {
  cmd <- snapshot_command("/s", r_upgrade = FALSE)   # extract the string-building into this helper
  expect_lt(regexpr("guard_snapshot(", cmd, fixed = TRUE), regexpr("renv::snapshot(", cmd, fixed = TRUE))
  expect_match(cmd, "r_upgrade = FALSE", fixed = TRUE)
})
```

- [ ] **Step 2:** Extract the line-663 string into `snapshot_command(project, r_upgrade)`, prefix
  the guard call, and add `r_upgrade = FALSE` to `setup()` and `update()` with Rd docs saying when
  to use it.
- [ ] **Step 3:** Run `devtools::test()` and `devtools::check()`, and get 0/0/0.
- [ ] **Step 4:** Add the news fragment, run `/code-review`, and open a PR against `main`.

---

## Self-review notes

- §4.1 is Task 1. §4.2 is Task 1. §4.3 and §4.4 are Task 5. §5.1 is Task 4. §5.2 is Tasks 2 and 8.
  §5.3 is Tasks 3 and 6. §6 is Tasks 3 and 7. §3 is Task 9. §7 is Tasks 11 and 12. §8: each row's
  test is named in its task.
- One calibration is left to John by design: the coefficients in Task 2 Step 4, with their bound
  tests stated. The Large bound for Penny's fit is added only once her Large run records a peak.
- `cancel_job()`'s other-host option is probed with `formals()`, so Task 5 works whether or not
  `feat/cancel-job` adds it first.
