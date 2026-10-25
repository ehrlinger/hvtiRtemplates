test_that(".group_colors() draws one group black and never the role colors", {
  skip_if_not_installed("hvtiPlotR")
  expect_identical(.group_colors("All"), c(All = "#000000"))
  roles <- c(hvtiPlotR::hv_role_palette(c("e", "c"), event = "e", censored = "c"), "#0072B2", "#D55E00")
  for (n in c(2L, 4L, 6L)) {
    cols <- .group_colors(paste0("g", seq_len(n)))
    expect_identical(names(cols), paste0("g", seq_len(n)))
    expect_length(unique(cols), n)
    expect_false(any(toupper(cols) %in% toupper(roles)))
  }
  # Factor levels are taken as text, so numeric strata keep their order.
  expect_identical(names(.group_colors(factor(c(1, 2, 10)))), c("1", "2", "10"))
})

test_that("more groups than the house colors hold fall back with a warning, not an error", {
  many <- paste0("g", 1:8)
  expect_warning(cols <- .group_colors(many), "more than the house colors tell apart")
  expect_named(cols, many)
  expect_length(unique(cols), 8L)
})

test_that("every template that colors by role guards hvtiPlotR at the release that added the API", {
  role_api <- "hv_role_palette\\(|scale_colou?r_hv\\(|scale_fill_hv\\(|\\.group_colors\\("
  files <- list.files(system.file("templates", package = "hvtiRtemplates"), "[.]qmd$", recursive = TRUE, full.names = TRUE)
  if (!length(files)) files <- list.files(test_path("../../inst/templates"), "[.]qmd$", recursive = TRUE, full.names = TRUE)
  for (f in files) {
    txt <- readLines(f, warn = FALSE)
    if (!any(grepl(role_api, txt))) next
    floor <- regmatches(txt, regexpr('packageVersion\\("hvtiPlotR"\\) < "[0-9.]+"', txt))
    expect_length(floor, 1L)
    floor <- sub('.*< "([0-9.]+)"', "\\1", floor)
    expect_true(package_version(floor) >= "2.7.18", label = paste(basename(f), "guards hvtiPlotR at", floor))
  }
})
