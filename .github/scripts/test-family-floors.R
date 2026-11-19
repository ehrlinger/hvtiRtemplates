# Run the test suite against the family floors install-family-floors.R put in
# place, and fail on any skip as well as any failure (#566).
#
# A test that skips because an older family member lacks something is exactly
# the break this job exists to catch, and a skip does not turn the check red.
# Linux runs SKIP 0 under NOT_CRAN=true (AGENTS.md, "The automated gates"), so
# any skip here is new.

res <- as.data.frame(testthat::test_local(stop_on_failure = TRUE, reporter = "summary"))
skipped <- res[res$skipped, c("file", "test")]
cat(sprintf("\nFamily floors: FAIL %d | WARN %d | SKIP %d | PASS %d\n",
            sum(res$failed), sum(res$warning), nrow(skipped), sum(res$passed)))
if (nrow(skipped)) {
  print(skipped, row.names = FALSE)
  stop(nrow(skipped), " test(s) skipped against the family floors; each hides a path this job does not check.")
}
