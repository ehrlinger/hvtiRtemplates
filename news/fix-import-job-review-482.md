* A job's setup chunk is now read for `library("pkg")`, `library(package = pkg)` and `library(pkg, quietly =
  TRUE)` as well as `library(pkg)`, so the pre-render package check and `import_job()` see packages attached
  that way. Every shipped template yields the same package list as before.
