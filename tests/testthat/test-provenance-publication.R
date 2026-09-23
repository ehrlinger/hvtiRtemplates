make_hook_study <- function(root) {
  suppressMessages(hvtiRutilities::study_setup(
    root, study = "Hook study", study_tracker_id = 42L, adopt = TRUE
  ))
  data_path <- file.path(hvtiRutilities::study_dir("datasets", root), "cohort.csv")
  utils::write.csv(data.frame(id = 1L), data_path, row.names = FALSE)
  suppressMessages(hvtiRutilities::register_data(root, "cohort.csv"))
  invisible(root)
}

read_quarto_config <- function(root) {
  yaml::read_yaml(file.path(root, "_quarto.yml"))
}

test_that("hook installation creates a project and is idempotent", {
  root <- make_hook_study(withr::local_tempdir())

  .install_provenance_hooks(root)
  first <- readLines(file.path(root, "_quarto.yml"), warn = FALSE)
  .install_provenance_hooks(root)
  second <- readLines(file.path(root, "_quarto.yml"), warn = FALSE)
  config <- read_quarto_config(root)

  expect_identical(second, first)
  expect_identical(config$project$`pre-render`, .provenance_hook_command("pre"))
  expect_identical(config$project$`post-render`, .provenance_hook_command("post"))
  expect_false(grepl("Rscript", .provenance_hook_command("pre"), fixed = TRUE))
  expect_true(all(file.exists(file.path(root, .provenance_hook_files()))))
})

test_that("hook installation preserves scalar and list hooks and unrelated settings", {
  cases <- list(
    scalar = list(
      project = list(type = "default", `pre-render` = "Rscript before.R", `post-render` = "Rscript after.R"),
      format = list(html = list(toc = TRUE))
    ),
    list = list(
      project = list(
        type = "default",
        `pre-render` = list("Rscript first.R", "Rscript second.R"),
        `post-render` = list("Rscript finish.R")
      ),
      execute = list(freeze = "auto")
    )
  )

  for (name in names(cases)) {
    root <- make_hook_study(withr::local_tempdir())
    yaml::write_yaml(cases[[name]], file.path(root, "_quarto.yml"))
    .install_provenance_hooks(root)
    config <- read_quarto_config(root)

    expect_identical(config$format, cases[[name]]$format, info = name)
    expect_identical(config$execute, cases[[name]]$execute, info = name)
    expect_identical(tail(config$project$`pre-render`, 1L), .provenance_hook_command("pre"), info = name)
    expect_identical(tail(config$project$`post-render`, 1L), .provenance_hook_command("post"), info = name)
    expect_true(all(unlist(cases[[name]]$project[c("pre-render", "post-render")]) %in%
                      unlist(config$project[c("pre-render", "post-render")])), info = name)
  }
})

test_that("hook installation preserves YAML 1.2 string scalars", {
  root <- make_hook_study(withr::local_tempdir())
  writeLines(c("title: On", "project:", "  type: default"), file.path(root, "_quarto.yml"))

  .install_provenance_hooks(root)

  expect_identical(.read_quarto_config(file.path(root, "_quarto.yml"))$title, "On")
  expect_true("title: On" %in% readLines(file.path(root, "_quarto.yml"), warn = FALSE))
})

test_that("hook installation preserves project comments and multiline commands", {
  root <- make_hook_study(withr::local_tempdir())
  path <- file.path(root, "_quarto.yml")
  writeLines(c(
    "project: # keep this comment",
    "  type: default",
    "  pre-render: |",
    "    echo first",
    "    echo second"
  ), path)
  before <- .read_quarto_config(path)$project$`pre-render`

  .install_provenance_hooks(root)
  first <- readLines(path, warn = FALSE)
  .install_provenance_hooks(root)
  config <- .read_quarto_config(path)

  expect_identical(readLines(path, warn = FALSE), first)
  expect_true("project: # keep this comment" %in% readLines(path, warn = FALSE))
  expect_identical(config$project$`pre-render`[[1L]], before)
  expect_identical(utils::tail(config$project$`pre-render`, 1L), .provenance_hook_command("pre"))
})

test_that("hook installation refuses malformed Quarto configuration", {
  root <- make_hook_study(withr::local_tempdir())
  writeLines("project: [", file.path(root, "_quarto.yml"))

  expect_error(.install_provenance_hooks(root), "_quarto[.]yml")
  expect_identical(readLines(file.path(root, "_quarto.yml"), warn = FALSE), "project: [")
})

test_that("hook installation restores preexisting files when config publication fails", {
  root <- make_hook_study(withr::local_tempdir())
  config_path <- file.path(root, "_quarto.yml")
  writeLines(c("project:", "  type: default"), config_path)
  config_before <- readLines(config_path, warn = FALSE)
  hook_paths <- file.path(root, .provenance_hook_files())
  dir.create(dirname(hook_paths[[1L]]), recursive = TRUE)
  hook_before <- c("existing pre hook", "existing post hook")
  Map(writeLines, hook_before, hook_paths)
  real_restore <- .restore_provenance_file
  expect_error(
    testthat::with_mocked_bindings(
      .install_provenance_hooks(root),
      .copy_provenance_file = function(from, to, overwrite = FALSE) {
        if (identical(basename(to), "_quarto.yml")) return(FALSE)
        file.copy(from, to, overwrite = overwrite)
      },
      .restore_provenance_file = function(path, state) {
        if (identical(basename(path), "_quarto.yml")) stop("config is locked")
        real_restore(path, state)
      },
      .package = "hvtiRtemplates"
    ),
    "could not update _quarto[.]yml"
  )

  expect_identical(readLines(config_path, warn = FALSE), config_before)
  expect_identical(unname(vapply(hook_paths, readLines, character(1L), warn = FALSE)), hook_before)
})

test_that("one rollback error does not prevent restoring other hook files", {
  root <- make_hook_study(withr::local_tempdir())
  config_path <- file.path(root, "_quarto.yml")
  writeLines(c("project:", "  type: default"), config_path)
  config_before <- readLines(config_path, warn = FALSE)
  hook_paths <- file.path(root, .provenance_hook_files())
  dir.create(dirname(hook_paths[[1L]]), recursive = TRUE)
  hook_before <- c("existing pre hook", "existing post hook")
  Map(writeLines, hook_before, hook_paths)
  real_restore <- .restore_provenance_file

  expect_warning(
    expect_error(
      testthat::with_mocked_bindings(
        .install_provenance_hooks(root),
        .copy_provenance_file = function(from, to, overwrite = FALSE) {
          if (identical(basename(to), "_quarto.yml")) return(FALSE)
          file.copy(from, to, overwrite = overwrite)
        },
        .restore_provenance_file = function(path, state) {
          if (identical(path, normalizePath(hook_paths[[1L]], mustWork = FALSE))) stop("pre hook is locked")
          real_restore(path, state)
        },
        .package = "hvtiRtemplates"
      ),
      "could not update _quarto[.]yml"
    ),
    "rollback could not restore"
  )

  expect_identical(readLines(config_path, warn = FALSE), config_before)
  expect_identical(readLines(hook_paths[[2L]], warn = FALSE), hook_before[[2L]])
})

test_that("render inputs resolve to one canonical study-relative qmd", {
  root <- make_hook_study(withr::local_tempdir())
  dir.create(file.path(root, "10_descriptive"), showWarnings = FALSE)
  source <- file.path(root, "10_descriptive", "cohort-eda-dc.qmd")
  intermediate <- file.path(root, "10_descriptive", "cohort-eda-dc.rmarkdown")
  writeLines("source", source)
  writeLines("intermediate", intermediate)

  expect_identical(.provenance_source(source, root), "10_descriptive/cohort-eda-dc.qmd")
  expect_identical(.provenance_source(intermediate, root), "10_descriptive/cohort-eda-dc.qmd")
  unlink(source)
  expect_error(.provenance_source(intermediate, root), "canonical.*qmd")

  dir.create(file.path(root, "30_analyses"), showWarnings = FALSE)
  writeLines("one", file.path(root, "10_descriptive", "same.qmd"))
  writeLines("two", file.path(root, "30_analyses", "same.qmd"))
  writeLines("intermediate", file.path(root, "same.rmarkdown"))
  expect_error(.provenance_source(file.path(root, "same.rmarkdown"), root), "ambiguous")
})

test_that("embedded payloads are HTML-safe and exactly recoverable", {
  payload <- list(
    job = "cohort-eda-dc",
    source = "10_descriptive/cohort-eda-dc.qmd",
    text = "</script><script>alert('x')</script>&"
  )
  html <- .provenance_html(payload)

  expect_length(gregexpr("<script", html, fixed = TRUE)[[1L]], 1L)
  expect_false(grepl("</script><script>", html, fixed = TRUE))
  expect_true(grepl("\\u003c", html, fixed = TRUE))
  expect_true(grepl("\\u0026", html, fixed = TRUE))
  expect_identical(.extract_provenance(html, managed = TRUE), payload)
})

test_that("managed HTML rejects missing duplicate and malformed payloads", {
  valid <- .provenance_html(list(job = "one"))

  expect_error(.extract_provenance("<html><!-- hvti-provenance-managed --></html>", managed = TRUE), "missing")
  expect_error(.extract_provenance(paste(valid, valid), managed = TRUE), "exactly one")
  expect_error(
    .extract_provenance(sub('{"job":"one"}', "{bad", valid, fixed = TRUE), managed = TRUE),
    "malformed"
  )
  expect_null(.extract_provenance("<html>ordinary</html>", managed = FALSE))
})

test_that("data capture brackets the actual read and rejects changing bytes", {
  root <- make_hook_study(withr::local_tempdir())
  cfg <- hvtiRutilities::study_config(root)

  captured <- .provenance_read("study", cfg, function() hvtiRutilities::read_built(cfg))
  expect_equal(captured$value$id, 1L)
  expect_identical(captured$record$sha256, hvtiRutilities::provenance_data("study", cfg)$sha256)

  expect_error(
    .provenance_read("study", cfg, function() {
      value <- hvtiRutilities::read_built(cfg)
      write("changed", hvtiRutilities::built_path(cfg))
      value
    }),
    "changed while it was read"
  )
})

test_that("file data capture snapshots the file actually read", {
  root <- make_hook_study(withr::local_tempdir())
  cfg <- hvtiRutilities::study_config(root)
  path <- file.path(hvtiRutilities::study_dir("datasets", root), "named.parquet")
  write("original", path)

  captured <- .provenance_file_read("analysis_set:named", path, cfg, function() readLines(path),
                                    role = "analysis_set:named")
  expect_identical(
    captured$record$path,
    file.path(basename(hvtiRutilities::study_dir("datasets", root)), "named.parquet")
  )
  expect_identical(captured$record$sha256, digest::digest(path, algo = "sha256", file = TRUE))
  expect_error(
    .provenance_file_read("analysis_set:named", path, cfg, function() {
      value <- readLines(path)
      write("changed", path)
      value
    }),
    "changed while it was read"
  )
})

test_that("pre-render invalidates only matching sources and post-render rejects stale payloads", {
  root <- make_hook_study(withr::local_tempdir())
  .install_provenance_hooks(root)
  managed <- file.path(root, "managed.qmd")
  other <- file.path(root, "other.qmd")
  writeLines("hvtiRtemplates:::.embed_provenance()", managed)
  writeLines("ordinary", other)
  for (stem in c("managed", "other")) {
    writeLines("html", file.path(root, paste0(stem, ".html")))
    payload <- c(
      hvtiRutilities::capture_provenance(stem, data = list(), cfg = hvtiRutilities::study_config(root)),
      list(source = paste0(stem, ".qmd"))
    )
    hvtiRutilities::publish_provenance(file.path(root, paste0(stem, ".html")), payload)
  }

  state <- .provenance_pre_render(root, inputs = managed)
  expect_false(file.exists(file.path(root, "managed.provenance.json")))
  expect_true(file.exists(file.path(root, "other.provenance.json")))

  current <- c(
    hvtiRutilities::capture_provenance("managed", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "managed.qmd", .hvti_render_id = state$render_id)
  )
  writeLines(.provenance_html(current), file.path(root, "managed.html"))
  .provenance_post_render(root, outputs = file.path(root, "managed.html"))
  expect_true(file.exists(file.path(root, "managed.provenance.json")))

  state <- .provenance_pre_render(root, inputs = managed)
  current$.hvti_render_id <- "stale"
  writeLines(.provenance_html(current), file.path(root, "managed.html"))
  expect_error(.provenance_post_render(root, outputs = file.path(root, "managed.html")), "stale")
  expect_false(file.exists(file.path(root, "managed.provenance.json")))
})

test_that("Quarto file lists may be direct or file-backed", {
  root <- withr::local_tempdir()
  paths <- c("one.qmd", "nested/two.qmd")
  withr::local_envvar(QUARTO_PROJECT_INPUT_FILES = paste(paths, collapse = "\n"))
  expect_identical(.quarto_project_files("QUARTO_PROJECT_INPUT_FILES", root), file.path(root, paths))

  list_file <- tempfile(fileext = ".txt")
  writeLines(paths, list_file)
  withr::local_envvar(QUARTO_PROJECT_INPUT_FILES = NA, QUARTO_USE_FILE_FOR_PROJECT_INPUT_FILES = list_file)
  expect_identical(.quarto_project_files("QUARTO_PROJECT_INPUT_FILES", root), file.path(root, paths))
})

test_that("pre-render ignores unmanaged non-QMD inputs", {
  root <- make_hook_study(withr::local_tempdir())
  .install_provenance_hooks(root)
  managed <- file.path(root, "managed.qmd")
  notes <- file.path(root, "notes.md")
  writeLines("hvtiRtemplates:::.embed_provenance()", managed)
  writeLines("ordinary markdown", notes)

  state <- .provenance_pre_render(root, inputs = c(managed, notes))

  expect_identical(unlist(state$managed_sources, use.names = FALSE), "managed.qmd")
})

test_that("pre-render invalidates matching sidecars in hidden output directories", {
  root <- make_hook_study(withr::local_tempdir())
  .install_provenance_hooks(root)
  managed <- file.path(root, "managed.qmd")
  writeLines("hvtiRtemplates:::.embed_provenance()", managed)
  dir.create(file.path(root, ".rendered"))
  output <- file.path(root, ".rendered", "managed.html")
  writeLines("html", output)
  payload <- c(
    hvtiRutilities::capture_provenance("managed", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "managed.qmd")
  )
  hvtiRutilities::publish_provenance(output, payload)

  .provenance_pre_render(root, inputs = managed)

  expect_false(file.exists(hvtiRutilities::provenance_path(output)))
})

test_that("document-level freeze is resolved by Quarto", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto CLI is required")
  root <- make_hook_study(withr::local_tempdir())
  source <- file.path(root, "frozen.qmd")
  writeLines(c("---", "format: html", "execute:", "  freeze: true", "---", "", "text"), source)

  expect_true(.provenance_source_frozen(source))
})

test_that("post-render fails when a managed source has no payload", {
  root <- make_hook_study(withr::local_tempdir())
  .install_provenance_hooks(root)
  source <- file.path(root, "managed.qmd")
  output <- file.path(root, "managed.html")
  writeLines("hvtiRtemplates:::.embed_provenance()", source)
  writeLines("<html>payload missing</html>", output)
  .provenance_pre_render(root, inputs = source)

  expect_error(.provenance_post_render(root, outputs = output), "missing a current provenance payload")
  expect_false(file.exists(hvtiRutilities::provenance_path(output)))
})

test_that("frozen HTML retains its execution payload when the source is unchanged", {
  root <- make_hook_study(withr::local_tempdir())
  .install_provenance_hooks(root)
  config <- read_quarto_config(root)
  .write_quarto_config(within(config, execute <- list(freeze = TRUE)), file.path(root, "_quarto.yml"))
  source <- file.path(root, "managed.qmd")
  output <- file.path(root, "managed.html")
  writeLines("hvtiRtemplates:::.embed_provenance()", source)
  state <- .provenance_pre_render(root, inputs = source)
  payload <- c(
    hvtiRutilities::capture_provenance("managed", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(
      source = "managed.qmd",
      .hvti_render_id = "original-render",
      .hvti_source_sha256 = unlist(state$source_sha256, use.names = FALSE)[[1L]]
    )
  )
  original_rendered <- payload$rendered
  writeLines(.provenance_html(payload), output)

  .provenance_post_render(root, outputs = output)

  record <- jsonlite::read_json(hvtiRutilities::provenance_path(output), simplifyVector = FALSE)
  expect_identical(record$rendered, original_rendered)
})
