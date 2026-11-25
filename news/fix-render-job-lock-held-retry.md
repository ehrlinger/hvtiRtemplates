* `render_job()` now checks and moves a job's held-open `execute-results` folder
  while holding the study's render lock (#625, #637). Before, it released the
  lock first, so another render of the same job could start between the check
  and the move and have its own folder moved aside. When another render holds
  the lock, the folder is left in place and the rerun goes ahead.
  That hold is this R process's, with a heartbeat of its own, so a session
  that dies holding it leaves a lock the next render takes over, on this host
  or another.
