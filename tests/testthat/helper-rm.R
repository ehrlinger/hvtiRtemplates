# rm: the regression-model templates. lm_chunk() and lm_eval_job() in helper-lm.R
# are generic over a template's source, so they are reused here.

rm_data <- function(n = 120L) {
  withr::local_seed(42)
  d <- data.frame(ccfid = seq_len(n), id = seq_len(n), age = stats::rnorm(n, 60, 10),
                  female = rep(0:1, length.out = n))
  d$outcome <- 20 + 0.3 * d$age - 2 * d$female + stats::rnorm(n, 0, 4)
  d$exposure <- 35 - 0.1 * d$age + 1.5 * d$female + stats::rnorm(n, 0, 3)
  d
}

rm_mi_data <- function(n = 120L) {
  d <- rm_data(n)
  second <- d
  withr::with_seed(7, second$age <- second$age + stats::rnorm(n, 0, 1))
  rbind(transform(d, imp = 1L), transform(second, imp = 2L))
}

rm_run <- function(qualifier, labels, env, choices = list()) {
  src <- readLines(template_path("rm", qualifier), warn = FALSE)
  for (label in unique(vapply(labels, setup_label, ""))) {  # nolint: object_usage_linter.
    code <- lm_chunk(src, label)  # nolint: object_usage_linter.
    if (identical(label, "setup")) {
      eval_setup_chunk(code, env)  # nolint: object_usage_linter.
    } else {
      suppressMessages(eval(parse(text = code), envir = env))
    }
    if (identical(label, "edit-study-choices")) {
      list2env(choices, envir = env)
      if (!"tbl-data" %in% labels) {
        if (!exists(".id", envir = env, inherits = FALSE)) env$.id <- env$ID
        if (!exists(".response", envir = env, inherits = FALSE)) {
          # What tbl-data does: settle the scale, then build the response from it.
          env$RESPONSE_SCALE <- hvtiRtemplates:::.response_scale(env$RESPONSE_SCALE)
          env$.response <- hvtiRtemplates:::.response_term(env$d, env$OUTCOME, env$RESPONSE_SCALE)
        }
        if (!exists("job_data", envir = env, inherits = FALSE)) env$job_data <- list()
      }
    }
  }
  invisible(env)
}

# Scaffold the `qualifier` job in a fresh study, work its EDIT: markers, and render it,
# or with `render = FALSE` evaluate its chunks in this session (lm_eval_job).
# `choices` sets study choices beyond the qualifier's own, such as `IMPUTATION <- "imp"`.
rm_render_fixture <- function(qualifier, data = NULL, render = TRUE, choices = character(), .local_envir = parent.frame()) {
  root <- tempfile("rm-study-")
  withr::defer(unlink(root, recursive = TRUE), envir = .local_envir)
  d <- if (is.null(data)) rm_data() else data
  suppressMessages(hvtiRutilities::study_setup(root, study = "Synthetic rm study", study_tracker_id = 42L))
  utils::write.csv(d, file.path(root, "00_datasets", "built.csv"), row.names = FALSE)
  suppressMessages(hvtiRutilities::register_data(
    root, built = "built.csv", role = "study", population = "Synthetic cohort"
  ))
  subject <- if (identical(qualifier, "balancing_continuous")) "exposure" else "outcome"
  job <- add_job("rm", subject, "analysis", dir = root, qualifier = qualifier)
  lines <- gsub("EDIT:", "REVIEWED:", readLines(job, warn = FALSE), fixed = TRUE)
  response <- if (identical(qualifier, "balancing_continuous")) "exposure" else "outcome"
  lines[grepl("^OUTCOME <- ", lines)] <- sprintf('OUTCOME <- "%s"', response)
  for (replacement in choices) {
    key <- sub(" .*", "", replacement)
    # The first line only: the study choice, not a later `IMPUTATION <- attr(...)` that reads a resolved value back.
    lines[which(grepl(paste0("^", key, " <- "), lines))[1L]] <- replacement
  }
  writeLines(lines, job)
  if (!render) return(list(root = root, job = job, env = lm_eval_job(job)))  # nolint: object_usage_linter.
  quarto::quarto_render(job, execute_dir = dirname(job), quiet = TRUE)
  list(root = root, job = job, output = sub("[.]qmd$", ".html", job))
}

# A rendered report's text outside its code blocks, so a test reads what the report
# says rather than the template source folded under "Code".
rm_report_prose <- function(html) {
  text <- paste(readLines(html, warn = FALSE), collapse = "\n")
  gsub("(?s)<pre[^>]*>.*?</pre>", "", text, perl = TRUE)
}
