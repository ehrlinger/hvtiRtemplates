# Every figure and table a template shows is numbered, and no template teaches
# a retired palette. The house rules are in inst/templates/README.md
# ("Figures, tables and color"). Quarto numbers a figure only when its chunk
# label starts with `fig-` and the chunk has `fig-cap`, and a table only with a
# `tbl-` label and `tbl-cap`; a `knitr::kable(caption = )` caption prints
# without a number. A chunk that calls a table or figure function without
# showing one (a chunk that only defines helpers) says so with a comment
# `# unnumbered: <reason>`.

table_calls <- c("kable", "kbl", "gt", "flextable", "hv_tbl_summary",
                 "hv_correlation_table", "hv_man_table")
# Helpers whose value is a table that prints when the call stands alone on a
# line (or inside print()); an assignment such as `bag <- boot_bag(...)` shows
# nothing, so only a bare call counts. boot_validate() is absent on purpose: it
# returns invisible(TRUE) and exists for the error it raises.
printed_table_calls <- c("proc_contents", "proc_means", "proc_freq", "boot_provenance", "boot_health",
                         "boot_seeds", "boot_frequencies", "boot_concepts", "boot_dropped",
                         "boot_shortfall", "boot_clusters", "boot_select", "boot_chunk_files")
figure_calls <- c("ggplot", "plot", "hv_trends", "hv_followup", "hv_followup_panels",
                  "hv_spaghetti", "hv_eda_pages", "hv_correlation_matrix")
retired_palettes <- paste0("[\"'](Set1|Set2|Set3|Dark2|Paired|Accent|Pastel1|Pastel2|RdYlGn)[\"']",
                           "|scale_(colou?r|fill)_(lancet|npg|jama|nejm)\\(")

# R chunks of one template: label, options, and code without option lines.
template_chunks <- function(path) {
  src <- readLines(path, warn = FALSE)
  open <- grep("^```\\{r[^}]*\\}\\s*$", src)
  close <- grep("^```\\s*$", src)
  lapply(open, function(o) {
    end <- close[close > o][1L]
    body <- if (end > o + 1L) src[(o + 1L):(end - 1L)] else character()
    is_opt <- grepl("^#\\|", body)
    opts <- sub("^#\\|\\s*", "", body[is_opt])
    keys <- sub(":.*$", "", opts)
    vals <- trimws(sub("^[^:]*:", "", opts))
    list(line = o, opts = stats::setNames(vals, keys), code = body[!is_opt])
  })
}

calls_any <- function(code, fns) {
  any(grepl(paste0("(^|[^A-Za-z0-9_.])(", paste(fns, collapse = "|"), ")\\s*\\("), code))
}

prints_any <- function(code, fns) {
  fn <- paste(fns, collapse = "|")
  any(grepl(paste0("^\\s*((", fn, ")|print\\(\\s*(", fn, "))\\s*\\("), code))
}

shows_output <- function(ch) {
  !identical(unname(ch$opts["eval"]), "false") && !identical(unname(ch$opts["include"]), "false")
}

test_that("every figure and table a template shows is numbered", {
  tl <- template_list()
  for (i in seq_len(nrow(tl))) {
    for (ch in template_chunks(tl$file[[i]])) {
      if (!shows_output(ch) || any(grepl("^\\s*# unnumbered: \\S", ch$code))) next
      where <- sprintf("%s, chunk at line %d", tl$name[[i]], ch$line)
      label <- if ("label" %in% names(ch$opts)) ch$opts[["label"]] else ""
      is_tbl <- calls_any(ch$code, table_calls) || prints_any(ch$code, printed_table_calls)
      is_fig <- calls_any(ch$code, figure_calls) ||
        any(c("fig-cap", "fig-width", "fig-height") %in% names(ch$opts))
      expect_false(is_tbl && is_fig, label = paste(where, "mixes a table and a figure; split it"))
      if (is_tbl && !is_fig) {
        expect_true(startsWith(label, "tbl-") && "tbl-cap" %in% names(ch$opts),
                    label = paste(where, "shows a table without a tbl- label and tbl-cap"))
        expect_false(any(grepl("caption\\s*=", ch$code)),
                     label = paste(where, "puts the table caption in caption =, not tbl-cap"))
      }
      if (is_fig && !is_tbl) {
        expect_true(startsWith(label, "fig-") && "fig-cap" %in% names(ch$opts),
                    label = paste(where, "shows a figure without a fig- label and fig-cap"))
      }
    }
  }
})

test_that("no template teaches a retired palette", {
  tl <- template_list()
  for (i in seq_len(nrow(tl))) {
    txt <- readLines(tl$file[[i]], warn = FALSE)
    expect_false(any(grepl(retired_palettes, txt)),
                 label = paste("template", tl$name[[i]], "uses a retired palette; use hvtiPlotR::hv_palette()"))
  }
})

test_that("the numbering rule catches what it should", {
  tmp <- tempfile(fileext = ".qmd")
  on.exit(unlink(tmp))
  writeLines(c("```{r}", "#| label: counts", "knitr::kable(x, caption = \"Counts\")", "```",
               "```{r}", "#| label: fig-ok", "#| fig-cap: \"A plot.\"", "plot(1)", "```",
               "```{r}", "#| label: helpers", "# unnumbered: defines helpers only",
               "show <- function(d) knitr::kable(d)", "```"), tmp)
  chunks <- template_chunks(tmp)
  expect_length(chunks, 3L)
  expect_true(calls_any(chunks[[1]]$code, table_calls))
  expect_false(startsWith(chunks[[1]]$opts[["label"]], "tbl-"))
  expect_true(calls_any(chunks[[2]]$code, figure_calls))
  expect_true(any(grepl("^\\s*# unnumbered: \\S", chunks[[3]]$code)))
  expect_false(calls_any("hv_plot_helper(x)", figure_calls))
  expect_true(grepl(retired_palettes, "scale_color_brewer(palette = \"Set1\")"))
  expect_true(grepl(retired_palettes, "scale_color_brewer(palette = 'Dark2')"))
  expect_true(prints_any("proc_means(d, vars = v)", printed_table_calls))
  expect_true(prints_any("  print(boot_health(bag))", printed_table_calls))
  expect_false(prints_any("bag <- boot_bag(files)", printed_table_calls))
  expect_false(prints_any("h <- boot_health(bag)", printed_table_calls))
})
