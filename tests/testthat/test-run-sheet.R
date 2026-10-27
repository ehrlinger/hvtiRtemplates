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

test_that("a plain ``` block hides its lines from the headings and is not a chunk", {
  f <- .sheet_fixture(.fx("## One", "```", "## shell comment", "x <- 1", "```", "```{r}", "y <- 2", "```", "## Two"))
  facts <- .run_sheet_facts(f)
  expect_identical(facts$layout$headings$text, c("One", "Two"))
  expect_identical(vapply(facts$calls, `[[`, "", "fn"), "<-")
})

# A catalog with no rows, for a graph whose reads all name their file.
.no_catalog <- function() {
  cat <- data.frame(prefix = character(), qualifier = character())
  cat$upstream <- list()
  cat
}

test_that("a ### with no ## above it opens the outline rather than nesting", {
  f <- .sheet_fixture(.fx("### Lead", "", "## Main"))
  facts <- .run_sheet_facts(f)
  out <- .sheet_outline(facts, .handoff_graph(list(facts), .no_catalog()))
  expect_identical(substr(out, 1L, 3L), c("1. ", "1. "))
})

test_that("a runner's file read in two chunks is one prerequisite", {
  read <- "x <- .read_handoff(set_path('estimates', 'runs.rds'), 'runs', cfg, 'the companion runner')"
  f <- .sheet_fixture(.fx("```{r}", read, "```", "", "## Again", "", "```{r}", read, "```"))
  facts <- .run_sheet_facts(f)
  graph <- .handoff_graph(list(facts), .no_catalog())
  expect_identical(nrow(graph), 2L)
  pre <- .sheet_prerequisites(facts, graph, data.frame(package = character(), floor = character()), .no_catalog())
  expect_identical(sum(grepl("Run the companion runner first", pre, fixed = TRUE)), 1L)
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
  expect_true(edge("lm-propensity_binary", "lp-mirror"))
  expect_false(edge("lm-binary", "lp-mirror"))
  expect_true(edge("lm-binary", "lm-checkpred"))
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
  # The reads a default run does not make: vt-fit's screen and SID distance (VP_SET and
  # SID_SET are NULL), vt-explain's SID strata (STRATIFY is NULL) and hm's selection runner
  # (the selection reports "not run" without it). Every other read is required.
  opt <- g[g$optional, , drop = FALSE]
  expect_setequal(paste(opt$consumer, opt$route), c("vt-fit catalog", "vt-explain catalog", "hm none"))
  expect_false(any(g$optional & g$consumer == "vt-explain" & g$producer == "vt-fit", na.rm = TRUE))
  expect_false(any(g$optional & g$consumer == "hm" & g$producer == "hz", na.rm = TRUE))
})

test_that("a read inside an if or a function is optional, and one at top level is not", {
  f <- .sheet_fixture(.fx(
    "```{r}",
    "a <- .read_handoff(set_path('estimates', 'a.rds'), 'a', cfg, 'x')",
    "if (!is.null(B_SET)) b <- .read_handoff(set_path('estimates', 'b.rds'), 'b', cfg, 'x') else b <- NULL",
    "reader <- function(p, read = function(q) .read_handoff(set_path('estimates', 'c.rds'), 'c', cfg, 'x')) read(p)",
    "```"
  ))
  rh <- Filter(function(e) identical(e$fn, ".read_handoff"), .run_sheet_facts(f)$calls)
  expect_identical(vapply(rh, `[[`, NA, "optional"), c(FALSE, TRUE, TRUE))
})

test_that("the shipped sheets say an optional read is optional, and never as a step to run first", {
  sheets <- .run_sheets()
  md <- function(n) sheets[[which(vapply(sheets, `[[`, "", "name") == n)]]$markdown
  expect_match(md("vt-fit"), "**Optional: the jobs it can read from.**", fixed = TRUE)
  expect_no_match(md("vt-fit"), "it reads from.**", fixed = TRUE)
  expect_match(md("vt-explain"), "Render **vt-fit** first", fixed = TRUE)
  expect_match(md("vt-explain"),
               "**Optional: the job it can read from.** Some of its choices read a saved result from **sid-clusters**", fixed = TRUE)
  expect_no_match(md("vt-explain"), "Render **sid-clusters** first", fixed = TRUE)
  expect_match(md("hm"), "**Optional: the companion hm selection runner.**", fixed = TRUE)
  expect_no_match(md("hm"), "Run the companion hm selection runner first", fixed = TRUE)
  expect_match(md("hm"), "Render **hz** first", fixed = TRUE)
})

test_that("a non-literal read with no catalog upstream is an error naming the template", {
  f <- .sheet_fixture(.fx("```{r}", "x <- .read_handoff(PATH, 'r', cfg, 'the other job')", "```"), "zz-orphan")
  cat <- data.frame(prefix = "zz", qualifier = "orphan", stringsAsFactors = FALSE)
  cat$upstream <- list(character())
  expect_error(.handoff_graph(list(`zz-orphan` = .run_sheet_facts(f)), cat), "zz-orphan.*upstream")
})

# ---- The wording ----------------------------------------------------------------
# A small study of fixture templates, one per variant a sheet words differently,
# and a catalog for them. Snapshots are taken of these, never of a shipped
# template, so editing a template does not churn them.
.fixture_templates <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(dir, "30_analyses"))
  tok <- paste0("ED", "IT", ":")
  setup <- function(...) {
    c("```{r}", "#| label: setup", "library(stats)", "if (packageVersion(\"stats\") < \"4.0.0\") stop(\"old\")", ...,
      "```", "")
  }
  put <- function(name, ...) writeLines(.fx(...), file.path(dir, "30_analyses", paste0(name, ".qmd")))
  put("zz-fit",
      setup(".job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE, envir = environment())"),
      paste("<!--", tok, "name the job this replaces. -->"), "",
      "## Study choices", "", "```{r}", paste("#", tok, "the dataset."), "DATASET <- \"built\"",
      paste("#", tok, "the seed."), "SEED <- 1", "```", "",
      "## Fit", "", "```{r}",
      "hvtiRtemplates::guard_long_fit(\"zz-fit\", dir = CACHE_DIR, why = \"it takes hours at study size\", refit = REFIT)",
      "hvtiRtemplates::guard_memory(.code)",
      "fit <- cache_fit(\"zz-fit\", .code, seed = SEED, dir = CACHE_DIR, refit = REFIT)",
      "d <- hvtiRtemplates::read_job_data(cfg, DATASET)", "```", "",
      "## Save", "", "```{r}", "saveRDS(fit, set_path(\"estimates\", \"zz.rds\"))", "```")
  put("zz-explain",
      setup(),
      "## Study choices", "", "```{r}", paste("#", tok, "the variables."), "VARS <- NULL", "```", "",
      "## Upstream", "", "```{r}",
      ".fit <- hvtiRtemplates:::.read_handoff(set_path(\"estimates\", \"zz.rds\"), \"fit\", cfg, \"the zz-fit job\")",
      "```", "", "### What the fit says", "", "Prose.")
  put("zz-build",
      setup(".job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE, envir = environment(), box_data = FALSE)"),
      "```{r}", paste("#", tok, "the snapshot."), "SNAPSHOT <- \"x\"", "```")
  put("zz-boot",
      setup(),
      "## Study choices", "", "```{r}", "DATASET <- NULL", "```", "",
      "## The screen", "", "```{r}",
      "bag <- hvtiRtemplates:::.read_bootstrap_artifact(BAG, \"bag\", cfg)",
      "sel <- hvtiRtemplates:::.read_handoff(MODEL_PATH, \"model\", cfg, REBUILD)",
      "runs <- hvtiRtemplates:::.read_handoff(set_path(\"estimates\", \"runs.rds\"), \"runs\", cfg, \"the companion runner\")",
      "```")
  dir
}

.fixture_catalog <- function() {
  cat <- data.frame(prefix = "zz", qualifier = c("fit", "explain", "build", "boot"),
                    name = c("Demo: fit", "Demo: explain", "Demo: build", "Demo: boot"),
                    description = c("Fits the demo.", "Explains the demo fit.", "Builds the demo data.", "Screens the demo."),
                    deprecation_note = c(NA, NA, NA, "Use zz-fit instead."), stringsAsFactors = FALSE)
  cat$upstream <- list(character(), character(), character(), "zz-fit")
  cat
}

.fixture_sheets <- function(env = parent.frame()) {
  s <- .run_sheets(.fixture_templates(env), catalog = .fixture_catalog())
  stats::setNames(s, vapply(s, `[[`, "", "name"))
}

test_that("a guarded, cached fit that another template reads", {
  expect_snapshot(cat(.fixture_sheets()[["zz-fit"]]$markdown))
})

test_that("a template that reads another's hand-off, with a ### section", {
  expect_snapshot(cat(.fixture_sheets()[["zz-explain"]]$markdown))
})

test_that("a template that builds its dataset and has no sections", {
  expect_snapshot(cat(.fixture_sheets()[["zz-build"]]$markdown))
})

test_that("a deprecated template with a runner, a catalog-route read and a runner's file", {
  expect_snapshot(cat(.fixture_sheets()[["zz-boot"]]$markdown))
})

test_that("every shipped template's sheet has its sections, markers, packages and headings", {
  facts <- .all_facts()
  g <- .handoff_graph(facts)
  cat <- template_catalog()
  for (f in facts) {
    md <- .run_sheet_md(f, g, cat)
    info <- f$name
    for (s in c("## What it does", "## Prerequisites", "## Outline", "## Run it")) expect_true(s %in% md, info = info)
    expect_identical("## Where to go next" %in% md, f$name %in% g$producer, info = info)
    counts <- as.integer(sub(" choices? marked.*$", "", regmatches(md, regexpr("[0-9]+ choices? marked", md))))
    expect_identical(sum(counts), nrow(f$markers), info = info)
    for (p in .template_packages(f$file)$package) expect_true(any(grepl(paste0("`", p, "`"), md, fixed = TRUE)), info = info)
    outline <- md[grepl("^(1\\.|   -) \\*\\*", md)]
    titles <- sub("^(1\\.|   -) \\*\\*(.*?)\\*\\*.*$", "\\2", outline)
    titles <- setdiff(titles, c("Above the first section", "The whole job"))
    expect_identical(titles, f$layout$headings$text, info = info)
  }
})

test_that("a guarded template is run in the background, and others are rendered", {
  s <- .fixture_sheets()
  expect_match(s[["zz-fit"]]$markdown, "hvti run 30_analyses/zz.fit.<subject>.<type>.qmd", fixed = TRUE)
  expect_no_match(s[["zz-explain"]]$markdown, "hvti run", fixed = TRUE)
})

test_that(".md_inline_html() escapes everything and converts only code, bold and links", {
  expect_identical(.md_inline_html("a < b & \"c\" > d"), "a &lt; b &amp; &quot;c&quot; &gt; d")
  expect_identical(.md_inline_html("`x <- 1` and **y**"), "<code>x &lt;- 1</code> and <strong>y</strong>")
  expect_identical(.md_inline_html("`**not bold**`"), "<code>**not bold**</code>")
  expect_identical(.md_inline_html("**A `code` heading**"), "<strong>A <code>code</code> heading</strong>")
  expect_identical(.md_inline_html("[a `b`](c.html) `[d](e)`"), "<a href=\"c.html\">a <code>b</code></a> <code>[d](e)</code>")
  expect_identical(.md_inline_html("[t](u.html)", base = "../"), "<a href=\"../u.html\">t</a>")
  expect_identical(.md_inline_html("[t](https://x.org/a#b)", base = "../"), "<a href=\"https://x.org/a#b\">t</a>")
  expect_identical(.md_inline_html("*one* _two_"), "*one* _two_")
})

test_that(".run_sheet_html() builds headings, paragraphs and nested lists", {
  html <- .run_sheet_html(c("# T", "", "## S", "", "Some", "text.", "", "1. **A**", "   - **B**", "1. C", "", "- d"))
  expect_identical(strsplit(html, "\n")[[1L]], c(
    "<h1>T</h1>", "<h2>S</h2>", "<p>Some text.</p>",
    "<ol>", "<li><strong>A</strong><ul><li><strong>B</strong></li></ul></li>", "<li>C</li>", "</ol>",
    "<ul>", "<li>d</li>", "</ul>"
  ))
})

test_that("the sheets survive the JSON the gallery reads", {
  s <- .run_sheets()
  back <- jsonlite::fromJSON(jsonlite::toJSON(s, auto_unbox = TRUE))
  expect_identical(names(back), c("name", "title", "markdown", "html"))
  files <- list.files(.templates_dir(), "[.]qmd$", recursive = TRUE)
  expect_setequal(back$name, sub("[.]qmd$", "", basename(files)))
  expect_false(anyNA(back$html))
})
