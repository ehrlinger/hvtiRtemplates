study_setup_vignette_path <- function() {
  source <- testthat::test_path("..", "..", "vignettes", "study-setup.qmd")
  if (file.exists(source)) return(source)
  system.file("doc", "study-setup.qmd", package = "hvtiRtemplates")
}

# The source is in the checkout (devtools::test()) and in the installed doc/
# folder (R CMD check). An install without built vignettes, as under covr, has
# neither, and that is a missing input rather than a failing vignette.
skip_without_vignette <- function() {
  path <- study_setup_vignette_path()
  testthat::skip_if_not(file.exists(path), "vignette source not available")
  path
}

test_that("study setup vignette declares the complete workflow", {
  path <- skip_without_vignette()
  txt <- readLines(path, warn = FALSE)
  expect_true(any(grepl("adopt = TRUE", txt, fixed = TRUE)))
  expect_true(any(grepl('role = "study"', txt, fixed = TRUE)))
  expect_true(any(grepl('role = "named"', txt, fixed = TRUE)))
  for (source in c("dc.tables.sas", "dc.gfup.sas", "dp.trends.sas", "dp.postage.sas")) {
    expect_true(any(grepl(source, txt, fixed = TRUE)))
  }
  expect_true(any(grepl("renv::init()", txt, fixed = TRUE)))
  expect_true(any(grepl("renv::snapshot()", txt, fixed = TRUE)))
})

test_that("the released legacy article name points to study setup", {
  legacy <- testthat::test_path(
    "..", "..", "vignettes", "legacy-study-migration.qmd"
  )
  if (!file.exists(legacy)) {
    legacy <- system.file(
      "doc", "legacy-study-migration.qmd", package = "hvtiRtemplates"
    )
  }
  testthat::skip_if_not(file.exists(legacy), "vignette source not available")
  txt <- readLines(legacy, warn = FALSE)
  expect_true(any(grepl("study-setup.html", txt, fixed = TRUE)))
})

test_that("the tutorial sets up new and adopted studies before analysis", {
  path <- skip_without_vignette()
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
    expect_true(exists("new_root", envir = env, inherits = FALSE))
    expect_true(exists("adopted_root", envir = env, inherits = FALSE))
    expect_true(all(dir.exists(file.path(
      env$new_root,
      c("00_datasets", "10_descriptive", "20_distributions", "30_analyses",
        "40_graphs", "50_documents", "90_estimates")
    ))))
    expect_false(dir.exists(file.path(env$adopted_root, ".git")))
    expect_length(Sys.glob(file.path(env$adopted_root, "tp*")), 0L)
    expect_true(dir.exists(env$adoption_backup))
    expect_true(dir.exists(file.path(env$adoption_backup, ".git")))
    expect_true(length(Sys.glob(file.path(env$adoption_backup, "tp*"))) > 0L)
    expect_named(
      env$new_jobs,
      c("general", "tables", "gfup", "trends", "postage")
    )
    expect_true(all(file.exists(env$new_jobs)))
    expect_true(file.exists(file.path(env$new_root, "00_datasets", "eda.parquet")))
    expect_true(file.exists(file.path(env$adopted_root, "datasets", "eda.parquet")))
    expect_equal(env$cohorts$rows, c(40L, 24L))
    expect_equal(env$cohorts$events, c(20L, 12L))
    expect_named(
      env$adopted_jobs,
      c("general", "tables", "gfup", "trends", "postage")
    )
    expect_true(all(file.exists(env$adopted_jobs)))
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
      render_job(job, final = TRUE, quiet = TRUE)
      expect_true(file.exists(sub("[.]qmd$", ".html", job)))
    }
    figures <- file.path(env$root, "graphs", "cohort-eda",
                         c("dp-trends-hx_chf-all.png", "dp-trends-lvmassi-all.png", "dp-postage-page-01.png"))
    expect_true(all(file.exists(figures)))
    expect_true(all(file.info(figures)$size > 1000L))
  })
  capture.output(eval(as.expression(c(as.list(parse(text = code)), list(checks))), env))
})

test_that("adoption cleanup refuses an existing backup before moving files", {
  lines <- readLines(skip_without_vignette(), warn = FALSE)
  start <- match("#| label: inventory-adoption-cleanup", lines)
  end <- start + match("```", lines[-seq_len(start)])
  code <- parse(text = lines[seq.int(start + 1L, end - 1L)])

  adopted_root <- withr::local_tempdir()
  adoption_backup <- withr::local_tempdir()
  dir.create(file.path(adopted_root, ".git"))
  writeLines("current git", file.path(adopted_root, ".git", "HEAD"))
  writeLines("current template", file.path(adopted_root, "tp.shared.sas"))
  writeLines("earlier backup", file.path(adoption_backup, "tp.shared.sas"))
  env <- list2env(list(
    adopted_root = adopted_root,
    adoption_backup = adoption_backup
  ))

  expect_error(eval(code, env), "backup path already exists")
  expect_true(dir.exists(file.path(adopted_root, ".git")))
  expect_true(file.exists(file.path(adopted_root, "tp.shared.sas")))
  expect_identical(
    readLines(file.path(adoption_backup, "tp.shared.sas")),
    "earlier backup"
  )
})

test_that("adoption cleanup finds nested tp files and permits no legacy git", {
  lines <- readLines(skip_without_vignette(), warn = FALSE)
  start <- match("#| label: inventory-adoption-cleanup", lines)
  end <- start + match("```", lines[-seq_len(start)])
  code <- parse(text = lines[seq.int(start + 1L, end - 1L)])

  adopted_root <- withr::local_tempdir()
  dir.create(file.path(adopted_root, "descriptive"))
  nested_tp <- file.path(adopted_root, "descriptive", "tp.dc.tables.sas")
  writeLines("nested template", nested_tp)
  adoption_backup <- tempfile(
    pattern = "adoption-backup-", tmpdir = dirname(adopted_root)
  )
  withr::defer(unlink(adoption_backup, recursive = TRUE),
               envir = testthat::teardown_env())
  env <- list2env(list(
    adopted_root = adopted_root,
    adoption_backup = adoption_backup
  ))

  expect_no_error(eval(code, env))
  expect_false(file.exists(nested_tp))
  expect_true(file.exists(file.path(
    adoption_backup, "descriptive", "tp.dc.tables.sas"
  )))
  expect_false(dir.exists(file.path(adoption_backup, ".git")))
})

test_that("adoption cleanup rolls back every move after a later failure", {
  lines <- readLines(skip_without_vignette(), warn = FALSE)
  start <- match("#| label: inventory-adoption-cleanup", lines)
  end <- start + match("```", lines[-seq_len(start)])
  code <- parse(text = lines[seq.int(start + 1L, end - 1L)])

  adopted_root <- withr::local_tempdir()
  adoption_backup <- tempfile(
    pattern = "adoption-backup-", tmpdir = dirname(adopted_root)
  )
  withr::defer(unlink(adoption_backup, recursive = TRUE),
               envir = testthat::teardown_env())
  dir.create(file.path(adopted_root, ".git"))
  writeLines("current git", file.path(adopted_root, ".git", "HEAD"))
  writeLines("current template", file.path(adopted_root, "tp.shared.sas"))
  calls <- 0L
  fail_second_rename <- function(from, to) {
    calls <<- calls + 1L
    if (calls == 2L) return(FALSE)
    base::file.rename(from, to)
  }
  env <- list2env(list(
    adopted_root = adopted_root,
    adoption_backup = adoption_backup,
    file.rename = fail_second_rename
  ))

  expect_error(eval(code, env), "Could not move legacy scaffolding")
  expect_true(dir.exists(file.path(adopted_root, ".git")))
  expect_true(file.exists(file.path(adopted_root, "tp.shared.sas")))
  expect_false(file.exists(adoption_backup) || dir.exists(adoption_backup))
})

test_that("EDA declaration preserves other sets and refuses replacement", {
  lines <- readLines(skip_without_vignette(), warn = FALSE)
  start <- match("#| label: write-eda-set", lines)
  end <- start + match("```", lines[-seq_len(start)])
  expressions <- parse(text = lines[seq.int(start + 1L, end - 1L)])
  definition <- expressions[vapply(expressions, function(x) {
    is.call(x) && identical(x[[1L]], as.name("<-")) &&
      identical(x[[2L]], as.name("declare_eda"))
  }, logical(1L))]

  fixture <- withr::local_tempdir()
  root <- file.path(fixture, "study")
  study_setup(root, study = "Analysis-set preservation", study_tracker_id = 1L)
  built <- data.frame(
    ccfid = seq_len(40L), dead = rep(0:1, 20L),
    iv_dead = seq_len(40L) / 10
  )
  utils::write.csv(
    built, file.path(root, "00_datasets", "built.csv"), row.names = FALSE
  )
  register_data(root, built = "built.csv", event = "dead", time = "iv_dead",
                role = "study", population = "Synthetic cohort")
  cfg_file <- file.path(root, "_study.yml")
  cfg <- yaml::read_yaml(cfg_file)
  existing <- list(
    id = "ccfid", vars = names(built), exclude = list(),
    expect = list(n = 40L, n_events = 20L)
  )
  cfg$analysis_sets <- list(existing = existing)
  yaml::write_yaml(cfg, cfg_file)
  env <- list2env(list(built = built))
  eval(definition, env)

  expect_no_error(env$declare_eda(root))
  updated <- yaml::read_yaml(cfg_file)
  expect_identical(updated$analysis_sets$existing, existing)
  expect_named(updated$analysis_sets, c("existing", "eda"))
  before <- readLines(cfg_file, warn = FALSE)
  expect_error(env$declare_eda(root), "already has an eda analysis set")
  expect_identical(readLines(cfg_file, warn = FALSE), before)
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

test_that("the tutorial embeds its PNG before temporary study cleanup", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  lines <- readLines(skip_without_vignette(), warn = FALSE)
  setup <- lines[grepl("^workspace <-", lines)]
  start <- match("#| label: inspect-outputs", lines)
  end <- start + match("```", lines[-seq_len(start)])
  expressions <- parse(text = lines[seq.int(start + 1L, end - 1L)])
  image <- expressions[vapply(expressions, function(x) {
    any(grepl("knitr::", deparse(x), fixed = TRUE))
  }, logical(1L))]
  fixture <- withr::local_tempdir()
  path <- file.path(fixture, "image-lifetime.qmd")
  # Use the article's actual lifetime and image-output expressions, isolating
  # Pandoc conversion from unrelated template dependency requirements.
  writeLines(c(
    "---", 'title: "Temporary study image"', "format:", "  html:",
    "    embed-resources: true", "---", "```{r}", "#| echo: false",
    setup, "root <- workspace", 'writeLines(root, "study-root.txt")',
    'png <- file.path(root, "postage.png")',
    "grDevices::png(png, width = 480, height = 320)",
    "graphics::plot(1:3, c(2, 1, 3))", "invisible(grDevices::dev.off())",
    'writeLines(knitr::image_uri(png), "expected-image.txt")',
    unlist(lapply(image, deparse)), "```"
  ), path)
  quarto::quarto_render(path, execute_dir = fixture, quiet = TRUE)
  html <- paste(readLines(file.path(fixture, "image-lifetime.html"), warn = FALSE), collapse = "\n")
  uri <- readLines(file.path(fixture, "expected-image.txt"))
  expect_false(dir.exists(readLines(file.path(fixture, "study-root.txt"))))
  expect_true(grepl(paste0('src="', uri, '"'), html, fixed = TRUE))
  expect_false(grepl('src="[^"]*postage[.]png', html))
})
