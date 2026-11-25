# A job that records provenance needs the study's Quarto provenance hooks, and
# .embed_provenance() finds them missing only at the end of the render. These
# tests pin the check that stops such a job before the render starts (#645).

precheck_study <- function(root) {
  suppressMessages(hvtiRutilities::study_setup(
    root, study = "Precheck study", study_tracker_id = 42L, adopt = TRUE, cleanup = FALSE, renv = FALSE
  ))
  data_path <- file.path(hvtiRutilities::study_dir("datasets", root), "cohort.csv")
  utils::write.csv(data.frame(id = 1L), data_path, row.names = FALSE)
  suppressMessages(hvtiRutilities::register_data(root = root, file = "cohort.csv"))
  invisible(normalizePath(root, winslash = "/"))
}

managed_job <- function(root) {
  dir <- file.path(root, "analyses")
  dir.create(dir, showWarnings = FALSE)
  job <- file.path(dir, "cohort.eda.dc.general.qmd")
  writeLines(c("---", "format: html", "---", "```{r}", "cat(hvtiRtemplates:::.embed_provenance(", "```"), job)
  normalizePath(job, winslash = "/")
}

test_that("render_job stops before rendering a managed job when the study has no _quarto.yml", {
  skip_if_not_installed("quarto")
  root <- precheck_study(withr::local_tempdir())
  job <- managed_job(root)
  called <- FALSE
  local_mocked_bindings(quarto_render = function(...) called <<- TRUE, .package = "quarto")

  err <- expect_error(render_job(job), class = "hvtiRtemplates_provenance_hooks_missing")
  expect_false(called)
  msg <- conditionMessage(err)
  expect_match(msg, "stopped before rendering", fixed = TRUE)
  # The fix names the exported function, which a study author can call; an internal one is not theirs to use.
  expect_match(msg, paste0("hvtiRtemplates::install_provenance_hooks(\"", root, "\")"), fixed = TRUE)
  expect_no_match(msg, ":::", fixed = TRUE)
  expect_match(msg, "delete that _quarto.yml", fixed = TRUE)
})

test_that("render_job renders a managed job once the hooks are installed", {
  skip_if_not_installed("quarto")
  root <- precheck_study(withr::local_tempdir())
  job <- managed_job(root)
  .install_provenance_hooks(root)
  called <- FALSE
  local_mocked_bindings(quarto_render = function(...) called <<- TRUE, .package = "quarto")

  render_job(job)
  expect_true(called)
  expect_null(.provenance_hooks_problem(job))
})

test_that("a document that records no provenance is not checked", {
  skip_if_not_installed("quarto")
  root <- precheck_study(withr::local_tempdir())
  doc <- file.path(root, "notes.qmd")
  writeLines(c("---", "format: html", "---", "Plain."), doc)
  called <- FALSE
  local_mocked_bindings(quarto_render = function(...) called <<- TRUE, .package = "quarto")

  render_job(doc)
  expect_true(called)
})

test_that("a study _quarto.yml without the hooks is named, and is not to be deleted", {
  root <- precheck_study(withr::local_tempdir())
  job <- managed_job(root)
  writeLines(c("project:", "  type: default"), file.path(root, "_quarto.yml"))

  problem <- .provenance_hooks_problem(job)
  expect_match(problem$message, "pre-render hook is missing or is not last", fixed = TRUE)
  expect_match(problem$fix, "hvtiRtemplates::install_provenance_hooks(", fixed = TRUE)
  expect_no_match(problem$fix, "delete", fixed = TRUE)
})

test_that("hooks whose files are gone fail the check as they would fail the render", {
  root <- precheck_study(withr::local_tempdir())
  job <- managed_job(root)
  .install_provenance_hooks(root)
  unlink(file.path(root, .provenance_hook_files()[["post"]]))

  problem <- .provenance_hooks_problem(job)
  expect_match(problem$message, "Provenance hook file is missing", fixed = TRUE)
  # The same condition, met at the end of a render, stops .embed_provenance().
  withr::local_envvar(QUARTO_PROJECT_DIR = root)
  expect_error(
    .embed_provenance(job, data = list(), cfg = hvtiRutilities::study_config(root)),
    "Provenance hook file is missing", fixed = TRUE
  )
})

test_that("a _quarto.yml nearer the job than the study root fails the check", {
  root <- precheck_study(withr::local_tempdir())
  job <- managed_job(root)
  .install_provenance_hooks(root)
  writeLines(c("project:", "  type: default"), file.path(dirname(job), "_quarto.yml"))

  problem <- .provenance_hooks_problem(job)
  expect_match(problem$message, "configured Quarto study project", fixed = TRUE)
  expect_match(problem$fix, paste0("Move ", dirname(job), "/_quarto.yml aside"), fixed = TRUE)
  expect_no_match(problem$fix, ".install_provenance_hooks(", fixed = TRUE)
})

test_that("a nearer _quarto.yaml is named as the file it is", {
  root <- precheck_study(withr::local_tempdir())
  job <- managed_job(root)
  .install_provenance_hooks(root)
  writeLines(c("project:", "  type: default"), file.path(dirname(job), "_quarto.yaml"))

  problem <- .provenance_hooks_problem(job)
  expect_match(problem$fix, paste0("Move ", dirname(job), "/_quarto.yaml aside: it makes"), fixed = TRUE)
  expect_no_match(problem$fix, "_quarto.yml", fixed = TRUE)
})

test_that("submit_job stops before launching a managed job without the hooks", {
  skip_on_os("windows") # submit_job() is not available on Windows
  root <- precheck_study(withr::local_tempdir())
  job <- managed_job(root)
  launched <- FALSE
  local_mocked_bindings(.launch = function(cmd) launched <<- TRUE)

  expect_error(submit_job(job), class = "hvtiRtemplates_provenance_hooks_missing")
  expect_false(launched)
  expect_false(file.exists(.run_files(job)$runner))
})

test_that("run_job refuses a managed job without the hooks and names the command", {
  root <- precheck_study(withr::local_tempdir())
  job <- managed_job(root)
  submitted <- FALSE
  local_mocked_bindings(submit_job = function(...) submitted <<- TRUE, .warn_stale_hvti = function() NULL)

  err <- expect_error(run_job(job, quiet = TRUE), class = "hvtiRtemplates_run_refused")
  expect_false(submitted)
  expect_match(conditionMessage(err), "provenance: ", fixed = TRUE)
  expect_match(conditionMessage(err), "hvtiRtemplates::install_provenance_hooks(", fixed = TRUE)

  check <- .check_provenance_hooks(job)
  expect_false(check$ok)
  .install_provenance_hooks(root)
  expect_true(.check_provenance_hooks(job)$ok)
})

test_that("install_provenance_hooks() installs the hooks from anywhere inside the study", {
  root <- precheck_study(withr::local_tempdir())
  job <- managed_job(root)
  expect_false(is.null(.provenance_hooks_problem(job)))

  out <- install_provenance_hooks(file.path(root, "analyses"))
  expect_identical(out, file.path(root, "_quarto.yml"))
  expect_null(.provenance_hooks_problem(job))
  # Running it again changes nothing.
  before <- readLines(out)
  install_provenance_hooks(root)
  expect_identical(readLines(out), before)
})

test_that("install_provenance_hooks() refuses a folder outside a study", {
  expect_error(install_provenance_hooks(withr::local_tempdir()), "no _study.yml found", fixed = TRUE)
  withr::local_dir(withr::local_tempdir())
  expect_error(install_provenance_hooks(), "not inside a study")
})

test_that("install_provenance_hooks() updates a study's _quarto.yaml in place, and makes no _quarto.yml beside it", {
  root <- precheck_study(withr::local_tempdir())
  job <- managed_job(root)
  yaml_path <- file.path(root, "_quarto.yaml")
  writeLines(c("project:", "  type: default", "  output-dir: _out", "execute:", "  echo: false"), yaml_path)

  expect_identical(install_provenance_hooks(root), yaml_path)
  expect_false(file.exists(file.path(root, "_quarto.yml")))
  config <- .read_quarto_config(yaml_path)
  expect_identical(config$project$`output-dir`, "_out")
  expect_identical(config$execute$echo, FALSE)
  expect_true(.provenance_hook_command("pre") %in% config$project$`pre-render`)
  # Discovery and the check before a render read the same file, so the job is ready.
  expect_null(.provenance_hooks_problem(job))
})

test_that("install_provenance_hooks() refuses a study with both _quarto.yml and _quarto.yaml, naming both", {
  root <- precheck_study(withr::local_tempdir())
  job <- managed_job(root)
  yml <- file.path(root, "_quarto.yml")
  yaml_path <- file.path(root, "_quarto.yaml")
  writeLines(c("project:", "  type: default"), yml)
  writeLines(c("project:", "  type: default"), yaml_path)
  before <- lapply(c(yml, yaml_path), readLines)

  err <- expect_error(install_provenance_hooks(root))
  expect_match(conditionMessage(err), yml, fixed = TRUE)
  expect_match(conditionMessage(err), yaml_path, fixed = TRUE)
  expect_identical(lapply(c(yml, yaml_path), readLines), before)
  expect_false(dir.exists(file.path(root, dirname(.provenance_hook_files()[[1L]]))))
  # The check before a render says the same, rather than reading one file of the two.
  expect_match(.provenance_hooks_problem(job)$message, "both", fixed = TRUE)
})

test_that("install_provenance_hooks() creates _quarto.yml when the study has neither file", {
  root <- precheck_study(withr::local_tempdir())
  expect_false(any(file.exists(file.path(root, c("_quarto.yml", "_quarto.yaml")))))
  expect_identical(install_provenance_hooks(root), file.path(root, "_quarto.yml"))
  expect_false(file.exists(file.path(root, "_quarto.yaml")))
  expect_true(.provenance_hook_command("post") %in% .read_quarto_config(file.path(root, "_quarto.yml"))$project$`post-render`)
})
