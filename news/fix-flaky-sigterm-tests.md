* Two `cancel_job()` tests no longer fail on a loaded machine. Each sent SIGTERM to a shell whose `trap` might not
  have run yet: "a job that ignores SIGTERM" signalled its bystander as soon as it started, and "a process the job
  starts while shutting down" waited a fixed second. A shell signalled before its `trap` line dies on the signal,
  so the first ended in under the grace period and the second never wrote `late.pid`. Each shell now writes a file
  once its `trap` is set, and the test waits for that file before cancelling.
