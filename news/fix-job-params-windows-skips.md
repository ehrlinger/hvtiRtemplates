* Five tests in `test-job-params.R` call `submit_job()` or `cancel_job()`, neither of which runs on Windows, and
  now skip there as the file's other five do. The file arrived after the 2026-11-16 weekly sweep, and pull requests
  run no Windows leg, so it first ran on Windows in a dispatched sweep and failed five times. The `cancel_job()`
  check on `output_file` moves into its own test, so the `render_job()`, `submit_job()` and `run_job()` argument
  checks beside it still run on Windows.
