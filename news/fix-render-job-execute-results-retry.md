- `render_job()` survives the execute-results race on the network study share
  (#625). Its one rerun met the same `.nfs` entry the first render left, and on
  lri failed three renders of three. Before a rerun it now waits up to a minute
  for the share to let go of the folder, and if the entries outlast that and are
  all the folder holds, moves it beside the job as
  `<job>.execute-results.stale-<time>`, deleting nothing. It renders up to three
  times in all, and a final failure, like `job_status()`, gives the `lsof` and
  `rm -rf` commands for the job's `_files` folder.
