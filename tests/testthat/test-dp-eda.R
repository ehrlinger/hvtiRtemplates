# dp-eda is rendered, not only read: its sections call hv_followup_panels(),
# followup_check() and hv_eda_pages() at render time, and a static test would
# pass a template whose section chunk fails. scaffold_job() is in
# helper-migration.R. One fixture per render keeps the check time down.

# The fixture's iv_opyrs runs to 40, so the template's 1990 origin would place
# operations in 2030; the job refuses that, and these tests use 1980.
eda_edits <- list(
  "^ANALYSIS_SET <- " = "ANALYSIS_SET <- NULL",
  "^ORIGIN_YEAR <- " = "ORIGIN_YEAR <- 1980"
)

test_that("dp-eda renders every section into one self-contained report", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  s <- scaffold_job("dp", "eda", eda_edits, kind = "dp-postage")
  quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
  html <- sub("[.]qmd$", ".html", s$job)
  expect_true(file.exists(html))
  graphs <- file.path(s$root, "graphs", "cohort-eda")
  pages <- sprintf("dp-eda-%s-page-01.png", c("continuous", "percent", "count"))
  pngs <- file.path(graphs, c("dp-eda-gfup-all.png", pages))
  expect_true(all(file.exists(pngs)))
  text <- paste(readLines(html, warn = FALSE), collapse = "\n")
  for (heading in c("Overview", "Goodness of follow-up", "Continuous variables",
                    "Categorical variables, percent", "Categorical variables, counts")) {
    expect_match(text, paste0("<h2[^>]*>[^<]*", heading), info = heading)
  }
  # embed-resources: every saved figure is inside the report. An image Quarto
  # could not find is left as a file link and would not be counted here.
  # regmatches(), not length(gregexpr()): no match returns -1, whose length is 1.
  n_png <- length(list.files(graphs, "^dp-eda-.*[.]png$"))
  expect_identical(length(regmatches(text, gregexpr("src=\"data:image/png", text))[[1L]]), n_png)
})

test_that("dp-eda draws the same pages as dp-postage over the same data", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  root <- migration_study_fixture("dp-postage")
  eda <- scaffold_job("dp", "eda", eda_edits, root = root)
  postage <- scaffold_job("dp", "postage", eda_edits["^ANALYSIS_SET <- "], root = root)
  for (job in c(eda$job, postage$job)) quarto::quarto_render(job, execute_dir = dirname(job), quiet = TRUE)
  graphs <- file.path(root, "graphs", "cohort-eda")
  pages <- function(stem) list.files(graphs, paste0("^", stem, "-(continuous|percent|count)-"), full.names = TRUE)
  expect_identical(sub("^dp-eda-", "", basename(pages("dp-eda"))),
                   sub("^dp-postage-", "", basename(pages("dp-postage"))))
  # Byte for byte: the same function, arguments and device give the same file.
  expect_identical(unname(tools::md5sum(pages("dp-eda"))), unname(tools::md5sum(pages("dp-postage"))))
  expect_gt(length(pages("dp-eda")), 2L)
})

test_that("dp-eda leaves out a section not named in SECTIONS", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  edits <- c(eda_edits, list("^SECTIONS <- " = "SECTIONS <- c(\"count\", \"continuous\")"))
  s <- scaffold_job("dp", "eda", edits, kind = "dp-postage", subfolder = "checks")
  quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
  graphs <- file.path(s$root, "graphs", "cohort-eda")
  expect_false(file.exists(file.path(graphs, "dp-eda-gfup-all.png")))
  expect_length(list.files(graphs, "^dp-eda-percent-"), 0L)
  expect_true(file.exists(file.path(graphs, "dp-eda-count-page-01.png")))
  # A job kept in a subfolder still embeds its pages.
  text <- paste(readLines(sub("[.]qmd$", ".html", s$job), warn = FALSE), collapse = "\n")
  n_png <- length(list.files(graphs, "^dp-eda-.*[.]png$"))
  expect_identical(length(regmatches(text, gregexpr("src=\"data:image/png", text))[[1L]]), n_png)
  # The heading, not the folded source that prints it.
  expect_false(grepl("<h2[^>]*>[^<]*Goodness of follow-up", text))
})

test_that("dp-eda VARIABLES = NULL leaves out identifiers written without a separator", {
  # The spec chunk, not a render: dp-postage's test covers the rule's edges, and
  # this one proves dp-eda carries the same rule rather than an older copy.
  lines <- readLines(template_path("dp", "eda"), warn = FALSE)
  start <- match("#| label: spec", lines)
  end <- start + match("```", lines[-seq_len(start)])
  spec <- parse(text = lines[seq.int(start + 1L, end - 1L)])
  n <- 12L
  env <- list2env(list(d = data.frame(year = seq_len(n), age = 40 + seq_len(n), ccfid = 1000L + seq_len(n),
                                      patientid = sprintf("P%03d", seq_len(n)), carotid = rep(0:1, 6)),
                       X_VAR = "year", VARIABLES = NULL, EXCLUDE = character(),
                       GRID_NCOL = 4L, GRID_NROW = 4L, UNIQUE_LIMIT = 6L,
                       SECTIONS = c("followup", "continuous", "percent", "count"), ALPHA = 0.5,
                       label_map = function(d) data.frame(key = names(d), label = names(d))))
  out <- capture.output(eval(spec, env))
  expect_identical(env$VARIABLES, c("age", "carotid"))
  expect_match(paste(out, collapse = " "), "ccfid, patientid")
})
