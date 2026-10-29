# Datasets family: bd, the job that cuts a study's dataset from a master
# snapshot and checks its cut before it is registered. bd's
# prepare() makes the snapshot the way a real one is made, a SAS
# dataset run through hvtiRdatabuild::snapshot_master(), so the parquet and its
# .meta.json sidecar are the real formats. The "master" is the gallery's own
# simulated cohort, read back from the study it is registered in, so it adds
# no columns and draws nothing.
#
# REGISTER stays FALSE, the template's own choice: bd writes its working file,
# datasets/study_cohort.rds, and registers nothing, so every later job still
# reads the gallery's registered built.rds. Registering would make bd's cut the
# study's dataset and move every report after it.
#
# The file name sorts first, so bd renders before every other job, as a
# study's dataset build runs before the analyses that read it.

# The cohort columns the master carries: the demo's own, as a master names them.
bd_master_columns <- c("patient_id", "dt_surg", "iv_opyrs", "age", "female", "race_grp", "bmi", "hx_chf",
                       "hx_dm", "nyha_pr", "lvef", "plvmassi", "creat_pr", "dead", "iv_dead")

bd_master <- function(root, job) {
  dir <- file.path(root, "master")
  dir.create(dir, showWarnings = FALSE)
  d <- readRDS(file.path(study_dir("datasets", root), "built.rds"))[bd_master_columns]
  # write_sas() is superseded in haven, and warns so; it still writes a file
  # haven and snapshot_master() read back.
  suppressWarnings(haven::write_sas(d, file.path(dir, "built.sas7bdat")))
  writeLines("data master; run;", file.path(dir, "bd.data.sas"))
  cfg <- file.path(dir, "master.yml")
  writeLines(c("name: master_gallery", "key: [patient_id]", paste0("snapshots: ", dir), "current: built.sas7bdat",
               paste0("build_program: ", file.path(dir, "bd.data.sas"))), cfg)
  invisible(utils::capture.output(suppressMessages(
    hvtiRdatabuild::snapshot_master(hvtiRdatabuild::read_master_config(cfg), file.path(dir, "snapshot"),
                                    which = "current")
  )))
}

gallery_family(
  "datasets",
  jobs = list(
    "bd" = list(subject = "study", type = "build", prepare = bd_master, choices = list(
      # Named from the study root, so the job file carries no machine's path.
      "^MASTER <- " = "MASTER <- file.path(.root, \"master\", \"snapshot\", \"built.parquet\")",
      "^KEEP <- c\\(" = paste0("KEEP <- c(\"dt_surg\", \"age\", \"female\", \"race_grp\", \"bmi\", \"hx_chf\", \"hx_dm\", ",
                               "\"nyha_pr\", \"lvef\", \"creat_pr\", \"dead\", \"iv_dead\")"),
      # The creatinine rule shows the SAS reading of a missing condition: about
      # 8% of creatinine is missing, and those rows are kept and counted.
      "^EXCLUDE <- " = paste(
        "EXCLUDE <- list(",
        "  is.na(dt_surg) ~ \"No surgery date\",",
        "  dt_surg < as.Date(\"1995-01-01\") ~ \"Operated before 1995\",",
        "  creat_pr > 2 ~ \"Creatinine over 2 mg/dL\"",
        ")", sep = "\n"
      ),
      "^ID  <- " = "ID  <- \"patient_id\"",
      "^CROSSTABS <- list\\(c\\(\"dead\", \"sex\"\\)\\)$" = "CROSSTABS <- list(c(\"dead\", \"female\"))",
      "^#   d\\$dead    <- " = paste(
        "#   d$dead    <- as.integer(!is.na(d$dt_death))",
        "d$op_year <- as.integer(format(d$dt_surg, \"%Y\"))", sep = "\n"
      )
    ))
  )
)
