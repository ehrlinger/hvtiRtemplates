# .figure_pages() lays a study-sized panel count out on pages no larger than
# 6.5 by 9 in, and never refuses; .partial_subset() cuts a partial-dependence
# result to one page's variables.

test_that("panels fill a page row by row and spill onto the next page", {
  pages <- .figure_pages(8, panel_width = 3.25, panel_height = 2.5)
  expect_length(pages, 2L)
  expect_identical(pages[[1]]$index, 1:6)
  expect_identical(pages[[2]]$index, 7:8)
  expect_identical(c(pages[[1]]$ncol, pages[[1]]$width, pages[[1]]$height), c(2, 6.5, 7.5))
  # A short last page is only as tall as its rows.
  expect_identical(c(pages[[2]]$width, pages[[2]]$height), c(6.5, 2.5))
})

test_that("no page is larger than 6.5 by 9 in, whatever the panel count or size", {
  for (n in c(1, 2, 3, 7, 25, 101)) {
    for (h in c(2, 3, 6, 10, 24)) {
      pages <- .figure_pages(n, panel_height = h)
      expect_identical(sort(unlist(lapply(pages, `[[`, "index"))), seq_len(n))
      expect_true(all(vapply(pages, function(p) p$width <= 6.5 && p$height <= 9, logical(1))), info = paste(n, h))
    }
  }
})

test_that("a single panel is drawn at its own width, and no panels draw no page", {
  one <- .figure_pages(1)
  expect_identical(c(one[[1]]$ncol, one[[1]]$width, one[[1]]$height), c(1, 3.25, 3))
  expect_identical(.figure_pages(0), list())
})

test_that("a page height caps the rows, as the two-by-two facet pages use it", {
  pages <- .figure_pages(5, panel_height = 3, page_height = 6)
  expect_identical(lapply(pages, `[[`, "index"), list(1:4, 5L))
  expect_identical(pages[[1]]$height, 6)
})

test_that("a partial-dependence result keeps only the page's variables, and its class", {
  x <- structure(list(continuous = data.frame(x = 1:4, yhat = 0, name = c("a", "a", "b", "c")),
                      categorical = data.frame(x = "l", yhat = 0, name = "d")),
                 class = "gg_partial_rfsrc", partial.type = "surv")
  cut <- .partial_subset(x, c("a", "d"))
  expect_s3_class(cut, "gg_partial_rfsrc")
  expect_identical(attr(cut, "partial.type"), "surv")
  expect_identical(cut$continuous$name, c("a", "a"))
  expect_identical(cut$categorical$name, "d")
  # An empty frame, as VarPro leaves its categorical one, is passed through.
  empty <- structure(list(continuous = data.frame(name = "a"), categorical = data.frame()), class = "gg_partial_varpro")
  expect_identical(.partial_subset(empty, "a")$categorical, data.frame())
})

test_that(".partial_horizon_keys() gives each horizon a line type in every timed panel, under one legend", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("patchwork")
  d <- data.frame(x = rep(1:3, 7), yhat = seq_len(21), time = rep(seq(10, 70, 10), each = 3))
  d$.time_factor <- factor(d$time)
  timed <- ggplot2::ggplot(d, ggplot2::aes(x = .data$x, y = .data$yhat, color = .data$.time_factor,
                                           group = .data$.time_factor)) +
    ggplot2::geom_line() + ggplot2::labs(color = "Time")
  plain <- ggplot2::ggplot(d[c("x", "yhat")], ggplot2::aes(x = .data$x, y = .data$yhat)) + ggplot2::geom_line()
  fig <- hvtiRtemplates:::.partial_horizon_keys(patchwork::wrap_plots(timed, plain, ncol = 1))
  expect_length(unique(ggplot2::ggplot_build(fig[[1]])$data[[1]]$linetype), 7L)
  expect_identical(unique(ggplot2::ggplot_build(fig[[2]])$data[[1]]$linetype), 1L)
  withr::local_pdf(NULL)
  g <- ggplot2::ggplotGrob(fig[[1]])
  box <- g$grobs[[which(grepl("guide-box", g$layout$name) & vapply(g$grobs, inherits, NA, "gtable"))[1]]]
  expect_identical(sum(box$layout$name == "guides"), 1L)
  # A single ggplot, with no horizon, is returned as it is.
  expect_identical(hvtiRtemplates:::.partial_horizon_keys(plain), plain)
})
