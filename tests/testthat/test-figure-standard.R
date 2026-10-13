# The figure standard, dev/specs/2026-10-13-figure-standard-design.md: a single
# panel is 6 by 4 in, type is 12 pt in the hvtiPlotR theme, and every figure has
# a numbered caption. Captions built by .child() at render time are not visible
# here; the static ones are, and they are most of them.

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
      if (!grepl("theme_hv_manuscript\\(base_size = 12[,)]", code[[i]])) {
        out <- c(out, paste0(label, ":", i, ": theme_hv_manuscript() without base_size = 12"))
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
