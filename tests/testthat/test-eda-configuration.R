test_that("jobs present their study choices before reading data", {
  files <- c("10_descriptive/dc-general.qmd", "10_descriptive/dc-gfup.qmd",
             "10_descriptive/dc-tables.qmd", "10_descriptive/dp-postage.qmd",
             "20_distributions/ac.qmd", "20_distributions/hz.qmd",
             "30_analyses/bc.qmd", "30_analyses/bh.qmd", "30_analyses/bl.qmd",
             "30_analyses/br.qmd", "30_analyses/hm.qmd", "40_graphs/dp-gfup.qmd",
             "40_graphs/dp-trends.qmd",
             "40_graphs/hp.qmd", "40_graphs/hs.qmd")
  required <- list(
    `dc-general.qmd` = c("DATASET", "ANALYSIS_SET", "CATEGORICAL", "CONTINUOUS", "KEY_COLS"),
    `dc-gfup.qmd` = c("DATASET", "ANALYSIS_SET", "EVENT", "FOLLOWUP", "CHECKS"),
    `dc-tables.qmd` = c("DATASET", "ANALYSIS_SET", "GROUPS", "WORD_FILE", "CORR"),
    `dp-postage.qmd` = c("DATASET", "ANALYSIS_SET", "X_VAR", "VARIABLES", "GRID_NCOL"),
    `ac.qmd` = c("DERIVED", "TIME", "STATUS", "grid", "labs"),
    `hz.qmd` = c("phases", "theta0"),
    `bc.qmd` = c("EXPECT_BOOT", "BOOT_FILE", "RETAIN_PCT", "CLUSTERS", "COLLINEAR_R"),
    `bh.qmd` = c("EXPECT_CHUNKS", "EXPECT_BOOT", "BOOT_PREFIX", "RETAIN_PCT", "CLUSTERS", "COLLINEAR_R"),
    `bl.qmd` = c("EXPECT_BOOT", "BOOT_FILE", "RETAIN_PCT", "CLUSTERS", "COLLINEAR_R"),
    `br.qmd` = c("EXPECT_BOOT", "BOOT_FILE", "RETAIN_PCT", "CLUSTERS", "COLLINEAR_R"),
    `hm.qmd` = c("TIME", "EVENT", "SAS_JOB", "SAS_MACRO", "SHAPE_PARAMS", "DECILE_TIME"),
    `dp-gfup.qmd` = c("DATASET", "ANALYSIS_SET", "OPYRS", "ORIGIN_YEAR", "CLOSE_DATE",
                      "PANELS", "EVENTS", "ALPHA"),
    `dp-trends.qmd` = c("DATASET", "TRENDS", "XBREAKS", "SUBGROUPS"),
    `hp.qmd` = c("years", "t_max", "TIME", "EVENT"),
    `hs.qmd` = c("TIME", "HORIZONS", "AGE_COL", "MALE_COL", "SCALE")
  )
  root <- system.file("templates", package = "hvtiRtemplates")
  if (!nzchar(root)) {
    root <- testthat::test_path("..", "..", "inst", "templates")
  }
  for (file in files) {
    lines <- readLines(file.path(root, file), warn = FALSE)
    config <- grep("^#\\| label: study-choices$", lines)
    first_work <- grep("^#\\| label: (data|cohort|expect|read-upstream)$", lines)[1L]
    expect_true(length(config) == 1L, info = file)
    if (length(config) != 1L) next
    expect_true(config < first_work, info = file)
    end <- config + which(lines[(config + 1L):length(lines)] == "```")[[1L]]
    choices <- lines[(config + 1L):(end - 1L)]
    expect_true(any(grepl("^# EDIT:", choices)), info = paste(file, "edit markers"))
    for (name in required[[basename(file)]]) {
      expect_true(any(grepl(paste0("^", name, "[[:space:]]*<-"), choices)),
                  info = paste(file, name))
      if (name != "VARIABLES") {
        expect_equal(sum(grepl(paste0("^", name, "[[:space:]]*<-"), lines)), 1L,
                     info = paste(file, name, "must have one edit point"))
      }
    }
  }
})
