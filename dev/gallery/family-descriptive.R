# Descriptive family: the four jobs the descriptives demo already renders, with
# the demo's own choices, plus dc-general and dc-stddiff. The demo cohort needs
# no extra columns for these; dc-stddiff splits it on the lm family's
# `approach`, which gallery_data() adds before any job renders.

gallery_family(
  "descriptive",
  jobs = c(
    lapply(demo_choices, function(choices) list(subject = "cohort", type = "eda", choices = choices)),
    list(
      "dc-general" = list(subject = "cohort", type = "eda", choices = c(whole_cohort, demo_id, list(
        "^  Demography = c\\(\"female\"\\)$" = paste(
          "  Demography = c(\"female\", \"race_grp\"),",
          "  History    = c(\"hx_chf\", \"hx_dm\", \"nyha_pr\")", sep = "\n"
        ),
        "^  Demography = c\\(\"age\"\\)$" = paste(
          "  Demography = c(\"age\", \"bmi\"),",
          "  Echo       = c(\"lvef\", \"plvmassi\"),",
          "  Laboratory = \"creat_pr\"", sep = "\n"
        )
      ))),
      "dc-stddiff" = list(subject = "approach", type = "balance", choices = c(whole_cohort, demo_id, list(
        "^GROUP <- " = "GROUP <- \"approach\"",
        "^GROUP_1 <- " = "GROUP_1 <- \"transcatheter\"",
        "^GAUSSIAN    <- " = "GAUSSIAN    <- c(\"age\", \"bmi\", \"lvef\")",
        "^NONG_ORD    <- " = "NONG_ORD    <- \"nyha_pr\"",
        "^BINARY      <- " = "BINARY      <- c(\"female\", \"hx_chf\", \"hx_dm\")",
        "^CATEGORICAL <- " = "CATEGORICAL <- \"race_grp\"",
        "^N_PERM <- " = "N_PERM <- 200L"
      )))
    )
  )
)
