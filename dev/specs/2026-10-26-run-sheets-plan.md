# Run sheets implementation plan

> **For agentic workers:** executed inline in the session that wrote it, task by task, test first.
> Each task names its tests in full and its functions by signature. The implementation code lands in
> the task's commit rather than being copied here first, because the same session writes both.

**Goal:** a generated run sheet (what it does, prerequisites, outline, run it, where to go next) for
every template, published as one page per template in the gallery.

**Spec:** `dev/specs/2026-10-26-run-sheets-design.md`.

**Architecture:** one new internal file, `R/run-sheet.R`, reads every template with R's own parser,
builds the hand-off graph across templates, and writes each sheet as Markdown and HTML.
`dev/gallery/gallery.R` saves the sheets as JSON, `package.py` writes `sheets/<name>.html`, and
`index.html` links each row to its sheet.

**Tech stack:** base R (`parse()`, `match.call()`), `jsonlite` (already in Imports), testthat 3
snapshots, Python 3 standard library.

## Global constraints

- No new export. No version bump. A `news/feat-run-sheets.md` fragment, because `R/` ships.
- Roxygen is Rd markup, not Markdown. The new functions are internal and carry `#` comments only, as
  `R/job-setup.R` does.
- Lines at most 135 characters. Every default linter applies to `R/`.
- The `EDIT:` token is built (`paste0("ED", "IT", ":")`), never written literally in `R/` or in tests.
- Snapshots use fixture templates only, never shipped ones.
- Nothing renders a job, and nothing runs against `/Volumes/qhsstudies`.

## File map

| File | Change | Responsibility |
|---|---|---|
| `R/job-setup.R` | modify | `.guard_edits()` calls the shared `.edit_marker_lines()` |
| `R/run-sheet.R` | create | reading a template, the hand-off graph, the wording, the HTML |
| `inst/extdata/templates.json` | modify | `upstream` for `lm-checkpred`, `vt-fit` and `vt-explain` |
| `tests/testthat/test-run-sheet.R` | create | every test in spec section 5 |
| `tests/testthat/_snaps/run-sheet.md` | create | fixture wording |
| `dev/gallery/gallery.R` | modify | write `run-sheets.json` |
| `dev/gallery/package.py` | modify | write `sheets/<name>.html`, and fail when a sheet is missing |
| `dev/gallery/index.html` | modify | a "Run sheet" link on each row |
| `news/feat-run-sheets.md` | create | the NEWS bullet |

---

### Task 1: one marker helper for the guard and the sheet

**Files:** modify `R/job-setup.R`; test in `tests/testthat/test-run-sheet.R`.

**Produces:** `.edit_marker_lines(src)` takes a character vector of lines and returns
`data.frame(line = <int>, text = <chr>)`, one row per line carrying the token, with `text` trimmed and
cut to 96 characters.

- [ ] Write the failing test:

```r
test_that(".edit_marker_lines() finds the token and cuts each line as the draft banner does", {
  tok <- paste0("ED", "IT", ":")
  src <- c("x <- 1", paste("  #", tok, "set x"), paste("#", tok, strrep("a", 200)))
  m <- .edit_marker_lines(src)
  expect_identical(m$line, c(2L, 3L))
  expect_identical(m$text[1L], paste("#", tok, "set x"))
  expect_identical(nchar(m$text[2L]), 96L)
})
```

- [ ] Run `devtools::test(filter = "run-sheet")`. It fails because the function is not found.
- [ ] Add `.edit_marker_lines()` to `R/job-setup.R` beside `.guard_edits()`, and make `.guard_edits()`
  build its message from it. The message must stay byte-identical.
- [ ] Run `devtools::test(filter = "run-sheet|job-setup|guard")`. All pass, and the existing guard
  tests are unchanged.
- [ ] Commit: "Share the marker reader between the draft guard and run sheets".

### Task 2: read a template

**Files:** create `R/run-sheet.R`; tests in `tests/testthat/test-run-sheet.R`.

**Produces:**
- `.qmd_layout(src)` returns `list(chunk = <int per line, 0 outside a chunk>, headings = data.frame(line, level, text))`.
  An R chunk opens at a line matching ```` ^```\{r ```` and closes at the next ```` ^``` ````. A heading
  is `^#{2,3} \S` outside a chunk.
- `.call_name(call)` returns the function name for `fn(...)`, `pkg::fn(...)` and `pkg:::fn(...)`, and
  `NA` otherwise.
- `.template_calls(src, layout)` returns a list of `list(line, fn, call)`, one for every call in every
  chunk, found recursively through arguments, function bodies and default arguments. `line` is the
  chunk's first line.
- `.estimates_bindings(src, layout)` returns a named character vector: the top-level symbols bound to
  `set_path("estimates", "<literal>")`, with `NA` for a symbol bound to two different files.
- `.estimates_file(x, bindings)` returns the literal file for a `set_path("estimates", "<f>")` call, or for a
  symbol in `bindings`, and `NA` otherwise.
- `.run_sheet_facts(file)` returns `list(name, folder, src, layout, calls, bindings, markers)`, where
  `markers` is `.edit_marker_lines(src)`.

- [ ] Write the failing tests. Fixtures go through a helper that writes a template to a temporary
  file:

```r
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
    "reader <- function(p = 'a', read = function(q) hvtiRtemplates:::.read_handoff(q, 'SID fit', cfg, 'the sid job')) NULL",
    ".fit <- hvtiRtemplates:::.read_handoff(",
    "  set_path(\"estimates\", \"rfs.rds\"), \"forest\", cfg, \"the rfs-fit job\"",
    ")",
    "# .read_handoff(set_path('estimates', 'commented.rds'), 'x', cfg, 'nobody')",
    "```"))
  facts <- .run_sheet_facts(f)
  rh <- Filter(function(c) identical(c$fn, ".read_handoff"), facts$calls)
  expect_length(rh, 2L)
  expect_setequal(vapply(rh, function(c) as.character(c$call[[5L]]), ""), c("the sid job", "the rfs-fit job"))
  expect_identical(facts$layout$headings$text, "Upstream")
})

test_that("a hand-off path bound once at top level resolves; one bound twice does not", {
  f <- .sheet_fixture(.fx("```{r}",
    "MODEL_PATH <- set_path(\"estimates\", \"lm-binary.rds\")",
    "TWICE <- set_path(\"estimates\", \"a.rds\")", "TWICE <- set_path(\"estimates\", \"b.rds\")",
    "```"))
  b <- .run_sheet_facts(f)$bindings
  expect_identical(.estimates_file(quote(MODEL_PATH), b), "lm-binary.rds")
  expect_identical(.estimates_file(quote(TWICE), b), NA_character_)
  expect_identical(.estimates_file(quote(set_path("estimates", "c.rds")), b), "c.rds")
  expect_identical(.estimates_file(quote(set_path("graphs", "c.rds")), b), NA_character_)
})

test_that("headings inside a chunk are R comments, not sections", {
  f <- .sheet_fixture(.fx("## One", "```{r}", "## not a heading", "```", "### Two"))
  h <- .run_sheet_facts(f)$layout$headings
  expect_identical(h$text, c("One", "Two"))
  expect_identical(h$level, c(2L, 3L))
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
```

  `.templates_dir()` is the source tree's `inst/templates` when it exists, and
  `system.file("templates", package = "hvtiRtemplates")` otherwise. It is the same fallback AGENTS.md
  requires of the vignette tests.
- [ ] Run them. They fail because the functions are not found.
- [ ] Implement the six functions in `R/run-sheet.R`. Skip an argument that is the empty symbol while
  walking, because formals with no default hold one.
- [ ] Run the tests. They pass.
- [ ] Mutation check: cut `.template_calls()` back to top-level expressions, and confirm the
  default-argument test and the shipped-template test both fail. Then restore it.
- [ ] Commit: "Read a template's sections, markers and calls for its run sheet".

### Task 3: the hand-off graph

**Files:** modify `R/run-sheet.R` and `inst/extdata/templates.json`; test in `test-run-sheet.R`.

**Consumes:** `.run_sheet_facts()`, `.estimates_file()`, `template_catalog()`.

**Produces:** `.handoff_graph(facts, catalog = template_catalog())` takes a named list of facts and
returns `data.frame(consumer, producer, file, route, rebuild, line)`:
- `route` is `"literal"`, `"catalog"` or `"none"`;
- `producer` is `NA` when the route is `"none"`;
- one row per (read, producer).

Literal reads match producers on the file, through `saveRDS(x, <estimates file>)`. A non-literal read
takes producers from the consumer's catalog `upstream` values. A value matches a template whose name
equals it or whose prefix equals it, and never the consumer itself.

- [ ] Write the failing tests:

```r
test_that("the hand-off graph on the shipped templates", {
  g <- .handoff_graph(.all_run_sheet_facts())
  edge <- function(p, c) any(g$producer == p & g$consumer == c, na.rm = TRUE)
  expect_true(edge("ac", "hp"))
  expect_true(edge("hz", "hp"))
  expect_true(edge("hz", "hm"))
  expect_true(edge("hm", "hs-setup"))
  expect_true(edge("rfs-fit", "rfs-explain"))
  expect_true(edge("sid-fit", "sid-clusters"))
  expect_true(edge("lm-binary", "lp-mirror"))
  expect_true(edge("sid-clusters", "vt-explain"))
  expect_false(any(g$producer == g$consumer, na.rm = TRUE))
  expect_setequal(unique(g$consumer[g$route == "catalog"]),
                  c("hs-concordance", "lm-checkpred", "lp-mirror", "vt-fit", "vt-explain"))
  expect_identical(unique(g$consumer[g$route == "none"]), "hm")
  expect_identical(g$rebuild[g$route == "none"], "the companion hm selection runner")
})

test_that("a non-literal read with no catalog upstream is an error naming the template", {
  f <- .sheet_fixture(.fx("```{r}", "x <- .read_handoff(PATH, 'r', cfg, 'the other job')", "```"), "zz-orphan")
  cat <- data.frame(prefix = "zz", qualifier = "orphan", upstream = I(list(character())))
  expect_error(.handoff_graph(list(`zz-orphan` = .run_sheet_facts(f)), cat), "zz-orphan.*upstream")
})
```

  `.all_run_sheet_facts()` is the test helper `lapply` over `.templates_dir()`, named by template.
- [ ] Run them. They fail.
- [ ] Implement `.handoff_graph()`. Add `"upstream"` values to `templates.json`:
  `lm-checkpred` gets `["lm"]`, `vt-fit` gets `["sid-fit", "vp-fit"]`, and `vt-explain` gets
  `["sid-clusters"]`. Run `python3 dev/specs/artifacts/check-roadmap-counts.py`.
- [ ] Run the tests. They pass. Mutation check: drop the catalog route, and confirm the first test fails.
- [ ] Commit: "Link templates by the hand-offs they save and read".

### Task 4: the wording, and the page fragment

**Files:** modify `R/run-sheet.R`; tests and snapshot in `test-run-sheet.R` and `_snaps/run-sheet.md`.

**Consumes:** facts, the graph, `template_catalog()` and `.template_packages()`.

**Produces:**
- `.run_sheet_md(name, facts, graph, catalog)` returns a character vector of Markdown lines, as in spec
  section 2. The report link is relative to the gallery folder (`reports/<name>.html`). Vignette links
  are absolute (`https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#render-as-you-go`),
  as `index.html`'s `SITE` constant already writes them.
- `.md_inline_html(x, base = "")` converts one Markdown line to HTML. It escapes `& < > "` and converts
  `` `code` ``, `**bold**` and `[text](href)`, putting `base` before a relative href.
- `.run_sheet_html(md, base)` returns block HTML: `## ` lines become `<h2>`, `- ` runs become `<ul>`,
  `1. ` runs become `<ol>`, two-space-indented `- ` lines become a nested `<ul>`, and other non-blank
  lines become `<p>`.
- `.run_sheets(dir = .templates_dir(), base = "../")` returns a list of
  `list(name, title, markdown, html)`, one per template on disk, ordered by folder and then name.

- [ ] Write the failing tests:
  - Snapshots of `.run_sheet_md()` for fixtures: a producer and its consumer in one call, which gives
    the "where to go next" line and the upstream prerequisite; `guard_long_fit(why = "it takes hours")`
    with `guard_memory()`; `box_data = FALSE`; `DATASET <- NULL` with a bootstrap read; a template with
    no heading; a `###` heading; a non-literal `rebuild`. Each uses
    `expect_snapshot(cat(md, sep = "\n"))`. The fixture catalog is a small data frame built in the
    test.
  - Every shipped template: the sheet has `## What it does`, `## Prerequisites`, `## Outline` and
    `## Run it`. It has `## Where to go next` exactly when the graph has the template as a producer.
    Its marker counts sum to `nrow(.edit_marker_lines(src))`. Every package of
    `.template_packages(f)` appears in the prerequisites. Its outline headings equal the template's
    headings.
  - `.md_inline_html()`: `"a < b & \"c\""` is escaped. `` "`x`" ``, `"**y**"` and `"[t](u.html)"`
    convert, and with `base = "../"` the href is `../u.html`. `"[t](https://x)"` keeps its absolute href.
  - The round trip: `jsonlite::fromJSON(jsonlite::toJSON(.run_sheets(), auto_unbox = TRUE))` has
    columns `name`, `title`, `markdown` and `html`, with one row per template.
- [ ] Run them. They fail.
- [ ] Implement the four functions.
- [ ] Run the tests. Review every snapshot by reading it, not by accepting it. Then they pass.
- [ ] Commit: "Write each template's run sheet as an outline with prerequisites and next steps".

### Task 5: the gallery

**Files:** modify `dev/gallery/gallery.R`, `dev/gallery/package.py` and `dev/gallery/index.html`.

- [ ] In `gallery.R`'s `sys.nframe() == 0L` block, after `gallery-build.csv` is written:
  `jsonlite::write_json(hvtiRtemplates:::.run_sheets(), file.path(root, "run-sheets.json"), auto_unbox = TRUE, pretty = TRUE)`.
  It reads the installed templates, which are the ones it rendered.
- [ ] In `package.py`, add `write_sheets(root, out, names)`. It reads `<root>/run-sheets.json` and exits
  naming any template on disk that has no sheet. It writes `<out>/sheets/<name>.html`: a page shell in
  the gallery's palette and type, the sheet's `html`, and a footer saying the page is generated, with
  the build stamp. Call it from `__main__`. Each `gallery_data()` row gets `"sheet": True`.
- [ ] In `index.html`, add a "Run sheet" link beside "Then run it" when `t.sheet` is set:
  `href="sheets/${t.name}.html"`.
- [ ] Verify without rendering: install the branch into a scratch library, run
  `.run_sheets()` to a JSON file in a scratch study folder, and give that folder a `gallery-build.csv`
  that points every template at a one-line stand-in report. Run `package.py` into a scratch output,
  then open `index.html` and two sheets (`rfs-fit` and `hp`) in the browser pane, at phone width and
  at desktop width.
- [ ] Commit: "Publish each template's run sheet in the gallery".

### Task 6: finish

- [ ] Write `news/feat-run-sheets.md`, the bullet as it will read in NEWS.md.
- [ ] Run `devtools::document()`. Expect no change to `man/` or `NAMESPACE`.
- [ ] Run `devtools::test()` with `NOT_CRAN=true`, and read the `SKIP n | PASS` line.
- [ ] Run `devtools::check()`. Target 0/0/0.
- [ ] Run `lintr::lint_package()`. Expect it clean.
- [ ] Run the three `dev/specs/artifacts/check-*.py` scripts. All pass.
- [ ] Run `/code-review` locally, and fix what it finds.
- [ ] Push, then open a PR against `main`. The body says the local review stood in for Copilot, records
  the mutation checks, and gives John the lri gallery rebuild commands.
