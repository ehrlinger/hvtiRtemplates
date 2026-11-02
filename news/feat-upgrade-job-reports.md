* `upgrade_job()` now says what it did, naming the archived job and report. A job already current with its template is left
  alone, with a message, and no longer adds a pair to `_archive` at every call.
