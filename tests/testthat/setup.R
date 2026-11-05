# At most two cores, as CRAN asks, wherever a test fits a model that would
# otherwise take every core: randomForestSRC uses all OpenMP threads unless
# rf.cores is set, and CI's two-core runners hide it. Restored when the suite
# ends.
withr::local_options(rf.cores = 2L, mc.cores = 2L, .local_envir = teardown_env())
withr::local_envvar(OMP_THREAD_LIMIT = "2", .local_envir = teardown_env())

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
