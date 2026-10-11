figure_templates <- c("dc-gfup", "dc-stddiff", "dc-tables", "dc-eda", "dc-trends", "hp",
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

test_that("every printed figure is also saved, under its documented name", {
  expected <- list(
    bc = "bc-frequencies", bh = "bh-frequencies", bl = "bl-frequencies", br = "br-frequencies",
    `nb-boostmtree` = c("nb-boostmtree-error", "nb-boostmtree-path", "nb-boostmtree-calibration",
                        "nb-boostmtree-importance", "nb-boostmtree-effects-", "nb-boostmtree-traces"),
    `rfc-fit` = c("rfc-fit-diagnostics-error", "rfc-fit-diagnostics-roc"),
    `rfr-fit` = c("rfr-fit-diagnostics-error", "rfr-fit-diagnostics-predicted"),
    `rfs-fit` = c("rfs-fit-diagnostics-error", "rfs-fit-diagnostics-survival", "rfs-fit-diagnostics-brier")
  )
  for (t in c("rfc-explain", "rfr-explain", "rfs-explain")) {
    expected[[t]] <- paste0(t, c("-importance", "-varpro", "-dependence-marginal", "-dependence-partial",
                                 "-dependence-varpro"))
  }
  for (name in names(expected)) {
    src <- template_source(name)
    saves <- src[grepl("save_figure(", src, fixed = TRUE)]
    for (fig in expected[[name]]) {
      expect_true(any(grepl(paste0("\"", fig), saves, fixed = TRUE)), info = paste(name, fig))
    }
  }
})
