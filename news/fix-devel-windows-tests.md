- `render_job()` recognises a Quarto crash under R-devel too, where an object
  not found is an `objectNotFoundError` rather than a `simpleError`; it had
  passed the crash through as Quarto's raw error there.
