- `render_job()` recognises a Quarto crash under R-devel too, where an object
  not found is an `objectNotFoundError` rather than a `simpleError`; it had
  passed the crash through as Quarto's raw error there.
- Tests: the bystander wait behind the intermittent `test-background-job.R`
  failure (#587) no longer gives up on one not-running read taken while the
  process execs into R.
