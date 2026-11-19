# Run the test suite against the family floors install-family-floors.R put in
# place, and fail on any skip as well as any failure (#566).
#
# A test that skips because an older family member lacks something is exactly
# the break this job exists to catch, and a skip does not turn the check red.
# Linux runs SKIP 0 under NOT_CRAN=true (AGENTS.md, "The automated gates"), so
# any skip here is new.

# testthat stops reporting after 10 failures by default. One missing function
# at a floor fails many tests, and the cap would hide every other break behind
# it. stop_on_failure is off so the counts below always print.
options(testthat.progress.max_fails = Inf, testthat.summary.max_reports = Inf)
res <- as.data.frame(testthat::test_local(stop_on_failure = FALSE, reporter = "summary"))
bad <- res[res$failed > 0 | res$error, c("file", "test")]
skipped <- res[res$skipped, c("file", "test")]
cat(sprintf("\nFamily floors: FAIL %d | WARN %d | SKIP %d | PASS %d\n",
            nrow(bad), sum(res$warning), nrow(skipped), sum(res$passed)))
if (nrow(bad)) {
  cat("\nFailed at the floors:\n")
  print(bad, row.names = FALSE)
}
if (nrow(skipped)) {
  cat("\nSkipped at the floors; each hides a path this job does not check:\n")
  print(skipped, row.names = FALSE)
}
if (nrow(bad) || nrow(skipped)) quit(status = 1)
