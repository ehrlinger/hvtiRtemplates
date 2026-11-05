# At most two cores, as CRAN asks, wherever a test fits a model that would
# otherwise take every core: randomForestSRC uses all OpenMP threads unless
# rf.cores is set, and CI's two-core runners hide it. Restored when the suite
# ends.
withr::local_options(rf.cores = 2L, mc.cores = 2L, .local_envir = teardown_env())
withr::local_envvar(OMP_THREAD_LIMIT = "2", .local_envir = teardown_env())

# A render's R process loads the installed hvtiRtemplates, so every render first
# checks that it is the code under test (helper-stale-install.R) and skips with
# the fix when it is not. Both ways a test reaches a render are wrapped here, so
# a new render test is covered without remembering a gate. A test that mocks
# either one replaces this wrapper for its own duration. A test that compares the
# installed version with one taken in this process, as run_job()'s real-chain
# test does, refuses before it renders, so it calls skip_if_stale_install() itself.
.record_fingerprint_here()
if (requireNamespace("quarto", quietly = TRUE)) {
  local({
    real_render <- quarto::quarto_render
    testthat::local_mocked_bindings(
      quarto_render = function(...) {
        skip_if_stale_install()
        real_render(...)
      },
      .package = "quarto", .env = teardown_env()
    )
  })
}
local({
  real_submit <- .submit_job
  testthat::local_mocked_bindings(
    .submit_job = function(...) {
      skip_if_stale_install()
      real_submit(...)
    },
    .env = teardown_env()
  )
})
