# Every template carries its own HTML format: a report is sent on as one
# self-contained file, and reads full width with its contents on the left.
# Each template states this in its own header (a copied file does not inherit
# _quarto.yml), so a template that drifts is caught here.

front_matter <- function(file) {
  lines <- readLines(file, warn = FALSE)
  fence <- which(lines == "---")
  yaml::yaml.load(paste(lines[(fence[1L] + 1L):(fence[2L] - 1L)], collapse = "\n"))
}

test_that("every template renders self-contained, full width, contents on the left", {
  files <- template_list()$file
  expect_gt(length(files), 0L)
  for (file in files) {
    html <- front_matter(file)$format$html
    label <- basename(file)
    expect_true(isTRUE(html$`embed-resources`), label = label)
    expect_true(isTRUE(html$toc), label = label)
    expect_identical(html$`toc-location`, "left", label = label)
    expect_identical(html$`page-layout`, "full", label = label)
    expect_identical(html$grid$`body-width`, "2000px", label = label)
    expect_identical(html$grid$`sidebar-width`, "250px", label = label)
  }
})
