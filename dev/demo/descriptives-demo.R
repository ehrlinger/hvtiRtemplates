# Descriptives demo, everything in one run: tables, trends, goodness of
# follow-up and EDA plots over the synthetic study in demo-study.R.
#
#   Rscript dev/demo/descriptives-demo.R            # renders into a temp study
#   Rscript dev/demo/descriptives-demo.R ~/eda-demo # or into a folder you keep
#
# The hands-on version, one job at a time, is descriptives-slides.qmd. Compare
# what this renders against reference/ (see reference/README.md).

.here <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
source(file.path(if (length(.here)) dirname(.here) else "dev/demo", "demo-study.R"))

args <- commandArgs(trailingOnly = TRUE)
root <- demo_study(if (length(args)) args[[1L]] else file.path(tempdir(), "descriptives-demo"))
reports <- demo_jobs(root)
message("\nStudy: ", root, "\n", paste0("  ", names(reports), ": ", reports, collapse = "\n"))
if (interactive()) for (r in reports) utils::browseURL(r)
