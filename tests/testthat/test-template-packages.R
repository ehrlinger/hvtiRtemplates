test_that("the rfc-fit template's setup chunk yields its packages and floors", {
  pkgs <- .template_packages(template_path("rfc", qualifier = "fit"))
  expect_identical(pkgs$package, c("randomForestSRC", "ggRandomForests", "hvtiRutilities"))
  expect_identical(pkgs$floor, c("3.7.0", "4.0.0", NA))
})

test_that("every shipped template's setup chunk names at least one package", {
  files <- template_list()$file
  for (file in files) {
    pkgs <- .template_packages(file)
    expect(nrow(pkgs) > 0L, paste("no packages read from", basename(file)))
    expect_false(anyNA(pkgs$package))
  }
})

test_that("a template with no setup chunk is an error", {
  file <- withr::local_tempfile(fileext = ".qmd")
  writeLines(c("```{r}", "x <- 1", "```"), file)
  expect_error(.template_packages(file), "no setup chunk")
})

test_that("a package checked with requireNamespace() counts, as dc-eda's patchwork does", {
  pkgs <- .template_packages(template_path("dc", qualifier = "eda"))
  expect_true("patchwork" %in% pkgs$package)
})

test_that("hz and hm declare numDeriv in their setup chunk, so add_job() installs it", {
  for (prefix in c("hz", "hm")) {
    pkgs <- .template_packages(template_path(prefix))
    expect_true("numDeriv" %in% pkgs$package, info = prefix)
  }
})
