test_that("render_job drafts by default and sets strict only for a final render", {
  skip_if_not_installed("quarto")
  job <- tempfile(fileext = ".qmd")
  writeLines("x", job)
  on.exit(unlink(job), add = TRUE)
  seen <- list()
  local_mocked_bindings(
    quarto_render = function(input, execute_dir, ...) {
      seen[[length(seen) + 1L]] <<- list(strict = Sys.getenv("HVTI_TEMPLATE_STRICT", NA), dir = execute_dir)
    },
    .package = "quarto"
  )
  old <- Sys.getenv("HVTI_TEMPLATE_STRICT", unset = NA)
  Sys.setenv(HVTI_TEMPLATE_STRICT = "0")
  on.exit(if (is.na(old)) Sys.unsetenv("HVTI_TEMPLATE_STRICT") else Sys.setenv(HVTI_TEMPLATE_STRICT = old), add = TRUE)

  render_job(job)
  render_job(job, final = TRUE)

  expect_identical(seen[[1L]]$strict, "0")
  expect_identical(seen[[2L]]$strict, "1")
  expect_identical(seen[[2L]]$dir, dirname(normalizePath(job, winslash = "/")))
  expect_identical(Sys.getenv("HVTI_TEMPLATE_STRICT"), "0")
})

test_that("render_job restores the environment when the render fails", {
  skip_if_not_installed("quarto")
  job <- tempfile(fileext = ".qmd")
  writeLines("x", job)
  on.exit(unlink(job), add = TRUE)
  local_mocked_bindings(quarto_render = function(...) stop("unresolved EDIT markers"), .package = "quarto")
  old <- Sys.getenv("HVTI_TEMPLATE_STRICT", unset = NA)
  Sys.unsetenv("HVTI_TEMPLATE_STRICT")
  on.exit(if (is.na(old)) Sys.unsetenv("HVTI_TEMPLATE_STRICT") else Sys.setenv(HVTI_TEMPLATE_STRICT = old), add = TRUE)

  expect_error(render_job(job, final = TRUE), "unresolved")
  expect_true(is.na(Sys.getenv("HVTI_TEMPLATE_STRICT", unset = NA)))
})

test_that("render_job rejects a missing file and a non-logical final", {
  expect_error(render_job(tempfile(fileext = ".qmd")), "render_job\\(\\):")
  job <- tempfile(fileext = ".qmd")
  writeLines("x", job)
  on.exit(unlink(job), add = TRUE)
  expect_error(render_job(job, final = "yes"), "render_job\\(\\):")
})

test_that("render_job rejects a directory path", {
  skip_if_not_installed("quarto")
  called <- FALSE
  local_mocked_bindings(quarto_render = function(...) called <<- TRUE, .package = "quarto")

  expect_error(render_job(tempdir()), "render_job\\(\\):")
  expect_false(called)
})

test_that("render_job runs Quarto's R on the calling R unless QUARTO_R is set", {
  skip_if_not_installed("quarto")
  job <- tempfile(fileext = ".qmd")
  writeLines("x", job)
  on.exit(unlink(job), add = TRUE)
  seen <- character()
  local_mocked_bindings(
    quarto_render = function(...) seen[[length(seen) + 1L]] <<- Sys.getenv("QUARTO_R", NA),
    .package = "quarto"
  )
  old <- Sys.getenv("QUARTO_R", unset = NA)
  on.exit(if (is.na(old)) Sys.unsetenv("QUARTO_R") else Sys.setenv(QUARTO_R = old), add = TRUE)

  Sys.unsetenv("QUARTO_R")
  render_job(job)
  expect_identical(seen[[1L]], R.home("bin"))
  expect_true(is.na(Sys.getenv("QUARTO_R", unset = NA)))

  Sys.setenv(QUARTO_R = "/opt/R/chosen/bin")
  render_job(job)
  expect_identical(seen[[2L]], "/opt/R/chosen/bin")
  expect_identical(Sys.getenv("QUARTO_R"), "/opt/R/chosen/bin")

  Sys.setenv(QUARTO_R = "")
  render_job(job)
  expect_identical(seen[[3L]], R.home("bin"))
  # Windows has no empty environment variable: setting one to "" removes it.
  if (.Platform$OS.type != "windows") expect_identical(Sys.getenv("QUARTO_R", unset = NA), "")
})

test_that("render_job unsets QUARTO_R after a failed render", {
  skip_if_not_installed("quarto")
  job <- tempfile(fileext = ".qmd")
  writeLines("x", job)
  on.exit(unlink(job), add = TRUE)
  local_mocked_bindings(quarto_render = function(...) stop("render failed"), .package = "quarto")
  old <- Sys.getenv("QUARTO_R", unset = NA)
  Sys.unsetenv("QUARTO_R")
  on.exit(if (is.na(old)) Sys.unsetenv("QUARTO_R") else Sys.setenv(QUARTO_R = old), add = TRUE)

  expect_error(render_job(job), "render failed")
  expect_true(is.na(Sys.getenv("QUARTO_R", unset = NA)))
})

# Quarto's Deno runtime can die as it starts. bash reports it on stderr as the
# launcher's unexpanded source line, and the quarto package, formatting that
# line with cli, turns it into an unrelated error. processx::run() is mocked
# to fail the way the launcher does, so the quarto package builds that error
# itself, on every platform, without a crash to wait for.
quarto_fails_with <- function(stderr, status) {
  real_run <- processx::run
  function(command = NULL, args = character(), ...) {
    if (identical(args, "--version")) return(real_run(command, args, ...))
    cnd <- structure(
      list(message = "System command 'quarto' failed", call = NULL, stderr = stderr, stdout = "", status = status),
      class = c("system_command_status_error", "rlib_error_3_0", "rlib_error", "error", "condition")
    )
    stop(cnd)
  }
}
deno_crash_line <- paste0(
  "/Applications/quarto/bin/quarto: line 206: 4242 Segmentation fault: 11  ",
  "\"${QUARTO_DENO}\" ${QUARTO_ACTION} ${QUARTO_DENO_OPTIONS} \"${QUARTO_TARGET}\" \"$@\""
)

test_that("render_job reports a Deno crash as Quarto's, and keeps the original", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto is not installed")
  job <- tempfile(fileext = ".qmd")
  writeLines("x", job)
  on.exit(unlink(job), add = TRUE)
  local_mocked_bindings(run = quarto_fails_with(deno_crash_line, 139L), .package = "processx")

  e <- tryCatch(render_job(job, quiet = TRUE), error = function(e) e)
  expect_s3_class(e, "hvtiRtemplates_quarto_crashed")
  expect_match(conditionMessage(e), "Quarto crashed before rendering", fixed = TRUE)
  expect_match(conditionMessage(e), "Render the job again", fixed = TRUE)
  # Base R prints no parent, so the cause is in the message.
  expect_match(conditionMessage(e), "Quarto said: ", fixed = TRUE)
  expect_true(hvtiRtemplates:::.quarto_crashed(e$parent))
})

test_that("render_job passes a job's own failure through unchanged", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto is not installed")
  job <- tempfile(fileext = ".qmd")
  writeLines("x", job)
  on.exit(unlink(job), add = TRUE)
  # A chunk error that names the token, an exit status no signal produced,
  # and a stderr carrying no braces: none of them is a Quarto crash.
  for (case in list(list("Error: QUARTO_DENO is mentioned by this analysis", 1L), list("", 200L))) {
    local_mocked_bindings(run = quarto_fails_with(case[[1L]], case[[2L]]), .package = "processx")
    e <- tryCatch(render_job(job, quiet = TRUE), error = function(e) e)
    expect_s3_class(e, "error")
    expect_false(inherits(e, "hvtiRtemplates_quarto_crashed"))
    expect_false(hvtiRtemplates:::.quarto_crashed(e))
  }
})

test_that(".quarto_crashed needs the exact pair, not the token", {
  skip_if_not_installed("processx")
  expect_false(hvtiRtemplates:::.quarto_crashed(simpleError("object 'QUARTO_DENO' not found")))
  expect_false(hvtiRtemplates:::.quarto_crashed(simpleError("Could not evaluate cli `{}` expression: `QUARTO_DENO`.")))
  e <- tryCatch(processx::run("sh", c("-c", "exit 200")), error = function(e) e)
  expect_false(hvtiRtemplates:::.quarto_crashed(e))
})

test_that(".quarto_crashed takes R-devel's classed object-not-found error", {
  # R 4.7 signals an object not found as objectNotFoundError, not simpleError.
  inner <- errorCondition("object 'QUARTO_DENO' not found", class = "objectNotFoundError")
  outer <- structure(
    list(message = "Could not evaluate cli `{}` expression: `QUARTO_DENO`.", call = NULL, parent = inner),
    class = c("rlib_error_3_0", "rlib_error", "error", "condition")
  )
  expect_true(hvtiRtemplates:::.quarto_crashed(outer))
})

race_error <- function(dir) {
  paste0("Error returned by quarto CLI.\nERROR: Directory not empty (os error 39): remove '",
         file.path(dir, "job_files", "execute-results"), "'")
}

test_that("render_job renders once more when Quarto reports the execute-results race, and says why", {
  skip_if_not_installed("quarto")
  dir <- withr::local_tempdir()
  job <- file.path(dir, "job.qmd")
  writeLines("x", job)
  calls <- 0L
  local_mocked_bindings(quarto_render = function(...) {
    calls <<- calls + 1L
    if (calls == 1L) stop(race_error(dir))
    invisible(NULL)
  }, .package = "quarto")

  msgs <- testthat::capture_messages(render_job(job))
  expect_match(msgs[1L], "Directory not empty", fixed = TRUE)
  expect_match(msgs[2L], "attempt 2 of 3", fixed = TRUE)
  expect_identical(calls, 2L)
})

test_that("render_job gives up after a third race, with its own class, the commands, and the original error kept", {
  skip_if_not_installed("quarto")
  dir <- withr::local_tempdir()
  job <- file.path(dir, "job.qmd")
  writeLines("x", job)
  calls <- 0L
  local_mocked_bindings(quarto_render = function(...) {
    calls <<- calls + 1L
    stop(race_error(dir))
  }, .package = "quarto")

  e <- expect_error(suppressMessages(render_job(job)), class = "hvtiRtemplates_execute_results_stuck")
  files <- file.path(normalizePath(dir, winslash = "/"), "job_files")
  expect_match(conditionMessage(e), "in each of 3 renders", fixed = TRUE)
  expect_match(conditionMessage(e), paste0("lsof +D ", shQuote(files)), fixed = TRUE)
  expect_match(conditionMessage(e), paste0("rm -rf ", shQuote(files)), fixed = TRUE)
  expect_match(conditionMessage(e$parent), "os error 39", fixed = TRUE)
  expect_identical(calls, 3L)
})

# A folder left as Quarto leaves it on the share: its file deleted while still held, so only an .nfs entry remains.
stuck_folder <- function(dir, extra = NULL) {
  results <- file.path(dir, "job_files", "execute-results")
  dir.create(results, recursive = TRUE, showWarnings = FALSE)
  for (f in c(".nfs000000000123abcd00000001", extra)) writeLines("{}", file.path(results, f))
  results
}

test_that("before a rerun, render_job waits for the share to let go of the folder's .nfs entries", {
  skip_if_not_installed("quarto")
  dir <- withr::local_tempdir()
  job <- file.path(dir, "job.qmd")
  writeLines("x", job)
  calls <- 0L
  slept <- numeric()
  local_mocked_bindings(quarto_render = function(...) {
    calls <<- calls + 1L
    if (calls == 1L) {
      stuck_folder(dir)
      stop(race_error(dir))
    }
    # The rerun starts only once the share has let go.
    expect_false(any(startsWith(list.files(file.path(dir, "job_files", "execute-results"), all.files = TRUE), ".nfs")))
    invisible(NULL)
  }, .package = "quarto")
  # The share lets go during the second wait.
  local_mocked_bindings(.race_sleep = function(s) {
    slept <<- c(slept, s)
    if (length(slept) == 2L) unlink(list.files(file.path(dir, "job_files", "execute-results"), "^[.]nfs",
                                               all.files = TRUE, full.names = TRUE))
  })

  msgs <- testthat::capture_messages(render_job(job))
  expect_identical(calls, 2L)
  expect_identical(slept, c(1, 2))
  expect_true(any(grepl("let go of it after 3 s", msgs, fixed = TRUE)))
  expect_true(any(grepl("attempt 2 of 3", msgs, fixed = TRUE)))
  expect_length(Sys.glob(file.path(dir, "*.stale-*")), 0L)
})

test_that("an .nfs entry that outlasts the wait has its folder moved beside the job, not deleted", {
  skip_if_not_installed("quarto")
  dir <- withr::local_tempdir()
  job <- file.path(dir, "job.qmd")
  writeLines("x", job)
  results <- file.path(dir, "job_files", "execute-results")
  calls <- 0L
  local_mocked_bindings(quarto_render = function(...) {
    calls <<- calls + 1L
    if (calls == 1L) {
      stuck_folder(dir)
      stop(race_error(dir))
    }
    expect_false(dir.exists(results))
    invisible(NULL)
  }, .package = "quarto")
  local_mocked_bindings(.race_sleep = function(s) NULL)

  msgs <- testthat::capture_messages(render_job(job))
  expect_identical(calls, 2L)
  aside <- Sys.glob(file.path(dir, "job.execute-results.stale-*"))
  expect_length(aside, 1L)
  expect_identical(list.files(aside, all.files = TRUE, no.. = TRUE), ".nfs000000000123abcd00000001")
  expect_true(any(grepl("still held open after 60 s", msgs, fixed = TRUE)))
  expect_true(any(grepl(basename(aside), msgs, fixed = TRUE)))
})

test_that("a held folder that holds anything but .nfs entries is left in place, and the job is still rerun", {
  skip_if_not_installed("quarto")
  dir <- withr::local_tempdir()
  job <- file.path(dir, "job.qmd")
  writeLines("x", job)
  calls <- 0L
  local_mocked_bindings(quarto_render = function(...) {
    calls <<- calls + 1L
    if (calls == 1L) {
      stuck_folder(dir, extra = "html.json")
      stop(race_error(dir))
    }
    invisible(NULL)
  }, .package = "quarto")
  local_mocked_bindings(.race_sleep = function(s) NULL)

  msgs <- testthat::capture_messages(render_job(job))
  expect_identical(calls, 2L)
  expect_true(file.exists(file.path(dir, "job_files", "execute-results", "html.json")))
  expect_length(Sys.glob(file.path(dir, "*.stale-*")), 0L)
  expect_true(any(grepl("left in place", msgs, fixed = TRUE)))
})

test_that("a Quarto error that only leaves execute-results behind is passed through, not retried", {
  skip_if_not_installed("quarto")
  dir <- withr::local_tempdir()
  job <- file.path(dir, "job.qmd")
  writeLines("x", job)
  results <- file.path(dir, "job_files", "execute-results")
  calls <- 0L
  local_mocked_bindings(quarto_render = function(...) {
    calls <<- calls + 1L
    dir.create(results, recursive = TRUE, showWarnings = FALSE)
    stop("ERROR: PermissionDenied: project freezer is read-only")
  }, .package = "quarto")

  expect_error(render_job(job), "freezer is read-only", fixed = TRUE)
  expect_identical(calls, 1L)
})

test_that("an os error 39 on another document's execute-results is not this job's race", {
  skip_if_not_installed("quarto")
  dir <- withr::local_tempdir()
  job <- file.path(dir, "job.qmd")
  writeLines("x", job)
  other <- "ERROR: Directory not empty (os error 39): remove '/other/other_files/execute-results'"
  calls <- 0L
  local_mocked_bindings(quarto_render = function(...) {
    calls <<- calls + 1L
    stop(other)
  }, .package = "quarto")

  expect_error(render_job(job), "/other/other_files", fixed = TRUE)
  expect_identical(calls, 1L)
})

test_that("a job's own error that mentions os error 39 and execute-results is not the race", {
  skip_if_not_installed("quarto")
  dir <- withr::local_tempdir()
  job <- file.path(dir, "job.qmd")
  writeLines("x", job)
  calls <- 0L
  local_mocked_bindings(quarto_render = function(...) {
    calls <<- calls + 1L
    stop("chunk `clean`: could not tidy execute-results after os error 39 in ", file.path(dir, "job_files"))
  }, .package = "quarto")

  expect_error(render_job(job), "chunk `clean`", fixed = TRUE)
  expect_identical(calls, 1L)
})

test_that("the race matches this job's folder through a symlinked study path, existing or not", {
  real <- withr::local_tempdir()
  link <- file.path(withr::local_tempdir(), "study")
  # Windows takes a junction: unlink() removes one, but warns that it cannot delete a
  # Windows symbolic link when the temporary folder is cleaned up. If the link is
  # refused, the test runs on the real path rather than skipping.
  made <- suppressWarnings(if (.Platform$OS.type == "windows") Sys.junction(real, link) else file.symlink(real, link))
  if (!made) link <- real
  expected <- .execute_results_dir(file.path(normalizePath(real), "job.qmd"))
  line <- function(d) paste0("ERROR: Directory not empty (os error 39): remove '", file.path(d, "job_files", "execute-results"), "'")
  expect_true(.is_execute_results_race(line(link), expected))
  dir.create(file.path(real, "job_files", "execute-results"), recursive = TRUE)
  expect_true(.is_execute_results_race(line(link), expected))
  expect_false(.is_execute_results_race(line(file.path(real, "sub")), expected))
})

test_that("render_job deletes no execute-results folder, which another render of the job may own", {
  skip_if_not_installed("quarto")
  dir <- withr::local_tempdir()
  job <- file.path(dir, "job.qmd")
  writeLines("x", job)
  active <- file.path(dir, "job_files", "execute-results", "html.json")
  dir.create(dirname(active), recursive = TRUE)
  writeLines("{}", active)
  local_mocked_bindings(quarto_render = function(...) {
    expect_true(file.exists(active))
    invisible(NULL)
  }, .package = "quarto")

  render_job(job)
  expect_true(file.exists(active))
})

test_that("the race is read from the run log when the error chain lost Quarto's message", {
  skip_if_not_installed("quarto")
  dir <- withr::local_tempdir()
  job <- file.path(dir, "job.qmd")
  writeLines("x", job)
  log <- file.path(dir, "job.run.log")
  writeLines("an earlier run's output", log)
  calls <- 0L
  local_mocked_bindings(quarto_render = function(...) {
    calls <<- calls + 1L
    if (calls == 1L) {
      cat("\033[91m", sub("^[^\n]*\n", "", race_error(dir)), "\033[39m\n\nStack trace:\n", file = log, append = TRUE, sep = "")
      stop("Internal error in `cli::ansi_strwrap()`")
    }
    invisible(NULL)
  }, .package = "quarto")

  msgs <- testthat::capture_messages(render_job(job))
  expect_match(msgs[1L], "Directory not empty", fixed = TRUE)
  expect_match(msgs[2L], "attempt 2 of 3", fixed = TRUE)
  expect_identical(calls, 2L)
})

test_that("a race already in the run log before this render began is not read as this render's", {
  skip_if_not_installed("quarto")
  dir <- withr::local_tempdir()
  job <- file.path(dir, "job.qmd")
  writeLines("x", job)
  writeLines(sub("^[^\n]*\n", "", race_error(dir)), file.path(dir, "job.run.log"))
  calls <- 0L
  local_mocked_bindings(quarto_render = function(...) {
    calls <<- calls + 1L
    stop("chunk failed")
  }, .package = "quarto")

  expect_error(render_job(job), "chunk failed")
  expect_identical(calls, 1L)
})

test_that("the stuck error names the folders moved aside before each rerun", {
  skip_if_not_installed("quarto")
  dir <- withr::local_tempdir()
  job <- file.path(dir, "job.qmd")
  writeLines("x", job)
  calls <- 0L
  local_mocked_bindings(quarto_render = function(...) {
    calls <<- calls + 1L
    stuck_folder(dir)
    stop(race_error(dir))
  }, .package = "quarto")
  # The folder's name carries milliseconds; a real wait is a minute, so this one only has to outlast the clock's tick.
  local_mocked_bindings(.race_sleep = function(s) if (s == 1) Sys.sleep(0.01))

  e <- expect_error(suppressMessages(render_job(job)), class = "hvtiRtemplates_execute_results_stuck")
  aside <- Sys.glob(file.path(dir, "job.execute-results.stale-*"))
  expect_length(aside, 2L)
  for (a in basename(aside)) expect_match(conditionMessage(e), a, fixed = TRUE)
  expect_identical(calls, 3L)
})

# A study root with its render lock, the lock owned by `owner` when one is given.
lock_root <- function(owner = NULL) {
  root <- withr::local_tempdir(.local_envir = parent.frame())
  if (!is.null(owner)) {
    lock <- .provenance_lock_path(root)
    dir.create(lock, recursive = TRUE)
    jsonlite::write_json(owner, file.path(lock, "owner.json"), auto_unbox = TRUE)
  }
  root
}

test_that("the folder is moved holding the study's render lock, taken over from the failed render, then released", {
  skip_if_not_installed("ps")
  dir <- withr::local_tempdir()
  results <- stuck_folder(dir)
  # The failed attempt's Quarto process has exited, so its lock is a dead render's.
  root <- lock_root(list(pid = 999999L, created = "0.000000", host = Sys.info()[["nodename"]]))
  lock <- .provenance_lock_path(root)
  local_mocked_bindings(.race_sleep = function(s) NULL, .start_provenance_heartbeat = function(...) TRUE)
  released <- NULL
  real_release <- .release_provenance_lock
  local_mocked_bindings(.release_provenance_lock = function(root, me) {
    # At release the lock is still this process's, and the folder has already moved: the move was made inside it.
    released <<- list(owner = jsonlite::read_json(file.path(lock, "owner.json")), moved = !dir.exists(results))
    real_release(root, me)
  })

  out <- .settle_execute_results(results, root = root)
  expect_identical(released$owner, .provenance_self_owner())
  expect_true(released$moved)
  expect_false(dir.exists(results))
  expect_length(Sys.glob(file.path(dir, "job.execute-results.stale-*")), 1L)
  expect_match(out, "was moved to", fixed = TRUE)
  expect_false(dir.exists(lock))
})

test_that("a render lock the move could not release is named, since this session would hold it until it exits", {
  skip_if_not_installed("ps")
  dir <- withr::local_tempdir()
  results <- stuck_folder(dir)
  root <- lock_root(list(pid = 999999L, created = "0.000000", host = Sys.info()[["nodename"]]))
  lock <- .provenance_lock_path(root)
  local_mocked_bindings(.race_sleep = function(s) NULL, .start_provenance_heartbeat = function(...) TRUE,
                        .release_provenance_lock = function(root, me) invisible(NULL))

  expect_warning(out <- .settle_execute_results(results, root = root), "could not be released", fixed = TRUE)
  expect_match(out, "was moved to", fixed = TRUE)
  expect_identical(jsonlite::read_json(file.path(lock, "owner.json")), .provenance_self_owner())
  w <- tryCatch(.release_settled_lock(root, .provenance_self_owner()), warning = conditionMessage)
  expect_match(w, paste0("delete ", lock, "."), fixed = TRUE)
  expect_match(w, .provenance_takeover_path(lock), fixed = TRUE)
})

test_that("a folder is left in place while another render holds the study's render lock", {
  skip_if_not_installed("ps")
  dir <- withr::local_tempdir()
  results <- stuck_folder(dir)
  # The session's parent stands in for a live render, as a Quarto render's owner is the R hook's parent.
  live <- .provenance_render_owner()
  root <- lock_root(live)
  local_mocked_bindings(.race_sleep = function(s) NULL)

  out <- .settle_execute_results(results, root = root)
  expect_true(dir.exists(results))
  expect_length(Sys.glob(file.path(dir, "*.stale-*")), 0L)
  expect_match(out, "render lock could not be taken, so the folder was left in place. Another Quarto render", fixed = TRUE)
  # Only the sentence naming the holder: the advice to wait and render again is for someone starting a render.
  expect_no_match(out, "Wait for it", fixed = TRUE)
  expect_identical(jsonlite::read_json(file.path(.provenance_lock_path(root), "owner.json")), live)
})

test_that("a lock this R process already holds is neither moved under nor released", {
  skip_if_not_installed("ps")
  dir <- withr::local_tempdir()
  results <- stuck_folder(dir)
  root <- lock_root(.provenance_self_owner())
  local_mocked_bindings(.race_sleep = function(s) NULL)

  out <- .settle_execute_results(results, root = root)
  expect_true(dir.exists(results))
  expect_match(out, "This R process already holds it.", fixed = TRUE)
  expect_true(dir.exists(.provenance_lock_path(root)))
})

test_that("the lock is the Quarto project's, the folder holding _quarto.yml that the hooks lock", {
  root <- withr::local_tempdir()
  writeLines("project: {}", file.path(root, "_quarto.yml"))
  job_dir <- file.path(root, "10_descriptive")
  dir.create(job_dir)
  expect_identical(.job_quarto_project(job_dir), normalizePath(root, winslash = "/"))
  expect_null(.job_quarto_project(withr::local_tempdir()))
})

test_that("a free study render lock is held by this R process, its heartbeat tied to it, and released after the move", {
  skip_if_not_installed("ps")
  dir <- withr::local_tempdir()
  results <- stuck_folder(dir)
  root <- lock_root()
  lock <- .provenance_lock_path(root)
  beats <- list()
  local_mocked_bindings(.race_sleep = function(s) NULL,
                        .start_provenance_heartbeat = function(lock, owner, ...) beats[[length(beats) + 1L]] <<- owner)

  .settle_execute_results(results, root = root)
  expect_false(dir.exists(results))
  # Should this process die holding the lock, the session's parent may live on; the owner and the loop that beats for
  # it are this process, so the lock then reads as dead here and its heartbeat stops for other hosts.
  expect_length(beats, 1L)
  expect_identical(beats[[1L]], .provenance_self_owner())
  expect_identical(beats[[1L]]$pid, Sys.getpid())
  expect_false(dir.exists(lock))
})
