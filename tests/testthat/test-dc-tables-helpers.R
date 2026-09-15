template <- system.file(
  "templates", "10_descriptive", "dc-tables.qmd",
  package = "hvtiRtemplates"
)
if (!nzchar(template)) {
  template <- testthat::test_path(
    "..", "..", "inst", "templates", "10_descriptive", "dc-tables.qmd"
  )
}
template_lines <- readLines(template, warn = FALSE)
helper_label <- grep("^#\\| label: helpers$", template_lines)
helper_end <- helper_label + which(template_lines[-seq_len(helper_label)] == "```")[[1L]]
eval(parse(text = template_lines[(helper_label + 1L):(helper_end - 1L)]))

d <- data.frame(
  age = c(55.5, 61, 70.2, 48, 66, 59, 72.1, 50),
  female = c(0, 1, 1, 0, 1, 0, 0, 1),
  flag = c(TRUE, FALSE, TRUE, TRUE, FALSE, NA, TRUE, FALSE),
  nyha = c(1, 2, 2, 3, 4, 1, 2, 3),
  race = c("W", "B", "W", "O", "W", "W", "B", "W"),
  code = c(1, 2, 1, 2, 2, 1, 1, 2)
)

test_that("classify_buckets sorts by the data", {
  b <- classify_buckets(d, names(d))
  expect_setequal(b$continuous, "age")
  expect_setequal(b$binary, c("female", "flag"))
  expect_setequal(b$categorical, c("nyha", "race", "code"))
})

test_that("overrides win over the data", {
  b <- classify_buckets(d, names(d), overrides = list(continuous = "nyha"))
  expect_true("nyha" %in% b$continuous)
  expect_false("nyha" %in% b$categorical)
})

test_that("override buckets must be explicitly and uniquely named", {
  expect_error(
    classify_buckets(d, names(d), overrides = list("nyha")),
    "named"
  )
  duplicate_names <- structure(
    list("age", "nyha"),
    names = c("continuous", "continuous")
  )
  expect_error(
    classify_buckets(d, names(d), overrides = duplicate_names),
    "unique"
  )
})

test_that("binary inference matches hv_tbl_summary's accepted data", {
  binary_data <- data.frame(
    character_yes_no = c("Yes", "No", "Yes", NA),
    factor_yes_no = factor(c("No", "Yes", "No", NA), levels = c("No", "Yes")),
    all_zero = rep(0, 4)
  )

  b <- classify_buckets(binary_data, names(binary_data))

  expect_setequal(b$binary, c("character_yes_no", "factor_yes_no"))
  expect_identical(b$categorical, "all_zero")
})

test_that("every variable lands in exactly one bucket", {
  b <- classify_buckets(d, names(d))
  expect_setequal(unlist(b, use.names = FALSE), names(d))
})
