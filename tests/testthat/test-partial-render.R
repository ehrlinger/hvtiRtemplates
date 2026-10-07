# A part-built job renders with chunks skipped or the render stopped early, and
# says so; a final render refuses it, as it refuses an unresolved EDIT: marker.

partial_source <- c(
  "```{r}",
  "#| label: one",
  "#| skip: \"waiting on the corrected coding\"",
  "x <- 1",
  "```",
  "```{r}",
  "hvtiRtemplates::stop_here()",
  "```",
  "# stop_here() in a comment is not a stop",
  "#| skip in prose is not a skip either"
)

test_that("the partial-render points are read from the source, with their lines", {
  points <- .partial_points(partial_source)
  expect_identical(points$line, c(3L, 7L))
  expect_identical(points$kind, c("skip", "stop"))
  expect_identical(points$reason[[1L]], "waiting on the corrected coding")
  expect_identical(nrow(.partial_points(c("x <- 1", "# nothing here"))), 0L)
})

test_that("only live syntax counts: examples, plain blocks, body lines and eval: false do not", {
  # Each of these looks like a skip or a stop and is not one. Raised in review
  # on #243: a false point marks a draft PARTIAL and refuses a final render.
  dead <- c(
    "````",                                   # a documentation example, as the tutorial shows one
    "```{r}",
    "#| skip: \"example only\"",
    "hvtiRtemplates::stop_here()",
    "```",
    "````",
    "```r",                                   # a plain, non-executed code block
    "stop_here()",
    "```",
    "```{r}",
    "#| label: body",
    "x <- 1",
    "#| skip: \"a comment in the body, not an option\"",
    "```",
    "```{r}",
    "#| eval: false",
    "stop_here()",                            # never runs
    "```"
  )
  expect_identical(nrow(.partial_points(dead)), 0L)
  # The same file with one live point of each kind finds exactly those two.
  live <- c(dead, "```{r}", "#| label: real", "#| skip: \"real\"", "y <- 2", "```",
            "```{r, echo = FALSE}", "stop_here()", "```")
  points <- .partial_points(live)
  expect_identical(points$kind, c("skip", "stop"))
  expect_identical(points$line, c(length(dead) + 3L, length(dead) + 7L))
})

test_that("a skip must give its reason as a quoted string", {
  for (line in c("#| skip: true", "#| skip:", "#| skip: \"\"", "#| skip: waiting")) {
    expect_error(.partial_points(c("```{r}", line, "```")), "needs its reason", info = line)
  }
  expect_identical(.partial_points(c("```{r}", "#| skip: 'single quotes are fine'", "```"))$reason,
                   "single quotes are fine")
})

test_that("a draft lists every point in a callout; a strict render stops", {
  f <- withr::local_tempfile(fileext = ".qmd")
  writeLines(partial_source, f)
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "")
  out <- NULL
  expect_warning(utils::capture.output(out <- .guard_partial(f)), "rendered in part \\(2 point")
  expect_match(out, "PARTIAL", fixed = TRUE)
  expect_match(out, "line 3: chunk skipped, waiting on the corrected coding", fixed = TRUE)
  expect_match(out, "line 7: the render stops here", fixed = TRUE)
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  expect_error(.guard_partial(f), "HVTI_TEMPLATE_STRICT is set")
})

test_that("a job with no partial-render point prints nothing", {
  f <- withr::local_tempfile(fileext = ".qmd")
  writeLines(c("```{r}", "x <- 1", "```"), f)
  expect_silent(out <- .guard_partial(f))
  expect_identical(out, character())
  expect_identical(.guard_partial(NULL), character())
})

test_that("stop_here() does nothing outside a render", {
  expect_null(stop_here())
})

test_that("every template carries the guard-partial chunk, just after the EDIT: guard", {
  for (path in template_list()$file) {
    lines <- readLines(path, warn = FALSE)
    edits <- match("#| label: guard-edits", lines)
    partial <- match("#| label: guard-partial", lines)
    expect_false(is.na(partial), info = basename(path))
    # Nothing but the guard-edits chunk's own body sits between the two.
    between <- lines[seq.int(edits, partial)]
    expect_identical(sum(between == "```{r}"), 1L, info = basename(path))
    expect_true(any(grepl(".guard_partial(knitr::current_input())", lines, fixed = TRUE)),
                info = basename(path))
    # The template's own text must not trip the reader.
    expect_identical(nrow(.partial_points(lines)), 0L, info = basename(path))
  }
})

test_that("a part-built job renders what is done, and a final render refuses it", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  s <- scaffold_gfup(list("^ANALYSIS_SET <- " = "ANALYSIS_SET <- NULL", "^ORIGIN_YEAR <- " = "ORIGIN_YEAR <- 1980"))
  lines <- readLines(s$job, warn = FALSE)
  # Skip the window table; stop before the event-coding section. The figure
  # sits between the two, so it shows that what is above a stop still renders.
  at <- match("#| label: tbl-window", lines)
  lines <- append(lines, "#| skip: \"waiting on the corrected coding\"", after = at)
  at <- match("## Event-coding consistency", lines)
  lines <- append(lines, c("```{r}", "hvtiRtemplates::stop_here()", "```", ""), after = at - 1L)
  writeLines(lines, s$job)

  quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
  html <- paste(readLines(sub("[.]qmd$", ".html", s$job), warn = FALSE), collapse = "\n")
  expect_match(html, "PARTIAL", fixed = TRUE)
  expect_match(html, "chunk skipped, waiting on the corrected coding", fixed = TRUE)
  expect_no_match(html, "Table [0-9]+: Operation years and the close date")
  expect_no_match(html, "Event-coding consistency", fixed = TRUE)
  expect_gt(length(list.files(file.path(s$root, "graphs"), pattern = "^dc-gfup-.*[.]png$", recursive = TRUE)), 0L)
  # The stopped render still carries provenance, and it says the report is partial.
  sidecar <- sub("[.]qmd$", ".provenance.json", s$job)
  expect_true(file.exists(sidecar))
  prov <- jsonlite::fromJSON(sidecar, simplifyVector = FALSE)
  partial <- if (is.null(prov$extra$partial)) prov$partial else prov$extra$partial
  kinds <- vapply(partial, function(p) p$kind, character(1L))
  expect_identical(kinds, c("skip", "stop"))

  # Final: clear the EDIT: markers so the refusal under test is the partial one.
  writeLines(gsub(paste0("ED", "IT:"), "Set:", readLines(s$job, warn = FALSE), fixed = TRUE), s$job)
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  err <- tryCatch({
    utils::capture.output(quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = FALSE),
                          type = "message")
    NULL
  }, error = function(e) conditionMessage(e))
  expect_false(is.null(err))
})

test_that("a stop that cannot run is not listed", {
  # A stop_here() in a skipped chunk, or in one that does not evaluate, is never
  # reached, so listing it would misstate what the report leaves out.
  src <- c("```{r}", "#| skip: \"later\"", "hvtiRtemplates::stop_here()", "```",
           "```{r}", "#| eval: !expr FALSE", "stop_here()", "```")
  points <- .partial_points(src)
  expect_identical(points$kind, "skip")
  expect_identical(points$line, 2L)
  # Every false spelling knitr's YAML parser accepts, and nothing it does not.
  # Raised by Codex on #257 for `off`.
  for (v in c("false", "FALSE", "no", "off", "Off", "n", "!expr FALSE", "!expr F")) {
    expect_identical(nrow(.partial_points(c("```{r}", paste("#| eval:", v), "stop_here()", "```"))), 0L, info = v)
  }
  # Read as knitr reads them, these run, so the stop stays listed: a bare F is the
  # string "F" to the parser, and a dynamic !expr may well be TRUE.
  for (v in c("true", "yes", "on", "F", "!expr figure_drawn")) {
    expect_identical(.partial_points(c("```{r}", paste("#| eval:", v), "stop_here()", "```"))$kind, "stop", info = v)
  }
})

test_that("the guard leaves no global option set and its hook ignores other documents", {
  f <- withr::local_tempfile(fileext = ".qmd")
  writeLines(partial_source, f)
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "")
  before <- options()
  suppressWarnings(.guard_partial(f))
  expect_identical(options(), before)
  expect_length(hvtiRtemplates:::.partial_state$points, 2L)
  # Outside the job that set it, the skip hook hands the options back unchanged.
  hook <- knitr::opts_hooks$get("skip")
  opts <- list(label = "other", skip = TRUE, eval = TRUE, include = TRUE)
  expect_identical(hook(opts), opts)
})
