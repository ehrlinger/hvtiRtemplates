numbered_output_chunk <- function(job, label) {
  lines <- readLines(job)
  start <- match(paste0("#| label: ", label), lines)
  end <- start + match("```", lines[-seq_len(start)])
  parse(text = lines[seq.int(start + 1L, end - 1L)])
}

test_that("numbered migrated jobs save and embed figures in their logical folders", {
  for (kind in c("dp-trends", "dc-tables")) {
    root <- normalizePath(migration_study_fixture(kind), winslash = "/")
    bare <- c("datasets", "descriptive", "distributions", "analyses", "graphs", "documents", "estimates")
    numbered <- paste0(c("00", "10", "20", "30", "40", "50", "90"), "_", bare)
    for (i in seq_along(bare)) {
      stopifnot(file.rename(file.path(root, bare[[i]]), file.path(root, numbered[[i]])))
    }
    trends <- kind == "dp-trends"
    folder <- if (trends) "40_graphs" else "10_descriptive"
    job <- migrate_job(
      file.path(root, folder, if (trends) "dp.trends.sas" else "dc.tables.sas"),
      "cohort", "eda", if (trends) "dp" else "dc", if (trends) "trends" else "tables", dir = root
    )
    expect_identical(dirname(job), file.path(root, folder))
    env <- list2env(list(
      .root = root, read_built = hvtiRutilities::read_built, study_config = hvtiRutilities::study_config,
      hv_trends = hvtiPlotR::hv_trends, theme_hv_manuscript = hvtiPlotR::theme_hv_manuscript,
      hv_correlation_table = hvtiRtables::hv_correlation_table,
      hv_correlation_matrix = hvtiPlotR::hv_correlation_matrix,
      labs = ggplot2::labs, scale_y_continuous = ggplot2::scale_y_continuous,
      scale_x_continuous = ggplot2::scale_x_continuous, coord_cartesian = ggplot2::coord_cartesian
    ))
    eval(numbered_output_chunk(job, "set"), env)
    if (trends) {
      capture.output(eval(numbered_output_chunk(job, "data"), env))
      eval(numbered_output_chunk(job, "trends"), env)
      eval(numbered_output_chunk(job, "helpers"), env)
    } else {
      env$d <- hvtiRutilities::read_built(hvtiRutilities::study_config(root))
      env$CORR <- list(vars = "age", with = "bmi", by = NULL)
    }
    printed <- capture.output(eval(numbered_output_chunk(job, if (trends) "figures" else "correlation"), env))
    filenames <- if (trends) c("dp-trends-hx_chf-all.png", "dp-trends-lvmassi-all.png") else "dc-tables-correlation-matrix.png"
    for (filename in filenames) {
      relative <- file.path("cohort-eda", filename)
      expect_true(file.exists(file.path(dirname(job), relative)))
      expect_true(any(grepl(paste0("](", relative, ")"), printed, fixed = TRUE)))
    }
    expect_false(dir.exists(file.path(root, "graphs")))
    expect_false(dir.exists(file.path(root, "descriptive", "cohort-eda")))
  }
})
