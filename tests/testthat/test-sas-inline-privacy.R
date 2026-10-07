# These tests migrate 128 SAS files, each into a study of its own. Building the
# study is most of the cost of a call, so one is built per file and each call
# gets a copy of it, which is what a fresh build would produce.
inline_privacy_cache <- new.env()
inline_privacy_file_env <- environment()
inline_privacy_study <- function(.local_envir = parent.frame()) {
  if (is.null(inline_privacy_cache$root)) {
    inline_privacy_cache$root <- migration_study_fixture(.local_envir = inline_privacy_file_env)
  }
  root <- withr::local_tempdir(.local_envir = .local_envir)
  from <- list.files(inline_privacy_cache$root, all.files = TRUE, no.. = TRUE, full.names = TRUE)
  stopifnot(all(file.copy(from, root, recursive = TRUE, copy.date = TRUE)))
  root
}

# migrate_job() lists the templates, and reads the template catalog, several
# times a call. Neither can change while the file runs, so each is read once, by
# the real template_list() and template_catalog(), and served from that read for
# the rest of the test.
local_template_list_once <- function(.local_envir = parent.frame()) {
  listed <- template_list()
  catalog <- template_catalog()
  testthat::local_mocked_bindings(template_list = function() listed, template_catalog = function() catalog,
                                  .package = "hvtiRtemplates", .env = .local_envir)
}

inline_privacy_migrate <- function(root, kind, middle, after = TRUE) {
  prefix <- if (startsWith(kind, "dc-")) "dc" else "dp"
  qualifier <- sub("^[^-]+-", "", kind)
  before <- switch(kind,
    "dc-tables" = "%desc_tab(vartype=continuous,input=built,varlist=/* Before */ age);",
    "dc-gfup" = "set built; proc means; var iv_dead; by dead; run;",
    "dp-trends" = "set built; year=floor(iv_opyrs)+1985; %let continuous=lvmassi;",
    "dp-eda" = "set built; %let pref_time_var=iv_dead; %let variables=age;"
  )
  suffix <- switch(kind,
    "dc-tables" = "%desc_tab(vartype=continuous,input=built,varlist=/* After */ bmi);",
    "dc-gfup" = "proc means; var iv_fup; run;",
    "dp-trends" = "%let percent=hx_chf;",
    "dp-eda" = "%let ncol=2;"
  )
  path <- file.path(root, "descriptive", "inline.sas")
  writeLines(c(before, middle, if (after) c("age=age+10; if female=1;", suffix)), path)
  hash <- tools::md5sum(path)
  job <- migrate_job(path, "cohort", "eda", prefix, qualifier, dir = root)
  list(job = readLines(job), report = readLines(sub("[.]qmd$", "-migration.md", job)),
       unchanged = identical(tools::md5sum(path), hash))
}

test_that("every SAS adapter withholds all inline aliases after apostrophe comments", {
  local_template_list_once()
  for (kind in c("dc-tables", "dc-gfup", "dp-trends", "dp-eda")) {
    for (alias in c("datalines", "cards", "lines", "datalines4", "cards4", "lines4")) {
      for (comment in c("* don't disclose records;", "%* don't disclose records;")) {
        out <- inline_privacy_migrate(inline_privacy_study(), kind, c(
          comment, paste0(alias, ";"), "PATIENT_SENTINEL_472 43", "PATIENT_SENTINEL_938 ' unbalanced",
          if (endsWith(alias, "4")) ";;;;" else ";"
        ))
        expect_false(any(grepl("PATIENT_SENTINEL", c(out$job, out$report), fixed = TRUE)), info = paste(kind, alias, comment))
        expect_true(any(grepl("line=4; text=Inline SAS data content withheld", out$report, fixed = TRUE)))
        expect_true(any(grepl("age=age+10;", out$report, fixed = TRUE)))
        expect_true(any(grepl("if female=1;", out$report, fixed = TRUE)))
        expect_true(any(grepl("EDIT:.*withheld", out$job)))
        expected <- switch(kind, "dc-tables" = "After =", "dc-gfup" = "iv_fup",
                           "dp-trends" = "hx_chf", "dp-eda" = "GRID_NCOL <- 2L")
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
  local_template_list_once()
  for (alias in c("datalines", "cards", "lines", "datalines4", "cards4", "lines4")) {
    terminator <- if (endsWith(alias, "4")) ";;;;" else ";"
    cases <- c(cases, list(
      c(paste0(alias, "; PATIENT_SENTINEL_472 43", terminator), "PATIENT_SENTINEL_938 51", terminator),
      c(paste0(alias, "; PATIENT_SENTINEL_472 43", terminator), "PATIENT_SENTINEL_938 51"),
      c(paste0(alias, ";"), "PATIENT_SENTINEL_472 ' unmatched quote")
    ))
  }
  for (kind in c("dc-tables", "dc-gfup", "dp-trends", "dp-eda")) {
    for (rows in cases) {
      out <- inline_privacy_migrate(inline_privacy_study(), kind, rows, after = FALSE)
      expect_false(any(grepl("PATIENT_SENTINEL", c(out$job, out$report), fixed = TRUE)), info = paste(kind, rows[[1L]]))
      expect_true(any(grepl("withheld", out$report, fixed = TRUE)))
      expect_true(any(grepl("EDIT:.*withheld", out$job)))
      expect_true(out$unchanged)
    }
  }
})
