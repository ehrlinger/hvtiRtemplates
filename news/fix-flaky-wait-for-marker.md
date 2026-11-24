* The background-job tests that wait for a bystander's marker no longer fail at random on Linux. The wait ended on
  the first `ps::ps_find_tree()` hit, often while the bystander was still `sh`, then read the marker again and
  could miss it in the instant the process execs; it now waits until the marker is on the bystander's own
  `bin/exec/R`, after which nothing execs again, and keeps the read that ended the wait (#639).
