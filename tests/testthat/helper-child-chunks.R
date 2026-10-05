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
