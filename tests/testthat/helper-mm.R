# mm: the mixed-model template. lm_chunk() in helper-lm.R is generic over a template's source.

# A synthetic longitudinal cohort: n patients with 2 to 6 measurements each, a log-normal response
# whose log has a random intercept, and a within-patient correlation of rho on the log scale.
mm_data <- function(n = 200L, rho = 0.5) {
  withr::local_seed(42)
  per <- sample(2:6, n, replace = TRUE)
  id <- rep(seq_len(n), per)
  time <- unlist(lapply(per, function(k) sort(stats::runif(k, 0, 10))))
  age <- rep(stats::rnorm(n, 60, 10), per)
  female <- rep(rep(0:1, length.out = n), per)
  total <- 0.04
  b <- rep(stats::rnorm(n, 0, sqrt(rho * total)), per)
  e <- stats::rnorm(length(id), 0, sqrt((1 - rho) * total))
  y <- exp(3 + 0.2 * log(time + 1) + 0.01 * (age - 60) - 0.1 * female + b + e)
  data.frame(ccfid = id, id = id, time = time, age = age, female = female, y = y)
}

# The functions the template's mm-helpers chunk defines, in an environment of their own.
mm_helpers <- function() {
  src <- readLines(template_path("mm"), warn = FALSE)
  env <- new.env(parent = globalenv())
  eval(parse(text = lm_chunk(src, "mm-helpers")), envir = env)  # nolint: object_usage_linter.
  env
}

# The data with visit numbers for TIME.
mm_visits <- function() {
  d <- mm_data()
  d$time <- stats::ave(d$time, d$ccfid, FUN = seq_along)
  d
}

# A cohort whose log response has an independent random intercept (SD 0.2) and random slope on
# log(time + 1) (SD 0.1), residual SD 0.1: what SAS's RANDOM int <slope> / subject=id fits.
mm_slopes <- function(n = 300L) {
  withr::local_seed(7)
  per <- sample(4:6, n, replace = TRUE)
  id <- rep(seq_len(n), per)
  time <- unlist(lapply(per, function(k) sort(stats::runif(k, 0, 10))))
  age <- rep(stats::rnorm(n, 60, 10), per)
  b0 <- rep(stats::rnorm(n, 0, 0.2), per)
  b1 <- rep(stats::rnorm(n, 0, 0.1), per)
  lt <- log(time + 1)
  ly <- 3 + 0.2 * lt + 0.01 * (age - 60) + b0 + b1 * lt + stats::rnorm(length(id), 0, 0.1)
  data.frame(ccfid = id, time = time, age = age, ly = ly)
}

# Scaffold an mm job in a fresh study holding mm_data(), work its EDIT: markers and render it.
mm_render_fixture <- function(choices = character(), .local_envir = parent.frame()) {
  root <- tempfile("mm-study-")
  withr::defer(unlink(root, recursive = TRUE), envir = .local_envir)
  suppressMessages(hvtiRutilities::study_setup(root, study = "Synthetic mm study", study_tracker_id = 42L, renv = FALSE))
  utils::write.csv(mm_data(), file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"), row.names = FALSE)
  suppressMessages(hvtiRutilities::register_data(root, file = "built.csv", role = "study",
                                                 population = "Synthetic cohort", key = c("ccfid", "time")))
  job <- add_job("mm", "outcome", "mixed", dir = root)
  lines <- gsub("EDIT:", "REVIEWED:", readLines(job, warn = FALSE), fixed = TRUE)
  defaults <- c('OUTCOME <- "y"', 'RESPONSE_SCALE <- "log"', 'TIME_TERMS <- c("log(time + 1)")')
  for (replacement in c(defaults, choices)) {
    key <- sub(" .*", "", replacement)
    hit <- which(grepl(paste0("^", key, " <- "), lines))
    stopifnot(length(hit) >= 1L)
    lines[hit[1L]] <- replacement
  }
  writeLines(lines, job)
  quarto::quarto_render(job, execute_dir = dirname(job), quiet = TRUE)
  list(root = root, job = job, output = sub("[.]qmd$", ".html", job))
}
