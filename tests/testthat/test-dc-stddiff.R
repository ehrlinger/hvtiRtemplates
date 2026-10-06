# dc-stddiff: the balance table. The derive chunk is run against synthetic data
# so each study choice is tested without a render, and one render proves the
# whole job, figure included, runs end to end. scaffold_job() is in
# helper-migration.R.

stddiff_chunk <- function(label) {
  lines <- readLines(template_path("dc", "stddiff"), warn = FALSE)
  start <- match(paste0("#| label: ", label), lines)
  end <- start + match("```", lines[-seq_len(start)])
  parse(text = lines[seq.int(start + 1L, end - 1L)])
}

stddiff_data <- function() {
  i <- seq_len(60L)
  data.frame(
    ccfid = 1000L + i,
    tavr = i %% 2L,
    arm = c("surgical", "transcatheter", "medical")[1L + i %% 3L],
    age = 50 + (i %% 7L) * 3 + (i %% 2L) * 4,
    female = as.integer(i %% 3L == 0L),
    nyha = 1L + i %% 4L,
    hx_chf = as.integer(i %% 5L == 0L),
    race = c("a", "b", "c")[1L + i %% 3L],
    match = as.integer(i <= 40L),
    mtwt = 0.5 + (i %% 3L) / 4
  )
}

# Run the template's own study choices, then the overrides, then derive.
run_stddiff <- function(..., d = stddiff_data()) {
  testthat::skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.5")
  record <- structure(data.frame(step = character(), value = character()),
                      selection = list(id = "ccfid", key = "ccfid"))
  env <- list2env(list(d = d, job_data = list(record = record)), parent = globalenv())
  eval(stddiff_chunk("edit-study-choices"), envir = env)
  overrides <- list(...)
  for (nm in names(overrides)) assign(nm, overrides[[nm]], envir = env)
  eval(stddiff_chunk("derive"), envir = env)
  env
}

test_that("the unadjusted comparison is ps_stddiff() on the whole cohort", {
  env <- run_stddiff(GAUSSIAN = "age", NONG_ORD = "nyha", BINARY = "hx_chf", CATEGORICAL = "race")
  expect_named(env$results, "Unadjusted")
  direct <- hvtiRpropensity::ps_stddiff(stddiff_data(), treatment_col = "tavr", gaussian = "age",
                                        nong_ord = "nyha", binary = "hx_chf", categorical = "race")
  expect_equal(env$balance$Unadjusted, direct$tables$stddiff$stddiff)
  expect_identical(env$balance$variable, c("age", "nyha", "hx_chf", "race"))
  expect_length(env$perm, 0L)
})

test_that("MATCH and WEIGHT add the matched and weighted comparisons", {
  env <- run_stddiff(MATCH = "match", WEIGHT = "mtwt")
  expect_named(env$results, c("Unadjusted", "Matched", "Weighted"))
  d <- stddiff_data()
  matched <- hvtiRpropensity::ps_stddiff(d[d$match == 1L, ], "tavr", gaussian = "age", binary = NULL)
  expect_equal(env$balance$Matched[[1L]], matched$tables$stddiff$stddiff[[1L]])
  weighted <- hvtiRpropensity::ps_stddiff(d, "tavr", gaussian = "age", weight_col = "mtwt")
  expect_equal(env$balance$Weighted[[1L]], weighted$tables$stddiff$stddiff[[1L]])
  expect_identical(env$group_counts$comparison, c("Unadjusted", "Matched", "Weighted"))
  expect_equal(env$group_counts[[2L]], c(30, 20, 30))
  expect_equal(env$group_counts[[5L]][[3L]], sum(d$mtwt[d$tavr == 1L]))
})

test_that("GROUP_1 recodes a two-valued group, and three values are refused", {
  d <- stddiff_data()
  pair <- d[d$arm != "medical", ]
  env <- run_stddiff(GROUP = "arm", GROUP_1 = "transcatheter", d = pair)
  expect_identical(unname(env$group_names), c("surgical", "transcatheter"))
  expect_identical(env$d$.stddiff_group, as.integer(pair$arm == "transcatheter"))
  expect_error(run_stddiff(GROUP = "arm", GROUP_1 = "transcatheter"),
               "exactly two values.*the data hold 3.*keep one pair with WHERE")
})

test_that("a bad choice stops by name before ps_stddiff() runs", {
  expect_error(run_stddiff(GAUSSIAN = c("age", "nope"), MATCH = "zilch"), "Unknown column\\(s\\): zilch, nope")
  expect_error(run_stddiff(GAUSSIAN = "age", BINARY = "age"), "one type only: age")
  expect_error(run_stddiff(GAUSSIAN = c("age", "ccfid")), "Not a covariate.*ccfid")
  expect_error(run_stddiff(GAUSSIAN = character(), BINARY = character()), "at least one variable")
  expect_error(run_stddiff(MATCH = "race"), "MATCH must be a 0/1")
  expect_error(run_stddiff(N_PERM = 2.5), "N_PERM must be 0")
})

test_that("the permutation reference skips the weighted comparison", {
  env <- run_stddiff(MATCH = "match", WEIGHT = "mtwt", N_PERM = 20L)
  expect_named(env$perm, c("Unadjusted", "Matched"))
  expect_equal(env$perm$Unadjusted$observed, env$balance$Unadjusted)
  again <- run_stddiff(MATCH = "match", WEIGHT = "mtwt", N_PERM = 20L)
  expect_identical(again$perm, env$perm)
})

test_that("dc-stddiff renders, figure and all", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.5")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- scaffold_job("dc", "stddiff", list(
    "^ANALYSIS_SET <- " = "ANALYSIS_SET <- NULL",
    "^GROUP <- " = "GROUP <- \"treatment\"",
    "^GAUSSIAN    <- " = "GAUSSIAN    <- c(\"age\", \"bmi\")",
    "^BINARY      <- " = "BINARY      <- \"hx_chf\"",
    "^CATEGORICAL <- " = "CATEGORICAL <- \"race_grp\"",
    "^WEIGHT <- " = "WEIGHT <- \"iv_opyrs\"",
    "^N_PERM <- " = "N_PERM <- 50L"
  ))
  quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
  html <- sub("[.]qmd$", ".html", s$job)
  expect_true(file.exists(html))
  out <- paste(readLines(html, warn = FALSE), collapse = "\n")
  expect_match(out, "Standardized difference of each variable", fixed = TRUE)
  expect_match(out, "Unadjusted: observed difference", fixed = TRUE)
  expect_match(out, "The weighted comparison has no reference", fixed = TRUE)
  png <- list.files(file.path(s$root, "graphs"), pattern = "^dc-stddiff-balance[.]png$",
                    recursive = TRUE, full.names = TRUE)
  expect_length(png, 1L)
  expect_gt(file.info(png)$size, 1000)
})
