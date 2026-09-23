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
      .restore_provenance_file = function(path, state, backup = NA_character_) {
        if (identical(basename(path), "_quarto.yml")) stop("config is locked")
        real_restore(path, state, backup)
      },
      .package = "hvtiRtemplates"
    ),
    "could not update _quarto[.]yml"
  )

  expect_identical(readLines(config_path, warn = FALSE), config_before)
  expect_identical(unname(vapply(hook_paths, readLines, character(1L), warn = FALSE)), hook_before)
  expect_length(list.files(dirname(hook_paths[[1L]]), pattern = "-backup-", all.files = TRUE), 0L)
})

test_that("backup copy failures leave no partial recovery file", {
  root <- withr::local_tempdir()
  path <- file.path(root, "pre-render-provenance.R")
  writeLines("existing pre hook", path)
  state <- .provenance_file_state(path)

  expect_error(
    testthat::with_mocked_bindings(
      .backup_provenance_file(path, state),
      .copy_provenance_file = function(from, to, overwrite = FALSE) {
        writeBin(as.raw(1:3), to)
        FALSE
      },
      .package = "hvtiRtemplates"
    ),
    "Could not preserve"
  )
  expect_length(list.files(root, pattern = "-backup-", all.files = TRUE), 0L)
})

test_that("failed atomic restoration retains the exact recovery backup", {
  root <- withr::local_tempdir()
  path <- file.path(root, "pre-render-provenance.R")
  writeLines("existing pre hook", path)
  state <- .provenance_file_state(path)
  backup <- .backup_provenance_file(path, state)
  writeLines("new pre hook", path)

  expect_error(
    testthat::with_mocked_bindings(
      .restore_provenance_file(path, state, backup),
      .rename_provenance_file = function(from, to) FALSE,
      .package = "hvtiRtemplates"
    ),
    "Could not atomically restore"
  )
  expect_identical(readLines(path, warn = FALSE), "new pre hook")
  expect_identical(.provenance_file_state(backup), state)
  expect_length(list.files(root, pattern = "-restore-", all.files = TRUE), 0L)
})

test_that("one rollback inspection error does not prevent restoring other hook files", {
  root <- make_hook_study(withr::local_tempdir())
  config_path <- file.path(root, "_quarto.yml")
  writeLines(c("project:", "  type: default"), config_path)
  config_before <- readLines(config_path, warn = FALSE)
  hook_paths <- file.path(root, .provenance_hook_files())
  dir.create(dirname(hook_paths[[1L]]), recursive = TRUE)
  hook_before <- c("existing pre hook", "existing post hook")
  Map(writeLines, hook_before, hook_paths)
  pre_hook_bytes <- readBin(hook_paths[[1L]], "raw", n = file.info(hook_paths[[1L]])$size)
  real_unchanged <- .provenance_file_unchanged

  rollback_warning <- NULL
  expect_error(
    withCallingHandlers(
      testthat::with_mocked_bindings(
        .install_provenance_hooks(root),
        .copy_provenance_file = function(from, to, overwrite = FALSE) {
          if (identical(basename(to), "_quarto.yml")) return(FALSE)
          file.copy(from, to, overwrite = overwrite)
        },
        .provenance_file_unchanged = function(path, state) {
          if (identical(path, normalizePath(hook_paths[[1L]], mustWork = FALSE))) stop("pre hook is unreadable")
          real_unchanged(path, state)
        },
        .package = "hvtiRtemplates"
      ),
      warning = function(warning) {
        rollback_warning <<- conditionMessage(warning)
        invokeRestart("muffleWarning")
      }
    ),
    "could not update _quarto[.]yml"
  )

  expect_identical(readLines(config_path, warn = FALSE), config_before)
  expect_identical(readLines(hook_paths[[2L]], warn = FALSE), hook_before[[2L]])
  expect_match(rollback_warning, "Original bytes remain at")
  recovery_path <- sub(".*Original bytes remain at '([^']+)'.*", "\\1", rollback_warning)
  expect_true(file.exists(recovery_path))
  expect_identical(readBin(recovery_path, "raw", n = file.info(recovery_path)$size), pre_hook_bytes)
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

test_that("sidecar publication replaces matching sources and withholds stale rollback pairs", {
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
  expect_true(file.exists(file.path(root, "managed.provenance.json")))
  expect_true(file.exists(file.path(root, "other.provenance.json")))
  expect_length(state$sidecar_backups, 1L)
  expect_true(file.exists(state$sidecar_backups[[1L]]$backup))

  current <- c(
    hvtiRutilities::capture_provenance("managed", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "managed.qmd", .hvti_render_id = state$render_id)
  )
  writeLines(.provenance_html(current), file.path(root, "managed.html"))
  .provenance_post_render(root, outputs = file.path(root, "managed.html"))
  expect_true(file.exists(file.path(root, "managed.provenance.json")))
  expect_false(file.exists(state$sidecar_backups[[1L]]$backup))

  prior_bytes <- readBin(file.path(root, "managed.provenance.json"), "raw",
                         n = file.info(file.path(root, "managed.provenance.json"))$size)
  state <- .provenance_pre_render(root, inputs = managed)
  current$.hvti_render_id <- "stale"
  writeLines(.provenance_html(current), file.path(root, "managed.html"))
  expect_warning(
    expect_error(.provenance_post_render(root, outputs = file.path(root, "managed.html")), "stale"),
    "does not match the current output"
  )
  expect_false(file.exists(file.path(root, "managed.provenance.json")))
  expect_identical(
    readBin(state$sidecar_backups[[1L]]$backup, "raw",
            n = file.info(state$sidecar_backups[[1L]]$backup)$size),
    prior_bytes
  )
  expect_false(file.exists(.provenance_state_path(root)))
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

test_that("pre-render preserves matching sidecars in hidden output directories", {
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

  state <- .provenance_pre_render(root, inputs = managed)

  expect_true(file.exists(hvtiRutilities::provenance_path(output)))
  expect_identical(
    state$sidecar_backups[[1L]]$path,
    .provenance_normalize_path(hvtiRutilities::provenance_path(output))
  )
  expect_true(file.exists(state$sidecar_backups[[1L]]$backup))
})

test_that("document-level freeze is resolved by Quarto", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto CLI is required")
  root <- make_hook_study(withr::local_tempdir())
  source <- file.path(root, "frozen.qmd")
  writeLines(c("---", "format: html", "execute:", "  freeze: true", "---", "", "text"), source)

  expect_true(.provenance_source_frozen(source))
})

test_that("Quarto omits post-render after a document execution error", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto CLI is required")
  root <- withr::local_tempdir()
  writeLines(c(
    "project:",
    "  type: default",
    "  pre-render: pre.R",
    "  post-render: post.R"
  ), file.path(root, "_quarto.yml"))
  writeLines("writeLines('pre', 'pre-ran')", file.path(root, "pre.R"))
  writeLines("writeLines('post', 'post-ran')", file.path(root, "post.R"))
  input <- file.path(root, "fail.qmd")
  fence <- paste(rep("\u0060", 3L), collapse = "")
  writeLines(c(
    "---",
    "title: failure",
    "format: html",
    "---",
    "",
    paste0(fence, "{r}"),
    "stop('deliberate render failure')",
    fence
  ), input)

  expect_error(quarto::quarto_render(input, execute_dir = root, quiet = TRUE), "Error running quarto CLI")

  expect_true(file.exists(file.path(root, "pre-ran")))
  expect_false(file.exists(file.path(root, "post-ran")))
})

test_that("a render failure before post-render leaves the prior sidecar in place", {
  root <- make_hook_study(withr::local_tempdir())
  .install_provenance_hooks(root)
  source <- file.path(root, "managed.qmd")
  output <- file.path(root, "managed.html")
  writeLines("hvtiRtemplates:::.embed_provenance()", source)
  writeLines("<html>payload missing</html>", output)
  prior <- c(
    hvtiRutilities::capture_provenance("managed", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "managed.qmd")
  )
  hvtiRutilities::publish_provenance(output, prior)
  sidecar <- hvtiRutilities::provenance_path(output)
  prior_bytes <- readBin(sidecar, "raw", n = file.info(sidecar)$size)

  .provenance_pre_render(root, inputs = source)

  expect_identical(readBin(sidecar, "raw", n = file.info(sidecar)$size), prior_bytes)
  expect_error(.provenance_post_render(root, outputs = output), "missing a current provenance payload")
  expect_identical(readBin(sidecar, "raw", n = file.info(sidecar)$size), prior_bytes)
  restored <- jsonlite::read_json(sidecar, simplifyVector = FALSE)
  expect_identical(restored$output$sha256, digest::digest(output, algo = "sha256", file = TRUE))
})

test_that("a multi-output failure removes partial sidecars and withholds mismatched prior ones", {
  root <- make_hook_study(withr::local_tempdir())
  .install_provenance_hooks(root)
  sources <- file.path(root, c("one.qmd", "two.qmd"))
  outputs <- file.path(root, c("one.html", "two.html"))
  writeLines("hvtiRtemplates:::.embed_provenance()", sources[[1L]])
  writeLines("hvtiRtemplates:::.embed_provenance()", sources[[2L]])
  writeLines("old one", outputs[[1L]])
  writeLines("old two", outputs[[2L]])
  old_two <- c(
    hvtiRutilities::capture_provenance("two", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "two.qmd")
  )
  hvtiRutilities::publish_provenance(outputs[[2L]], old_two)
  two_sidecar <- hvtiRutilities::provenance_path(outputs[[2L]])
  old_two_bytes <- readBin(two_sidecar, "raw", n = file.info(two_sidecar)$size)

  state <- .provenance_pre_render(root, inputs = sources)
  current_one <- c(
    hvtiRutilities::capture_provenance("one", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "one.qmd", .hvti_render_id = state$render_id)
  )
  writeLines(.provenance_html(current_one), outputs[[1L]])
  writeLines("<html>two failed</html>", outputs[[2L]])

  expect_warning(
    expect_error(.provenance_post_render(root, outputs = outputs), "missing a current provenance payload"),
    "does not match the current output"
  )
  expect_false(file.exists(hvtiRutilities::provenance_path(outputs[[1L]])))
  expect_false(file.exists(two_sidecar))
  expect_identical(
    readBin(state$sidecar_backups[[1L]]$backup, "raw", n = file.info(state$sidecar_backups[[1L]]$backup)$size),
    old_two_bytes
  )
  prior_record <- jsonlite::read_json(state$sidecar_backups[[1L]]$backup, simplifyVector = FALSE)
  expect_false(identical(prior_record$output$sha256, digest::digest(outputs[[2L]], algo = "sha256", file = TRUE)))
  expect_false(file.exists(.provenance_state_path(root)))
})

test_that("a failed sidecar restoration warns with the retained backup path", {
  root <- make_hook_study(withr::local_tempdir())
  .install_provenance_hooks(root)
  source <- file.path(root, "managed.qmd")
  output <- file.path(root, "managed.html")
  writeLines("hvtiRtemplates:::.embed_provenance()", source)
  writeLines("old html", output)
  prior <- c(
    hvtiRutilities::capture_provenance("managed", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "managed.qmd")
  )
  hvtiRutilities::publish_provenance(output, prior)
  state <- .provenance_pre_render(root, inputs = source)
  unlink(hvtiRutilities::provenance_path(output))

  rollback_warning <- NULL
  expect_error(
    withCallingHandlers(
      testthat::with_mocked_bindings(
        .provenance_post_render(root, outputs = output),
        .restore_provenance_file = function(...) stop("sidecar is locked"),
        .package = "hvtiRtemplates"
      ),
      warning = function(warning) {
        rollback_warning <<- conditionMessage(warning)
        invokeRestart("muffleWarning")
      }
    ),
    "missing a current provenance payload"
  )

  expect_match(rollback_warning, "sidecar is locked")
  expect_match(rollback_warning, state$sidecar_backups[[1L]]$backup, fixed = TRUE)
  expect_true(file.exists(state$sidecar_backups[[1L]]$backup))
})

test_that("abandoned recovery removes a durably recorded partial publication", {
  root <- make_hook_study(withr::local_tempdir())
  .install_provenance_hooks(root)
  source <- file.path(root, "managed.qmd")
  output <- file.path(root, "managed.html")
  writeLines("hvtiRtemplates:::.embed_provenance()", source)
  writeLines("new html", output)
  state <- .provenance_pre_render(root, inputs = source)
  sidecar <- .provenance_normalize_path(hvtiRutilities::provenance_path(output))
  payload <- c(
    hvtiRutilities::capture_provenance("managed", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "managed.qmd")
  )
  state$replacement_started <- list(sidecar)
  .write_json_atomic(state, .provenance_state_path(root))
  hvtiRutilities::publish_provenance(output, payload)

  .recover_abandoned_render(root)

  expect_false(file.exists(sidecar))
  expect_false(file.exists(.provenance_state_path(root)))
})

test_that("an interrupted portable state replacement recovers the prior complete state", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, ".hvtiR"))
  path <- .provenance_state_path(root)
  .write_json_atomic(list(value = "old"), path)
  real_rename <- .rename_provenance_file
  calls <- 0L

  expect_error(
    testthat::with_mocked_bindings(
      .write_json_atomic(list(value = "new"), path),
      .rename_provenance_file = function(from, to) {
        calls <<- calls + 1L
        if (calls == 1L) return(FALSE)
        if (calls == 2L) return(real_rename(from, to))
        stop("simulated interrupted state replacement")
      },
      .package = "hvtiRtemplates"
    ),
    "simulated interrupted state replacement"
  )

  expect_identical(.read_provenance_state(root)$value, "old")
  expect_true(file.exists(path))
})

test_that("post-render persists replacement intent before publishing", {
  root <- make_hook_study(withr::local_tempdir())
  .install_provenance_hooks(root)
  source <- file.path(root, "managed.qmd")
  output <- file.path(root, "managed.html")
  writeLines("hvtiRtemplates:::.embed_provenance()", source)
  state <- .provenance_pre_render(root, inputs = source)
  payload <- c(
    hvtiRutilities::capture_provenance("managed", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "managed.qmd", .hvti_render_id = state$render_id)
  )
  writeLines(.provenance_html(payload), output)
  observed <- NULL

  expect_error(
    testthat::with_mocked_bindings(
      .provenance_post_render(root, outputs = output),
      publish_provenance = function(...) {
        observed <<- .read_provenance_state(root)
        stop("simulated publication crash")
      },
      .package = "hvtiRutilities"
    ),
    "simulated publication crash"
  )

  expect_identical(
    unlist(observed$replacement_started, use.names = FALSE),
    .provenance_normalize_path(hvtiRutilities::provenance_path(output))
  )
})

test_that("abandoned recovery withholds a prior sidecar when its output changed", {
  root <- make_hook_study(withr::local_tempdir())
  .install_provenance_hooks(root)
  source <- file.path(root, "managed.qmd")
  output <- file.path(root, "managed.html")
  writeLines("hvtiRtemplates:::.embed_provenance()", source)
  writeLines("old html", output)
  prior <- c(
    hvtiRutilities::capture_provenance("managed", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "managed.qmd")
  )
  hvtiRutilities::publish_provenance(output, prior)
  state <- .provenance_pre_render(root, inputs = source)
  sidecar <- hvtiRutilities::provenance_path(output)
  backup <- state$sidecar_backups[[1L]]$backup
  prior_record <- jsonlite::read_json(backup, simplifyVector = FALSE)
  writeLines("new html", output)

  expect_warning(.recover_abandoned_render(root), backup, fixed = TRUE)

  expect_false(file.exists(sidecar))
  expect_true(file.exists(backup))
  expect_false(file.exists(.provenance_state_path(root)))
  expect_false(identical(prior_record$output$sha256, digest::digest(output, algo = "sha256", file = TRUE)))

  current <- .provenance_pre_render(root, inputs = source)
  expect_length(current$sidecar_backups, 0L)
  expect_true(file.exists(.provenance_state_path(root)))
})

test_that("committed abandoned recovery tolerates already removed backups", {
  root <- make_hook_study(withr::local_tempdir())
  .install_provenance_hooks(root)
  source <- file.path(root, "managed.qmd")
  output <- file.path(root, "managed.html")
  writeLines("hvtiRtemplates:::.embed_provenance()", source)
  writeLines("old html", output)
  prior <- c(
    hvtiRutilities::capture_provenance("managed", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "managed.qmd")
  )
  hvtiRutilities::publish_provenance(output, prior)
  state <- .provenance_pre_render(root, inputs = source)
  writeLines("new html", output)
  current <- c(
    hvtiRutilities::capture_provenance("managed", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "managed.qmd")
  )
  sidecar <- .provenance_normalize_path(hvtiRutilities::provenance_path(output))
  hvtiRutilities::publish_provenance(output, current)
  current_bytes <- readBin(sidecar, "raw", n = file.info(sidecar)$size)
  state$replacement_started <- list(sidecar)
  state$committed <- TRUE
  .write_json_atomic(state, .provenance_state_path(root))
  unlink(state$sidecar_backups[[1L]]$backup)

  .recover_abandoned_render(root)

  expect_identical(readBin(sidecar, "raw", n = file.info(sidecar)$size), current_bytes)
  expect_false(file.exists(.provenance_state_path(root)))
})

test_that("committed abandoned recovery removes surviving backups without rollback", {
  root <- make_hook_study(withr::local_tempdir())
  .install_provenance_hooks(root)
  source <- file.path(root, "managed.qmd")
  output <- file.path(root, "managed.html")
  writeLines("hvtiRtemplates:::.embed_provenance()", source)
  writeLines("old html", output)
  prior <- c(
    hvtiRutilities::capture_provenance("managed", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "managed.qmd")
  )
  hvtiRutilities::publish_provenance(output, prior)
  state <- .provenance_pre_render(root, inputs = source)
  writeLines("new html", output)
  current <- c(
    hvtiRutilities::capture_provenance("managed", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "managed.qmd")
  )
  sidecar <- .provenance_normalize_path(hvtiRutilities::provenance_path(output))
  hvtiRutilities::publish_provenance(output, current)
  current_bytes <- readBin(sidecar, "raw", n = file.info(sidecar)$size)
  backup <- state$sidecar_backups[[1L]]$backup
  state$replacement_started <- list(sidecar)
  state$committed <- TRUE
  .write_json_atomic(state, .provenance_state_path(root))

  .recover_abandoned_render(root)

  expect_identical(readBin(sidecar, "raw", n = file.info(sidecar)$size), current_bytes)
  expect_false(file.exists(backup))
  expect_false(file.exists(.provenance_state_path(root)))
})

test_that("a locked prior-state fallback cannot displace committed primary state", {
  root <- make_hook_study(withr::local_tempdir())
  .install_provenance_hooks(root)
  source <- file.path(root, "managed.qmd")
  output <- file.path(root, "managed.html")
  writeLines("hvtiRtemplates:::.embed_provenance()", source)
  writeLines("old html", output)
  prior <- c(
    hvtiRutilities::capture_provenance("managed", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "managed.qmd")
  )
  hvtiRutilities::publish_provenance(output, prior)
  state <- .provenance_pre_render(root, inputs = source)
  writeLines("new html", output)
  current <- c(
    hvtiRutilities::capture_provenance("managed", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "managed.qmd")
  )
  sidecar <- .provenance_normalize_path(hvtiRutilities::provenance_path(output))
  hvtiRutilities::publish_provenance(output, current)
  current_bytes <- readBin(sidecar, "raw", n = file.info(sidecar)$size)
  state$replacement_started <- list(sidecar)
  state$committed <- TRUE
  state_path <- .provenance_state_path(root)
  .write_json_atomic(state, state_path)
  previous <- .provenance_prior_state_path(state_path)
  stale <- state
  stale$committed <- FALSE
  jsonlite::write_json(stale, previous, auto_unbox = TRUE, null = "null", pretty = TRUE)
  real_unlink <- .unlink_provenance_state

  expect_error(
    testthat::with_mocked_bindings(
      .recover_abandoned_render(root),
      .unlink_provenance_state = function(path) {
        if (identical(path, previous)) return(1L)
        real_unlink(path)
      },
      .package = "hvtiRtemplates"
    ),
    previous,
    fixed = TRUE
  )
  expect_true(file.exists(state_path))
  expect_true(file.exists(previous))
  expect_identical(readBin(sidecar, "raw", n = file.info(sidecar)$size), current_bytes)

  .recover_abandoned_render(root)
  next_state <- .provenance_pre_render(root, inputs = source)

  expect_identical(readBin(sidecar, "raw", n = file.info(sidecar)$size), current_bytes)
  expect_length(next_state$sidecar_backups, 1L)
})

test_that("multi-sidecar recovery retries after a later restore fails", {
  root <- make_hook_study(withr::local_tempdir())
  .install_provenance_hooks(root)
  sources <- file.path(root, c("one.qmd", "two.qmd"))
  outputs <- file.path(root, c("one.html", "two.html"))
  sidecars <- vapply(outputs, hvtiRutilities::provenance_path, character(1L))
  for (i in seq_along(sources)) {
    writeLines("hvtiRtemplates:::.embed_provenance()", sources[[i]])
    writeLines(paste("old", i), outputs[[i]])
    prior <- c(
      hvtiRutilities::capture_provenance("managed", data = list(), cfg = hvtiRutilities::study_config(root)),
      list(source = basename(sources[[i]]))
    )
    hvtiRutilities::publish_provenance(outputs[[i]], prior)
  }
  state <- .provenance_pre_render(root, inputs = sources)
  unlink(sidecars)
  real_restore <- .restore_provenance_file
  calls <- 0L

  expect_error(
    testthat::with_mocked_bindings(
      .recover_abandoned_render(root),
      .restore_provenance_file = function(...) {
        calls <<- calls + 1L
        if (calls == 2L) stop("second restore locked")
        real_restore(...)
      },
      .package = "hvtiRtemplates"
    ),
    "second restore locked"
  )
  expect_true(all(file.exists(vapply(state$sidecar_backups, `[[`, character(1L), "backup"))))
  expect_true(file.exists(.provenance_state_path(root)))

  .recover_abandoned_render(root)

  expect_true(all(file.exists(sidecars)))
  for (i in seq_along(outputs)) {
    restored <- jsonlite::read_json(sidecars[[i]], simplifyVector = FALSE)
    expect_identical(restored$output$sha256, digest::digest(outputs[[i]], algo = "sha256", file = TRUE))
  }
  expect_false(any(file.exists(vapply(state$sidecar_backups, `[[`, character(1L), "backup"))))
  expect_false(file.exists(.provenance_state_path(root)))
})

test_that("pre-render cleans an abandoned backup when the sidecar is unchanged", {
  root <- make_hook_study(withr::local_tempdir())
  .install_provenance_hooks(root)
  source <- file.path(root, "managed.qmd")
  output <- file.path(root, "managed.html")
  writeLines("hvtiRtemplates:::.embed_provenance()", source)
  writeLines("old html", output)
  prior <- c(
    hvtiRutilities::capture_provenance("managed", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "managed.qmd")
  )
  hvtiRutilities::publish_provenance(output, prior)

  abandoned <- .provenance_pre_render(root, inputs = source)
  current <- .provenance_pre_render(root, inputs = source)

  expect_false(file.exists(abandoned$sidecar_backups[[1L]]$backup))
  expect_true(file.exists(current$sidecar_backups[[1L]]$backup))
  expect_length(list.files(root, pattern = "-backup-", recursive = TRUE, all.files = TRUE), 1L)
})

test_that("pre-render recovers an abandoned sidecar before starting another render", {
  root <- make_hook_study(withr::local_tempdir())
  .install_provenance_hooks(root)
  source <- file.path(root, "managed.qmd")
  output <- file.path(root, "managed.html")
  writeLines("hvtiRtemplates:::.embed_provenance()", source)
  writeLines("old html", output)
  prior <- c(
    hvtiRutilities::capture_provenance("managed", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "managed.qmd")
  )
  hvtiRutilities::publish_provenance(output, prior)
  sidecar <- hvtiRutilities::provenance_path(output)
  prior_bytes <- readBin(sidecar, "raw", n = file.info(sidecar)$size)

  abandoned <- .provenance_pre_render(root, inputs = source)
  unlink(sidecar)
  current <- .provenance_pre_render(root, inputs = source)

  expect_identical(readBin(sidecar, "raw", n = file.info(sidecar)$size), prior_bytes)
  restored <- jsonlite::read_json(sidecar, simplifyVector = FALSE)
  expect_identical(restored$output$sha256, digest::digest(output, algo = "sha256", file = TRUE))
  expect_false(file.exists(abandoned$sidecar_backups[[1L]]$backup))
  expect_true(file.exists(current$sidecar_backups[[1L]]$backup))
})

test_that("a successful unmanaged render retires the source's old sidecar", {
  root <- make_hook_study(withr::local_tempdir())
  .install_provenance_hooks(root)
  source <- file.path(root, "ordinary.qmd")
  output <- file.path(root, "ordinary.html")
  writeLines("ordinary source", source)
  writeLines("ordinary html", output)
  prior <- c(
    hvtiRutilities::capture_provenance("ordinary", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "ordinary.qmd")
  )
  hvtiRutilities::publish_provenance(output, prior)

  state <- .provenance_pre_render(root, inputs = source)
  .provenance_post_render(root, outputs = output)

  expect_false(file.exists(hvtiRutilities::provenance_path(output)))
  expect_false(file.exists(state$sidecar_backups[[1L]]$backup))
})

test_that("frozen HTML retains its execution payload when the source is unchanged", {
  root <- make_hook_study(withr::local_tempdir())
  .install_provenance_hooks(root)
  config <- read_quarto_config(root)
  .write_quarto_config(within(config, execute <- list(freeze = TRUE)), file.path(root, "_quarto.yml"))
  source <- file.path(root, "managed.qmd")
  output <- file.path(root, "managed.html")
  writeLines("hvtiRtemplates:::.embed_provenance()", source)
  writeLines("old html", output)
  prior <- c(
    hvtiRutilities::capture_provenance("managed", data = list(), cfg = hvtiRutilities::study_config(root)),
    list(source = "managed.qmd")
  )
  hvtiRutilities::publish_provenance(output, prior)
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
  expect_false(file.exists(state$sidecar_backups[[1L]]$backup))
})
