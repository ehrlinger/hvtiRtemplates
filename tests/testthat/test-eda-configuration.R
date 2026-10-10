test_that("jobs present their study choices before reading data", {
  files <- c("10_descriptive/dc-general.qmd", "10_descriptive/dc-gfup.qmd",
             "10_descriptive/dc-tables.qmd", "10_descriptive/dc-eda.qmd",
             "20_distributions/ac.qmd", "20_distributions/hz.qmd",
             "30_analyses/bc.qmd", "30_analyses/bh.qmd", "30_analyses/bl.qmd",
             "30_analyses/br.qmd", "30_analyses/hm.qmd",
             "10_descriptive/dc-trends.qmd",
             "40_graphs/hp.qmd", "40_graphs/hs-concordance.qmd",
             "40_graphs/hs-setup.qmd")
  required <- list(
    `dc-general.qmd` = c("DATASET", "ANALYSIS_SET", "CATEGORICAL", "CONTINUOUS", "ID"),
    `dc-gfup.qmd` = c("DATASET", "ANALYSIS_SET", "EVENT", "FOLLOWUP", "CHECKS", "OPYRS", "ORIGIN_YEAR",
                      "CLOSE_DATE", "PANELS", "EVENTS", "ALPHA", "COLORS"),
    `dc-tables.qmd` = c("DATASET", "ANALYSIS_SET", "GROUPS", "WORD_FILE", "CORR"),
    `dc-eda.qmd` = c("DATASET", "ANALYSIS_SET", "OPYRS", "ORIGIN_YEAR", "CLOSE_DATE", "PANELS", "EVENTS",
                     "X_VAR", "VARIABLES", "GRID_NCOL", "SECTIONS", "ALPHA"),
    `ac.qmd` = c("DATASET", "ANALYSIS_SET", "WHERE", "ID", "KEY", "DERIVED", "TIME", "EVENT", "grid", "labs"),
    `hz.qmd` = c("DATASET", "ANALYSIS_SET", "WHERE", "ID", "KEY", "TIME", "EVENT", "phases", "theta0"),
    `bc.qmd` = c("EXPECT_BOOT", "BOOT_FILE", "RETAIN_PCT", "CLUSTERS", "COLLINEAR_R"),
    `bh.qmd` = c("EXPECT_CHUNKS", "EXPECT_BOOT", "BOOT_PREFIX", "RETAIN_PCT", "CLUSTERS", "COLLINEAR_R"),
    `bl.qmd` = c("EXPECT_BOOT", "BOOT_FILE", "RETAIN_PCT", "CLUSTERS", "COLLINEAR_R"),
    `br.qmd` = c("EXPECT_BOOT", "BOOT_FILE", "RETAIN_PCT", "CLUSTERS", "COLLINEAR_R"),
    `hm.qmd` = c("DATASET", "ANALYSIS_SET", "WHERE", "ID", "KEY", "TIME", "EVENT", "SAS_JOB", "SAS_MACRO",
                 "SHAPE_PARAMS", "DECILE_TIME"),
    `dc-trends.qmd` = c("DATASET", "ANALYSIS_SET", "WHERE", "ID", "KEY", "TRENDS", "XBREAKS", "SUBGROUPS"),
    `hp.qmd` = c("DATASET", "ANALYSIS_SET", "WHERE", "ID", "KEY", "years", "t_max", "TIME", "EVENT"),
    `hs-concordance.qmd` = c("DATASET", "ANALYSIS_SET", "WHERE", "ID", "KEY", "TIME", "EVENT", "MODELS", "GROUP",
                             "HORIZON", "CARRY", "OVERLAP", "CROSS_STUDY"),
    `hs-setup.qmd` = c("DATASET", "ANALYSIS_SET", "WHERE", "ID", "KEY", "TIME", "EVENT", "HORIZONS", "AGE_COL",
                       "MALE_COL", "SCALE")
  )
  root <- system.file("templates", package = "hvtiRtemplates")
  if (!nzchar(root)) {
    root <- testthat::test_path("..", "..", "inst", "templates")
  }
  for (file in files) {
    lines <- readLines(file.path(root, file), warn = FALSE)
    config <- grep("^#\\| label: edit-study-choices$", lines)
    first_work <- grep("^#\\| label: (edit-)?(tbl-)?(data|cohort|expect|read-upstream)$", lines)[1L]
    expect_true(length(config) == 1L, info = file)
    if (length(config) != 1L) next
    expect_true(config < first_work, info = file)
    end <- config + which(lines[(config + 1L):length(lines)] == "```")[[1L]]
    choices <- lines[(config + 1L):(end - 1L)]
    expect_true(any(grepl("^# EDIT:", choices)), info = paste(file, "edit markers"))
    # hm, hp and hs set TIME and EVENT again in their data chunk, from the
    # selection hz recorded. That is not a second place to edit them.
    data_at <- grep("^#\\| label: tbl-data$", lines)
    outside <- lines
    if (length(data_at) == 1L) {
      data_end <- data_at + which(lines[(data_at + 1L):length(lines)] == "```")[[1L]]
      outside <- lines[-seq.int(data_at, data_end)]
    }
    for (name in required[[basename(file)]]) {
      expect_true(any(grepl(paste0("^", name, "[[:space:]]*<-"), choices)),
                  info = paste(file, name))
      if (name != "VARIABLES") {
        expect_equal(sum(grepl(paste0("^", name, "[[:space:]]*<-"), outside)), 1L,
                     info = paste(file, name, "must have one edit point"))
      }
    }
  }
})
