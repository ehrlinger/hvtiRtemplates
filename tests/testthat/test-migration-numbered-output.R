numbered_output_chunk <- function(job, label) {
  lines <- readLines(job)
  # A chunk holding an EDIT: marker is labeled edit-<label>; either names it.
  start <- grep(paste0("^#\\| label: (edit-)?", label, "$"), lines)[[1L]]
  end <- start + match("```", lines[-seq_len(start)])
  parse(text = lines[seq.int(start + 1L, end - 1L)])
}

test_that("numbered migrated jobs save and embed figures in their logical folders", {
  for (kind in c("dc-trends", "dc-tables")) {
    root <- normalizePath(migration_study_fixture(kind), winslash = "/")
    bare <- c("datasets", "descriptive", "distributions", "analyses", "graphs", "documents", "estimates")
    numbered <- paste0(c("00", "10", "20", "30", "40", "50", "90"), "_", bare)
    for (i in seq_along(bare)) {
      stopifnot(file.rename(file.path(root, bare[[i]]), file.path(root, numbered[[i]])))
    }
    trends <- kind == "dc-trends"
    # The legacy trends job sat in graphs; its dc-trends job is written to descriptive.
    folder <- if (trends) "40_graphs" else "10_descriptive"
    job <- migrate_job(
      file.path(root, folder, if (trends) "dp.trends.sas" else "dc.tables.sas"),
      "cohort", "eda", "dc", if (trends) "trends" else "tables", dir = root
    )
    expect_identical(dirname(job), file.path(root, "10_descriptive"))
    env <- list2env(list(
      .root = root, read_built = hvtiRutilities::read_built, study_config = hvtiRutilities::study_config,
      hv_trends = hvtiPlotR::hv_trends, theme_hv_manuscript = hvtiPlotR::theme_hv_manuscript,
      hv_correlation_table = hvtiRtables::hv_correlation_table,
      hv_correlation_matrix = hvtiPlotR::hv_correlation_matrix,
      labs = ggplot2::labs, scale_y_continuous = ggplot2::scale_y_continuous,
      scale_x_continuous = ggplot2::scale_x_continuous, coord_cartesian = ggplot2::coord_cartesian
    ))
    # The figure link is worked out from the job's own folder, as a render does.
    env$.in <- job
    eval(numbered_output_chunk(job, "set"), env)
    if (trends) {
      eval(numbered_output_chunk(job, "edit-study-choices"), env)
      capture.output(eval(numbered_output_chunk(job, "tbl-data"), env))
      capture.output(eval(numbered_output_chunk(job, "year"), env))
      capture.output(eval(numbered_output_chunk(job, "tbl-year-check"), env))
      eval(numbered_output_chunk(job, "helpers"), env)
    } else {
      env$d <- hvtiRutilities::read_built(hvtiRutilities::study_config(root))
      env$CORR <- list(vars = "age", with = "bmi", by = NULL)
      env$SAVE_FIGURES <- TRUE
      env$FIGURES <- NULL
    }
    # The figures are child chunks. A render sets knitr up for markdown and runs the
    # chunk in the job's folder; here the output is markdown and the working directory a scratch one.
    scratch <- withr::local_tempdir()
    withr::local_options(knitr.duplicate.label = "allow")
    knitr::render_markdown()
    withr::defer(knitr::knit_hooks$restore())
    printed <- withr::with_dir(scratch, capture.output(
      eval(numbered_output_chunk(job, if (trends) "figures" else "correlation"), env)
    ))
    filenames <- if (trends) c("dc-trends-hx_chf-all.png", "dc-trends-lvmassi-all.png") else "dc-tables-correlation-matrix.png"
    # A trends figure is written to graphs beside a job in descriptive, and linked across.
    relative_dir <- if (trends) file.path("..", "40_graphs", "cohort-eda") else "cohort-eda"
    for (filename in filenames) {
      relative <- file.path(relative_dir, filename)
      expect_true(file.exists(file.path(dirname(job), relative)))
      # Its publication copy sits beside it, under the same name.
      expect_true(file.exists(file.path(dirname(job), sub("[.]png$", ".pdf", relative))))
      expect_true(any(grepl(paste0("](", relative, ")"), printed, fixed = TRUE)))
    }
    expect_false(dir.exists(file.path(root, "graphs")))
    expect_false(dir.exists(file.path(root, "descriptive", "cohort-eda")))
  }
})
