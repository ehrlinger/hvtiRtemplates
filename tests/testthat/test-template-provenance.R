template_by_name <- function(name) {
  templates <- template_list()
  hit <- which(templates$name == name)
  stopifnot(length(hit) == 1L)
  templates$file[[hit]]
}

provenance_chunk_end <- function(source, label) {
  if (length(label) != 1L) return(integer())
  after_label <- (label + 1L):length(source)
  fence <- which(source[after_label] == "```")
  if (!length(fence)) return(integer())
  label + fence[[1L]]
}

provenance_chunk <- function(path) {
  source <- readLines(path, warn = FALSE)
  label <- grep("^#\\| label: provenance$", source)
  if (length(label) != 1L) return(character())
  open <- max(which(seq_along(source) < label & source == "```{r}"))
  close <- provenance_chunk_end(source, label)
  if (!length(close)) return(character())
  final <- tail(which(nzchar(trimws(source))), 1L)
  if (!identical(close, final)) {
    stop("The provenance chunk must end at the final nonblank line.", call. = FALSE)
  }
  source[open:close]
}

provenance_expressions <- function(path) {
  chunk <- provenance_chunk(path)
  parse(text = chunk[-c(1L, length(chunk))])
}

is_record_provenance_call <- function(expr) {
  if (!is.call(expr)) return(FALSE)
  fun <- expr[[1L]]
  direct <- is.call(fun) &&
    identical(as.character(fun[[1L]]), "::") &&
    identical(as.character(fun[[2L]]), "hvtiRutilities") &&
    identical(as.character(fun[[3L]]), "record_provenance")
  direct
}

r_chunk_expressions <- function(path) {
  source <- readLines(path, warn = FALSE)
  starts <- which(source == "```{r}")
  lapply(starts, function(start) {
    end <- start + which(source[(start + 1L):length(source)] == "```")[[1L]]
    parse(text = source[(start + 1L):(end - 1L)])
  })
}

record_provenance_call_count <- function(expr) {
  direct <- as.integer(is_record_provenance_call(expr))
  nested <- if (is.call(expr)) {
    sum(vapply(as.list(expr)[-1L], record_provenance_call_count, integer(1L)))
  } else {
    0L
  }
  direct + nested
}

template_provenance_call_count <- function(path) {
  chunks <- r_chunk_expressions(path)
  sum(vapply(chunks, function(chunk) {
    sum(vapply(chunk, record_provenance_call_count, integer(1L)))
  }, integer(1L)))
}

capture_provenance <- function(path, env) {
  captured <- NULL
  testthat::local_mocked_bindings(
    record_provenance = function(output, extra = NULL, dataset = "study", ...) {
      captured <<- list(output = output, extra = extra, dataset = dataset)
      invisible(output)
    },
    .package = "hvtiRutilities"
  )
  eval(provenance_expressions(path), envir = env)
  captured
}

test_that("provenance_chunk rejects an unlabeled later chunk", {
  path <- tempfile(fileext = ".qmd")
  writeLines(c(
    "```{r}",
    "#| label: provenance",
    "hvtiRutilities::record_provenance(.output)",
    "```",
    "```{r}",
    "invisible(NULL)",
    "```"
  ), path)

  expect_error(provenance_chunk(path), "final nonblank")
})

test_that("provenance calls outside the final chunk do not satisfy the contract", {
  path <- tempfile(fileext = ".qmd")
  writeLines(c(
    "```{r}",
    "hvtiRutilities::record_provenance(.output)",
    "```",
    "# hvtiRutilities::record_provenance(.output)",
    "```{r}",
    "#| label: provenance",
    "invisible(NULL)",
    "```"
  ), path)

  expressions <- provenance_expressions(path)
  expect_false(any(vapply(expressions, is_record_provenance_call, logical(1L))))
})

test_that("nested provenance calls do not satisfy the contract", {
  cases <- c(
    if_false = "if (FALSE) hvtiRutilities::record_provenance(.output)",
    quoted = "quote(hvtiRutilities::record_provenance(.output))",
    braced = "{ hvtiRutilities::record_provenance(.output); invisible(NULL) }"
  )

  for (name in names(cases)) {
    path <- tempfile(fileext = ".qmd")
    writeLines(c(
      "```{r}",
      "#| label: provenance",
      cases[[name]],
      "```"
    ), path)

    expressions <- provenance_expressions(path)
    expect_false(any(vapply(expressions, is_record_provenance_call, logical(1L))), info = name)
  }
})

test_that("provenance calls are unique across all R chunks", {
  path <- tempfile(fileext = ".qmd")
  writeLines(c(
    "```{r}",
    "if (FALSE) hvtiRutilities::record_provenance(.output)",
    "```",
    "```{r}",
    "#| label: provenance",
    "hvtiRutilities::record_provenance(.output)",
    "```"
  ), path)
  expect_false(template_provenance_call_count(path) == 1L)
})

test_that("every shipped template ends with one direct provenance chunk", {
  templates <- template_list()
  expect_equal(nrow(templates), 20L)

  for (path in templates$file) {
    source <- readLines(path, warn = FALSE)
    nonblank <- which(nzchar(trimws(source)))
    labels <- grep("^#\\| label: provenance$", source)
    chunk <- provenance_chunk(path)
    chunk_end <- provenance_chunk_end(source, labels)
    expressions <- provenance_expressions(path)
    info <- basename(path)

    expect_equal(length(labels), 1L, info = info)
    expect_identical(chunk_end, tail(nonblank, 1L), info = info)
    expect_identical(tail(grep("^#\\| label: ", source, value = TRUE), 1L),
                     "#| label: provenance", info = info)
    expect_equal(sum(vapply(expressions, is_record_provenance_call, logical(1L))), 1L, info = info)
    expect_equal(template_provenance_call_count(path), 1L, info = info)
    expect_true(any(grepl("subject = SUBJECT", chunk, fixed = TRUE)), info = info)
    expect_true(any(grepl("type = TYPE", chunk, fixed = TRUE)), info = info)
  }
})

test_that("provenance paths come only from the recovered render input", {
  for (path in template_list()$file) {
    chunk <- provenance_chunk(path)
    info <- basename(path)
    expect_true(any(grepl("file_path_sans_ext(basename(.in))", chunk, fixed = TRUE)), info = info)
    expect_true(any(grepl("file.path(dirname(.in), paste0(.job_stem, \".html\"))", chunk, fixed = TRUE)),
                info = info)
    expect_true(any(grepl("is.null(.in)", chunk, fixed = TRUE)), info = info)
    expect_false(any(grepl("getwd()", chunk, fixed = TRUE)), info = info)
  }
})

test_that("only templates with a local dataset choice override the dataset", {
  expected <- c("dc-general", "dc-gfup", "dc-tables", "dp-postage", "dp-trends")
  templates <- template_list()
  observed <- templates$name[vapply(templates$file, function(path) {
    any(grepl("dataset = DATASET", provenance_chunk(path), fixed = TRUE))
  }, logical(1L))]

  expect_setequal(observed, expected)
})

test_that("identity-only templates do not invent analysis or cohort blocks", {
  identity_only <- c("dc-general", "dc-tables", "dp-postage", "dp-trends", "bc", "bh", "bl", "br")
  for (prefix in identity_only) {
    chunk <- provenance_chunk(template_by_name(prefix))
    expect_false(any(grepl("analysis =", chunk, fixed = TRUE)), info = prefix)
    expect_false(any(grepl("cohort =", chunk, fixed = TRUE)), info = prefix)
  }
})

test_that("event-time templates record local coding and observed counts", {
  event_names <- c(ac = "STATUS", hz = "STATUS", hm = "EVENT", hp = "EVENT", hs = "EVENT")
  for (prefix in names(event_names)) {
    chunk <- provenance_chunk(template_by_name(prefix))
    event <- event_names[[prefix]]
    expect_true(any(grepl("variable = TIME", chunk, fixed = TRUE)), info = prefix)
    expect_true(any(grepl(paste0("variable = ", event), chunk, fixed = TRUE)), info = prefix)
    expect_true(any(grepl("event = 1L", chunk, fixed = TRUE)), info = prefix)
    expect_true(any(grepl("censored = 0L", chunk, fixed = TRUE)), info = prefix)
    expect_true(any(grepl("cohort = cc", chunk, fixed = TRUE)), info = prefix)
  }
})

test_that("forest templates take analysis identity and counts from runtime objects", {
  for (prefix in c("rfs-fit", "rfs-explain", "rfc-fit", "rfc-explain", "rfr-fit", "rfr-explain")) {
    chunk <- provenance_chunk(template_by_name(prefix))
    expect_true(any(grepl("forest$yvar", chunk, fixed = TRUE)), info = prefix)
    expect_true(any(grepl("cohort =", chunk, fixed = TRUE)), info = prefix)
    expect_false(any(grepl("variable = SUBJECT", chunk, fixed = TRUE)), info = prefix)
  }
})

test_that("RF provenance chunks record the fitted objects they consume", {
  rf_cases <- list(
    rfs = list(
      data = function() {
        data_env <- new.env()
        utils::data("veteran", package = "randomForestSRC", envir = data_env)
        data_env$veteran
      },
      choices = list(
        TIME = "time", STATUS = "status",
        PREDICTORS = c("trt", "celltype", "karno", "diagtime", "age", "prior"), NTREE = 50, SEED = 1
      )
    ),
    rfc = list(
      data = function() {
        data <- datasets::iris[datasets::iris$Species != "setosa", ]
        data$Species <- as.character(data$Species)
        data
      },
      choices = list(
        RESPONSE = "Species",
        PREDICTORS = c("Sepal.Length", "Sepal.Width", "Petal.Length", "Petal.Width"),
        ROC_CLASS = "virginica", NTREE = 50, SEED = 1
      )
    ),
    rfr = list(
      data = function() datasets::airquality[!is.na(datasets::airquality$Ozone), ],
      choices = list(
        RESPONSE = "Ozone", PREDICTORS = c("Solar.R", "Wind", "Temp", "Month", "Day"),
        NTREE = 50, SEED = 1, NA_ACTION = "na.impute"
      )
    )
  )

  for (prefix in names(rf_cases)) {
    rf_skip_unless_stack(rf_template_packages(prefix, "fit"))
    case <- rf_cases[[prefix]]
    fit <- rf_env(case$data())
    suppressWarnings(rf_run(prefix, "fit", c("set", "study-choices", "read", "fit", "save"), fit, case$choices))
    fit$SUBJECT <- "provenance"
    fit$TYPE <- "fit"
    fit$.in <- file.path(fit$.root, paste0(prefix, "-fit.rmarkdown"))

    fit_record <- capture_provenance(template_by_name(paste0(prefix, "-fit")), fit)
    expect_identical(fit_record$output, file.path(fit$.root, paste0(prefix, "-fit.html")), info = prefix)

    explain <- new.env(parent = globalenv())
    explain$.root <- fit$.root
    rf_run(prefix, "explain", c("set", "study-choices", "forest"), explain)
    explain$SUBJECT <- "provenance"
    explain$TYPE <- "explain"
    explain$.in <- file.path(explain$.root, paste0(prefix, "-explain.rmarkdown"))

    explain_record <- capture_provenance(template_by_name(paste0(prefix, "-explain")), explain)
    expect_identical(explain_record$output, file.path(explain$.root, paste0(prefix, "-explain.html")),
                     info = prefix)

    records <- list(fit = list(record = fit_record, env = fit), explain = list(record = explain_record, env = explain))
    for (qualifier in names(records)) {
      record <- records[[qualifier]]$record
      env <- records[[qualifier]]$env
      expect_identical(record$extra$subject, "provenance", info = paste(prefix, qualifier))
      expect_identical(record$extra$type, qualifier, info = paste(prefix, qualifier))

      if (identical(prefix, "rfs")) {
        time <- if (identical(qualifier, "fit")) env$TIME else env$forest$yvar.names[[1L]]
        status <- if (identical(qualifier, "fit")) env$STATUS else env$forest$yvar.names[[2L]]
        event <- env$forest$yvar[[status]]
        expect_identical(record$extra$analysis$time$variable, time, info = qualifier)
        expect_identical(record$extra$analysis$event$variable, status, info = qualifier)
        expect_identical(record$extra$analysis$event$event, 1L, info = qualifier)
        expect_identical(record$extra$analysis$event$censored, 0L, info = qualifier)
        expect_identical(record$extra$cohort, list(
          n = as.integer(nrow(env$forest$yvar)),
          n_events = as.integer(sum(event == 1)),
          n_censored = as.integer(sum(event == 0))
        ), info = qualifier)
      } else {
        variable <- if (identical(qualifier, "fit")) env$RESPONSE else env$forest$yvar.names[[1L]]
        kind <- if (identical(prefix, "rfc")) "classification" else "continuous"
        expect_identical(record$extra$analysis$outcome$variable, variable, info = qualifier)
        expect_identical(record$extra$analysis$outcome$kind, kind, info = qualifier)
        expect_identical(record$extra$cohort, list(n = as.integer(length(env$forest$yvar))), info = qualifier)
        if (identical(prefix, "rfc")) {
          expect_identical(record$extra$analysis$outcome$observed_levels, levels(env$forest$yvar), info = qualifier)
          if (identical(qualifier, "fit")) {
            expect_identical(record$extra$analysis$outcome$target_level, env$ROC_CLASS)
          } else {
            expect_null(record$extra$analysis$outcome$target_level)
          }
        }
      }
    }
  }
})

test_that("event-time provenance chunks retain observed STATUS and EVENT cohorts", {
  cases <- list(
    ac = list(event = "STATUS", time = "TIME", data = data.frame(time = c(1, 2, NA), status = c(1, 0, 1))),
    hm = list(event = "EVENT", time = "TIME", data = data.frame(time = c(1, 2, 3), event = c(1, 0, 1)))
  )

  for (prefix in names(cases)) {
    case <- cases[[prefix]]
    cc <- hvtiRutilities::cohort_counts(case$data, event = tolower(case$event), time = tolower(case$time))
    env <- new.env(parent = globalenv())
    env$.in <- file.path(tempdir(), paste0(prefix, "-provenance.rmarkdown"))
    env$SUBJECT <- "provenance"
    env$TYPE <- "event-time"
    env$TIME <- tolower(case$time)
    env[[case$event]] <- tolower(case$event)
    env$cc <- cc

    record <- capture_provenance(template_by_name(prefix), env)
    expect_identical(record$output, file.path(tempdir(), paste0(prefix, "-provenance.html")), info = prefix)
    expect_identical(record$extra$analysis$time$variable, env$TIME, info = prefix)
    expect_identical(record$extra$analysis$event$variable, env[[case$event]], info = prefix)
    expect_identical(record$extra$cohort, cc, info = prefix)
  }
})

make_provenance_study <- function(root) {
  suppressMessages(hvtiRutilities::study_setup(
    root, "Provenance render", 42L, adopt = TRUE
  ))
  data <- data.frame(id = 1:3, dead = c(1L, 0L, 0L), iv_dead = 1:3)
  utils::write.csv(
    data,
    file.path(hvtiRutilities::study_dir("datasets", root), "cohort.csv"),
    row.names = FALSE
  )
  suppressMessages(hvtiRutilities::register_data(root, "cohort.csv"))
  invisible(root)
}

write_provenance_job <- function(root, stem, prefix, definitions) {
  path <- file.path(root, paste0(stem, ".qmd"))
  chunk <- provenance_chunk(template_by_name(prefix))
  writeLines(c(
    "---", "format: html", "---", "",
    "```{r}",
    ".in <- knitr::current_input(dir = TRUE)",
    definitions,
    "```", "",
    chunk
  ), path)
  path
}

render_provenance_job <- function(job, root) {
  quarto::quarto_render(job, execute_dir = root, quiet = TRUE)
}

test_that("an endpoint-free render writes a stem-matched sidecar without invented blocks", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  root <- make_provenance_study(withr::local_tempdir())
  job <- write_provenance_job(
    root, "cohort-eda-dc-general", "dc-general",
    c('SUBJECT <- "cohort"', 'TYPE <- "eda"', 'DATASET <- "study"')
  )

  render_provenance_job(job, root)

  sidecar <- file.path(root, "cohort-eda-dc-general.provenance.json")
  record <- jsonlite::fromJSON(sidecar, simplifyVector = FALSE)
  expect_true(file.exists(file.path(root, "cohort-eda-dc-general.html")))
  expect_true(file.exists(sidecar))
  expect_identical(record$job, "cohort-eda-dc-general")
  expect_true(all(names(hvtiRutilities:::.provenance_required()) %in% names(record)))
  expect_identical(record$subject, "cohort")
  expect_identical(record$type, "eda")
  expect_false(any(c("analysis", "cohort") %in% names(record)))
})

test_that("an endpoint-driven render writes its local coding and observed cohort", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  root <- make_provenance_study(withr::local_tempdir())
  job <- write_provenance_job(
    root, "death-hz-hz", "hz",
    c(
      'SUBJECT <- "death"', 'TYPE <- "hz"',
      'TIME <- "iv_dead"', 'STATUS <- "dead"',
      "cc <- list(n = 3L, n_events = 1L, n_censored = 2L)"
    )
  )

  render_provenance_job(job, root)

  record <- jsonlite::fromJSON(
    file.path(root, "death-hz-hz.provenance.json"),
    simplifyVector = FALSE
  )
  expect_identical(record$analysis$time$variable, "iv_dead")
  expect_identical(record$analysis$event$variable, "dead")
  expect_identical(record$analysis$event$event, 1L)
  expect_identical(record$analysis$event$censored, 0L)
  expect_identical(record$cohort, list(n = 3L, n_events = 1L, n_censored = 2L))
})

test_that("a sidecar write failure fails the render", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  root <- make_provenance_study(withr::local_tempdir())
  job <- write_provenance_job(
    root, "cohort-eda-dc-general", "dc-general",
    c('SUBJECT <- "cohort"', 'TYPE <- "eda"', 'DATASET <- "study"')
  )
  dir.create(file.path(root, "cohort-eda-dc-general.provenance.json"))

  expect_error(
    render_provenance_job(job, root),
    "[Rr]ender|[Pp]rovenance|[Ss]idecar"
  )
})
