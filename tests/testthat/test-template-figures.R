figure_templates <- c("dc-gfup", "dc-stddiff", "dc-tables", "dp-eda", "dp-postage", "dp-gfup", "dp-trends", "hp",
                      "bc", "bh", "bl", "br", "nb-boostmtree", "rfc-explain", "rfr-explain", "rfs-explain",
                      "rfc-fit", "rfr-fit", "rfs-fit")

template_source <- function(name) {
  tl <- template_list()
  readLines(tl$file[sub(".", "-", tl$name, fixed = TRUE) == name | tl$name == name], warn = FALSE)
}

test_that("every figure template offers the two choices and the wrapper, with no EDIT marker on them", {
  for (name in figure_templates) {
    src <- template_source(name)
    expect_true(any(src == "SAVE_FIGURES <- TRUE"), info = name)
    expect_true(any(src == "FIGURES <- NULL"), info = name)
    expect_true(any(grepl("^save_figure <- function\\(plot, name", src)), info = name)
    choices <- grep("SAVE_FIGURES|FIGURES <- ", src)
    expect_false(any(grepl("EDIT:", src[choices], fixed = TRUE)), info = name)
  }
})

test_that("no template saves a figure except through save_figure()", {
  for (name in figure_templates) {
    src <- template_source(name)
    expect_false(any(grepl("ggplot2::ggsave(", src, fixed = TRUE)), info = name)
    expect_false(any(grepl("^\\s*png\\(", src)), info = name)
  }
})
