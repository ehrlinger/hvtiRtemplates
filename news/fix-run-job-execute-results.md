* `render_job()`, and so `run_job()` and `submit_job()`, now renders once more when Quarto fails with "Directory not
  empty (os error 39)" removing the job's `_files/execute-results` folder. Quarto writes and deletes that folder in
  one step of every project render, and on the study share the delete can arrive before the share lets go of the
  file, failing a job after every chunk has run. Only that error is retried, read from Quarto's message or the run
  log; any other failure passes through, and nothing is deleted. A second such failure stops with an error of class
  `hvtiRtemplates_execute_results_stuck` that says to delete the folder.
* `job_status()` explains a failure Quarto itself raised by its `ERROR:` line. It used to show the last 20 lines of
  the log, which a Deno stack trace fills, so the message that named the cause was cut off.
