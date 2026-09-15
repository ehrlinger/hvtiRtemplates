gfup_migrate <- function(root) {
  migrate_job(file.path(root, "descriptive", "dc.gfup.sas"),
              "cohort", "eda", "dc", "gfup", dir = root)
}

gfup_evidence <- function(root, extra = character()) {
  lines <- c(readLines(file.path(root, "descriptive", "dc.gfup.sas")), extra)
  list(root = root, source = data.frame(line = seq_along(lines), text = lines))
}

gfup_chunk <- function(job, label) {
  lines <- readLines(job, warn = FALSE)
  start <- match(paste0("#| label: ", label), lines)
  if (is.na(start)) stop("Missing chunk: ", label)
  end <- start + match("```", lines[-seq_len(start)])
  parse(text = lines[seq.int(start + 1L, end - 1L)])
}

gfup_env <- function(d) {
  list2env(list(d = d, EVENT = "dead", FOLLOWUP = c("iv_dead", "iv_fup"),
                IDENTIFIER = NULL, MAX_REVIEW_ROWS = 2L), parent = globalenv())
}

test_that("dc-gfup extracts agreed fields with source evidence and keeps identifiers disabled", {
  root <- migration_study_fixture("dc-gfup")
  out <- gfup_migrate(root)
  txt <- readLines(out, warn = FALSE)
  expect_true('EVENT <- "dead"' %in% txt)
  expect_true('FOLLOWUP <- c("iv_dead", "iv_fup")' %in% txt)
  expect_true('DATASET <- "study"' %in% txt)
  expect_true("ANALYSIS_SET <- NULL" %in% txt)
  expect_true("IDENTIFIER <- NULL" %in% txt)
  expect_false(any(grepl("study_id", txt, fixed = TRUE)))
  result <- hvtiRtemplates:::.migrate_dc_gfup(gfup_evidence(root), txt)
  expect_true(all(c(8L, 9L, 10L, 12L) %in% result$translated$line))
  for (value in c("study_id", "%inc vars", "current=", "maxfup=", "stroke_time")) {
    expect_true(any(grepl(value, result$unresolved$text, fixed = TRUE)), info = value)
  }
  expect_false(any(grepl("study_id", result$translated$text, fixed = TRUE)))
  report <- readLines(sub("[.]qmd$", "-migration.md", out), warn = FALSE)
  expect_true(any(grepl("study_id", report, fixed = TRUE)))
  env <- new.env()
  env$.root <- root
  env$read_built <- hvtiRutilities::read_built
  env$study_config <- hvtiRutilities::study_config
  eval(gfup_chunk(out, "data"), env)
  eval(gfup_chunk(out, "spec"), env)
  capture.output(eval(gfup_chunk(out, "qc"), env))
  expect_identical(nrow(env$d), 40L)
  expect_identical(env$cohort_counts, data.frame(full = 40L, event = 20L, censored = 20L, missing_event = 0L))
  expect_equal(env$followup_means$full$n, c(40L, 40L))
  expect_equal(env$followup_means$event$n, c(20L, 20L))
  expect_equal(env$followup_means$censored$n, c(20L, 20L))
})

test_that("dc-gfup rejects contradictory event evidence", {
  root <- migration_study_fixture("dc-gfup")
  for (extra in c("proc sort; by stroke; run;", "if stroke=0;")) {
    expect_error(hvtiRtemplates:::.migrate_dc_gfup(gfup_evidence(root, extra), character()), "contradictory event")
  }
})

test_that("dc-gfup QC reports literal summaries and caps private review rows", {
  d <- data.frame(dead = c(0, 1, NA, 0, 1, 0), iv_dead = c(NA, -1, 0, 1, 2, 3),
                  iv_fup = c(1, 2, 3, 4, 5, 6), local_id = letters[1:6])
  env <- gfup_env(d)
  code <- gfup_chunk(template_path("dc", "gfup"), "qc")
  output <- capture.output(eval(code, env))
  expect_identical(env$cohort_counts, data.frame(full = 6L, event = 2L, censored = 3L, missing_event = 1L))
  expect_equal(env$followup_qc[1L, ], data.frame(
    interval = "iv_dead", missing = 1L, negative = 1L, zero = 1L,
    min = -1, q1 = 0, median = 1, q3 = 2, mean = 1, sd = sqrt(2.5), max = 3
  ))
  expect_identical(nrow(env$review_rows), 2L)
  expect_identical(names(env$review_rows), c("dead", "iv_dead", "iv_fup"))
  expect_false(any(grepl("local_id", output, fixed = TRUE)))
  env$IDENTIFIER <- "local_id"
  capture.output(eval(code, env))
  expect_identical(env$review_rows$local_id, c("a", "b"))
})

test_that("dc-gfup validates every field and row cap before summarizing", {
  code <- gfup_chunk(template_path("dc", "gfup"), "qc")
  d <- data.frame(dead = c(0, 1), iv_dead = c(1, 2), iv_fup = c(2, 3))
  cases <- list(
    list(field = "EVENT", value = "absent", error = "Unknown"),
    list(field = "EVENT", value = c("dead", "iv_dead"), error = "EVENT"),
    list(field = "FOLLOWUP", value = "absent", error = "Unknown"),
    list(field = "FOLLOWUP", value = character(), error = "FOLLOWUP"),
    list(field = "IDENTIFIER", value = "absent", error = "Unknown"),
    list(field = "MAX_REVIEW_ROWS", value = 0, error = "positive integer"),
    list(field = "MAX_REVIEW_ROWS", value = 1.5, error = "positive integer"),
    list(field = "MAX_REVIEW_ROWS", value = c(1, 2), error = "positive integer"),
    list(field = "MAX_REVIEW_ROWS", value = NA, error = "positive integer"),
    list(field = "MAX_REVIEW_ROWS", value = Inf, error = "positive integer")
  )
  for (case in cases) {
    env <- gfup_env(d)
    env[[case$field]] <- case$value
    expect_error(eval(code, env), case$error)
  }
  env <- gfup_env(transform(d, dead = c(0, 2)))
  expect_error(eval(code, env), "binary")
  env <- gfup_env(transform(d, iv_fup = c("1", "2")))
  expect_error(eval(code, env), "numeric")
})

test_that("dc-gfup never promotes an ID field found in VAR evidence", {
  root <- migration_study_fixture("dc-gfup")
  evidence <- gfup_evidence(root, "proc print; var study_id iv_dead; run;")
  result <- hvtiRtemplates:::.migrate_dc_gfup(evidence, character())
  expect_false(any(grepl("study_id", result$regions, fixed = TRUE)))
  expect_false(any(grepl("study_id", result$translated$text, fixed = TRUE)))
  expect_true(any(grepl("study_id", result$unresolved$text, fixed = TRUE)))
})

test_that("dc-gfup handles multiline statements and quoted or commented scaffolding", {
  root <- migration_study_fixture("dc-gfup")
  source <- c("set built; title 'Evidence; by stroke; var wrong;';",
              "proc means; VaR iv_dead", "  iv_fup; BY dead; run;",
              "* by stroke;", "%* var wrong;", "/* by stroke; */", "if dead = 0;")
  evidence <- list(root = root, source = data.frame(line = seq_along(source), text = source))
  result <- hvtiRtemplates:::.migrate_dc_gfup(evidence, character())
  env <- new.env()
  eval(parse(text = result$regions[["dc-gfup-config"]]), env)
  expect_identical(env$EVENT, "dead")
  expect_identical(env$FOLLOWUP, c("iv_dead", "iv_fup"))
  expect_true(2L %in% result$translated$line)
  expect_true(any(grepl("Evidence; by stroke; var wrong;", result$unresolved$text, fixed = TRUE)))
  evidence <- gfup_evidence(root, "proc means; var maxfup; run;")
  result <- hvtiRtemplates:::.migrate_dc_gfup(evidence, character())
  eval(parse(text = result$regions[["dc-gfup-config"]]), env)
  expect_identical(env$FOLLOWUP, c("iv_dead", "iv_fup"))
})

test_that("dc-gfup keeps an unterminated block comment inactive through end of source", {
  root <- migration_study_fixture("dc-gfup")
  result <- hvtiRtemplates:::.migrate_dc_gfup(
    gfup_evidence(root, c("/* unfinished scaffold;", "by stroke; var wrong;")), character()
  )
  env <- new.env()
  eval(parse(text = result$regions[["dc-gfup-config"]]), env)
  expect_identical(env$EVENT, "dead")
  expect_identical(env$FOLLOWUP, c("iv_dead", "iv_fup"))
  expect_true(any(grepl("by stroke; var wrong;", result$unresolved$text, fixed = TRUE)))
})

test_that("dc-gfup marks incomplete evidence without choosing defaults", {
  root <- migration_study_fixture("dc-gfup")
  source <- c("set absent;", "%inc vars;", "/* var interval; by status; */")
  result <- hvtiRtemplates:::.migrate_dc_gfup(
    list(root = root, source = data.frame(line = 1:3, text = source)), character()
  )
  env <- new.env()
  eval(parse(text = result$regions[["dc-gfup-data"]]), env)
  eval(parse(text = result$regions[["dc-gfup-config"]]), env)
  expect_identical(env$DATASET, NA_character_)
  expect_identical(env$EVENT, NA_character_)
  expect_identical(env$FOLLOWUP, character())
  expect_true(any(grepl("set absent", result$unresolved$text, fixed = TRUE)))
})

test_that("dc-gfup requires complete SET evidence before selecting registered data", {
  root <- migration_study_fixture("dc-gfup")
  for (extra in c("set other(obs=10);", "set complete_cases;", "set built(obs=10);", "set built;",
                  "if flag then set other;", "else set other;")) {
    result <- hvtiRtemplates:::.migrate_dc_gfup(gfup_evidence(root, extra), character())
    env <- new.env()
    eval(parse(text = result$regions[["dc-gfup-data"]]), env)
    expect_identical(env$DATASET, NA_character_, info = extra)
    expect_false(any(grepl("^set ", result$translated$text, ignore.case = TRUE)), info = extra)
    expect_true(extra %in% result$unresolved$text, info = extra)
  }
})

test_that("dc-gfup does not promote locally assigned event or interval fields", {
  root <- migration_study_fixture("dc-gfup")
  cases <- list(
    list(code = "if dead=0 then iv_dead=(close_date-dt_surg)/365.25;", event = "dead", followup = "iv_fup"),
    list(code = "dead=1-olddead;", event = NA_character_, followup = c("iv_dead", "iv_fup")),
    list(code = "if olddead=0 then dead=1; else dead=0;", event = NA_character_, followup = c("iv_dead", "iv_fup")),
    list(code = "if dead=1 then iv_fup=iv_dead; else iv_dead=0;", event = "dead", followup = character())
  )
  for (case in cases) {
    result <- hvtiRtemplates:::.migrate_dc_gfup(gfup_evidence(root, case$code), character())
    env <- new.env()
    eval(parse(text = result$regions[["dc-gfup-config"]]), env)
    expect_identical(env$EVENT, case$event, info = case$code)
    expect_identical(env$FOLLOWUP, case$followup, info = case$code)
    expect_true(any(grepl("not executed", result$unresolved$reason, fixed = TRUE)))
    affected <- if (is.na(case$event)) "event" else "interval"
    expect_true(any(grepl(paste0("assigned ", affected), result$unresolved$reason, fixed = TRUE)), info = case$code)
    expect_false(any(grepl("^if .* then|^else |^dead=", result$translated$text)), info = case$code)
  }
})

test_that("dc-gfup ignores assignment-like strings and comments", {
  root <- migration_study_fixture("dc-gfup")
  result <- hvtiRtemplates:::.migrate_dc_gfup(gfup_evidence(root, c(
    "title 'if dead=0 then iv_dead=0; if flag then set other;';", "/* if dead=0 then iv_fup=0; */", "* dead=0;"
  )), character())
  env <- new.env()
  eval(parse(text = result$regions[["dc-gfup-data"]]), env)
  eval(parse(text = result$regions[["dc-gfup-config"]]), env)
  expect_identical(env$DATASET, "study")
  expect_identical(env$EVENT, "dead")
  expect_identical(env$FOLLOWUP, c("iv_dead", "iv_fup"))
})

test_that("dc-gfup dataset selection rejects both or neither and reads named data", {
  root <- migration_study_fixture("dc-gfup")
  code <- gfup_chunk(template_path("dc", "gfup"), "data")
  assignments <- vapply(code, function(x) {
    is.call(x) && identical(x[[1L]], quote(`<-`)) && as.character(x[[2L]]) %in% c("DATASET", "ANALYSIS_SET")
  }, logical(1))
  code <- code[!assignments]
  env <- list2env(list(.root = root, DATASET = "study", ANALYSIS_SET = "eda",
                       read_built = hvtiRutilities::read_built, study_config = hvtiRutilities::study_config))
  expect_error(eval(code, env), "exactly one")
  env$DATASET <- env$ANALYSIS_SET <- NULL
  expect_error(eval(code, env), "exactly one")
  env$DATASET <- "complete_cases"
  eval(code, env)
  expect_identical(nrow(env$d), 24L)
  evidence <- gfup_evidence(root)
  evidence$source$text <- sub("set built;", "set complete_cases;", evidence$source$text, fixed = TRUE)
  result <- hvtiRtemplates:::.migrate_dc_gfup(evidence, character())
  eval(parse(text = result$regions[["dc-gfup-data"]]), env)
  expect_identical(env$DATASET, "complete_cases")
})

test_that("dc-gfup reports empty and missing-only cohorts without fictitious subset rows", {
  code <- gfup_chunk(template_path("dc", "gfup"), "qc")
  for (n in c(0L, 2L)) {
    env <- gfup_env(data.frame(dead = rep(NA_real_, n), iv_dead = rep(NA_real_, n), iv_fup = rep(NA_real_, n)))
    expect_no_warning(capture.output(eval(code, env)))
    expect_equal(env$followup_means$event$n, c(0, 0))
    expect_equal(env$followup_means$censored$n, c(0, 0))
    expect_true(all(is.na(env$followup_qc$min)))
    expect_identical(nrow(env$review_rows), n)
  }
})

test_that("dc-gfup retains optional event-coding cross-tabs with field checks", {
  code <- gfup_chunk(template_path("dc", "gfup"), "checks")
  env <- list2env(list(d = data.frame(dead = c(0, 1, NA), event_source = c(0, 1, NA)),
                       CHECKS = list(c("dead", "event_source"))))
  output <- capture.output(eval(code, env))
  expect_true(any(grepl("NA", output, fixed = TRUE)))
  env$CHECKS <- list(c("dead", "missing_field"))
  expect_error(eval(code, env), "Unknown")
})
