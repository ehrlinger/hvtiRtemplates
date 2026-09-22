template_by_name <- function(name) {
  templates <- template_list()
  hit <- which(templates$name == name)
  stopifnot(length(hit) == 1L)
  templates$file[[hit]]
}

provenance_chunk_end <- function(source, label) {
  if (length(label) != 1L) return(integer())
  after_label <- (label + 1L):length(source)
  fence <- which(source[after_label] == "```")
  if (!length(fence)) return(integer())
  label + fence[[1L]]
}

provenance_chunk <- function(path) {
  source <- readLines(path, warn = FALSE)
  label <- grep("^#\\| label: provenance$", source)
  if (length(label) != 1L) return(character())
  open <- max(which(seq_along(source) < label & source == "```{r}"))
  close <- provenance_chunk_end(source, label)
  if (!length(close)) return(character())
  final <- tail(which(nzchar(trimws(source))), 1L)
  if (!identical(close, final)) {
    stop("The provenance chunk must end at the final nonblank line.", call. = FALSE)
  }
  source[open:close]
}

provenance_expressions <- function(path) {
  chunk <- provenance_chunk(path)
  parse(text = chunk[-c(1L, length(chunk))])
}

is_record_provenance_call <- function(expr) {
  if (!is.call(expr)) return(FALSE)
  fun <- expr[[1L]]
  direct <- is.call(fun) &&
    identical(as.character(fun[[1L]]), "::") &&
    identical(as.character(fun[[2L]]), "hvtiRutilities") &&
    identical(as.character(fun[[3L]]), "record_provenance")
  direct
}

test_that("provenance_chunk rejects an unlabeled later chunk", {
  path <- tempfile(fileext = ".qmd")
  writeLines(c(
    "```{r}",
    "#| label: provenance",
    "hvtiRutilities::record_provenance(.output)",
    "```",
    "```{r}",
    "invisible(NULL)",
    "```"
  ), path)

  expect_error(provenance_chunk(path), "final nonblank")
})

test_that("provenance calls outside the final chunk do not satisfy the contract", {
  path <- tempfile(fileext = ".qmd")
  writeLines(c(
    "```{r}",
    "hvtiRutilities::record_provenance(.output)",
    "```",
    "# hvtiRutilities::record_provenance(.output)",
    "```{r}",
    "#| label: provenance",
    "invisible(NULL)",
    "```"
  ), path)

  expressions <- provenance_expressions(path)
  expect_false(any(vapply(expressions, is_record_provenance_call, logical(1L))))
})

test_that("nested provenance calls do not satisfy the contract", {
  cases <- c(
    if_false = "if (FALSE) hvtiRutilities::record_provenance(.output)",
    quoted = "quote(hvtiRutilities::record_provenance(.output))",
    braced = "{ hvtiRutilities::record_provenance(.output); invisible(NULL) }"
  )

  for (name in names(cases)) {
    path <- tempfile(fileext = ".qmd")
    writeLines(c(
      "```{r}",
      "#| label: provenance",
      cases[[name]],
      "```"
    ), path)

    expressions <- provenance_expressions(path)
    expect_false(any(vapply(expressions, is_record_provenance_call, logical(1L))), info = name)
  }
})

test_that("every shipped template ends with one direct provenance chunk", {
  templates <- template_list()
  expect_equal(nrow(templates), 20L)

  for (path in templates$file) {
    source <- readLines(path, warn = FALSE)
    nonblank <- which(nzchar(trimws(source)))
    labels <- grep("^#\\| label: provenance$", source)
    chunk <- provenance_chunk(path)
    chunk_end <- provenance_chunk_end(source, labels)
    expressions <- provenance_expressions(path)
    info <- basename(path)

    expect_equal(length(labels), 1L, info = info)
    expect_identical(chunk_end, tail(nonblank, 1L), info = info)
    expect_identical(tail(grep("^#\\| label: ", source, value = TRUE), 1L),
                     "#| label: provenance", info = info)
    expect_equal(sum(vapply(expressions, is_record_provenance_call, logical(1L))), 1L, info = info)
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
