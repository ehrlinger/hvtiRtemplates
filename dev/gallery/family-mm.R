# Mixed-model family: mm, a repeated continuous response over follow-up. It
# reads the nb family's echo series, LV ejection fraction at two to six
# irregular visits per patient, so the gallery shows a linear mixed model and
# boosted trees on the same data. The series is registered by nb's prepare(),
# nb_register_echo(), called here as well because this file sorts, and so
# renders, before family-nb.R. It is wrapped, so the name is looked up when the
# job renders, by which time every family file has been sourced; the function
# writes the dataset once.
#
# Irregular times suit neither AR(1) nor UN, which need shared visits, so the
# job compares compound symmetry, the corpus's main form, with a random
# intercept and slope in time. The series' slopes depend on heart failure, age
# and sex, so each enters the fixed effects with its interaction with time;
# without them the two heart-failure profiles are forced to parallel curves,
# and the one with heart failure rises though the series falls. The random
# slope then holds only the patient-level spread the interactions leave.

gallery_family(
  "mm",
  jobs = list(
    "mm" = list(subject = "lvef", type = "mixed", prepare = function(root, job) nb_register_echo(root, job), choices = list(
      "^DATASET <- \"built\"$" = "DATASET <- \"echo\"",
      "^ID <- \"ccfid\"$" = "ID <- \"patient_id\"",
      "^TIME <- \"time\"$" = "TIME <- \"iv_echo\"",
      "^OUTCOME <- " = "OUTCOME <- \"lvef\"",
      "^TIME_TERMS <- " = "TIME_TERMS <- c(\"iv_echo\")",
      "^PREDICTORS <- " = "PREDICTORS <- c(\"age\", \"female\", \"hx_chf\", \"iv_echo:age\", \"iv_echo:female\", \"iv_echo:hx_chf\")",
      "^STRUCTURE <- " = "STRUCTURE <- c(\"cs\", \"slope\")",
      "^PREDICT_AT <- NULL$" = "PREDICT_AT <- list(list(age = 60, female = 0, hx_chf = 0), list(age = 60, female = 0, hx_chf = 1))"
    ))
  )
)
