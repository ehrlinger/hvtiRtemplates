# Boosted multivariate trees family: nb-boostmtree, for a response measured
# repeatedly over follow-up. The cohort has one row per patient, so this
# family's prepare() writes a second dataset, an echocardiography series of
# one row per visit, and registers it as "echo". The job reads it by DATASET,
# keyed on patient and visit time.
#
# 300 of the cohort's patients followed a year or more have two to six
# echoes each, at irregular times inside their own follow-up (to 15 years),
# no two at one time. Ejection fraction starts at the patient's preoperative
# value and drifts with time: it falls after operation in heart failure and in
# older patients and recovers slightly in the rest, so the partial effects
# have something to find.
#
# Every number is simulated from the gallery cohort; no study appears here.

nb_echo <- function(built) {
  withr::with_seed(20261002, {
    who <- sort(sample(which(built$iv_dead >= 1), 300L))
    base <- built[who, , drop = FALSE]
    visits <- sample(2:6, nrow(base), replace = TRUE)
    rows <- rep(seq_len(nrow(base)), visits)
    # Visit times in years, drawn on a 0.001-year grid without replacement,
    # so a patient's times are unique and inside that patient's follow-up.
    iv_echo <- unlist(lapply(seq_len(nrow(base)), function(i) {
      span <- max(2L, floor(min(base$iv_dead[[i]], 15) * 1000))
      sort(sample.int(span, visits[[i]])) / 1000
    }))
    p <- base[rows, , drop = FALSE]
    slope <- 0.4 - 1.2 * p$hx_chf - 0.04 * (p$age - 60) + 0.6 * p$female
    lvef <- p$lvef + slope * iv_echo + stats::rnorm(length(rows), 0, 3)
  })
  echo <- data.frame(
    patient_id = p$patient_id, iv_echo = iv_echo, lvef = round(pmin(80, pmax(10, lvef))),
    age = p$age, female = p$female, bmi = p$bmi, hx_chf = p$hx_chf, hx_dm = p$hx_dm, nyha_pr = p$nyha_pr
  )
  labels <- c(
    patient_id = "Patient identifier (synthetic)", iv_echo = "Years from operation to echocardiogram",
    lvef = "LV ejection fraction at the echocardiogram (%)", age = "Age at operation (years)",
    female = "Female", bmi = "Body mass index (kg/m2)", hx_chf = "History of heart failure",
    hx_dm = "Diabetes", nyha_pr = "NYHA functional class"
  )
  for (v in names(labels)) attr(echo[[v]], "label") <- labels[[v]]
  echo
}

nb_register_echo <- function(root, job) {
  dir <- hvtiRutilities::study_dir("datasets", root)
  if (file.exists(file.path(dir, "echo.rds"))) return(invisible())
  saveRDS(nb_echo(readRDS(file.path(dir, "built.rds"))), file.path(dir, "echo.rds"))
  invisible(utils::capture.output(suppressMessages(hvtiRutilities::register_data(
    root, built = "echo.rds", dataset = "echo", role = "named",
    population = "Synthetic echocardiography series, 300 patients, one row per visit"
  ))))
}

gallery_family(
  "nb",
  jobs = list(
    "nb-boostmtree" = list(subject = "lvef", type = "boost", prepare = nb_register_echo, choices = list(
      "^Replaces `analyses/<job>`" =
        "Gallery job on the synthetic echo series: LV ejection fraction over follow-up (iv_echo), six baseline predictors.",
      "^DATASET <- \"study\"$" = "DATASET <- \"echo\"",
      "^ID <- \"ccfid\"$" = "ID <- \"patient_id\"",
      "^RESPONSE <- " = "RESPONSE <- \"lvef\"",
      # A study's M is in the thousands; 200 keeps the gallery fast, and the
      # error path says whether it was enough.
      "^M  <- 1000$" = "M  <- 200"
    ))
  )
)
