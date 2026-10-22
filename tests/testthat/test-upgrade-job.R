# An rfs-fit job copied from the v1.3.0 template, before #303 folded its four
# setup chunks into one, with a study's choices made in it.
old_rfs_job <- function(root) {
  lines <- readLines(testthat::test_path("fixtures-upgrade", "rfs-fit-v1.3.0.qmd"), warn = FALSE)
  edits <- c(
    # Resolved: the marker above DATASET is deleted, as an analyst would.
    "^# EDIT: the registered dataset" = "# the registered dataset this job reads.",
    "^DATASET <- " = 'DATASET <- "built_r"',
    # Unresolved: PREDICTORS keeps its marker, and spans two lines.
    "^PREDICTORS <- " = 'PREDICTORS <- c("age", "female",\n                "lvmassi")',
    "^NTREE <- " = "NTREE <- 250",
    # A choice the current template does not have.
    "^SEED\\s+<- " = "SEED  <- 7\nOLD_KNOB <- 3"
  )
  for (pattern in names(edits)) {
    i <- grep(pattern, lines)
    stopifnot(length(i) == 1L)
    lines[i] <- edits[[pattern]]
  }
  # An analyst-added chunk.
  lines <- c(lines, "", "```{r}", "#| label: my-checks", "stopifnot(TRUE)", "```")
  path <- file.path(root, "analyses", "dead-rfs-rfs-fit.qmd")
  writeLines(unlist(strsplit(lines, "\n", fixed = TRUE)), path)
  path
}

test_that("an old rfs-fit job upgrades with its choices intact", {
  root <- migration_study_fixture()
  path <- old_rfs_job(root)
  job <- upgrade_job(path)
  lines <- readLines(job)

  # The current name, and the old job kept under a name nothing renders.
  expect_identical(basename(job), "rfs.fit.dead.rfs.qmd")
  expect_false(file.exists(path))
  expect_true(file.exists(paste0(path, ".pre-upgrade")))

  # The current template's shape: one setup chunk, no guard chunks.
  expect_length(grep("^#\\| label: setup$", lines), 1L)
  expect_length(grep("^#\\| label: (guard-edits|guard-partial|set)$", lines), 0L)

  # Each choice carried, multi-line values included.
  expect_identical(grep("^DATASET <- ", lines, value = TRUE), 'DATASET <- "built_r"')
  i <- grep("^PREDICTORS <- ", lines)
  expect_identical(lines[i:(i + 1L)], c('PREDICTORS <- c("age", "female",', '                "lvmassi")'))
  expect_identical(grep("^NTREE <- ", lines, value = TRUE), "NTREE <- 250")
  expect_identical(grep("^SEED\\s+<- ", lines, value = TRUE), "SEED  <- 7")
  expect_identical(grep("^(SUBJECT|TYPE)\\s+<- ", lines, value = TRUE), c('SUBJECT <- "dead"', 'TYPE    <- "rfs"'))

  # A marker the analyst resolved stays resolved; one left open stays open.
  token <- paste0("ED", "IT", ":")
  expect_false(any(grepl(token, lines[grep("^DATASET <- ", lines) - 1L], fixed = TRUE)))
  pred <- grep("^PREDICTORS <- ", lines)
  block <- lines[max(which(!grepl("^#", lines[seq_len(pred - 1L)]))):(pred - 1L)]
  expect_true(any(grepl(token, block, fixed = TRUE)))

  # The unplaced choice is in the job, commented out under a marker.
  i <- grep("^# OLD_KNOB <- 3$", lines)
  expect_length(i, 1L)
  expect_true(grepl(token, lines[[i - 1L]], fixed = TRUE))

  # Every R chunk still parses.
  chunks <- .qmd_chunks(lines)
  for (k in seq_len(nrow(chunks))) {
    expect_no_error(parse(text = lines[(chunks$open[[k]] + 1L):(chunks$close[[k]] - 1L)]))
  }
})

test_that("the upgrade report lists every choice by name and quotes no value", {
  root <- migration_study_fixture()
  job <- upgrade_job(old_rfs_job(root))
  report <- readLines(sub("[.]qmd$", "-upgrade.md", job))
  section <- function(title) {
    from <- which(report == paste("##", title)) + 1L
    to <- c(grep("^## ", report), length(report) + 1L)
    report[from:(to[to > from][1L] - 1L)]
  }
  expect_true(all(c("- `DATASET`", "- `PREDICTORS`", "- `NTREE`", "- `SEED`") %in% section("Carried")))
  expect_true(any(grepl("^- `OLD_KNOB`, old line [0-9]+$", section("Not placed"))))
  expect_true(any(grepl("`my-checks`.*not in the current template", section("Review"))))
  expect_true(any(grepl("not recorded", report)))
  expect_false(any(grepl("built_r|lvmassi", report)))
})

test_that("upgrade_job() refuses to overwrite and names a job it cannot read", {
  root <- migration_study_fixture()
  path <- old_rfs_job(root)
  file.create(paste0(path, ".pre-upgrade"))
  expect_error(upgrade_job(path), "already exists")
  expect_true(file.exists(path))

  odd <- file.path(root, "analyses", "notes.qmd")
  writeLines("x", odd)
  expect_error(upgrade_job(odd), "does not name a template")
})

test_that("add_job() stamps its job and upgrade_job() reads the stamp", {
  root <- migration_study_fixture()
  job <- add_job("dc", "cohort", "eda", dir = root, qualifier = "general")
  version <- as.character(utils::packageVersion("hvtiRtemplates"))
  expect_true(paste0("<!-- hvtiRtemplates: dc.general ", version, " -->") %in% readLines(job))
  lines <- sub('^DATASET <- "built"', 'DATASET <- "built_r"', readLines(job))
  writeLines(lines, job)
  upgraded <- upgrade_job(job)
  expect_identical(upgraded, normalizePath(job, winslash = "/"))
  expect_identical(grep("^DATASET <- ", readLines(upgraded), value = TRUE), 'DATASET <- "built_r"')
  report <- readLines(sub("[.]qmd$", "-upgrade.md", upgraded))
  expect_true(any(grepl(paste0("came from: ", version, "$"), report)))
})

test_that("choices are read from header-labeled chunks, beside calls that are not assignments", {
  lines <- c("```{r edit-study-choices, echo = FALSE}", "utils::head(1)", "DATASET <- \"x\"", "```",
             "```{r echo = FALSE}", "KEEP <- 1", "```")
  ch <- .job_choices(lines)
  expect_identical(ch$name, "DATASET")
  expect_identical(.qmd_chunks(lines)$label, c("edit-study-choices", NA))
})

test_that("an edit chunk that does not parse stops the upgrade rather than dropping its choices", {
  lines <- c("```{r}", "#| label: edit-study-choices", "DATASET <- (", "```")
  expect_error(.job_choices(lines), "does not parse")
})

test_that("upgrade_job() refuses when another spelling of the job exists", {
  root <- migration_study_fixture()
  path <- old_rfs_job(root)
  file.create(file.path(root, "analyses", "rfs.fit.dead.rfs.qmd"))
  expect_error(upgrade_job(path), "another copy of this job")
  expect_true(file.exists(path))
})

# Review of #313, at d3b741e: nine cases, one test each.

test_that("the report names marker lines and never quotes them", {
  # dc-tables marks WORD_FILE inline, so a value left unresolved shares its
  # line with the marker the report lists.
  root <- migration_study_fixture()
  job <- add_job("dc", "cohort", "eda", dir = root, qualifier = "tables")
  lines <- readLines(job)
  i <- grep("^WORD_FILE <- ", lines)
  lines[[i]] <- sub('"dc-tables.docx"', '"x99999123.docx"', lines[[i]], fixed = TRUE)
  writeLines(lines, job)
  upgraded <- upgrade_job(job)
  expect_true(any(grepl("x99999123", readLines(upgraded), fixed = TRUE)))
  report <- readLines(sub("[.]qmd$", "-upgrade.md", upgraded))
  expect_false(any(grepl("x99999123", report, fixed = TRUE)))
})

test_that("an upgraded job keeps the old job's permissions", {
  skip_on_os("windows")
  root <- migration_study_fixture()
  path <- old_rfs_job(root)
  Sys.chmod(path, "600", use_umask = FALSE)
  umask <- Sys.umask("022")
  withr::defer(Sys.umask(umask))
  job <- upgrade_job(path)
  expect_identical(format(file.info(job)$mode), "600")
  expect_identical(format(file.info(sub("[.]qmd$", "-upgrade.md", job))$mode), "600")
})

test_that("a dangling link where the job would go is refused, and nothing is written through it", {
  skip_on_os("windows")
  root <- migration_study_fixture()
  path <- old_rfs_job(root)
  outside <- file.path(withr::local_tempdir(), "escaped.qmd")
  file.symlink(outside, file.path(root, "analyses", "rfs.fit.dead.rfs.qmd"))
  expect_error(upgrade_job(path), "another copy of this job")
  expect_false(file.exists(outside))
  expect_true(file.exists(path))
})

test_that("choices are read from four-backtick fences and quoted labels", {
  old <- c("````{r}", "#| label: \"edit-study-choices\"", "DATASET <- \"chosen\"", "````")
  new <- c("```{r}", "#| label: edit-study-choices", "DATASET <- \"built\"", "```")
  expect_identical(.upgrade_lines(old, new)$lines[[3L]], "DATASET <- \"chosen\"")
})

test_that("a marker still open in the old job stays open when the template has none there", {
  token <- paste0("ED", "IT", ":")
  old <- c("```{r}", "#| label: edit-study-choices", paste("#", token, "pick a seed"), "SEED <- 7", "```")
  new <- c("```{r}", "#| label: edit-study-choices", "SEED <- 1", "```")
  out <- .upgrade_lines(old, new)$lines
  i <- grep("^SEED <- 7$", out)
  expect_true(grepl(token, out[[i - 1L]], fixed = TRUE))
})

test_that("code in an edit chunk other than its choices is reported, not dropped unseen", {
  root <- migration_study_fixture()
  path <- old_rfs_job(root)
  lines <- readLines(path)
  i <- grep("^NTREE <- ", lines)
  lines <- append(lines, "d <- subset(d, age >= 18)", after = i)
  writeLines(lines, path)
  report <- readLines(sub("[.]qmd$", "-upgrade.md", upgrade_job(path)))
  expect_true(any(grepl("`edit-study-choices`.*code other than its choices differs", report)))
})

test_that("two statements on one line carry only the choice the template has", {
  token <- paste0("ED", "IT", ":")
  old <- c("```{r}", "#| label: edit-study-choices", "NTREE <- 250; OLD_KNOB <- 3", "```")
  new <- c("```{r}", "#| label: edit-study-choices", "NTREE <- 1000", "```")
  u <- .upgrade_lines(old, new)
  expect_identical(u$lines[[3L]], "NTREE <- 250")
  expect_false(any(grepl("^OLD_KNOB", u$lines)))
  expect_true("# OLD_KNOB <- 3" %in% u$lines)
  expect_identical(u$unplaced$name, "OLD_KNOB")
  expect_true(any(grepl(token, u$lines, fixed = TRUE)))
})

test_that("a job under a renamed template moves to its folder, created if the study lacks it", {
  root <- migration_study_fixture()
  job <- add_job("dc", "cohort", "eda", dir = root, qualifier = "trends")
  old <- file.path(root, "graphs", "dp.trends.cohort.eda.qmd")
  file.rename(job, old)
  unlink(file.path(root, "descriptive"), recursive = TRUE)
  upgraded <- suppressWarnings(upgrade_job(old))
  expect_identical(basename(dirname(upgraded)), "descriptive")
  expect_identical(basename(upgraded), "dc.trends.cohort.eda.qmd")
  expect_true(file.exists(paste0(old, ".pre-upgrade")))
})

test_that("upgrade_job() installs the study's provenance hooks", {
  root <- migration_study_fixture()
  path <- old_rfs_job(root)
  unlink(file.path(root, "_quarto.yml"))
  upgrade_job(path)
  config <- readLines(file.path(root, "_quarto.yml"))
  expect_true(any(grepl("pre-render", config, fixed = TRUE)))
  expect_true(any(grepl("post-render", config, fixed = TRUE)))
})

# A study job that reports through a hand-added stopgap, `.bm_progress()`, defined in the job. The template now
# reports through the job's own `get(".job")$progress()`, and an upgrade must leave exactly that one reporter.
nb_stopgap_job <- function(root, helper_in) {
  job <- add_job("nb", subject = "lvef", type = "boost", dir = root, qualifier = "boostmtree")
  lines <- readLines(job)
  fit <- grep('progress = get(".job")$progress("iteration")', lines, fixed = TRUE)
  eff <- grep('progress = get(".job")$progress("prediction")', lines, fixed = TRUE)
  stopifnot(length(fit) == 1L, length(eff) == 1L)
  lines[[fit]] <- sub('get(".job")$progress("iteration")', 'get(".bm_progress")("fit")', lines[[fit]], fixed = TRUE)
  lines[[eff]] <- sub('get(".job")$progress("prediction")', 'get(".bm_progress")("partial effects")', lines[[eff]], fixed = TRUE)
  helper <- ".bm_progress <- function(label) function(step, steps) cat(label, step, steps, '\\n', file = stderr())"
  chunks <- hvtiRtemplates:::.qmd_chunks(lines)
  target <- if (helper_in == "edit") "edit-study-choices" else "fit"
  at <- chunks$close[chunks$label == target]
  stopifnot(length(at) == 1L)
  lines <- append(lines, helper, after = at - 1L)
  writeLines(lines, job)
  job
}

test_that("upgrading a job with a hand-added progress stopgap leaves the template's one reporter", {
  for (helper_in in c("edit", "fit")) {
    root <- migration_study_fixture()
    job <- nb_stopgap_job(root, helper_in)
    stopifnot(any(grepl(".bm_progress", readLines(job), fixed = TRUE)))
    upgraded <- readLines(upgrade_job(job))
    code <- upgraded[!grepl("^\\s*#", upgraded)]
    # No stopgap runs: the helper and both calls to it are gone from the code.
    expect_false(any(grepl(".bm_progress", code, fixed = TRUE)), info = helper_in)
    # The boostmtree() and partial.plot() calls each report once, through the job.
    expect_identical(sum(grepl("progress = ", code, fixed = TRUE)), 2L, info = helper_in)
    expect_identical(length(grep('progress = get(".job")$progress("iteration")', code, fixed = TRUE)), 1L, info = helper_in)
    expect_identical(length(grep('progress = get(".job")$progress("prediction")', code, fixed = TRUE)), 1L, info = helper_in)
    # Nothing is left as a comment that could be uncommented into a second reporter either.
    expect_false(any(grepl(".bm_progress", upgraded, fixed = TRUE)), info = helper_in)
  }
})

test_that("an empty report section reads None, never a blank entry", {
  root <- migration_study_fixture()
  # Nothing unplaced and nothing new: the current template against its own copy.
  job <- upgrade_job(add_job("dc", "cohort", "eda", dir = root, qualifier = "general"))
  report <- readLines(sub("[.]qmd$", "-upgrade.md", job))
  section <- function(title) {
    from <- which(report == paste("##", title)) + 1L
    to <- c(grep("^## ", report), length(report) + 1L)
    report[from:(to[to > from][1L] - 1L)]
  }
  expect_true("None." %in% section("Not placed"))
  expect_true("None." %in% section("New"))
  expect_false(any(grepl("``|line $", report)))
})

test_that("the job's own description is carried in place of the template's comment", {
  root <- migration_study_fixture()
  job <- add_job("dc", "cohort", "eda", dir = root, qualifier = "general")
  token <- paste0("ED", "IT", ":")
  lines <- readLines(job)
  i <- grep(paste0("^<!-- ", token, " name the job"), lines)
  expect_length(i, 1L)
  lines <- c(lines[seq_len(i - 1L)], "This job replaces the cohort's", "first look, `old/eda.sas`.", lines[-i])
  writeLines(lines, job)
  upgraded <- readLines(upgrade_job(job))
  expect_length(grep("^This job replaces the cohort's$", upgraded), 1L)
  expect_false(any(grepl(paste0("^<!-- ", token, " name the job"), upgraded)))
  report <- readLines(sub("[.]qmd$", "-upgrade.md", job))
  expect_true(any(grepl("^Carried from the old job", report)))
  expect_false(any(grepl("first look", report)))
})

test_that("a description still unwritten stays the template's comment, written once", {
  root <- migration_study_fixture()
  job <- upgrade_job(add_job("dc", "cohort", "eda", dir = root, qualifier = "general"))
  token <- paste0("ED", "IT", ":")
  expect_length(grep(paste0("^<!-- ", token, " name the job"), readLines(job)), 1L)
})

test_that("a description is carried from a job scaffolded before add_job() stamped it", {
  root <- migration_study_fixture()
  path <- old_rfs_job(root)
  lines <- readLines(path)
  i <- grep("^<!-- EDIT: name the job", lines)
  lines <- c(lines[seq_len(i - 1L)], "Replaces `rf.dead.sas`, on every candidate.", lines[-(i:(i + 2L))])
  writeLines(lines, path)
  upgraded <- readLines(upgrade_job(path))
  expect_length(grep("^Replaces `rf.dead.sas`, on every candidate[.]$", upgraded), 1L)
  expect_false(any(grepl("^<!-- EDIT: name the job", upgraded)))
})

test_that("comment lines a study added above a choice are listed for review", {
  root <- migration_study_fixture()
  job <- add_job("dc", "cohort", "eda", dir = root, qualifier = "general")
  lines <- readLines(job)
  i <- grep("^DATASET <- ", lines)
  lines <- c(lines[seq_len(i - 1L)], "# The day-level set, same-day pairs averaged;", "# see datasets/bd.day.R.",
             lines[-seq_len(i - 1L)])
  writeLines(lines, job)
  report <- readLines(sub("[.]qmd$", "-upgrade.md", upgrade_job(job)))
  expect_true(any(grepl(paste0("^- `DATASET`, old lines ", i, ", ", i + 1L, ": comment"), report)))
  expect_false(any(grepl("same-day", report)))
  # Only DATASET: the template's own comments above a choice are not listed.
  expect_length(grep("^- `[A-Z_]+`, old line", report), 1L)
})

test_that("a rewritten placeholder line after the comment is carried as the description", {
  root <- migration_study_fixture()
  job <- add_job("dc", "cohort", "general", dir = root, qualifier = "general")
  lines <- readLines(job)
  i <- grep("^<!-- EDIT: name the job", lines)
  j <- grep("^Replaces `descriptive/dc.general`[.]$", lines)
  expect_identical(j, i + 2L)
  lines[[j]] <- "Replaces `descriptive/dc.cohort.sas`."
  writeLines(lines[-i], job)
  upgraded <- readLines(upgrade_job(job))
  expect_length(grep("^Replaces `descriptive/dc.cohort.sas`[.]$", upgraded), 1L)
  expect_false(any(grepl("^Replaces `descriptive/dc.general`[.]$|^<!-- EDIT: name the job", upgraded)))
})

test_that("an older template's wording of the comment, untouched, is still open", {
  root <- migration_study_fixture()
  job <- add_job("dc", "cohort", "eda", dir = root, qualifier = "general")
  lines <- readLines(job)
  i <- grep("^<!-- EDIT: name the job", lines)
  lines[[i]] <- "<!-- EDIT: say which job this replaces. -->"
  writeLines(lines, job)
  upgraded <- readLines(upgrade_job(job))
  expect_length(grep("^<!-- EDIT: name the job", upgraded), 1L)
  expect_false(any(grepl("say which job", upgraded)))
  report <- readLines(sub("[.]qmd$", "-upgrade.md", job))
  expect_true(any(grepl("^The old job had not written it", report)))
})

test_that("a job whose template had no comment there keeps the current template's", {
  root <- migration_study_fixture()
  job <- add_job("dc", "cohort", "eda", dir = root, qualifier = "general")
  lines <- readLines(job)
  i <- grep("^<!-- EDIT: name the job", lines)
  writeLines(lines[-(i:(i + 1L))], job)
  upgraded <- readLines(upgrade_job(job))
  expect_length(grep("^<!-- EDIT: name the job", upgraded), 1L)
  report <- readLines(sub("[.]qmd$", "-upgrade.md", job))
  expect_true(any(grepl("^Not found in the old job", report)))
})
