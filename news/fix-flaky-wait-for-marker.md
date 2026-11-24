* The background-job tests that start a bystander carrying a marker no longer fail at random on Linux. Their wait
  ended on the first `ps::ps_find_tree()` hit, often while the bystander was still `sh`, so a later read could land
  in one of its execs and miss the marker; and a bystander killed mid-startup left the `uname` children R's
  startup runs still carrying it. The wait now ends once the bystander's own R code has run and the marker is on
  its pid, keeps the read that ended it, and the test waits for the killed bystander to exit (#639).
