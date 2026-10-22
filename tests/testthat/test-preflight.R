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
  installed <- function(p) if (p == "sf") "1.1" else c(quarto = "1.4.4", knitr = "1.48")[[p]]
  testthat::local_mocked_bindings(.installed_version = installed, .always_needed = function() c("quarto", "knitr"))
  ck <- .check_packages(job, root)
  expect_true(ck$ok)
  expect_match(ck$note, "sf", fixed = TRUE)
})

job_with_setup <- function(root) {
  job <- file.path(root, "analyses", "x.qmd")
  writeLines(c("```{r}", "#| label: setup", "library(knitr)", "```"), job)
  job
}

test_that("a dashed locked version matches the dotted installed one", {
  root <- lock_study(pkgs = list(quarto = "1.4.4", knitr = "1.48", survival = "3.5-8"))
  job <- job_with_setup(root)
  testthat::local_mocked_bindings(
    .installed_version = function(p) c(quarto = "1.4.4", knitr = "1.48", survival = "3.5.8")[[p]],
    .always_needed = function() c("quarto", "knitr", "survival")
  )
  ck <- .check_packages(job, root)
  expect_true(ck$ok)
  expect_null(ck$note)
})

test_that("a lock entry with no Version is unrecorded, not a crash", {
  root <- lock_study(pkgs = list(quarto = "1.4.4", knitr = "1.48"))
  lock <- jsonlite::read_json(file.path(root, "renv.lock"))
  lock$Packages$gh <- list(Package = "gh", Source = "GitHub")
  jsonlite::write_json(lock, file.path(root, "renv.lock"), auto_unbox = TRUE)
  job <- job_with_setup(root)
  testthat::local_mocked_bindings(
    .installed_version = function(p) c(quarto = "1.4.4", knitr = "1.48", gh = "1.0")[[p]],
    .always_needed = function() c("quarto", "knitr", "gh")
  )
  ck <- .check_packages(job, root)
  expect_false(ck$ok)
  expect_match(ck$message, "gh 1.0 is installed but not recorded", fixed = TRUE)
})

test_that("r_version treats an unparseable lock version as absent, with a note", {
  for (bad in c("", "devel", "4")) {
    root <- lock_study(r = bad)
    testthat::local_mocked_bindings(.session_r = function() numeric_version("4.5.3"))
    ck <- .check_r_version(root)
    expect_true(ck$ok)
    expect_match(ck$note, "could not be read", fixed = TRUE)
  }
})

test_that("packages notes when the job's own packages could not be read", {
  root <- lock_study()
  job <- file.path(root, "analyses", "x.qmd")
  writeLines("no setup chunk here", job)
  testthat::local_mocked_bindings(.installed_version = function(p) c(quarto = "1.4.4", knitr = "1.48")[[p]],
                                  .always_needed = function() c("quarto", "knitr"))
  ck <- .check_packages(job, root)
  expect_true(ck$ok)
  expect_match(ck$note, "could not be read", fixed = TRUE)
})

test_that("packages: neither installed nor recorded", {
  root <- lock_study(pkgs = list(knitr = "1.48"))
  job <- job_with_setup(root)
  testthat::local_mocked_bindings(.installed_version = function(p) if (p == "quarto") NA_character_ else "1.48",
                                  .always_needed = function() c("quarto", "knitr"))
  ck <- .check_packages(job, root)
  expect_false(ck$ok)
  expect_match(ck$message, "quarto is neither installed nor recorded", fixed = TRUE)
  expect_match(ck$fix, "hvtiR::update()", fixed = TRUE)
})

test_that("packages: installed newer than locked updates, older restores", {
  root <- lock_study(pkgs = list(quarto = "1.4.4", knitr = "1.48"))
  job <- job_with_setup(root)
  testthat::local_mocked_bindings(.installed_version = function(p) if (p == "knitr") "1.50" else "1.4.4",
                                  .always_needed = function() c("quarto", "knitr"))
  expect_match(.check_packages(job, root)$fix, "hvtiR::update()", fixed = TRUE)
  testthat::local_mocked_bindings(.installed_version = function(p) if (p == "knitr") "1.40" else "1.4.4")
  expect_match(.check_packages(job, root)$fix, 'renv::restore(packages = "knitr")', fixed = TRUE)
})

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

test_that(".job_setup() stops a render whose R is not the submitter's, and passes the same R", {
  setup_fixture()
  withr::local_envvar(HVTI_RUN_R = "/no/such/R/bin")
  expect_error(run_setup(), "render_r: .*/no/such/R/bin.*QUARTO_R")
  withr::local_envvar(HVTI_RUN_R = R.home("bin"))
  expect_no_error(run_setup())
})

test_that("render_r compares two spellings of one R home as equal", {
  skip_on_os("windows")
  home <- withr::local_tempdir()
  link <- file.path(withr::local_tempdir(), "R")
  file.symlink(home, link)
  testthat::local_mocked_bindings(.r_home = function() paste0(home, "/"))
  expect_true(.check_render_r(expected = link)$ok)
})

test_that("render_r's fix names the PATH as well as QUARTO_R", {
  testthat::local_mocked_bindings(.r_home = function() "/usr/lib/R/bin")
  expect_match(.check_render_r(expected = "/opt/R/4.5.3/lib/R/bin")$fix, "PATH", fixed = TRUE)
})

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
  testthat::local_mocked_bindings(job_status = function(path, quiet = FALSE) {
    list(state = "running", host = "lri-r06", progress = list(stale = TRUE))
  })
  ck <- .check_run_state(job)
  expect_match(ck$message, "probably", fixed = TRUE)
  expect_match(ck$fix, "cancel_job(", fixed = TRUE)
})

test_that("the abandon fix tells the user to confirm on that host first, by marker", {
  job <- status_job()
  testthat::local_mocked_bindings(job_status = function(path, quiet = FALSE) {
    list(state = "running", host = "lri-r06", marker = "PSabc123_1", progress = list(stale = TRUE))
  })
  ck <- .check_run_state(job)
  expect_match(ck$fix, "ps eww -u $USER | grep PSabc123_1", fixed = TRUE)
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

test_that("a fresh lock directory does not refuse", {
  job <- status_job()
  dir.create(.run_files(job)$lock)
  expect_true(.check_run_state(job)$ok)
})

test_that("finished, failed and vanished runs pass", {
  job <- status_job()
  .write_status(.run_files(job)$status, state = "failed", exit_code = 1L, pid = 999999L)
  expect_true(.check_run_state(job)$ok)
})

test_that("a run of this job on this host is refused as already running", {
  job <- status_job()
  .write_status(.run_files(job)$status, state = "running", pid = Sys.getpid(), host = Sys.info()[["nodename"]])
  ck <- .check_run_state(job)
  expect_false(ck$ok)
  expect_match(ck$message, "already running", fixed = TRUE)
})

test_that("quarto refuses a QUARTO_R that names another R", {
  withr::local_envvar(QUARTO_R = "/usr/lib/R/bin")
  testthat::local_mocked_bindings(.r_home = function() "/opt/R/4.5.3/lib/R/bin", .quarto_found = function() TRUE)
  ck <- .check_quarto()
  expect_false(ck$ok)
  expect_match(ck$message, "^quarto: QUARTO_R")
})

test_that("quarto refuses a missing CLI and passes a matching QUARTO_R", {
  testthat::local_mocked_bindings(.quarto_found = function() FALSE)
  expect_match(.check_quarto()$message, "cannot be found")
  withr::local_envvar(QUARTO_R = "/opt/R/4.5.3/lib/R/bin")
  testthat::local_mocked_bindings(.r_home = function() "/opt/R/4.5.3/lib/R/bin", .quarto_found = function() TRUE)
  expect_true(.check_quarto()$ok)
})

# A second job in the study, recorded running on lri-r03 with a fit stage three of seven and an hour into 1 of 3 steps.
other_running_job <- function(root, name = "nb.boostmtree.x.boost.qmd", dir = "analyses", host = "lri-r03", age_min = 0) {
  job <- file.path(root, dir, name)
  dir.create(dirname(job), recursive = TRUE, showWarnings = FALSE)
  writeLines("---\ntitle: x\n---", job)
  now <- Sys.time()
  .write_status(.run_files(job)$status, state = "running", pid = 1L, host = host, started = .stamp(now - 7200))
  .write_status(.run_files(job)$progress, pid = 1L, host = host, started = .stamp(now - 7200),
                updated = .stamp(now - age_min * 60), stage = "fit", stage_index = 3L, stage_count = 7L,
                stage_started = .stamp(now - 3600), step = 1L, steps = 3L, unit = "fold",
                step_started = .stamp(now - 3600 - age_min * 60), step_base = 0L, stages = c("a", "b", "fit"))
  job
}

test_that("study_render refuses another job running in the study and names it", {
  root <- lock_study()
  mine <- file.path(root, "analyses", "mine.qmd")
  writeLines("---\ntitle: x\n---", mine)
  other <- other_running_job(root)
  ck <- .check_study_render(mine, root)
  expect_false(ck$ok)
  expect_match(ck$message, "^study_render: another job is rendering in this study: analyses/nb.boostmtree.x.boost.qmd")
  expect_match(ck$message, "on lri-r03", fixed = TRUE)
  expect_match(ck$message, "in stage fit (3 of 7)", fixed = TRUE)
  expect_match(ck$message, "about (2h00m|1h59m) left")
  expect_match(ck$fix, "hvti status analyses/nb.boostmtree.x.boost.qmd", fixed = TRUE)
  expect_match(ck$fix, "hvti cancel analyses/nb.boostmtree.x.boost.qmd", fixed = TRUE)
  expect_true(file.exists(other))
})

test_that("study_render reports stale progress instead of a time left", {
  root <- lock_study()
  mine <- file.path(root, "analyses", "mine.qmd")
  other_running_job(root, age_min = 120)
  ck <- .check_study_render(mine, root)
  expect_match(ck$message, "has not moved for over 30 minutes", fixed = TRUE)
  expect_no_match(ck$message, "left", fixed = TRUE)
})

test_that("study_render names every running job", {
  root <- lock_study()
  mine <- file.path(root, "analyses", "mine.qmd")
  other_running_job(root, "a.qmd")
  other_running_job(root, "b.qmd", dir = "graphs")
  ck <- .check_study_render(mine, root)
  expect_match(ck$message, "analyses/a.qmd", fixed = TRUE)
  expect_match(ck$message, "graphs/b.qmd", fixed = TRUE)
})

test_that("study_render leaves the job's own run to run_state", {
  root <- lock_study()
  mine <- other_running_job(root, "mine.qmd")
  expect_true(.check_study_render(mine, root)$ok)
})

test_that("study_render passes for a finished job and for a study with no other jobs", {
  root <- lock_study()
  mine <- file.path(root, "analyses", "mine.qmd")
  expect_true(.check_study_render(mine, root)$ok)
  other <- file.path(root, "analyses", "done.qmd")
  writeLines("---\ntitle: x\n---", other)
  .write_status(.run_files(other)$status, state = "finished", pid = 1L, elapsed_s = 5L)
  expect_true(.check_study_render(mine, root)$ok)
})

test_that("study_render does not scan renv, .git or .hvtiR", {
  root <- lock_study()
  mine <- file.path(root, "analyses", "mine.qmd")
  other_running_job(root, "hidden.qmd", dir = "renv/library")
  other_running_job(root, "hidden.qmd", dir = ".git")
  expect_true(.check_study_render(mine, root)$ok)
})

test_that("study_render survives an unreadable status file", {
  root <- lock_study()
  mine <- file.path(root, "analyses", "mine.qmd")
  bad <- other_running_job(root, "bad.qmd")
  writeLines("", .run_files(bad)$status)
  expect_true(.check_study_render(mine, root)$ok)
})

test_that("study_render refuses a live render lock with no running job, and passes a dead owner", {
  root <- lock_study()
  mine <- file.path(root, "analyses", "mine.qmd")
  lock <- .provenance_lock_path(root)
  dir.create(lock, recursive = TRUE)
  jsonlite::write_json(list(pid = 4242L, created = "1.000000"), file.path(lock, "owner.json"), auto_unbox = TRUE)
  testthat::local_mocked_bindings(.provenance_owner_alive = function(owner) TRUE)
  ck <- .check_study_render(mine, root)
  expect_false(ck$ok)
  expect_match(ck$message, "process 4242", fixed = TRUE)
  expect_true(dir.exists(lock))
  testthat::local_mocked_bindings(.provenance_owner_alive = function(owner) FALSE)
  expect_true(.check_study_render(mine, root)$ok)
})

test_that("study_render copes with a study root holding regex metacharacters", {
  root <- lock_study()
  odd <- file.path(dirname(root), "st(udy)+1")
  file.rename(root, odd)
  mine <- file.path(odd, "analyses", "mine.qmd")
  other_running_job(odd)
  ck <- .check_study_render(mine, odd)
  expect_false(ck$ok)
  expect_match(ck$message, "in this study: analyses/nb.boostmtree", fixed = TRUE)
})

test_that("study_render does not follow a symlinked directory", {
  skip_on_os("windows")
  root <- lock_study()
  mine <- file.path(root, "analyses", "mine.qmd")
  file.symlink(root, file.path(root, "analyses", "loop"))
  elsewhere <- withr::local_tempdir()
  other_running_job(elsewhere, "linked.qmd", dir = ".")
  file.symlink(elsewhere, file.path(root, "graphs"))
  expect_true(.check_study_render(mine, root)$ok)
})

test_that("study_render names a job whose .qmd is missing, with its relative path", {
  root <- lock_study()
  mine <- file.path(root, "analyses", "mine.qmd")
  orphan <- file.path(root, "analyses", "gone.qmd")
  .write_status(.run_files(orphan)$status, state = "running", pid = 1L, host = "lri-r03", started = .stamp())
  ck <- .check_study_render(mine, root)
  expect_match(ck$message, "in this study: analyses/gone.qmd", fixed = TRUE)
  # and its own orphan files are not another job
  .write_status(.run_files(mine)$status, state = "running", pid = 1L, host = "lri-r03", started = .stamp())
  unlink(.run_files(orphan)$status)
  expect_true(.check_study_render(mine, root)$ok)
})

test_that("study_render sends a stale other-host job through confirm-then-abandon", {
  root <- lock_study()
  mine <- file.path(root, "analyses", "mine.qmd")
  other <- other_running_job(root, age_min = 120)
  .write_status(.run_files(other)$status, state = "running", pid = 1L, host = "lri-r03", started = .stamp(Sys.time() - 7200),
                marker = "PSabc123_1")
  ck <- .check_study_render(mine, root)
  expect_match(ck$fix, "hvti status analyses/nb.boostmtree.x.boost.qmd", fixed = TRUE)
  expect_match(ck$fix, "ps eww -u $USER | grep PSabc123_1", fixed = TRUE)
  expect_match(ck$fix, "other_host = \"abandon\"", fixed = TRUE)
  expect_lt(regexpr("grep", ck$fix, fixed = TRUE), regexpr("cancel_job(", ck$fix, fixed = TRUE))
  expect_no_match(ck$fix, "Wait for it", fixed = TRUE)
})

test_that("the abandon route always confirms first, even without cancel_job's other_host", {
  job <- status_job()
  st <- list(host = "lri-r06", marker = "PSabc123_1")
  testthat::local_mocked_bindings(cancel_job = function(path) NULL)
  fix <- .abandon_route(st, job)
  expect_match(fix, "^On lri-r06, confirm nothing is left with `ps eww -u \\$USER \\| grep PSabc123_1`")
  expect_match(fix, "delete", fixed = TRUE)
})

test_that("run_state refuses a fresh submission", {
  job <- status_job()
  .write_status(.run_files(job)$status, state = "submitted", submitted = .stamp())
  ck <- .check_run_state(job)
  expect_false(ck$ok)
  expect_match(ck$message, "already submitted", fixed = TRUE)
})

test_that("study_render copes with a stale running job that records no host", {
  root <- lock_study()
  mine <- file.path(root, "analyses", "mine.qmd")
  other <- file.path(root, "analyses", "nohost.qmd")
  writeLines("---\ntitle: x\n---", other)
  now <- Sys.time()
  .write_status(.run_files(other)$progress, pid = 1L, started = .stamp(now - 7200), updated = .stamp(now - 7200),
                stage = "fit", stage_index = 1L, stage_count = 2L, stages = c("fit", "b"))
  ck <- expect_no_error(.check_study_render(mine, root))
  expect_false(ck$ok)
  expect_match(ck$fix, "hvti cancel analyses/nohost.qmd", fixed = TRUE)
  expect_no_match(ck$fix, "other_host", fixed = TRUE)
})

test_that("the abandon route for a job on this host is a plain cancel", {
  job <- status_job()
  fix <- .abandon_route(list(host = Sys.info()[["nodename"]], marker = "PSabc123_1"), job)
  expect_match(fix, "hvti cancel", fixed = TRUE)
  expect_match(fix, sprintf('cancel_job("%s")', job), fixed = TRUE)
  expect_no_match(fix, "other_host", fixed = TRUE)
  expect_no_match(fix, "confirm", fixed = TRUE)
  expect_match(.abandon_route(list(host = NULL), job), "hvti cancel", fixed = TRUE)
})
