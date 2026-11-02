* A job's path from the study root now comes out right on Windows, where `run_job()` and the
  pre-flight checks printed the full path with mixed separators in their `hvti status` and
  `hvti cancel` advice. The test suite also passes again against randomForestSRC 3.10.0, Quarto
  1.11 and Windows.
