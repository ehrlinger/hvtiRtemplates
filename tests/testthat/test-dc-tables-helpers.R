template <- system.file(
  "templates", "10_descriptive", "dc-tables.qmd",
  package = "hvtiRtemplates"
)
if (!nzchar(template)) {
  template <- testthat::test_path(
    "..", "..", "inst", "templates", "10_descriptive", "dc-tables.qmd"
  )
}
template_lines <- readLines(template, warn = FALSE)
helper_label <- grep("^#\\| label: helpers$", template_lines)
helper_end <- helper_label + which(template_lines[-seq_len(helper_label)] == "```")[[1L]]
eval(parse(text = template_lines[(helper_label + 1L):(helper_end - 1L)]))

d <- data.frame(
  age = c(55.5, 61, 70.2, 48, 66, 59, 72.1, 50),
  female = c(0, 1, 1, 0, 1, 0, 0, 1),
  flag = c(TRUE, FALSE, TRUE, TRUE, FALSE, NA, TRUE, FALSE),
  nyha = c(1, 2, 2, 3, 4, 1, 2, 3),
  race = c("W", "B", "W", "O", "W", "W", "B", "W"),
  code = c(1, 2, 1, 2, 2, 1, 1, 2)
)

test_that("classify_buckets sorts by the data", {
  b <- classify_buckets(d, names(d))
  expect_setequal(b$continuous, "age")
  expect_setequal(b$binary, c("female", "flag"))
  expect_setequal(b$categorical, c("nyha", "race", "code"))
})

test_that("overrides win over the data", {
  b <- classify_buckets(d, names(d), overrides = list(continuous = "nyha"))
  expect_true("nyha" %in% b$continuous)
  expect_false("nyha" %in% b$categorical)
})

test_that("override buckets must be explicitly and uniquely named", {
  expect_error(
    classify_buckets(d, names(d), overrides = list("nyha")),
    "named"
  )
  duplicate_names <- structure(
    list("age", "nyha"),
    names = c("continuous", "continuous")
  )
  expect_error(
    classify_buckets(d, names(d), overrides = duplicate_names),
    "unique"
  )
})

test_that("binary inference matches hv_tbl_summary's accepted data", {
  binary_data <- data.frame(
    character_yes_no = c("Yes", "No", "Yes", NA),
    factor_yes_no = factor(c("No", "Yes", "No", NA), levels = c("No", "Yes")),
    all_zero = rep(0, 4)
  )

  b <- classify_buckets(binary_data, names(binary_data))

  expect_setequal(b$binary, c("character_yes_no", "factor_yes_no"))
  expect_identical(b$categorical, "all_zero")
})

test_that("every variable lands in exactly one bucket", {
  b <- classify_buckets(d, names(d))
  expect_setequal(unlist(b, use.names = FALSE), names(d))
})

# ---- %stddiff's standardized difference --------------------------------------
# %summarytable sent CON1 (mean +/- SD) to %stddiff as GAUSSIAN, CON2, CON3 and
# ORD1 as NONG_ORD, CAT1 as BINARY and CAT2 as CATG. stddiff_values() must do the
# same with dc-tables' buckets, MEAN_SD and ORDINAL, so each expectation below is
# a direct ps_stddiff() call with the buckets the macro would have used.

sd_data <- data.frame(
  grp = rep(c(0, 1), each = 20),
  age = c(seq(50, 69), seq(55, 93, by = 2)),
  creat = c(exp(seq(0, 1.9, by = 0.1)), exp(seq(0.5, 2.4, by = 0.1))),
  female = rep(c(0, 1, 1, 0, 1), 8),
  smoker = rep(c("Yes", "No", "No", "No"), 10),
  nyha = rep(c(1, 2, 3, 4, 2, 2, 3, 1), 5),
  race = rep(c("W", "B", "W", "O", "W"), 8)
)
sd_buckets <- list(continuous = c("age", "creat"), binary = c("female", "smoker"),
                   categorical = c("nyha", "race"))

expected_stddiff <- function(data, gaussian, nong_ord, binary, categorical, treated_level = NULL) {
  r <- hvtiRpropensity::ps_stddiff(data, treatment_col = "grp", gaussian = gaussian, nong_ord = nong_ord,
                                   binary = binary, categorical = categorical, treated_level = treated_level)
  s <- r$tables$stddiff
  stats::setNames(sprintf("%.1f", 100 * s$stddiff), s$variable)
}

test_that("stddiff_values sends each bucket to the %stddiff type %summarytable used", {
  skip_if_not_installed("hvtiRpropensity")
  yes_no <- transform(sd_data, smoker = smoker == "Yes")
  got <- stddiff_values(sd_data, "grp", sd_buckets, mean_sd = "age", ordinal = "nyha")
  want <- expected_stddiff(yes_no, gaussian = "age", nong_ord = c("creat", "nyha"),
                           binary = c("female", "smoker"), categorical = "race")
  expect_identical(got[names(want)], want)
  expect_setequal(names(got), unlist(sd_buckets, use.names = FALSE))
})

test_that("a continuous variable not shown as mean +/- SD is ranked, not treated as Gaussian", {
  skip_if_not_installed("hvtiRpropensity")
  got <- stddiff_values(sd_data, "grp", sd_buckets, mean_sd = character(0), ordinal = character(0))
  ranked <- expected_stddiff(transform(sd_data, smoker = smoker == "Yes"), gaussian = NULL,
                             nong_ord = c("age", "creat"), binary = c("female", "smoker"),
                             categorical = c("nyha", "race"))
  expect_identical(got[["age"]], ranked[["age"]])
  expect_identical(got[["nyha"]], ranked[["nyha"]])
})

test_that("GROUP_1 names the treated value of a two-valued group", {
  skip_if_not_installed("hvtiRpropensity")
  labeled <- transform(sd_data, grp = ifelse(grp == 1, "tavr", "savr"))
  got <- stddiff_values(labeled, "grp", sd_buckets, mean_sd = "age", ordinal = "nyha", group_1 = "tavr")
  want <- stddiff_values(sd_data, "grp", sd_buckets, mean_sd = "age", ordinal = "nyha")
  expect_identical(got, want)
})

test_that("stddiff_values refuses what %stddiff cannot compute", {
  skip_if_not_installed("hvtiRpropensity")
  expect_error(stddiff_values(sd_data, NULL, sd_buckets), "BY")
  three <- transform(sd_data, grp = rep(c(0, 1, 2, 1), 10))
  expect_error(stddiff_values(three, "grp", sd_buckets), "exactly two")
  expect_error(stddiff_values(sd_data, "grp", sd_buckets, ordinal = "age"), "ORDINAL")
  expect_error(stddiff_values(sd_data, "grp", sd_buckets, mean_sd = "nyha"), "MEAN_SD")
})

test_that("an ordered factor in ORDINAL is ranked by its level order", {
  skip_if_not_installed("hvtiRpropensity")
  as_factor <- transform(sd_data, nyha = factor(c("I", "II", "III", "IV")[nyha], levels = c("I", "II", "III", "IV")))
  got <- stddiff_values(as_factor, "grp", sd_buckets, mean_sd = "age", ordinal = "nyha")
  want <- stddiff_values(sd_data, "grp", sd_buckets, mean_sd = "age", ordinal = "nyha")
  expect_identical(got, want)
  as_text <- transform(sd_data, nyha = c("I", "II", "III", "IV")[nyha])
  expect_error(stddiff_values(as_text, "grp", sd_buckets, ordinal = "nyha"), "ORDINAL.*factor")
})

test_that("a two-valued BY that is not 0/1 asks for GROUP_1 by name", {
  skip_if_not_installed("hvtiRpropensity")
  labeled <- transform(sd_data, grp = ifelse(grp == 1, "tavr", "savr"))
  expect_error(stddiff_values(labeled, "grp", sd_buckets), "GROUP_1")
  expect_error(stddiff_values(labeled, "grp", sd_buckets, group_1 = "tarv"), "GROUP_1")
})

test_that("a 0/1 group stored as text or a factor needs no GROUP_1", {
  skip_if_not_installed("hvtiRpropensity")
  want <- stddiff_values(sd_data, "grp", sd_buckets, mean_sd = "age", ordinal = "nyha")
  for (as_type in list(as.character, function(x) factor(x, levels = c(0, 1)))) {
    coded <- transform(sd_data, grp = as_type(grp))
    expect_identical(stddiff_values(coded, "grp", sd_buckets, mean_sd = "age", ordinal = "nyha"), want)
  }
})

test_that("the commented GROUPS example uncomments to a grouping the template accepts", {
  # The example is there to be uncommented. Commented out, nothing parses it,
  # so a stray edit would ship a block that fails on the first job that uses it.
  begin <- grep("^# GROUPS-EXAMPLE-BEGIN$", template_lines)
  end <- grep("^# GROUPS-EXAMPLE-END$", template_lines)
  expect_length(begin, 1L)
  expect_length(end, 1L)
  block <- template_lines[(begin + 1L):(end - 1L)]
  expect_true(all(startsWith(block, "# ")))
  env <- new.env()
  eval(parse(text = substring(block, 3L)), envir = env)
  groups <- env$GROUPS
  expect_type(groups, "list")
  expect_true(all(nzchar(names(groups))))
  expect_true(all(vapply(groups, is.character, logical(1))))
  # A variable in two groups would be two rows of one table.
  vars <- unlist(groups, use.names = FALSE)
  expect_false(anyDuplicated(tolower(vars)) > 0L)
  # read_built() lowercases every column name, and GROUPS is matched exactly, so a capital never matches.
  expect_identical(vars, tolower(vars))
  # The example sits above the block migrate_job() rewrites, so a migrated job keeps it.
  expect_lt(end, grep("^# MIGRATE-BEGIN: dc-tables-config$", template_lines))
})

test_that("the commented GROUPS example is the house ODS list dc-eda draws", {
  # dc-tables keeps an inline copy a study author edits by deleting rows; the
  # CSV behind .ods_groups() is the source. Edit both, or this fails.
  begin <- grep("^# GROUPS-EXAMPLE-BEGIN$", template_lines)
  end <- grep("^# GROUPS-EXAMPLE-END$", template_lines)
  env <- new.env()
  eval(parse(text = substring(template_lines[(begin + 1L):(end - 1L)], 3L)), envir = env)
  expect_identical(env$GROUPS, hvtiRtemplates:::.ods_groups())
})

test_that(".ods_groups() keeps the columns a dataset has, and drops a section left empty", {
  groups <- hvtiRtemplates:::.ods_groups(c("AGE", "female", "dead", "not_a_column"))
  expect_identical(groups, list(Demography = c("female", "age"), `Time-related Outcomes` = "dead"))
  expect_length(hvtiRtemplates:::.ods_groups(character()), 0L)
})
