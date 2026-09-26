# Rebuild the reference set in dev/demo/reference/: the figures a demo run
# should produce, and the numbers its reports should print.
#
#   Rscript dev/demo/make-reference.R
#
# Run it when a template or an upstream package changes what the demo draws,
# look at the diff, and commit it only if the change is intended. The numbers
# come from the demo data through the functions the jobs call, not from
# scraping the reports, so a report that prints something else is the report
# disagreeing with its own engine.

.here <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
.dir <- if (length(.here)) dirname(.here) else "dev/demo"
source(file.path(.dir, "demo-study.R"))
out <- file.path(.dir, "reference")
dir.create(out, showWarnings = FALSE)

root <- demo_study(file.path(tempfile("reference-"), "study"))
reports <- demo_jobs(root)

# ---- Figures -----------------------------------------------------------------
# One of each kind, not every page: dp-postage is left out because test-dp-eda.R
# already proves its pages are byte-identical to dp-eda's.
graphs <- file.path(study_dir("graphs", root), "cohort-demo")
figures <- c("dp-trends-chf-all.png", "dp-trends-lvmass-all.png",
             "dp-gfup-all.png", "dp-gfup-reop.png",
             "dp-eda-continuous-page-01.png", "dp-eda-percent-page-01.png",
             "dp-eda-count-page-01.png")
stopifnot(all(file.exists(file.path(graphs, figures))))
unlink(list.files(out, "[.]png$", full.names = TRUE))
invisible(file.copy(file.path(graphs, figures), out))

# ---- Numbers -----------------------------------------------------------------
d <- read_built(study_config(root))
fc <- followup_check(d, event = "dead", followup = "iv_dead")
fp <- hvtiPlotR::hv_followup_panels(
  d, opyrs_col = "iv_opyrs", origin_year = 1990, close_date = as.Date("2025-12-31"),
  panels = list(all = list(status = "dead", time = "iv_dead", title = "All deaths")),
  events = list(reop = list(event = "reop", time = "iv_reop", death = "dead",
                            death_time = "iv_dead", label = "Reoperation"))
)
# dp-eda's default VARIABLES: every column but the x variable and the columns
# that look like an identifier or a date.
vars <- setdiff(names(d), c("year", "patient_id", "op_date"))
n_vars <- vapply(c("continuous", "percent", "count"), function(s) {
  hvtiPlotR::hv_eda_pages(d, x_col = "year", section = s, vars = vars)$meta$n_vars
}, integer(1L))
pct <- function(x) sprintf("%d (%.0f%%)", sum(x), 100 * mean(x))
chf <- function(years) sprintf("%.0f%%", 100 * mean(d$hx_chf[d$year %in% years]))

numbers <- data.frame(
  report = c(rep("all", 2L), rep("dc-tables", 4L), rep("dp-trends", 2L),
             rep("dc-gfup", 3L), rep("dp-gfup", 3L), rep("dp-eda", 4L)),
  quantity = c(
    "rows", "columns",
    "Age at operation, median", "Female, n (%)", "Race White, n (%)", "Creatinine, N non-missing",
    "Heart failure, operations 1990-1994", "Heart failure, operations 2020-2024",
    "Deaths", "Censored", "Zero follow-up intervals",
    "Close date", "All deaths, patients drawn", "Reoperation, patients drawn",
    "Left out as identifier or date", "Continuous variables", "Categorical variables, percent",
    "Categorical variables, counts"
  ),
  value = c(
    nrow(d), ncol(d),
    stats::median(d$age), pct(d$female), pct(d$race_grp == "White"), sum(!is.na(d$creat_pr)),
    chf(1990:1994), chf(2020:2024),
    fc$cohort$event, fc$cohort$censored, fc$intervals$zero,
    format(fp$meta$close_date), fp$data$n_drawn[fp$data$panel == "all"],
    fp$data$n_drawn[fp$data$panel == "reop"],
    "patient_id, op_date", n_vars[["continuous"]], n_vars[["percent"]], n_vars[["count"]]
  )
)
# The reports must print what the reference says, or the reference is wrong.
# Checked against the text of each rendered report, not against its source.
report_text <- function(name) {
  html <- paste(readLines(reports[[name]], warn = FALSE), collapse = "\n")
  gsub("\\s+", " ", gsub("<[^>]+>", " ", html))
}
must_show <- list(
  "dc-tables" = c(pct(d$female), pct(d$race_grp == "White")),
  "dp-eda" = c(sprintf("Continuous variables (%d)", n_vars[["continuous"]]),
               sprintf("Categorical variables, percent (%d)", n_vars[["percent"]]),
               sprintf("Categorical variables, counts (%d)", n_vars[["count"]]),
               "patient_id, op_date")
)
for (name in names(must_show)) {
  text <- report_text(name)
  absent <- must_show[[name]][!vapply(must_show[[name]], grepl, logical(1L), x = text, fixed = TRUE)]
  if (length(absent)) stop(name, " does not print: ", paste(absent, collapse = "; "), call. = FALSE)
}

utils::write.csv(numbers, file.path(out, "key-numbers.csv"), row.names = FALSE)
print(numbers, right = FALSE)
message("Reference written to ", normalizePath(out))
