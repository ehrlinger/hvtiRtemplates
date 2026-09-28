# Descriptive family: the six jobs the descriptives demo already renders, with
# the demo's own choices, plus dc-general. The demo cohort needs no extra
# columns for these.

gallery_family(
  "descriptive",
  jobs = c(
    lapply(demo_choices, function(choices) list(subject = "cohort", type = "eda", choices = choices)),
    list(
      "dc-general" = list(subject = "cohort", type = "eda", choices = c(whole_cohort, list(
        "^  Demography = c\\(\"female\"\\)$" = paste(
          "  Demography = c(\"female\", \"race_grp\"),",
          "  History    = c(\"hx_chf\", \"hx_dm\", \"nyha_pr\")", sep = "\n"
        ),
        "^  Demography = c\\(\"age\"\\)$" = paste(
          "  Demography = c(\"age\", \"bmi\"),",
          "  Echo       = c(\"lvef\", \"plvmassi\"),",
          "  Laboratory = \"creat_pr\"", sep = "\n"
        ),
        "^KEY_COLS <- \"ccfid\"$" = "KEY_COLS <- \"patient_id\""
      )))
    )
  )
)
