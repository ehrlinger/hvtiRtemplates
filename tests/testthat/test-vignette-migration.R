legacy_vignette_path <- function() {
  source <- test_path("..", "..", "vignettes", "legacy-study-migration.qmd")
  if (file.exists(source)) return(source)
  system.file("doc", "legacy-study-migration.qmd", package = "hvtiRtemplates")
}

test_that("legacy migration vignette declares the complete workflow", {
  path <- legacy_vignette_path()
  expect_true(file.exists(path))
  if (!file.exists(path)) return(invisible(NULL))
  txt <- readLines(path, warn = FALSE)
  expect_true(any(grepl("adopt = TRUE", txt, fixed = TRUE)))
  expect_true(any(grepl('role = "study"', txt, fixed = TRUE)))
  expect_true(any(grepl('role = "named"', txt, fixed = TRUE)))
  for (qualifier in c("tables", "gfup", "trends", "postage")) {
    expect_true(any(grepl(paste0('qualifier = "', qualifier, '"'), txt, fixed = TRUE)))
  }
})

test_that("the tutorial creates four reviewed jobs from its own disposable evidence", {
  path <- legacy_vignette_path()
  expect_true(file.exists(path))
  if (!file.exists(path)) return(invisible(NULL))
  lines <- readLines(path, warn = FALSE)
  starts <- which(lines == "```{r}")
  code <- character()
  for (start in starts) {
    end <- start + match("```", lines[-seq_len(start)])
    chunk <- lines[seq.int(start + 1L, end - 1L)]
    if (any(chunk %in% c("#| label: render-jobs", "#| label: inspect-outputs"))) next
    code <- c(code, chunk)
  }
  env <- new.env(parent = environment())
  # A single evaluation keeps the vignette's deferred cleanup after assertions.
  checks <- quote({
    expect_equal(env$cohorts$rows, c(40L, 24L))
    expect_equal(env$cohorts$events, c(20L, 12L))
    expect_length(env$jobs, 4L)
    expect_true(all(file.exists(env$jobs)))
    expect_true(all(file.exists(env$reports)))
    expect_identical(unname(tools::md5sum(env$legacy_files)), unname(env$legacy_checksums))
    for (job in env$jobs) {
      expect_false(any(grepl("EDIT:", readLines(job), fixed = TRUE)))
    }
    expect_match(paste(readLines(env$jobs[["postage"]]), collapse = "\n"),
                 'DATASET <- "complete_cases"', fixed = TRUE)
    expect_true(all(c("datasets", "descriptive", "distributions", "analyses", "graphs", "documents", "estimates") %in%
                      list.dirs(env$root, recursive = FALSE, full.names = FALSE)))
    # These tutorial jobs use registered data and can render independently of
    # the tables/follow-up templates' hvtiRdatabuild version requirement.
    skip_if_not_installed("hvtiPlotR", "2.7.14")
    skip_if_not_installed("quarto")
    skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
    for (job in env$jobs[c("trends", "postage")]) {
      quarto::quarto_render(job, execute_dir = dirname(job), quiet = TRUE)
      expect_true(file.exists(sub("[.]qmd$", ".html", job)))
    }
    figures <- file.path(env$root, "graphs", "cohort-eda",
                         c("dp-trends-hx_chf-all.png", "dp-trends-lvmassi-all.png", "dp-postage-page-01.png"))
    expect_true(all(file.exists(figures)))
    expect_true(all(file.info(figures)$size > 1000L))
  })
  capture.output(eval(as.expression(c(as.list(parse(text = code)), list(checks))), env))
})

test_that("the final migration verifier returns four lasting rendered fixtures", {
  expect_true(exists("render_all_migration_fixtures", mode = "function"))
  if (!exists("render_all_migration_fixtures", mode = "function")) return(invisible(NULL))
  skip_if_not_installed("hvtiRdatabuild", "0.2.1")
  skip_if_not_installed("hvtiRtables", "1.0.1")
  skip_if_not_installed("hvtiPlotR", "2.7.14")
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  results <- render_all_migration_fixtures()
  expect_named(results, c("dc-tables", "dc-gfup", "dp-trends", "dp-postage"))
  for (result in results) {
    expect_true(dir.exists(result$root))
    expect_true(file.exists(result$job))
    expect_true(file.exists(result$report))
    expect_true(any(grepl("[.]html$", result$outputs)))
    expect_true(all(file.exists(result$outputs)))
  }
  expect_true(any(grepl("[.]docx$", results[["dc-tables"]]$outputs)))
  expect_equal(sum(grepl("dp-postage-page-[0-9]+[.]png$", results[["dp-postage"]]$outputs)), 2L)
})
