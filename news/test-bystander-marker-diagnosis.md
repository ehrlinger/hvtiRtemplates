* The background-job tests that wait for a process's marker now wait up to 60 seconds rather than 30, stop as soon
  as that process dies, and when they fail say whether it was still running and what it printed, so a slow start
  on a loaded machine can be told from a process that never started (#587).
