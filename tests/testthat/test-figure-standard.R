# The figure standard, dev/specs/2026-10-13-figure-standard-design.md: a single
# panel is 6 by 4 in, type is 12 pt in the hvtiPlotR theme (8 pt on a page of small
# panels labeled directly, dc-eda's), and every figure has a numbered caption.
# Captions built by .child() at render time are not visible here; the static ones
# are, and they are most of them.

# Nothing is drawn larger than the printed page, 6.5 by 9 in: a figure whose panel
# count follows the study is paged instead: .figure_pages() for the RF and nb
# figures, dc-eda's grid pages, dc-stddiff's 30 rows a page. The one exception,
# matched by the size it is saved at, is dc-tables' scatter-plot matrix: every
# cell pairs two variables, so it cannot be split across pages.
page_exceptions <- c(
  "10_descriptive/dc-tables.qmd" = "width = 10, height = 10"
)

figure_standard_scan <- function(templates) {
  out <- character(0)
  for (f in list.files(templates, pattern = "[.]qmd$", recursive = TRUE, full.names = TRUE)) {
    label <- substring(f, nchar(templates) + 2L)
    src <- readLines(f, warn = FALSE)
    # A theme named in a string, such as a stop() message, or in a comment is not a call.
    code <- sub("#.*$", "", gsub("\"[^\"]*\"", "\"\"", src))
    if (!any(src == "    fig-width: 6") || !any(src == "    fig-height: 4")) {
      out <- c(out, paste0(label, ": format block lacks fig-width: 6 and fig-height: 4"))
    }
    # ggplot2's own themes default to 11 pt, so naming one undoes the standard.
    for (i in grep("theme_(minimal|bw|gr[ae]y|classic|light|linedraw)\\(", code)) {
      out <- c(out, paste0(label, ":", i, ": a ggplot2 theme, not theme_hv_manuscript(base_size = 12)"))
    }
    for (i in grep("theme_hv_manuscript\\(", code)) {
      facet_page <- grepl("theme_hv_manuscript\\(base_size = 8[,)]", code[[i]]) &&
        grepl(".eda_direct_labels(", code[[i]], fixed = TRUE)
      if (!grepl("theme_hv_manuscript\\(base_size = 12[,)]", code[[i]]) && !facet_page) {
        out <- c(out, paste0(label, ":", i, ": theme_hv_manuscript() without base_size = 12"))
      }
    }
    for (i in grep("^#\\| fig-(width|height): [0-9]|(width|height) = [0-9]", src)) {
      if (!is.na(page_exceptions[label]) && grepl(page_exceptions[[label]], src[[i]], fixed = TRUE)) next
      sizes <- regmatches(src[[i]], gregexpr("(width|height)(: | = )[0-9.]+", src[[i]]))[[1]]
      for (size in sizes) {
        inches <- as.numeric(sub("^.*(: | = )", "", size))
        if (inches > if (startsWith(size, "width")) 6.5 else 9) {
          out <- c(out, paste0(label, ":", i, ": ", size, " in is larger than the 6.5 by 9 in page"))
        }
      }
    }
    for (i in grep("^#\\| label: fig-", src)) {
      opts <- src[i:length(src)]
      opts <- opts[seq_len(match(FALSE, c(startsWith(opts, "#|"), FALSE)) - 1L)]
      if (!any(startsWith(opts, "#| fig-cap:"))) out <- c(out, paste0(label, ":", i, ": a fig- chunk with no fig-cap"))
    }
  }
  out
}

test_that("every shipped template meets the figure standard", {
  dir <- system.file("templates", package = "hvtiRtemplates")
  expect_true(nzchar(dir))
  # The scan must reach templates that draw figures, or a clean result proves nothing.
  expect_true(all(c("30_analyses/bc.qmd", "40_graphs/hp.qmd") %in%
                    list.files(dir, pattern = "[.]qmd$", recursive = TRUE)))
  expect_identical(figure_standard_scan(dir), character(0))
})

test_that("the scan catches each kind of violation", {
  dir <- withr::local_tempdir()
  writeLines(c("---", "format:", "  html:", "    toc: true", "---", "```{r}", "#| label: fig-x",
               "#| echo: false", "p + theme_minimal() + theme_hv_manuscript()", "```"),
             file.path(dir, "bad.qmd"))
  found <- figure_standard_scan(dir)
  expect_length(found, 4L)
  expect_match(found, "format block|ggplot2 theme|without base_size|no fig-cap", all = TRUE)
})

test_that("8 pt is allowed only on a page of small panels labeled directly", {
  dir <- withr::local_tempdir()
  writeLines(c("---", "format:", "  html:", "    fig-width: 6", "    fig-height: 4", "---", "```{r}",
               "page <- hvtiRtemplates:::.eda_direct_labels(p & theme_hv_manuscript(base_size = 8))",
               "q <- p + theme_hv_manuscript(base_size = 8)", "```"),
             file.path(dir, "eight.qmd"))
  found <- figure_standard_scan(dir)
  expect_identical(found, "eight.qmd:9: theme_hv_manuscript() without base_size = 12")
})

test_that("the scan catches a figure larger than the page, chunk option or saved size", {
  dir <- withr::local_tempdir()
  writeLines(c("---", "format:", "  html:", "    fig-width: 6", "    fig-height: 4", "---", "```{r}",
               "#| label: fig-wide", "#| fig-cap: \"Wide.\"", "#| fig-width: 9", "p + theme_hv_manuscript(base_size = 12)",
               "save_figure(p, \"tall\", width = 6, height = 24)", "```"),
             file.path(dir, "big.qmd"))
  expect_identical(figure_standard_scan(dir),
                   c("big.qmd:10: width: 9 in is larger than the 6.5 by 9 in page",
                     "big.qmd:12: height = 24 in is larger than the 6.5 by 9 in page"))
})

test_that("a save_figure() call is held to the page, as dc-eda's landscape pages were not", {
  dir <- withr::local_tempdir()
  # dc-eda's page save until 2026-10-15, word for word.
  writeLines(c("---", "format:", "  html:", "    fig-width: 6", "    fig-height: 4", "---", "```{r}",
               "    file <- save_figure(.page,",
               "                        sprintf(\"dc-eda-%s-page-%02d\", section, i), width = 11, height = 8.5, linked = TRUE)",
               "```"),
             file.path(dir, "eda.qmd"))
  expect_identical(figure_standard_scan(dir), c("eda.qmd:9: width = 11 in is larger than the 6.5 by 9 in page"))
})
