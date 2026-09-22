template_by_name <- function(name) {
  templates <- template_list()
  hit <- which(templates$name == name)
  stopifnot(length(hit) == 1L)
  templates$file[[hit]]
}

provenance_chunk <- function(path) {
  source <- readLines(path, warn = FALSE)
  label <- grep("^#\\| label: provenance$", source)
  if (length(label) != 1L) return(character())
  open <- max(which(seq_along(source) < label & source == "```{r}"))
  close <- label + which(source[(label + 1L):length(source)] == "```")[[1L]]
  source[open:close]
}

test_that("every shipped template ends with one direct provenance chunk", {
  templates <- template_list()
  expect_equal(nrow(templates), 20L)

  for (path in templates$file) {
    source <- readLines(path, warn = FALSE)
    nonblank <- which(nzchar(trimws(source)))
    labels <- grep("^#\\| label: provenance$", source)
    chunk <- provenance_chunk(path)
    info <- basename(path)

    expect_equal(length(labels), 1L, info = info)
    expect_identical(source[[tail(nonblank, 1L)]], "```", info = info)
    expect_identical(tail(grep("^#\\| label: ", source, value = TRUE), 1L),
                     "#| label: provenance", info = info)
    expect_equal(length(grep("hvtiRutilities::record_provenance\\(", source)), 1L, info = info)
    expect_true(any(grepl("subject = SUBJECT", chunk, fixed = TRUE)), info = info)
    expect_true(any(grepl("type = TYPE", chunk, fixed = TRUE)), info = info)
  }
})

test_that("provenance paths come only from the recovered render input", {
  for (path in template_list()$file) {
    chunk <- provenance_chunk(path)
    info <- basename(path)
    expect_true(any(grepl("file_path_sans_ext(basename(.in))", chunk, fixed = TRUE)), info = info)
    expect_true(any(grepl("file.path(dirname(.in), paste0(.job_stem, \".html\"))", chunk, fixed = TRUE)),
                info = info)
    expect_true(any(grepl("is.null(.in)", chunk, fixed = TRUE)), info = info)
    expect_false(any(grepl("getwd()", chunk, fixed = TRUE)), info = info)
  }
})
