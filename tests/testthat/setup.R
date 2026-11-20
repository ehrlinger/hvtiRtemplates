# At most two cores, as CRAN asks, wherever a test fits a model that would
# otherwise take every core: randomForestSRC uses all OpenMP threads unless
# rf.cores is set, and CI's two-core runners hide it. Restored when the suite
# ends.
withr::local_options(rf.cores = 2L, mc.cores = 2L, .local_envir = teardown_env())
withr::local_envvar(OMP_THREAD_LIMIT = "2", .local_envir = teardown_env())
# The template renders fit small synthetic cohorts with quarto_render() and render_job(), not run_job(), so
# guard_long_fit() is told to let them through. An environment variable, not options(): Quarto renders in a
# process of its own. test-guard-long-fit.R unsets it to test the guard itself.
withr::local_envvar(HVTI_ALLOW_LONG_FIT = "true", .local_envir = teardown_env())

# A render's R process loads the installed hvtiRtemplates, so every render first
# checks that the copy that process loads is the code under test
# (helper-stale-install.R), and skips with the fix when it is not. Both points
# where a test starts a render are wrapped here, so a new render test is covered
# without remembering a gate:
# - quarto_render(), checked with the R Quarto runs, in the directory it executes in;
# - .launch(), the last step of .submit_job(), checked with the Rscript and study
#   root .submit_job() is about to launch. Every refusal .submit_job() makes comes
#   before it, so a test of those refusals runs whatever is installed.
# A test that mocks either one replaces this wrapper for its own duration. A test
# that compares the installed version with one taken in this process, as
# run_job()'s real-chain test does, refuses before it renders, so it calls
# skip_if_stale_install() itself.
.record_fingerprint_here()
if (requireNamespace("quarto", quietly = TRUE)) {
  local({
    real_render <- quarto::quarto_render
    testthat::local_mocked_bindings(
      quarto_render = function(input = NULL, ..., execute_dir = NULL) {
        dir <- if (!is.null(execute_dir)) execute_dir else if (is.null(input)) getwd() else
          if (dir.exists(input)) input else dirname(input)
        skip_if_stale_install(dir, .quarto_rscript())
        real_render(input, ..., execute_dir = execute_dir)
      },
      .package = "quarto", .env = teardown_env()
    )
  })
}
local({
  real_launch <- .launch
  testthat::local_mocked_bindings(
    .launch = function(cmd) {
      caller <- parent.frame()
      root <- get0("root", envir = caller, inherits = FALSE)
      rscript <- get0("rscript", envir = caller, inherits = FALSE)
      if (!is.character(root) || !is.character(rscript)) {
        stop("setup.R's .launch() wrapper reads `root` and `rscript` from .submit_job(); its caller has none",
             call. = FALSE)
      }
      skip_if_stale_install(root, rscript)
      real_launch(cmd)
    },
    .env = teardown_env()
  )
})

# A test that draws with no device open makes R open its default one, which in
# Rscript is pdf() writing Rplots.pdf into this directory (#494). Nothing fails
# when that happens, and the file is swept into the next commit. So the suite
# looks twice. The state inspector compares, before and after every test, this
# process's open devices and the Rplots*.pdf here, and on a change adds a warning
# to that test that names it. Both, because each misses a case: a plain draw
# leaves the default device open, which only this process sees, while
# knitr::knit_child() closes the device it opened and leaves only the file. The
# file is shared, so under a parallel run a file change can also be reported on
# a test running in another worker at the time; the device change cannot. The
# teardown then stops the run on any new or rewritten Rplots*.pdf, since a
# warning alone fails nothing. Names and modification times, so a stale
# Rplots.pdf that a test overwrites is caught too.
local({
  dir <- getwd()
  rplots <- function() {
    files <- list.files(dir, pattern = "^Rplots.*\\.pdf$")
    stats::setNames(as.numeric(file.mtime(file.path(dir, files))), files)
  }
  before <- rplots()
  testthat::set_state_inspector(function() list(devices = names(grDevices::dev.list()), rplots = rplots()))
  withr::defer({
    testthat::set_state_inspector(NULL)
    after <- rplots()
    was <- before[names(after)]
    new <- names(after)[is.na(was) | after != was]
    if (length(new)) {
      stop("A test drew with no device open and left ", paste(new, collapse = ", "), " in ", dir,
           ". The test's warning names it; give it a device of its own (#494).", call. = FALSE)
    }
  }, envir = teardown_env())
})
