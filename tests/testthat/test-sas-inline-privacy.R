inline_privacy_migrate <- function(root, kind, middle, after = TRUE) {
  prefix <- if (startsWith(kind, "dc-")) "dc" else "dp"
  qualifier <- sub("^[^-]+-", "", kind)
  before <- switch(kind,
    "dc-tables" = "%desc_tab(vartype=continuous,input=built,varlist=/* Before */ age);",
    "dc-gfup" = "set built; proc means; var iv_dead; by dead; run;",
    "dp-trends" = "set built; year=floor(iv_opyrs)+1985; %let continuous=lvmassi;",
    "dp-postage" = "set built; %let pref_time_var=iv_dead; %let variables=age;"
  )
  suffix <- switch(kind,
    "dc-tables" = "%desc_tab(vartype=continuous,input=built,varlist=/* After */ bmi);",
    "dc-gfup" = "proc means; var iv_fup; run;",
    "dp-trends" = "%let percent=hx_chf;",
    "dp-postage" = "%let ncol=2;"
  )
  path <- file.path(root, "descriptive", "inline.sas")
  writeLines(c(before, middle, if (after) c("age=age+10; if female=1;", suffix)), path)
  hash <- tools::md5sum(path)
  job <- migrate_job(path, "cohort", "eda", prefix, qualifier, dir = root)
  list(job = readLines(job), report = readLines(sub("[.]qmd$", "-migration.md", job)),
       unchanged = identical(tools::md5sum(path), hash))
}

test_that("every SAS adapter withholds all inline aliases after apostrophe comments", {
  for (kind in c("dc-tables", "dc-gfup", "dp-trends", "dp-postage")) {
    for (alias in c("datalines", "cards", "lines", "datalines4", "cards4", "lines4")) {
      for (comment in c("* don't disclose records;", "%* don't disclose records;")) {
        out <- inline_privacy_migrate(migration_study_fixture(), kind, c(
          comment, paste0(alias, ";"), "PATIENT_SENTINEL_472 43", "PATIENT_SENTINEL_938 ' unbalanced",
          if (endsWith(alias, "4")) ";;;;" else ";"
        ))
        expect_false(any(grepl("PATIENT_SENTINEL", c(out$job, out$report), fixed = TRUE)), info = paste(kind, alias, comment))
        expect_true(any(grepl("line=4; text=Inline SAS data content withheld", out$report, fixed = TRUE)))
        expect_true(any(grepl("age=age+10;", out$report, fixed = TRUE)))
        expect_true(any(grepl("if female=1;", out$report, fixed = TRUE)))
        expect_true(any(grepl("EDIT:.*withheld", out$job)))
        expected <- switch(kind, "dc-tables" = "After =", "dc-gfup" = "iv_fup",
                           "dp-trends" = "hx_chf", "dp-postage" = "GRID_NCOL <- 2L")
        expect_true(any(grepl(expected, out$job, fixed = TRUE)), info = kind)
        expect_true(out$unchanged)
      }
    }
  }
})

test_that("SAS adapters fail closed for ambiguous delimiters and uncertain tokens", {
  cases <- list(
    c("title 'unterminated", "datalines;", "PATIENT_SENTINEL_472 43", ";"),
    c("/* unfinished comment", "cards;", "PATIENT_SENTINEL_472 43", ";")
  )
  for (alias in c("datalines", "cards", "lines", "datalines4", "cards4", "lines4")) {
    terminator <- if (endsWith(alias, "4")) ";;;;" else ";"
    cases <- c(cases, list(
      c(paste0(alias, "; PATIENT_SENTINEL_472 43", terminator), "PATIENT_SENTINEL_938 51", terminator),
      c(paste0(alias, "; PATIENT_SENTINEL_472 43", terminator), "PATIENT_SENTINEL_938 51"),
      c(paste0(alias, ";"), "PATIENT_SENTINEL_472 ' unmatched quote")
    ))
  }
  for (kind in c("dc-tables", "dc-gfup", "dp-trends", "dp-postage")) {
    for (rows in cases) {
      out <- inline_privacy_migrate(migration_study_fixture(), kind, rows, after = FALSE)
      expect_false(any(grepl("PATIENT_SENTINEL", c(out$job, out$report), fixed = TRUE)), info = paste(kind, rows[[1L]]))
      expect_true(any(grepl("withheld", out$report, fixed = TRUE)))
      expect_true(any(grepl("EDIT:.*withheld", out$job)))
      expect_true(out$unchanged)
    }
  }
})
