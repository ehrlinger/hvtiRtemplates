# Run sheets: the generated "before you run" page each template gets in the
# gallery. Design: dev/specs/2026-10-26-run-sheets-design.md.

test_that(".edit_marker_lines() finds the token and cuts each line as the draft banner does", {
  tok <- paste0("ED", "IT", ":")
  src <- c("x <- 1", paste("  #", tok, "set x"), paste("#", tok, strrep("a", 200)))
  m <- .edit_marker_lines(src)
  expect_identical(m$line, c(2L, 3L))
  expect_identical(m$text[1L], paste("#", tok, "set x"))
  expect_identical(nchar(m$text[2L]), 96L)
  expect_identical(nrow(.edit_marker_lines("nothing here")), 0L)
})

# A template written to a temporary file, in a numbered folder as the shipped
# ones are. `.fx()` puts a front matter above the lines given.
.sheet_fixture <- function(body, name = "zz-demo", env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(dir, "30_analyses"))
  f <- file.path(dir, "30_analyses", paste0(name, ".qmd"))
  writeLines(body, f)
  f
}
.fx <- function(...) c("---", "title: demo", "---", "", ...)

test_that("calls are found in default arguments, through ::: and across lines", {
  f <- .sheet_fixture(.fx(
    "```{r}", "#| label: setup", "x <- 1", "```", "", "## Upstream", "",
    "```{r}",
    paste0("reader <- function(p = 'a', read = function(q) hvtiRtemplates:::.read_handoff(q, 'SID fit', cfg, ",
           "'the sid job')) NULL"),
    ".fit <- hvtiRtemplates:::.read_handoff(",
    "  set_path(\"estimates\", \"rfs.rds\"), \"forest\", cfg, \"the rfs-fit job\"",
    ")",
    "# .read_handoff(set_path('estimates', 'commented.rds'), 'x', cfg, 'nobody')",
    "```"
  ))
  facts <- .run_sheet_facts(f)
  rh <- Filter(function(c) identical(c$fn, ".read_handoff"), facts$calls)
  expect_length(rh, 2L)
  expect_setequal(vapply(rh, function(c) as.character(c$call[[5L]]), ""), c("the sid job", "the rfs-fit job"))
  expect_identical(facts$layout$headings$text, "Upstream")
  expect_identical(facts$name, "zz-demo")
  expect_identical(facts$folder, "30_analyses")
})

test_that("a hand-off path bound once at top level resolves; one bound twice does not", {
  f <- .sheet_fixture(.fx(
    "```{r}",
    "MODEL_PATH <- set_path(\"estimates\", \"lm-binary.rds\")",
    "TWICE <- set_path(\"estimates\", \"a.rds\")",
    "TWICE <- set_path(\"estimates\", \"b.rds\")",
    "```"
  ))
  b <- .run_sheet_facts(f)$bindings
  expect_identical(.estimates_file(quote(MODEL_PATH), b), "lm-binary.rds")
  expect_identical(.estimates_file(quote(TWICE), b), NA_character_)
  expect_identical(.estimates_file(quote(set_path("estimates", "c.rds")), b), "c.rds")
  expect_identical(.estimates_file(quote(set_path("graphs", "c.rds")), b), NA_character_)
  expect_identical(.estimates_file(quote(OTHER), b), NA_character_)
})

test_that("headings inside a chunk are R comments, not sections", {
  f <- .sheet_fixture(.fx("## One", "```{r}", "## not a heading", "```", "### Two"))
  h <- .run_sheet_facts(f)$layout$headings
  expect_identical(h$text, c("One", "Two"))
  expect_identical(h$level, c(2L, 3L))
})

test_that(".call_name() reads bare and namespaced calls", {
  expect_identical(.call_name(quote(f(x))), "f")
  expect_identical(.call_name(quote(pkg::f(x))), "f")
  expect_identical(.call_name(quote(pkg:::f(x))), "f")
  expect_identical(.call_name(quote(g(1)(x))), NA_character_)
})

test_that("every shipped template parses, and the walk agrees with a text scan", {
  files <- list.files(.templates_dir(), "[.]qmd$", recursive = TRUE, full.names = TRUE)
  expect_gt(length(files), 40L)
  for (f in files) {
    facts <- .run_sheet_facts(f)
    code <- facts$src[facts$layout$chunk > 0L & !grepl("^\\s*#", facts$src)]
    fns <- vapply(facts$calls, `[[`, "", "fn")
    for (fn in c(".read_handoff", ".read_bootstrap_artifact", "cache_fit", "guard_long_fit", "guard_memory")) {
      in_text <- any(grepl(paste0(fn, "("), code, fixed = TRUE))
      expect_identical(fn %in% fns, in_text, info = paste(basename(f), fn))
    }
  }
})

# Every shipped template's facts, named by template. Read once per file.
.all_facts <- local({
  cache <- NULL
  function() {
    if (is.null(cache)) {
      files <- list.files(.templates_dir(), "[.]qmd$", recursive = TRUE, full.names = TRUE)
      cache <<- stats::setNames(lapply(files, .run_sheet_facts), sub("[.]qmd$", "", basename(files)))
    }
    cache
  }
})

test_that("the hand-off graph on the shipped templates", {
  g <- .handoff_graph(.all_facts())
  edge <- function(p, c) any(g$producer == p & g$consumer == c, na.rm = TRUE)
  expect_true(edge("ac", "hp"))
  expect_true(edge("hz", "hp"))
  expect_true(edge("hz", "hm"))
  expect_true(edge("hm", "hs-setup"))
  expect_true(edge("rfs-fit", "rfs-explain"))
  expect_true(edge("sid-fit", "sid-clusters"))
  expect_true(edge("vp-fit", "vp-individual"))
  expect_true(edge("lm-binary", "lp-mirror"))
  expect_true(edge("sid-clusters", "vt-explain"))
  expect_false(edge("hm", "hp"))
  expect_false(any(g$producer == g$consumer, na.rm = TRUE))
  # Which consumers take their producers from the catalog, because the
  # template does not name the file. A new one is a decision, not an accident.
  expect_setequal(unique(g$consumer[g$route == "catalog"]),
                  c("hs-concordance", "lm-checkpred", "lp-mirror", "vt-fit", "vt-explain"))
  # The one literal read no template writes: a companion runner does.
  expect_identical(g$consumer[g$route == "none"], "hm")
  expect_identical(g$rebuild[g$route == "none"], "the companion hm selection runner")
})

test_that("a non-literal read with no catalog upstream is an error naming the template", {
  f <- .sheet_fixture(.fx("```{r}", "x <- .read_handoff(PATH, 'r', cfg, 'the other job')", "```"), "zz-orphan")
  cat <- data.frame(prefix = "zz", qualifier = "orphan", stringsAsFactors = FALSE)
  cat$upstream <- list(character())
  expect_error(.handoff_graph(list(`zz-orphan` = .run_sheet_facts(f)), cat), "zz-orphan.*upstream")
})
