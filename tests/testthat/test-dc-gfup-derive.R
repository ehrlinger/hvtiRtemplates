template <- system.file(
  "templates", "10_descriptive", "dc-gfup.qmd",
  package = "hvtiRtemplates"
)
if (!nzchar(template)) {
  template <- testthat::test_path(
    "..", "..", "inst", "templates", "10_descriptive", "dc-gfup.qmd"
  )
}
template_lines <- readLines(template, warn = FALSE)
derive_label <- grep("^#\\| label: derive$", template_lines)
derive_end <- derive_label + which(template_lines[-seq_len(derive_label)] == "```")[[1L]]
derive_code <- parse(text = template_lines[(derive_label + 1L):(derive_end - 1L)])

test_that("the follow-up survivor set excludes unknown vital status", {
  d <- data.frame(
    dt_surg = as.Date(c("2020-01-01", "2020-01-01", "2020-01-01")),
    iv_dead = c(4, 4, 4),
    dead = c(0, 1, NA),
    iv_fup = c(3, 3, 3)
  )
  env <- list2env(
    list(
      d = d,
      COLS = c(
        dt_surg = "dt_surg", iv_dead = "iv_dead",
        dead = "dead", iv_fup = "iv_fup"
      ),
      CHECKS = list(),
      CLOSE_DATE = as.Date("2026-01-01")
    ),
    parent = baseenv()
  )

  eval(derive_code, envir = env)

  expect_identical(nrow(env$survivors), 1L)
  expect_false(anyNA(env$survivors$dead))
})
