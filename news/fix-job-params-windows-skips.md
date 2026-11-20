* `cancel_job()` checks `output_file` before it refuses to run on Windows, as `submit_job()` already does, so a
  malformed `output_file` there gets its own error rather than the platform refusal.
* Four tests in `test-job-params.R` call `submit_job()`, which does not run on Windows, and now skip there as the
  file's other five do. The file arrived after the 2026-11-16 weekly sweep, and pull requests run no Windows leg,
  so it first ran on Windows in a dispatched sweep and failed.
