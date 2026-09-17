trends_evidence <- function(root, lines = NULL) {
  if (is.null(lines)) lines <- readLines(file.path(root, "graphs", "dp.trends.sas"))
  list(root = root, source = data.frame(line = seq_along(lines), text = lines))
}

trends_chunk <- function(job, label) {
  lines <- readLines(job, warn = FALSE)
  start <- match(paste0("#| label: ", label), lines)
  end <- start + match("```", lines[-seq_len(start)])
  parse(text = lines[seq.int(start + 1L, end - 1L)])
}

trends_config <- function(result) {
  env <- new.env()
  for (region in c("dp-trends-data", "dp-trends-trends", "dp-trends-xbreaks")) {
    eval(parse(text = result$regions[[region]]), env)
  }
  env
}

test_that("migration render helper executes a trends job where current_input is readable", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  out <- render_migrated_fixture("dp-trends")
  expect_true(file.exists(sub("[.]qmd$", ".html", out$job)))
  expected <- file.path(out$root, "graphs", "cohort-eda", c("dp-trends-hx_chf-all.png", "dp-trends-lvmassi-all.png"))
  expect_true(all(expected %in% out$outputs))
  expect_true(all(file.info(expected)$size > 1000))
})

test_that("dp-trends migrates explicit year and ordered trend intent into executable chunks", {
  root <- migration_study_fixture("dp-trends")
  out <- migrate_job(file.path(root, "graphs", "dp.trends.sas"), "cohort", "eda", "dp", "trends", dir = root)
  txt <- readLines(out, warn = FALSE)
  expect_true("d$year <- floor(d$iv_opyrs) + 1985" %in% txt)
  expect_true("XBREAKS <- seq(1985, 2025, 5)" %in% txt)
  env <- list2env(list(.root = root, read_built = hvtiRutilities::read_built, study_config = hvtiRutilities::study_config))
  capture.output(eval(trends_chunk(out, "data"), env))
  eval(trends_chunk(out, "trends"), env)
  eval(trends_chunk(out, "helpers"), env)
  expect_identical(env$DATASET, "study")
  expect_equal(env$d$year, 1986:2025)
  expect_identical(names(env$TRENDS), c("hx_chf", "lvmassi"))
  expect_identical(env$TRENDS$hx_chf$kind, "percent")
  expect_identical(env$TRENDS$lvmassi$kind, "continuous")
  expect_equal(env$TRENDS$hx_chf$ylim, c(0, 100))
  expect_equal(env$TRENDS$lvmassi$ybreaks, seq(80, 140, 10))
  expect_equal(env$XBREAKS, seq(1985, 2025, 5))
  expect_identical(env$trend_long(env$d, env$TRENDS$hx_chf)$value, 100 * env$d$hx_chf)
  expect_identical(env$trend_long(env$d, env$TRENDS$lvmassi)$value, env$d$lvmassi)
  expect_identical(levels(env$trend_long(env$d, env$TRENDS$hx_chf)$series), "Heart failure")
  result <- hvtiRtemplates:::.migrate_dp_trends(trends_evidence(root), txt)
  expect_true(all(c(3:11, 21:22) %in% result$translated$line))
  expect_true(all(c(13:20) %in% result$ignored$line))
  expect_true(all(diff(result$translated$line) >= 0))
  expect_false(any(grepl("legacy-trends.png", txt, fixed = TRUE)))
})

test_that("dp-trends keeps inactive statements and unsupported filtering out of executable facts", {
  root <- migration_study_fixture("dp-trends")
  evidence <- trends_evidence(root)
  extra <- c(
    "/* %let percent=wrong; year=floor(other)+2000; */",
    "* set absent;", "%* label hx_chf='wrong';",
    "title 'year=floor(other)+2000; %let percent=wrong;';",
    "where female=1;", "if age>50;", "smooth.spline(year, hx_chf);"
  )
  evidence <- trends_evidence(root, c(evidence$source$text, extra))
  result <- hvtiRtemplates:::.migrate_dp_trends(evidence, readLines(template_path("dp", "trends")))
  env <- trends_config(result)
  expect_identical(env$DATASET, "study")
  expect_identical(names(env$TRENDS), c("hx_chf", "lvmassi"))
  expect_true(any(grepl("where female", result$unresolved$text, fixed = TRUE)))
  expect_true(any(grepl("if age", result$unresolved$text, fixed = TRUE)))
  expect_true(any(grepl("smooth.spline", result$ignored$text, fixed = TRUE)))
  expect_false(any(grepl("female|age>50|wrong|smooth.spline", result$regions)))
})

test_that("dp-trends refuses overwritten intent declarations and conflicting shared axes", {
  root <- migration_study_fixture("dp-trends")
  lines <- trends_evidence(root)$source$text
  result <- hvtiRtemplates:::.migrate_dp_trends(trends_evidence(root, c(lines, "%let percent=female;")), character())
  expect_identical(names(trends_config(result)$TRENDS), "lvmassi")
  expect_true(all(c(5L, 25L) %in% result$unresolved$line))
  lines[22L] <- "plot lvmassi*year / haxis=axis3 vaxis=axis3;"
  result <- hvtiRtemplates:::.migrate_dp_trends(trends_evidence(root, lines), character())
  expect_identical(trends_config(result)$XBREAKS, NULL)
  expect_true(all(c(21L, 22L) %in% result$unresolved$line))
})

test_that("dp-trends does not treat source transformations as registered measurements", {
  root <- migration_study_fixture("dp-trends")
  lines <- trends_evidence(root)$source$text
  result <- hvtiRtemplates:::.migrate_dp_trends(trends_evidence(root, c(lines, "hx_chf=1-hx_chf;")), character())
  expect_identical(names(trends_config(result)$TRENDS), "lvmassi")
  result <- hvtiRtemplates:::.migrate_dp_trends(trends_evidence(root, c(lines, "iv_opyrs=age/10;")), character())
  expect_match(result$regions[["dp-trends-year"]], "NA_real_", fixed = TRUE)
})

test_that("dp-trends executes its plotting engine and retains long-data and subgroup validation", {
  root <- migration_study_fixture("dp-trends")
  out <- migrate_job(file.path(root, "graphs", "dp.trends.sas"), "cohort", "eda", "dp", "trends", dir = root)
  env <- list2env(list(
    .root = root, read_built = hvtiRutilities::read_built, study_config = hvtiRutilities::study_config,
    ENDPOINT = "cohort", TYPE = "eda", hv_trends = hvtiPlotR::hv_trends, theme_hv_manuscript = hvtiPlotR::theme_hv_manuscript,
    labs = ggplot2::labs, scale_y_continuous = ggplot2::scale_y_continuous, scale_x_continuous = ggplot2::scale_x_continuous,
    coord_cartesian = ggplot2::coord_cartesian
  ))
  capture.output(eval(trends_chunk(out, "data"), env))
  eval(trends_chunk(out, "trends"), env)
  eval(trends_chunk(out, "helpers"), env)
  # Run the template's own set_path closure; only current_input is naturally
  # absent when chunks execute outside knitr, as its documented guard allows.
  eval(trends_chunk(out, "set"), env)
  output <- capture.output(eval(trends_chunk(out, "figures"), env))
  expect_true(all(file.exists(file.path(root, "graphs", "cohort-eda",
                                        c("dp-trends-hx_chf-all.png", "dp-trends-lvmassi-all.png")))))
  expect_true(any(grepl("40 of 40 rows drawn; 0 missing", output, fixed = TRUE)))
  bad <- env$d
  bad$hx_chf[1L] <- 2
  expect_error(env$trend_long(bad, env$TRENDS$hx_chf), "0/1")
  bad$hx_chf <- NULL
  expect_error(env$trend_long(bad, env$TRENDS$hx_chf), "not in the data")
  spec <- env$TRENDS$hx_chf
  spec$summary <- "median"
  expect_error(env$trend_long(env$d, spec), "not a prevalence")
  env$SUBGROUPS <- list(short = function(d) TRUE)
  expect_error(capture.output(eval(trends_chunk(out, "figures"), env)), "one TRUE/FALSE per patient")
  env$SUBGROUPS <- list(empty = function(d) rep(FALSE, nrow(d)))
  expect_error(capture.output(eval(trends_chunk(out, "figures"), env)), "selects no patients")
})

test_that("dp-trends cannot select a dataset from partial or contradictory SET evidence", {
  root <- migration_study_fixture("dp-trends")
  original <- trends_evidence(root)$source$text
  for (extra in c("set complete_cases;", "set built(obs=10);", "if flag then set absent;")) {
    result <- hvtiRtemplates:::.migrate_dp_trends(trends_evidence(root, c(original, extra)), character())
    expect_identical(trends_config(result)$DATASET, NA_character_)
    expect_true(any(grepl("EDIT:", result$regions, fixed = TRUE)))
  }
  named <- trends_evidence(root, sub("set built;", "set complete_cases;", original, fixed = TRUE))
  result <- hvtiRtemplates:::.migrate_dp_trends(named, character())
  expect_identical(trends_config(result)$DATASET, "complete_cases")
})

test_that("dp-trends leaves inferred origins and ambiguous or absent definitions for review", {
  root <- migration_study_fixture("dp-trends")
  lines <- trends_evidence(root)$source$text
  lines[4L] <- "year=floor(iv_opyrs); /* year origin: 1985 */"
  result <- hvtiRtemplates:::.migrate_dp_trends(trends_evidence(root, lines), character())
  expect_match(result$regions[["dp-trends-year"]], "floor(d$iv_opyrs) + 1985", fixed = TRUE)
  expect_match(result$regions[["dp-trends-year"]], "EDIT:", fixed = TRUE)
  expect_true(4L %in% result$unresolved$line)
  for (extra in c("year=floor(iv_opyrs)+2000;", "%let continuous=hx_chf;", "hx_chf=1-hx_chf;")) {
    result <- hvtiRtemplates:::.migrate_dp_trends(trends_evidence(root, c(lines, extra)), character())
    expect_true(any(grepl("EDIT:", result$regions, fixed = TRUE)))
    expect_true(extra %in% result$unresolved$text)
  }
  result <- hvtiRtemplates:::.migrate_dp_trends(trends_evidence(root, "set built;"), character())
  expect_identical(trends_config(result)$TRENDS, list())
  expect_identical(trends_config(result)$XBREAKS, NULL)
  expect_match(result$regions[["dp-trends-year"]], "NA_real_", fixed = TRUE)
})

test_that("dp-trends keeps procedure filters and additional class grouping unresolved", {
  root <- migration_study_fixture("dp-trends")
  original <- trends_evidence(root)$source$text
  unsupported <- c(
    "proc means data=trends(where=(female=1)) noprint;",
    "proc gplot data=annual(where=(female=1));",
    "class year female;"
  )
  for (statement in unsupported) {
    result <- hvtiRtemplates:::.migrate_dp_trends(trends_evidence(root, c(original, statement)), character())
    expect_true(statement %in% result$unresolved$text, info = statement)
    expect_false(statement %in% result$ignored$text, info = statement)
    expect_false(any(grepl("female", result$regions, fixed = TRUE)))
  }
})

test_that("dp-trends invalidates intent when any competing definition is unsupported", {
  root <- migration_study_fixture("dp-trends")
  original <- trends_evidence(root)$source$text
  for (statement in c("%let percent=;", "%let percent=%scan(hx_chf,1);", "%let percent=hx_chf--female;",
                      "%if flag %then %let percent=;")) {
    result <- hvtiRtemplates:::.migrate_dp_trends(trends_evidence(root, c(original, statement)), character())
    expect_identical(names(trends_config(result)$TRENDS), "lvmassi", info = statement)
    expect_true(all(c(5L, 25L) %in% result$unresolved$line), info = statement)
    expect_false(5L %in% result$translated$line, info = statement)
  }
  result <- hvtiRtemplates:::.migrate_dp_trends(trends_evidence(root, c(original, "%let continuous=;")), character())
  expect_identical(names(trends_config(result)$TRENDS), "hx_chf")
})

test_that("dp-trends inventories competing axis label and plot declarations before accepting values", {
  root <- migration_study_fixture("dp-trends")
  original <- trends_evidence(root)$source$text
  extra <- "axis1 order=(2000 to 2025 by 5) label=('Year');"
  result <- hvtiRtemplates:::.migrate_dp_trends(trends_evidence(root, c(original, extra)), character())
  expect_identical(trends_config(result)$XBREAKS, NULL)
  expect_true(all(c(9L, 21L, 22L, 25L) %in% result$unresolved$line))
  expect_false(any(c(9L, 21L, 22L) %in% result$translated$line))
  extra <- "axis2 label=('Patients');"
  result <- hvtiRtemplates:::.migrate_dp_trends(trends_evidence(root, c(original, extra)), character())
  expect_identical(trends_config(result)$TRENDS$hx_chf$ylim, NULL)
  expect_true(all(c(10L, 21L, 25L) %in% result$unresolved$line))
  extra <- "label lvmassi='LV mass' hx_chf='CHF';"
  result <- hvtiRtemplates:::.migrate_dp_trends(trends_evidence(root, c(original, extra)), character())
  expect_identical(trends_config(result)$TRENDS$hx_chf$labels, "hx_chf")
  expect_identical(trends_config(result)$TRENDS$lvmassi$labels, "lvmassi")
  expect_true(all(c(7L, 8L, 25L) %in% result$unresolved$line))
  extra <- "plot hx_chf*year / haxis=axis1 vaxis=axis2 overlay;"
  result <- hvtiRtemplates:::.migrate_dp_trends(trends_evidence(root, c(original, extra)), character())
  expect_identical(trends_config(result)$TRENDS$hx_chf$ybreaks, NULL)
  expect_true(all(c(21L, 25L) %in% result$unresolved$line))
})

test_that("dp-trends generates executable R for SAS names reserved or nonsyntactic in R", {
  root <- migration_study_fixture("dp-trends")
  original <- trends_evidence(root)$source$text
  for (field in c("repeat", "if", "next", "function", "_interval")) {
    lines <- gsub("iv_opyrs", field, original, fixed = TRUE)
    lines <- gsub("hx_chf", field, lines, fixed = TRUE)
    result <- hvtiRtemplates:::.migrate_dp_trends(trends_evidence(root, lines), character())
    expect_no_error(lapply(result$regions, function(x) parse(text = x)))
    env <- trends_config(result)
    env$d <- setNames(data.frame(c(1.25, 2.75)), field)
    eval(parse(text = result$regions[["dp-trends-year"]]), env)
    expect_equal(env$d$year, c(1986, 1987))
    expect_identical(names(env$TRENDS), c(field, "lvmassi"))
    expect_identical(env$TRENDS[[field]]$cols, field)
  }
})

test_that("dp-trends returns parseable candidate origins from multiline prose", {
  root <- migration_study_fixture("dp-trends")
  original <- trends_evidence(root)$source$text
  original[4L] <- "year=floor(iv_opyrs); /* Candidate only:\nyear origin: 1985\nconfirm before use. */"
  result <- hvtiRtemplates:::.migrate_dp_trends(trends_evidence(root, original), character())
  expect_no_error(lapply(result$regions, function(x) parse(text = x)))
  expect_match(result$regions[["dp-trends-year"]], "EDIT:", fixed = TRUE)
  env <- new.env()
  env$d <- data.frame(iv_opyrs = c(1.25, 2.75))
  eval(parse(text = result$regions[["dp-trends-year"]]), env)
  expect_equal(env$d$year, c(1986, 1987))
})

test_that("dp-trends inventories else branches for axis label and plot definitions", {
  root <- migration_study_fixture("dp-trends")
  original <- trends_evidence(root)$source$text
  branch <- "%if &flag %then %put unchanged;"
  cases <- list(
    list(statement = "%else axis1 order=(2000 to 2020 by 10);", lines = c(9L, 21L, 22L, 26L), choice = "axis"),
    list(statement = "%else label hx_chf='Conditional heart failure';", lines = c(7L, 26L), choice = "label"),
    list(statement = "%else plot hx_chf*year / haxis=axis1 vaxis=axis3;", lines = c(21L, 26L), choice = "plot")
  )
  for (case in cases) {
    evidence <- trends_evidence(root, c(original, branch, case$statement))
    result <- hvtiRtemplates:::.migrate_dp_trends(evidence, character())
    env <- trends_config(result)
    expect_true(all(case$lines %in% result$unresolved$line), info = case$statement)
    expect_false(any(case$lines %in% result$translated$line), info = case$statement)
    expect_false(case$statement %in% result$ignored$text)
    if (case$choice == "axis") expect_identical(env$XBREAKS, NULL)
    if (case$choice == "label") expect_identical(env$TRENDS$hx_chf$labels, "hx_chf")
    if (case$choice == "plot") expect_identical(env$TRENDS$hx_chf$ylim, NULL)
  }
})
