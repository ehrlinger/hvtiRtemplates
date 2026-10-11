# lp-mirror: the mirrored propensity histogram, read from a saved
# lm-propensity_binary bundle. The design is
# dev/specs/2026-10-11-lp-mirror-template-design.md; its section 7 lists what
# these tests cover. All data are synthetic.

test_that("lp-mirror is a graphs template that add_job() scaffolds by its full name", {
  tl <- template_list()
  row <- tl[tl$name == "lp.mirror", ]
  expect_identical(nrow(row), 1L)
  expect_identical(row$folder, "graphs")
  expect_identical(row$call, "add_job(\"lp.mirror\", subject = \"treatment\", type = \"propensity\")")
  root <- lm_study()
  job <- add_job("lp.mirror", "treatment", "propensity", dir = root)
  expect_identical(basename(job), "lp.mirror.treatment.propensity.qmd")
  expect_identical(normalizePath(dirname(job)), normalizePath(hvtiRutilities::study_dir("graphs", root)))
  src <- readLines(job, warn = FALSE)
  expect_identical(grep("^SUBJECT\\s+<- ", src, value = TRUE), "SUBJECT <- \"treatment\"")
  expect_identical(grep("^TYPE\\s+<- ", src, value = TRUE), "TYPE    <- \"propensity\"")
})

test_that("the job's package guards ask for the versions DESCRIPTION suggests", {
  src <- readLines(template_path("lp", "mirror"), warn = FALSE)
  suggests <- gsub("\\s+", " ", utils::packageDescription("hvtiRtemplates")$Suggests)
  for (pkg in c("hvtiRpropensity", "hvtiPlotR")) {
    minimum <- sub(paste0(".*", pkg, " \\(>= ([0-9.]+)\\).*"), "\\1", suggests)
    guard <- regmatches(src, regexpr(paste0("packageVersion[(]\"", pkg, "\"[)] < \"[0-9.]+\""), src))
    expect_length(guard, 1L)
    expect_identical(sub('.*< "([0-9.]+)"$', "\\1", guard), minimum, info = pkg)
    expect_true(any(grepl(paste0(pkg, " >= ", minimum), src, fixed = TRUE)), info = pkg)
  }
})
