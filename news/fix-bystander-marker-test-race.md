* The `cancel_job()` test of a live process without the run's marker no longer
  fails intermittently on Linux. It called `cancel_job()` while its bystander
  was still exec'ing from `sh` to `Rscript` to `R`, when Linux cannot read a
  process's environment, and `cancel_job()` rightly refused the process as
  ambiguous. The test now waits until R itself is running. `cancel_job()` is
  unchanged.
