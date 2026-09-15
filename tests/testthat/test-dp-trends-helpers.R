template <- system.file(
  "templates", "40_graphs", "dp-trends.qmd",
  package = "hvtiRtemplates"
)
if (!nzchar(template)) {
  template <- testthat::test_path(
    "..", "..", "inst", "templates", "40_graphs", "dp-trends.qmd"
  )
}
template_lines <- readLines(template, warn = FALSE)
helper_label <- grep("^#\\| label: helpers$", template_lines)
helper_end <- helper_label + which(template_lines[-seq_len(helper_label)] == "```")[[1L]]
eval(parse(text = template_lines[(helper_label + 1L):(helper_end - 1L)]))

test_that("percent trends reject factor-coded indicators", {
  d <- data.frame(
    year = rep(2020:2021, each = 2L),
    flag = factor(c("0", "1", "0", "1"))
  )

  expect_error(
    trend_long(d, list(cols = "flag", kind = "percent", labels = "Flag")),
    "numeric.*logical"
  )
})

test_that("percent trends reject median summaries", {
  d <- data.frame(year = rep(2020:2021, each = 2L), flag = c(0, 1, 0, 1))

  expect_error(
    trend_long(
      d,
      list(cols = "flag", kind = "percent", labels = "Flag", summary = "median")
    ),
    "mean"
  )
})

test_that("continuous trends accept median summaries", {
  d <- data.frame(year = rep(2020:2021, each = 2L), value = c(1, 4, 2, 8))

  out <- trend_long(
    d,
    list(cols = "value", kind = "continuous", labels = "Value", summary = "median")
  )

  expect_equal(out$value, c(1, 4, 2, 8))
})
