identifiability_data <- function() {
  data.frame(nyha = c(rep(1L, 28L), 2L, 3L), age = c(rep(60, 28L), 91, 95), lab = seq_len(30L) + 0.5,
             dt_surg = as.Date("2020-01-01") + seq_len(30L), arm = rep(c("a", "b"), 15L), far = c(seq_len(29L), 500))
}

test_that("each check finds its case, by column and count", {
  f <- hvtiRtemplates:::.identifiability_check(identifiability_data(), c("nyha", "age", "dt_surg", "lab"),
                                               extremes = "far", cells = c("nyha", "age", "dt_surg"))
  expect_equal(f[f$check == "small", "column"], c("nyha", "age"))
  expect_equal(f[f$check == "small" & f$column == "nyha", "count"], 2L)
  expect_equal(f[f$check == "age", "count"], 2L)
  expect_equal(f[f$check == "date", "column"], "dt_surg")
  expect_equal(f[f$check == "extreme", "count"], 1L)
  # Every column has a maximum: one with no outlier finds nothing.
  expect_equal(nrow(hvtiRtemplates:::.identifiability_check(identifiability_data(), extremes = "lab")), 0L)
  # All values equal, or all missing, finds nothing and does not fail.
  same <- data.frame(a = rep(1, 10L), b = rep(NA_real_, 10L))
  expect_equal(nrow(hvtiRtemplates:::.identifiability_check(same, extremes = c("a", "b"))), 0L)
  expect_named(f, c("check", "column", "count"))
})

test_that("small cells are counted within `by`, and a threshold can be raised", {
  d <- identifiability_data()
  f <- hvtiRtemplates:::.identifiability_check(d, by = "arm", small = 2L, cells = "nyha")
  expect_equal(f$count, 2L)
  expect_equal(nrow(hvtiRtemplates:::.identifiability_check(d, small = 1L, cells = "nyha")), 0L)
})

test_that("a small group is flagged over continuous rows alone", {
  d <- data.frame(arm = c(rep("A", 3L), rep("B", 27L)), measurement = seq_len(30L))
  f <- hvtiRtemplates:::.identifiability_check(d, "measurement", by = "arm")
  expect_equal(f$check, "group")
  expect_equal(f$column, "arm")
  expect_equal(f$count, 1L)
  expect_match(hvtiRtemplates:::.identifiability_notice(f), "`arm` has 1 group of fewer than 5 patients", fixed = TRUE)
  expect_equal(nrow(hvtiRtemplates:::.identifiability_check(d, "measurement", by = "arm", small = 3L)), 0L)
})

test_that("only the columns a template shows by level count as cells, whatever their type", {
  d <- data.frame(measure = c(rep(1:8, 3L), 9), site = c(rep(1:12, 2L), 13))
  expect_equal(nrow(hvtiRtemplates:::.identifiability_check(d, "measure")), 0L)
  f <- hvtiRtemplates:::.identifiability_check(d, "site", cells = "site")
  expect_equal(f$count, 13L)
})

test_that("a group's own ages and dates are read", {
  d <- data.frame(age_group = rep(c(60, 95), each = 10L), dt_op = rep(as.Date("2020-01-01") + 0:1, 10L))
  f <- hvtiRtemplates:::.identifiability_check(d, by = "age_group")
  expect_equal(f[f$check == "age", "count"], 10L)
  f <- hvtiRtemplates:::.identifiability_check(d, by = "dt_op")
  expect_equal(f[f$check == "date", "count"], 20L)
})

test_that("a printed cross-tab is counted jointly, its missing cells too, and an unknown one is ignored", {
  d <- data.frame(a = rep(c("x", "y"), each = 10L), b = c(rep("p", 9L), NA, rep("q", 10L)))
  f <- hvtiRtemplates:::.identifiability_check(d, tables = list(c("a", "b"), "absent"))
  expect_equal(f$column, "a by b")
  expect_equal(f$count, 1L)
})

test_that("nothing found prints nothing, and absent columns are ignored", {
  f <- hvtiRtemplates:::.identifiability_check(identifiability_data(), c("arm", "absent"), age = "absent")
  expect_equal(nrow(f), 0L)
  expect_identical(as.character(hvtiRtemplates:::.identifiability_notice(f)), "")
})

test_that("the notice names columns and counts, never a value, and reaches the run record", {
  old <- hvtiRtemplates:::.run_state$identifiability
  withr::defer(assign("identifiability", old, envir = hvtiRtemplates:::.run_state))
  assign("identifiability", NULL, envir = hvtiRtemplates:::.run_state)
  out <- hvtiRtemplates:::.identifiability_notice(
    hvtiRtemplates:::.identifiability_check(identifiability_data(), "age", cells = "age")
  )
  expect_match(out, "Before this goes in a manuscript", fixed = TRUE)
  expect_match(out, "older than 89", fixed = TRUE)
  expect_false(grepl("91|95", out))
  expect_equal(hvtiRtemplates:::.run_state$identifiability$check, c("small", "age"))
})

test_that("every template that calls the check has its chunk", {
  for (q in list(c("dc", "tables"), c("dc", "gfup"), c("ac", NA), c("dc", "stddiff"), c("dc", "trends"), c("hz", NA),
                 c("hp", NA), c("lg", NA), c("lp", "mirror"), c("vt", "fit"), c("vt", "explain"), c("sid", "clusters"),
                 c("vp", "individual"))) {
    path <- if (is.na(q[[2L]])) template_path(q[[1L]]) else template_path(q[[1L]], q[[2L]])
    expect_true("#| label: identifiability" %in% readLines(path, warn = FALSE))
  }
})

# Each template's own chunk, run on the objects its report has built by then. Returns the findings
# it recorded, so a test states what that report's reader is warned of.
identifiability_chunk <- function(path, env) {
  old <- hvtiRtemplates:::.run_state$identifiability
  withr::defer(assign("identifiability", old, envir = hvtiRtemplates:::.run_state))
  assign("identifiability", NULL, envir = hvtiRtemplates:::.run_state)
  src <- readLines(path, warn = FALSE)
  at <- which(src == "#| label: identifiability")
  code <- src[(at + 1L):(at + which(src[(at + 1L):length(src)] == "```")[1L] - 1L)]
  utils::capture.output(eval(parse(text = code), envir = list2env(env, parent = globalenv())))
  found <- hvtiRtemplates:::.run_state$identifiability
  if (is.null(found)) return(integer())
  stats::setNames(found$count, paste(found$check, found$column))
}

test_that("the counts helper counts what is shown, and a zero is no patient", {
  f <- hvtiRtemplates:::.identifiability_counts(c(0, 1, 4, 5, NA), "x")
  expect_equal(f$count, 2L)
  expect_equal(nrow(hvtiRtemplates:::.identifiability_counts(c(0, 5), "x")), 0L)
  expect_equal(hvtiRtemplates:::.identifiability_counts(table(c("a", "a", "b")), "x", small = 2L)$count, 1L)
  expect_match(hvtiRtemplates:::.identifiability_sentence("at_risk", "all patients", 2L, 5L), "at risk at 2 times", fixed = TRUE)
})

test_that("a sparse calendar year is counted by its patients, and a crowded one is not", {
  d <- data.frame(op = c(rep(1.2, 10L), 2.5, 2.6, rep(3.1, 5L)))
  expect_equal(hvtiRtemplates:::.identifiability_check(d, sparse = "op")$count, 2L)
  expect_equal(hvtiRtemplates:::.identifiability_check(d, sparse = "op")$check, "position")
  expect_equal(nrow(hvtiRtemplates:::.identifiability_check(d, sparse = "op", small = 2L)), 0L)
})

test_that("dc-stddiff warns of a small group in each comparison and of no variable", {
  d <- data.frame(tavr = c(rep(0L, 20L), rep(1L, 3L)), age = 95, m = c(rep(1L, 2L), rep(0L, 18L), rep(1L, 2L), 0L))
  f <- identifiability_chunk(template_path("dc", "stddiff"), list(
    GROUP = "tavr", comparisons = list(Unadjusted = list(data = d), Matched = list(data = d[d$m == 1L, ]), Weighted = list(data = d))
  ))
  expect_equal(f, c("group tavr" = 1L, "group tavr, Matched" = 2L))
})

test_that("dc-trends counts each trend's thin years, by subgroup, and its outlying year", {
  d <- data.frame(year = c(1950, rep(2000:2003, each = 10L)), x = c(1, rep(c(1, NA), 20L)), age_gt = 95)
  f <- identifiability_chunk(template_path("dc", "trends"), list(
    d = d, TRENDS = list(a = list(cols = "x"), b = list(cols = "age_gt")),
    SUBGROUPS = list(all = function(d) rep(TRUE, nrow(d)), bad = function(d) TRUE)
  ))
  # x holds 5 of 10 in each year, so only 1950 is thin; the malformed filter is the figures chunk's to stop.
  expect_equal(f, c("extreme year" = 1L, "small x by year, all" = 1L, "small age_gt by year, all" = 1L))
})

test_that("lg reads its groups' extremes and events, over the patients in them", {
  d <- data.frame(age = c(seq(50, 70, length.out = 99), 200), bmi = rep(1:5, 20L), dead = rep(c(1L, 0L, 0L, 0L, 0L), 20L))
  env <- list(
    d = d, .event = d$dead, .time = c(rep(1, 99), NA), LINK = "hazard",
    variables = data.frame(name = c("age", "bmi"), kind = c("continuous", "ordinal"), groups = 5L)
  )
  f <- identifiability_chunk(template_path("lg"), env)
  # The patient at 200 has no follow-up, so is in no group; bmi's levels are not extremes.
  expect_false(any(grepl("extreme|^age age", names(f))))
  expect_true(all(grepl("events by group", names(f))))
  env$d$age[[50L]] <- 200
  expect_equal(identifiability_chunk(template_path("lg"), env)[["extreme age"]], 1L)
  expect_equal(identifiability_chunk(template_path("lg"), env)[["age age"]], 1L)
})

test_that("lp-mirror counts its groups and, with MATCH, the matched in them, and no bar", {
  scores <- data.frame(score = 1:30, group = c(rep("a", 28L), "b", "b"), matched = c(rep(1L, 4L), rep(0L, 24L), 1L, 0L))
  f <- identifiability_chunk(template_path("lp", "mirror"), list(scores = scores, MATCH = "m", .meta = list(treatment_col = "tavr")))
  expect_equal(f, c("group tavr" = 1L, "group tavr, matched" = 2L))
  f <- identifiability_chunk(template_path("lp", "mirror"), list(scores = scores, MATCH = NULL, .meta = list(treatment_col = "tavr")))
  expect_equal(f, c("group tavr" = 1L))
})

test_that("hz counts events and the longest follow-up, over the rows fitted", {
  d <- data.frame(t = c(1:30, 500, 900), e = c(1L, 1L, rep(0L, 29L), NA))
  f <- identifiability_chunk(template_path("hz"), list(d = d, TIME = "t", EVENT = "e"))
  expect_equal(f, c("small e" = 1L, "extreme t" = 1L))
})

test_that("hp counts the longest follow-up alone, over the rows fitted", {
  d <- data.frame(t = c(1:30, 500, 900), e = c(rep(1L, 31L), NA))
  f <- identifiability_chunk(template_path("hp"), list(d = d, TIME = "t", EVENT = "e", fitted_rows = !is.na(d$e)))
  expect_equal(f, c("extreme t" = 1L))
})

test_that("ac counts small numbers at risk at the horizons and the figure's times, overall and by stratum", {
  d <- data.frame(t = c(seq(0.5, 6, length.out = 40), 11, 12), e = 1L, s = rep(c("a", "b"), 21L))
  env <- list(d = d, TIME = "t", EVENT = "e", STRATA = "s", grid = c(1, 2), RISK_TIMES = NULL, PLOT_MAX = NULL, CLEVEL = 0.68,
              risk_times = function(plot_max) pretty(c(0, plot_max))[pretty(c(0, plot_max)) <= plot_max])
  f <- identifiability_chunk(template_path("ac"), env)
  # The figure's times are 0, 2, ..., 12: after 6, 8 and 10 two patients remain, and after 12 none does.
  expect_equal(f[["at_risk all patients"]], 3L)
  expect_gt(f[["at_risk s"]], 0L)
  # PLOT_MAX ends the figure, so its later counts are no longer shown.
  env$PLOT_MAX <- 4
  env$grid <- 1
  f <- identifiability_chunk(template_path("ac"), env)
  expect_false("at_risk all patients" %in% names(f))
})

test_that("dc-gfup warns of an operation year of few patients only when the figure is drawn", {
  d <- data.frame(op = c(rep(1.5, 20L), 2.1, 2.2), fu = 1:22, dead = rep(0:1, 11L))
  env <- list(d = d, EVENT = "dead", FOLLOWUP = "fu", CHECKS = list(), OPYRS = "op", figure_drawn = TRUE)
  expect_equal(identifiability_chunk(template_path("dc", "gfup"), env)[["position op"]], 2L)
  env$figure_drawn <- FALSE
  expect_false("position op" %in% names(identifiability_chunk(template_path("dc", "gfup"), env)))
})

test_that("vt-fit counts its arms, events, numbers at risk and flagged patients", {
  km <- data.frame(t = c(1:30, 900), e = c(rep(0L, 28L), 1L, 1L, 0L), a = factor(rep(c("x", "y"), length.out = 31L)))
  f <- identifiability_chunk(template_path("vt", "fit"), list(
    .km_data = km, TIME = "t", STATUS = "e", ARM = "a", .counts = data.frame(Patients = c(15L, 16L, 3L)),
    .km = list(tables = list(risk = data.frame(n.risk = c(15L, 2L, 0L)))),
    .ood_counts = table(c("g", "g"), c("x", "y")),
    .overlap = list(combinations = data.frame(flagged_by = c("none", "gower"), x = c(20L, 1L), y = c(30L, 0L)))
  ))
  expect_equal(f[["extreme t"]], 1L)
  expect_equal(f[["small a by e"]], 2L)
  expect_equal(f[["small patients by arm"]], 1L)
  expect_equal(f[["at_risk each arm's observed outcome"]], 1L)
  expect_equal(f[["small out of distribution, by method and arm"]], 2L)
  expect_equal(f[["small patients by the rules that flag them"]], 1L)
})

test_that("vt-explain counts each table's patients, and a level beside the few a twin favors", {
  r <- data.frame(ID = letters[1:12], arm = "x", stringsAsFactors = FALSE)
  d_all <- data.frame(id = letters[1:12], sex = c("f", rep("m", 11L)), age = 95)
  env <- list(
    ARMS = c("x", "y"), r = r, .eligible = rep(TRUE, 12L), .d_all = d_all, .benefit = r[1:2, ], .future = data.frame(favors = "x"),
    .vt = list(settings = list(id = "id"), predictors = list(names = c("sex", "age"))),
    .sens = data.frame(kept = c(12L, 3L)), .dd = data.frame(a = 1), .dist_tab = data.frame(patients = 12L, out_of_distribution = 1L),
    .sr = data.frame(stratum = "p", arm = "x")
  )
  f <- identifiability_chunk(template_path("vt", "explain"), env)
  expect_equal(f[["small patients kept, by rule and arm"]], 1L)
  expect_equal(f[["small patients by arm and method"]], 1L)
  expect_equal(f[["small patients by stratum and arm"]], 1L)
  expect_equal(f[["small patients whose twin favors the other arm"]], 1L)
  expect_equal(f[["small patients with no arm, by the arm their twin favors"]], 1L)
  # Beside the 2 favored: f 1 and m 1. Among the rest, m 10.
  expect_equal(f[["small levels of a characteristic, beside those patients"]], 2L)
  # With no favored patient the characteristics are not printed, so no level is counted, and a predictor
  # absent from the data stops nothing.
  none <- env
  none$.benefit <- r[0L, ]
  none$.vt$predictors$names <- c("sex", "age", "absent")
  expect_false("small levels of a characteristic, beside those patients" %in%
                 names(identifiability_chunk(template_path("vt", "explain"), none)))
  env <- env[names(env) != ".sr"]
  env$.dd <- data.frame()
  f <- identifiability_chunk(template_path("vt", "explain"), env)
  expect_false(any(grepl("stratum|method", names(f))))
})

test_that("sid-clusters counts each cluster at every K and the moves between them", {
  letters_at <- data.frame(ccfid = 1:30, C2 = c(rep("A", 28L), "B", "B"), C3 = c(rep("A", 20L), rep("B", 9L), "C"))
  f <- identifiability_chunk(template_path("sid", "clusters"), list(sid_letters = letters_at, K_RANGE = 2:3))
  expect_equal(f, c("small C2" = 1L, "small C3" = 1L, "small C2 by C3" = 2L))
  f <- identifiability_chunk(template_path("sid", "clusters"), list(sid_letters = letters_at, K_RANGE = 2L))
  expect_equal(f, c("small C2" = 1L))
})

test_that("vp-individual reads only the values it draws, for patients with a gradient", {
  idata <- data.frame(age = c(seq(60, 80, length.out = 29), 95), rare = c(1, 1, rep(0, 28L)),
                      sbp = c(seq(100, 140, length.out = 29), 900), skipped = c(seq(1, 2, length.out = 29), 900))
  grad <- data.frame(age = 1, rare = 1, sbp = c(rep(1, 29L), NA), skipped = 1)
  f <- identifiability_chunk(template_path("vp", "individual"), list(.idata = idata, grad = grad, show = c("age", "rare", "sbp")))
  # The patient at 900 in sbp has no gradient, so no point; `skipped` is not drawn.
  expect_equal(f[["age age"]], 1L)
  expect_equal(f[["small rare"]], 1L)
  expect_false(any(grepl("sbp|skipped", names(f))))
})

test_that("a rendered dc-tables report carries the callout and the run record's counts", {
  skip_on_cran()
  skip_if_not(quarto::quarto_available())
  root <- migration_study_fixture(NULL, edit_built = function(b) {
    b$rare <- as.integer(seq_len(nrow(b)) <= 2L)
    b
  })
  s <- scaffold_job("dc", "tables", list("^  Symptoms   = c\\(\"nyha_pr\"\\)" = "  Symptoms = c(\"rare\")"), root = root)
  quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
  html <- paste(unlist(lapply(list.files(root, "[.]html$", recursive = TRUE, full.names = TRUE), readLines, warn = FALSE)),
                collapse = "\n")
  expect_match(html, "Before this goes in a manuscript", fixed = TRUE)
  expect_match(html, "Identifiability", fixed = TRUE)
})
