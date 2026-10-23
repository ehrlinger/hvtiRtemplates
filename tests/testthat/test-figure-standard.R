# The figure standard, dev/specs/2026-10-13-figure-standard-design.md: a single
# panel is saved at 6 by 4 in and drawn in the report at 9 by 6 (.report_size(),
# 2026-10-23), type is 12 pt in the hvtiPlotR theme (8 pt on a page of small
# panels, dc-eda's), and every figure has a numbered caption.
# Captions built by .child() at render time are not visible here; the static ones
# are, and they are most of them.

# Nothing is saved larger than the printed page, 6.5 by 9 in, nor drawn in the
# report larger than .report_size() of it, 9.75 by 13.5: a figure whose panel
# count follows the study is paged instead: .figure_pages() for the RF and nb
# figures, dc-eda's grid pages, dc-stddiff's 30 rows a page. The one exception
# is dc-tables' scatter-plot matrix, decided 2026-10-15 (the spec's rule 5):
# every cell pairs two variables, so it cannot be split across pages. It is
# matched by its whole save_figure() line, so no other figure in dc-tables, at
# any size, passes under it.
page_exceptions <- c(
  "10_descriptive/dc-tables.qmd" = paste0("save_figure(plot(cm) + theme_hv_manuscript(base_size = 12), ",
                                          "sub(\"[.]png$\", \"\", fname), width = 10, height = 10,")
)

figure_standard_scan <- function(templates) {
  out <- character(0)
  for (f in list.files(templates, pattern = "[.]qmd$", recursive = TRUE, full.names = TRUE)) {
    label <- substring(f, nchar(templates) + 2L)
    src <- readLines(f, warn = FALSE)
    # A theme named in a string, such as a stop() message, or in a comment is not a call.
    code <- sub("#.*$", "", gsub("\"[^\"]*\"", "\"\"", src))
    if (!any(src == "    fig-width: 9") || !any(src == "    fig-height: 6")) {
      out <- c(out, paste0(label, ": format block lacks fig-width: 9 and fig-height: 6"))
    }
    # ggplot2's own themes default to 11 pt, so naming one undoes the standard.
    for (i in grep("theme_(minimal|bw|gr[ae]y|classic|light|linedraw)\\(", code)) {
      out <- c(out, paste0(label, ":", i, ": a ggplot2 theme, not theme_hv_manuscript(base_size = 12)"))
    }
    for (i in grep("theme_hv_manuscript\\(", code)) {
      facet_page <- grepl("theme_hv_manuscript\\(base_size = 8[,)]", code[[i]]) &&
        grepl(".eda_page_panels(", code[[i]], fixed = TRUE)
      if (!grepl("theme_hv_manuscript\\(base_size = 12[,)]", code[[i]]) && !facet_page) {
        out <- c(out, paste0(label, ":", i, ": theme_hv_manuscript() without base_size = 12"))
      }
    }
    for (i in grep("^#\\| fig-(width|height): [0-9]|(width|height) = [0-9]", src)) {
      if (!is.na(page_exceptions[label]) && identical(trimws(src[[i]]), page_exceptions[[label]])) next
      sizes <- regmatches(src[[i]], gregexpr("(width|height)(: | = )[0-9.]+", src[[i]]))[[1]]
      for (size in sizes) {
        inches <- as.numeric(sub("^.*(: | = )", "", size))
        page <- if (startsWith(size, "width")) 6.5 else 9
        # A chunk option sizes the report's copy; `width =` the saved one.
        if (grepl(": ", size, fixed = TRUE)) {
          if (inches > .report_size(page)) {
            out <- c(out, paste0(label, ":", i, ": ", size, " in is larger than the report's 9.75 by 13.5 in"))
          }
        } else if (inches > page) {
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

test_that("8 pt is allowed only on a page of small panels", {
  dir <- withr::local_tempdir()
  writeLines(c("---", "format:", "  html:", "    fig-width: 9", "    fig-height: 6", "---", "```{r}",
               "page <- hvtiRtemplates:::.eda_page_panels(p & theme_hv_manuscript(base_size = 8))",
               "q <- p + theme_hv_manuscript(base_size = 8)", "```"),
             file.path(dir, "eight.qmd"))
  found <- figure_standard_scan(dir)
  expect_identical(found, "eight.qmd:9: theme_hv_manuscript() without base_size = 12")
})

test_that("the scan catches a figure larger than the page, chunk option or saved size", {
  dir <- withr::local_tempdir()
  writeLines(c("---", "format:", "  html:", "    fig-width: 9", "    fig-height: 6", "---", "```{r}",
               "#| label: fig-wide", "#| fig-cap: \"Wide.\"", "#| fig-width: 10", "p + theme_hv_manuscript(base_size = 12)",
               "save_figure(p, \"tall\", width = 6, height = 24)", "```"),
             file.path(dir, "big.qmd"))
  expect_identical(figure_standard_scan(dir),
                   c("big.qmd:10: width: 10 in is larger than the report's 9.75 by 13.5 in",
                     "big.qmd:12: height = 24 in is larger than the 6.5 by 9 in page"))
})

test_that("a save_figure() call is held to the page, as dc-eda's landscape pages were not", {
  dir <- withr::local_tempdir()
  # dc-eda's page save until 2026-10-15, word for word.
  writeLines(c("---", "format:", "  html:", "    fig-width: 9", "    fig-height: 6", "---", "```{r}",
               "    file <- save_figure(.page,",
               "                        sprintf(\"dc-eda-%s-page-%02d\", section, i), width = 11, height = 8.5, linked = TRUE)",
               "```"),
             file.path(dir, "eda.qmd"))
  expect_identical(figure_standard_scan(dir), c("eda.qmd:9: width = 11 in is larger than the 6.5 by 9 in page"))
})

test_that("the page exception covers dc-tables' scatter-plot matrix line and nothing else", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "10_descriptive"))
  writeLines(c("---", "format:", "  html:", "    fig-width: 9", "    fig-height: 6", "---", "```{r}",
               paste0("  ", page_exceptions[["10_descriptive/dc-tables.qmd"]]),
               "  save_figure(p, \"dc-tables-other\", width = 10, height = 10, linked = TRUE)", "```"),
             file.path(dir, "10_descriptive", "dc-tables.qmd"))
  expect_identical(figure_standard_scan(dir),
                   c("10_descriptive/dc-tables.qmd:9: width = 10 in is larger than the 6.5 by 9 in page",
                     "10_descriptive/dc-tables.qmd:9: height = 10 in is larger than the 6.5 by 9 in page"))
})

test_that("the report's size and the saved size are held to different limits", {
  dir <- withr::local_tempdir()
  # 9.75 in is the page's width at report size, so the chunk passes; the same
  # figure saved 9 in wide would not fit the printed page.
  writeLines(c("---", "format:", "  html:", "    fig-width: 9", "    fig-height: 6", "---", "```{r}",
               "#| label: fig-page", "#| fig-cap: \"Page.\"", "#| fig-width: 9.75", "#| fig-height: 13.5",
               "save_figure(p, \"page\", width = 9, height = 6)", "```"),
             file.path(dir, "split.qmd"))
  expect_identical(figure_standard_scan(dir), "split.qmd:12: width = 9 in is larger than the 6.5 by 9 in page")
})
