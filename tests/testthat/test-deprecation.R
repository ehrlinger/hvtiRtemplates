# Two ways a template name retires, both driven by the catalog rather than by a
# name in the code. A template marked `deprecated_by` still ships and warns. A
# template listed under `renamed` is gone from disk, and its old name resolves
# to the new one with the same class of warning. dp-eda and dp-trends were
# renamed dc-eda and dc-trends on 2026-10-10. dp-gfup, deprecated in favor of
# dc-gfup in 1.3.0, and dp-postage, deprecated in favor of dp-eda in 1.2.3, are
# removed.

# The value of `expr`, and every warning it raised, muffled.
caught_warnings <- function(expr) {
  caught <- list()
  value <- withCallingHandlers(expr, warning = function(w) {
    caught[[length(caught) + 1L]] <<- w
    invokeRestart("muffleWarning")
  })
  list(value = value, warnings = caught)
}

# The one deprecation warning a call raised, or a failure naming how many.
expect_one_deprecation <- function(result, pattern) {
  deprecated <- Filter(function(w) inherits(w, "hvtiRtemplates_deprecated"), result$warnings)
  testthat::expect_length(deprecated, 1L)
  if (length(deprecated)) testthat::expect_match(conditionMessage(deprecated[[1L]]), pattern)
}

test_that("the catalog lists the two renames, and marks nothing deprecated", {
  renames <- hvtiRtemplates:::.template_renames()
  expect_identical(renames$from, c("dp-eda", "dp-trends"))
  expect_identical(renames$to, c("dc-eda", "dc-trends"))
  expect_identical(renames$from_folder, c("descriptive", "graphs"))
  shipped <- sub(".", "-", template_list()$name, fixed = TRUE)
  expect_true(all(renames$to %in% shipped))
  expect_false(any(renames$from %in% shipped))
  expect_true(all(is.na(template_catalog()$deprecated_by)))
})

test_that("template_path() takes an old name, warns once naming the new one, and returns the new template", {
  for (q in c("eda", "trends")) {
    for (name in list(c("dp", q), paste0("dp.", q), paste0("dp-", q))) {
      got <- caught_warnings(do.call(template_path, as.list(name)))
      expect_identical(basename(got$value), paste0("dc-", q, ".qmd"), info = name)
      expect_one_deprecation(got, paste0("^template_path\\(\\): dp[.]", q, " is deprecated in favor of dc[.]", q,
                                         "[.] Renamed on 2026-10-10.*removed in the one after[.]$"))
    }
  }
})

test_that("add_job() under an old name warns once and scaffolds the dc template", {
  root <- migration_study_fixture(NULL)
  got <- caught_warnings(add_job("dp.trends", "cohort", "eda", dir = root))
  expect_one_deprecation(got, "^add_job\\(\\): dp[.]trends is deprecated in favor of dc[.]trends")
  # dc-trends is written to descriptive, where dp-trends was written to graphs.
  expect_identical(normalizePath(got$value), normalizePath(file.path(root, "descriptive", "dc.trends.cohort.eda.qmd")))
  # The same job, line for line, that the new name scaffolds.
  same <- add_job("dc.trends", "cohort", "eda", dir = migration_study_fixture(NULL))
  expect_identical(readLines(got$value), readLines(same))
  expect_false(dir.exists(file.path(root, "graphs", "cohort-eda")))
  expect_length(list.files(file.path(root, "graphs"), "[.]qmd$"), 0L)

  got <- caught_warnings(add_job("dp", "cohort", "eda", dir = root, qualifier = "eda"))
  expect_one_deprecation(got, "^add_job\\(\\): dp[.]eda is deprecated in favor of dc[.]eda")
  expect_identical(normalizePath(got$value), normalizePath(file.path(root, "descriptive", "dc.eda.cohort.eda.qmd")))
})

test_that("open_job() under an old name warns once, in its own name, and scaffolds the dc template", {
  root <- migration_study_fixture(NULL)
  got <- caught_warnings(suppressMessages(open_job("dp", "other", "eda", dir = root, qualifier = "trends")))
  expect_one_deprecation(got, "^open_job\\(\\): dp[.]trends is deprecated in favor of dc[.]trends")
  expect_identical(normalizePath(got$value), normalizePath(file.path(root, "descriptive", "dc.trends.other.eda.qmd")))
})

test_that("migrate_job() warns for an old name the caller passes, not for one a legacy source carries", {
  root <- migration_study_fixture("dc-trends")
  source <- file.path(root, "graphs", "dp.trends.sas")
  got <- caught_warnings(migrate_job(source, "cohort", "eda", "dp", "trends", dir = root))
  expect_one_deprecation(got, "^migrate_job\\(\\): dp[.]trends is deprecated in favor of dc[.]trends")
  expect_identical(normalizePath(got$value), normalizePath(file.path(root, "descriptive", "dc.trends.cohort.eda.qmd")))
  # The converter that ran is dc-trends's: the source's year rule reached the job.
  expect_true("d$year <- floor(d$iv_opyrs) + 1985" %in% readLines(got$value))

  # The corpus names its trends jobs dp.trends.*, and always will.
  root <- migration_study_fixture("dc-trends")
  source <- file.path(root, "graphs", "dp.trends.sas")
  got <- caught_warnings(migrate_job(source, "cohort", "eda", dir = root))
  expect_length(Filter(function(w) inherits(w, "hvtiRtemplates_deprecated"), got$warnings), 0L)
  expect_identical(normalizePath(got$value), normalizePath(file.path(root, "descriptive", "dc.trends.cohort.eda.qmd")))
  # Naming only the qualifier leaves the prefix to the source's name, so it maps silently too.
  root <- migration_study_fixture("dc-trends")
  source <- file.path(root, "graphs", "dp.trends.sas")
  got <- caught_warnings(migrate_job(source, "cohort", "eda", qualifier = "trends", dir = root))
  expect_length(Filter(function(w) inherits(w, "hvtiRtemplates_deprecated"), got$warnings), 0L)
  expect_identical(normalizePath(got$value), normalizePath(file.path(root, "descriptive", "dc.trends.cohort.eda.qmd")))
  # So does a caller who names only the prefix, as before the rename.
  root <- migration_study_fixture("dc-trends")
  source <- file.path(root, "graphs", "dp.trends.sas")
  got <- caught_warnings(migrate_job(source, "cohort", "eda", prefix = "dp", dir = root))
  expect_one_deprecation(got, "^migrate_job\\(\\): dp[.]trends is deprecated")
  expect_identical(normalizePath(got$value), normalizePath(file.path(root, "descriptive", "dc.trends.cohort.eda.qmd")))
})

# A dp.trends job scaffolded before the rename sits in graphs/. Its name is the
# one study authors and saved outputs know, so it is opened, not duplicated.
test_that("an existing dp.trends job is opened under either name, and never duplicated", {
  for (stem in c("dp.trends.cohort.eda", "cohort-eda-dp-trends")) {
    s <- list(root = migration_study_fixture(NULL))
    s$old <- file.path(s$root, "graphs", paste0(stem, ".qmd"))
    file.copy(template_path("dc.trends"), s$old)
    expect_message(opened <- open_job("dc", "cohort", "eda", dir = s$root, qualifier = "trends"),
                   "already exists; opening it unchanged")
    expect_identical(normalizePath(opened), normalizePath(s$old), info = stem)
    got <- caught_warnings(suppressMessages(open_job("dp.trends", "cohort", "eda", dir = s$root)))
    expect_identical(normalizePath(got$value), normalizePath(s$old), info = stem)
    expect_one_deprecation(got, "^open_job\\(\\): dp[.]trends")
    expect_error(add_job("dc.trends", "cohort", "eda", dir = s$root),
                 "already exists as '[^']*graphs/[^']*dp[.-]trends[^']*', under the template's name before it was renamed")
    expect_error(suppressWarnings(add_job("dp.trends", "cohort", "eda", dir = s$root), classes = "hvtiRtemplates_deprecated"),
                 "under the template's name before it was renamed")
    expect_false(file.exists(file.path(s$root, "descriptive", "dc.trends.cohort.eda.qmd")), info = stem)
  }
  # A different set is a different job, and scaffolds in descriptive as usual.
  made <- suppressMessages(open_job("dc", "other", "eda", dir = s$root, qualifier = "trends"))
  expect_identical(normalizePath(made), normalizePath(file.path(s$root, "descriptive", "dc.trends.other.eda.qmd")))
})

test_that("migrate_job() refuses to write a second copy of an existing dp.trends job", {
  root <- migration_study_fixture("dc-trends")
  old <- file.path(root, "graphs", "dp.trends.cohort.eda.qmd")
  file.copy(template_path("dc.trends"), old)
  expect_error(migrate_job(file.path(root, "graphs", "dp.trends.sas"), "cohort", "eda", "dc", "trends", dir = root),
               "under the template's name before it was renamed")
  expect_false(file.exists(file.path(root, "descriptive", "dc.trends.cohort.eda.qmd")))
})

test_that("an existing dp.trends job in graphs still renders, with its figures embedded", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  # A migrated job carries real choices for the fixture's data. Moved to where
  # and as what a dp-trends job was scaffolded, it is the job a study holds.
  root <- migration_study_fixture("dc-trends")
  job <- migrate_job(file.path(root, "graphs", "dp.trends.sas"), "cohort", "eda", "dc", "trends", dir = root)
  .resolve_fixture_markers(job, readLines(testthat::test_path("fixtures-migration", "dc-trends", "review-markers.txt")))
  old <- file.path(root, "graphs", "dp.trends.cohort.eda.qmd")
  expect_true(file.rename(job, old))
  quarto::quarto_render(old, execute_dir = dirname(old), quiet = TRUE)
  html <- sub("[.]qmd$", ".html", old)
  expect_true(file.exists(html))
  figures <- file.path(root, "graphs", "cohort-eda", c("dc-trends-hx_chf-all.png", "dc-trends-lvmassi-all.png"))
  expect_true(all(file.exists(figures)))
  # Each figure link resolved from graphs/, so each image was embedded.
  expect_gte(lengths(regmatches(paste(readLines(html, warn = FALSE), collapse = "\n"),
                                gregexpr("data:image/png;base64", paste(readLines(html, warn = FALSE), collapse = "\n")))), 2L)
  expect_true(file.exists(sub("[.]qmd$", ".provenance.json", old)))
})

test_that("dp-gfup is removed, and asking for it names dc.gfup", {
  root <- migration_study_fixture(NULL)
  calls <- list(quote(add_job("dp.gfup", "cohort", "eda", dir = root)),
                quote(add_job("dp", "cohort", "eda", dir = root, qualifier = "gfup")),
                quote(open_job("dp", "cohort", "eda", dir = root, qualifier = "gfup")),
                quote(template_path("dp", "gfup")),
                quote(template_path("dp-gfup")))
  for (call in calls) {
    expect_error(eval(call), "unknown template: dp[.]gfup[.] Qualified 'gfup': dc[.]gfup[.] Available: ",
                 info = deparse(call))
  }
  expect_length(list.files(root, "gfup", recursive = TRUE), 0L)
  expect_false("dp.gfup" %in% template_list()$name)
  expect_false(file.exists(file.path(system.file("templates", package = "hvtiRtemplates"), "40_graphs", "dp-gfup.qmd")))
})

test_that("the removed dp-postage is an unknown template, with no namesake to offer", {
  root <- migration_study_fixture(NULL)
  for (call in list(quote(add_job("dp.postage", "cohort", "eda", dir = root)),
                    quote(add_job("dp", "cohort", "eda", dir = root, qualifier = "postage")),
                    quote(template_path("dp", "postage")))) {
    expect_error(eval(call), "unknown template: dp[.]postage[.] Available: ", info = deparse(call))
  }
  expect_length(list.files(root, "postage", recursive = TRUE), 0L)
  expect_false("dp.postage" %in% template_list()$name)
})

test_that("a supported template does not warn", {
  root <- migration_study_fixture(NULL)
  expect_no_warning(template_path("dc", "eda"))
  expect_no_warning(template_path("dc.trends"))
  expect_no_warning(add_job("dc", "cohort", "eda", dir = root, qualifier = "eda"))
})

test_that("the deprecation warning follows the catalog, whichever template it marks", {
  catalog <- template_catalog()
  catalog$deprecated_by[catalog$prefix == "ac"] <- "hz"
  catalog$deprecation_note[catalog$prefix == "ac"] <- "A test note."
  local_mocked_bindings(template_catalog = function() catalog)
  expect_warning(template_path("ac"), "ac is deprecated in favor of hz. A test note.", fixed = TRUE)
  catalog$deprecated_by <- NA_character_
  expect_no_warning(template_path("dc", "gfup"))
})

test_that("a rename follows the catalog's renamed list, whichever name it retires", {
  renames <- data.frame(from = "zz-gfup", to = "dc-gfup", from_folder = "graphs", note = "A test note.",
                        stringsAsFactors = FALSE)
  local_mocked_bindings(.template_renames = function() renames)
  expect_warning(path <- template_path("zz.gfup"), "zz.gfup is deprecated in favor of dc.gfup. A test note.",
                 fixed = TRUE, class = "hvtiRtemplates_deprecated")
  expect_identical(basename(path), "dc-gfup.qmd")
  expect_error(template_path("dp.trends"), "unknown template: dp[.]trends[.] Qualified 'trends': dc[.]trends")
})
