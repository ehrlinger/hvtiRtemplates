# Template code emits some tables and figures as child chunks with
# knitr::knit_child(), so Quarto can number each one. Run outside a render,
# knitr gives every child a graphics device and a figure folder in the working
# directory, and keeps one registry of chunk labels for the whole session, so a
# second call that emits the same label would be refused. A test that evaluates
# such a chunk calls this first: it works in a scratch directory and allows the
# repeated labels.
local_child_chunks <- function(env = parent.frame()) {
  withr::local_dir(withr::local_tempdir(.local_envir = env), .local_envir = env)
  withr::local_options(knitr.duplicate.label = "allow", .local_envir = env)
}

# A ggsave() stand-in for tests that skip the drawing: it writes a 1 x 1 PNG, as the real
# one writes a file, so a saved figure is not taken for a page that drew nothing and a
# report chunk can still embed it. The caller's device is put back.
stub_ggsave <- function(filename, plot, ...) {
  before <- grDevices::dev.cur()
  grDevices::png(filename, width = 1, height = 1)
  grid::grid.newpage()
  grDevices::dev.off()
  if (before > 1L) grDevices::dev.set(before)
  invisible(filename)
}
