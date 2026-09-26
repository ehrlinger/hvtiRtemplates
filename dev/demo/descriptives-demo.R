# Descriptives demo: tables, trends, goodness of follow-up and EDA plots.
#
# Builds a synthetic study, scaffolds one job from each descriptive template
# with add_job(), sets each job's study choices the way a study author would,
# and renders them. Every number is simulated: no study, patient or
# identifier from any real dataset appears here.
#
#   Rscript dev/demo/descriptives-demo.R            # renders into a temp study
#   Rscript dev/demo/descriptives-demo.R ~/eda-demo # or into a folder you keep
#
# Walk-through order for the meeting, each an HTML report beside its job:
#   1. dc-tables   the CORR Word table (descriptive/cohort-demo-dc-tables.qmd)
#   2. dp-trends   trends over operation year (graphs/)
#   3. dc-gfup     follow-up interval checks (descriptive/)
#   4. dp-gfup     the goodness-of-follow-up figure (graphs/)
#   5. dp-postage  EDA postage stamps by section (descriptive/)
#   6. dp-eda      the whole EDA report in one render (descriptive/)
#
# Needs hvtiRtemplates with dp-eda, hvtiPlotR >= 2.7.17, hvtiRutilities >=
# 1.4.1, hvtiRtables, patchwork, quarto (the R package and the CLI).

suppressPackageStartupMessages({
  library(hvtiRtemplates)
  library(hvtiRutilities)
})

args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) path.expand(args[[1L]]) else file.path(tempdir(), "descriptives-demo")
if (dir.exists(root)) stop("Demo folder already exists: ", root, ". Remove it or name another.", call. = FALSE)
dir.create(dirname(root), recursive = TRUE, showWarnings = FALSE)

# ---- 1. A synthetic cohort ---------------------------------------------------
# 800 operations from 1990 to 2024, followed to a close date of 2025-12-31.
# The shapes are chosen to give the reports something to find: heart failure
# falls over the years, LV mass drifts down, creatinine is missing for about
# 8%, and one patient in ten is lost to follow-up early, which the
# goodness-of-follow-up figure shows as blue points well below the diagonal.
set.seed(20260928)
n <- 800L
origin <- 1990
close_date <- as.Date("2025-12-31")
iv_opyrs <- sort(stats::runif(n, 0, 35))
year <- origin + floor(iv_opyrs)
op_date <- as.Date(paste0(origin, "-01-01")) + round(iv_opyrs * 365.25)
potential <- as.numeric(close_date - op_date) / 365.25
era <- (year - origin) / 35
age <- round(stats::rnorm(n, 58 + 8 * era, 12))
female <- stats::rbinom(n, 1L, 0.35)
hx_dm <- stats::rbinom(n, 1L, 0.15 + 0.15 * era)
hx_chf <- stats::rbinom(n, 1L, 0.45 - 0.30 * era)
nyha_pr <- pmin(4L, pmax(1L, round(stats::rnorm(n, 2.6 - 0.6 * era, 0.8))))
race_grp <- sample(c("White", "Black", "Other"), n, TRUE, c(0.78, 0.14, 0.08))
bmi <- round(stats::rnorm(n, 27 + 2 * era, 4.5), 1)
lvef <- round(pmin(75, pmax(15, stats::rnorm(n, 55 - 10 * hx_chf, 9))))
plvmassi <- round(stats::rnorm(n, 135 - 25 * era, 28))
creat_pr <- round(stats::rlnorm(n, log(1.0) + 0.1 * hx_dm, 0.3), 2)
creat_pr[stats::runif(n) < 0.08] <- NA
t_death <- stats::rexp(n, 1 / (25 - 0.2 * (age - 58)))
lost <- stats::runif(n) < 0.10
t_censor <- ifelse(lost, stats::runif(n, 0, potential), potential)
dead <- as.integer(t_death <= t_censor)
iv_dead <- round(pmin(t_death, t_censor), 3)
t_reop <- stats::rexp(n, 1 / 30)
reop <- as.integer(t_reop < iv_dead)
iv_reop <- round(pmin(t_reop, iv_dead), 3)

built <- data.frame(
  patient_id = sprintf("DEMO%04d", seq_len(n)), op_date,
  iv_opyrs = round(iv_opyrs, 3), year, age, female, race_grp, bmi,
  hx_chf, hx_dm, nyha_pr, lvef, plvmassi, creat_pr,
  dead, iv_dead, reop, iv_reop
)
labels <- c(
  patient_id = "Patient identifier (synthetic)", op_date = "Date of operation",
  iv_opyrs = "Years from 1 January 1990 to operation", year = "Year of operation",
  age = "Age at operation (years)", female = "Female", race_grp = "Race",
  bmi = "Body mass index (kg/m2)", hx_chf = "History of heart failure",
  hx_dm = "Diabetes", nyha_pr = "NYHA functional class", lvef = "LV ejection fraction (%)",
  plvmassi = "LV mass index (g/m2)", creat_pr = "Creatinine (mg/dL)",
  dead = "Death", iv_dead = "Follow-up to death or censoring (years)",
  reop = "Reoperation", iv_reop = "Follow-up to reoperation (years)"
)
for (v in names(labels)) attr(built[[v]], "label") <- labels[[v]]

# ---- 2. A study around it ----------------------------------------------------
# .rds keeps the variable labels, which the EDA pages and tables print; a .csv
# would drop them and every panel would be titled by its column name.
# study_setup() and register_data() print a study checklist; the demo keeps
# the console for the render progress.
invisible(utils::capture.output(suppressMessages(study_setup(
  root, study = "Descriptives demo (synthetic)", study_tracker_id = 1L,
  umbrella = "Demo", owner = "CORR", irb_number = "DEMO", cvir_no = "DEMO"
))))
data_dir <- study_dir("datasets", root)
saveRDS(built, file.path(data_dir, "built.rds"))
invisible(utils::capture.output(suppressMessages(register_data(
  root, built = "built.rds", role = "study", population = "Synthetic cohort, 800 operations"
))))

# ---- 3. Scaffold and set each job --------------------------------------------
# set_choices() is what a study author does by hand: replace the lines under
# the EDIT: markers, then resolve the markers. Each pattern must match exactly
# one line, so a template change that moves a choice stops the demo instead of
# rendering the default silently. The demo reads the whole built cohort
# (ANALYSIS_SET <- NULL), so it needs no hvtiRdatabuild analysis set.
set_choices <- function(job, choices) {
  lines <- readLines(job, warn = FALSE)
  for (pattern in names(choices)) {
    hit <- grep(pattern, lines)
    if (length(hit) != 1L) stop(basename(job), ": expected one line matching ", pattern, call. = FALSE)
    lines[hit] <- choices[[pattern]]
  }
  # Resolving the markers is what lets render_job(final = TRUE) accept the job.
  writeLines(gsub("EDIT:", "Demo:", lines, fixed = TRUE), job)
  job
}
whole_cohort <- list("^ANALYSIS_SET <- " = "ANALYSIS_SET <- NULL")
reop_event <- list("^EVENTS <- list\\(\\)$" = paste0(
  "EVENTS <- list(reop = list(event = \"reop\", time = \"iv_reop\", death = \"dead\", ",
  "death_time = \"iv_dead\", label = \"Reoperation\"))"
))
close <- list("^CLOSE_DATE <- NULL$" = "CLOSE_DATE <- as.Date(\"2025-12-31\")")

jobs <- c(
  "dc-tables" = set_choices(add_job("dc", "cohort", "demo", dir = root, qualifier = "tables"), c(
    whole_cohort,
    # GROUPS spans several lines; replace its two group lines, keep its brackets.
    list("^  Demography = c\\(\"age\", \"female\"\\),$" = paste(
      "  Demography = c(\"age\", \"female\", \"race_grp\", \"bmi\"),",
      "  History    = c(\"hx_chf\", \"hx_dm\", \"nyha_pr\"),",
      "  Echo       = c(\"lvef\", \"plvmassi\"),", sep = "\n"
    ),
    "^  Symptoms   = c\\(\"nyha_pr\"\\)$" = "  Laboratory = \"creat_pr\"")
  )),
  "dp-trends" = set_choices(add_job("dp", "cohort", "demo", dir = root, qualifier = "trends"), list(
    "^d\\$year <- floor\\(d\\$iv_opyrs\\) \\+ 1985$" = "d$year <- floor(d$iv_opyrs) + 1990",
    "^SUBGROUPS <- " = paste0("SUBGROUPS <- list(all = function(d) rep(TRUE, nrow(d)), ",
                              "diabetic = function(d) d$hx_dm == 1)")
  )),
  "dc-gfup" = set_choices(add_job("dc", "cohort", "demo", dir = root, qualifier = "gfup"), c(
    whole_cohort, list("^CHECKS <- list\\(\\)$" = "CHECKS <- list(c(\"dead\", \"reop\"))")
  )),
  "dp-gfup" = set_choices(add_job("dp", "cohort", "demo", dir = root, qualifier = "gfup"),
                          c(whole_cohort, close, reop_event)),
  "dp-postage" = set_choices(add_job("dp", "cohort", "demo", dir = root, qualifier = "postage"),
                             whole_cohort),
  "dp-eda" = set_choices(add_job("dp", "cohort", "demo", dir = root, qualifier = "eda"),
                         c(whole_cohort, close, reop_event))
)

# ---- 4. Render ---------------------------------------------------------------
# final = TRUE: an unresolved EDIT: marker would stop the render rather than
# print a DRAFT banner, which is how an accepted result is rendered.
for (name in names(jobs)) {
  message("Rendering ", name, " ...")
  render_job(jobs[[name]], final = TRUE, quiet = TRUE)
}
reports <- sub("[.]qmd$", ".html", jobs)
stopifnot(all(file.exists(reports)))
message("\nStudy: ", root, "\n", paste0("  ", names(reports), ": ", reports, collapse = "\n"))
if (interactive()) for (r in reports) utils::browseURL(r)
invisible(reports)
