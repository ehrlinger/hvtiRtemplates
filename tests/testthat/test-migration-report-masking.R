# Every value below is synthetic. Each one stands for an identifier a legacy
# job can carry in code: the report must mask it whatever converter runs.
sas_sentinels <- c(
  "SENTINEL_DQ", "SENTINEL_SQ", "SENTINEL_SQL1", "SENTINEL_SQL2", "SENTINEL_LET", "SENTINEL_TITLE",
  "SENTINEL_BLOCK1", "SENTINEL_BLOCK2", "SENTINEL_MULTI", "SENTINEL_STAR", "SENTINEL_MACROSTAR",
  "SENTINEL_PATH", "7654321", "MRN0000001"
)

sas_planted_lines <- c(
  "%let study = SENTINEL_LET;",
  "filename out \"&root/studies/SENTINEL_PATH dir/z.sas\";",
  "title2 \"Cohort for SENTINEL_TITLE\";",
  "/* don't use SENTINEL_BLOCK1; SENTINEL_BLOCK2 */",
  "/* first line of a comment",
  "   SENTINEL_MULTI */",
  "* SENTINEL_STAR excluded;",
  "%* SENTINEL_MACROSTAR;",
  "data drop; set nothing;",
  "if mrn = \"SENTINEL_DQ\" then delete;",
  "if ccfid = 7654321 then delete;",
  "where mrn='SENTINEL_SQ' and id = MRN0000001;",
  "run;",
  "proc sql; insert into t values ('SENTINEL_SQL1', \"SENTINEL_SQL2\"); quit;"
)

masked_report <- function(job) {
  paste(readLines(sub("[.]qmd$", "-migration.md", job), warn = FALSE), collapse = "\n")
}

expect_no_sentinel <- function(text, sentinels, info = NULL) {
  for (sentinel in sentinels) expect_false(grepl(sentinel, text, fixed = TRUE), info = paste(info, sentinel))
}

test_that("reports mask literals, comments, long numbers and macro values for every SAS converter", {
  cases <- list(
    "dc-tables" = c(folder = "descriptive", stem = "dc.tables", prefix = "dc", qualifier = "tables"),
    "dc-gfup" = c(folder = "descriptive", stem = "dc.gfup", prefix = "dc", qualifier = "gfup"),
    "dp-trends" = c(folder = "graphs", stem = "dp.trends", prefix = "dp", qualifier = "trends")
  )
  for (kind in names(cases)) {
    spec <- cases[[kind]]
    root <- migration_study_fixture(kind)
    source <- file.path(root, spec[["folder"]], paste0(spec[["stem"]], ".sas"))
    writeLines(c(sas_planted_lines, readLines(source)), source)
    job <- migrate_job(source, "cohort", "eda", spec[["prefix"]], spec[["qualifier"]], dir = root)
    report <- masked_report(job)
    expect_no_sentinel(report, sas_sentinels, info = kind)
    expect_match(report, "\"[string]\"", fixed = TRUE, info = kind)
  }
})

test_that("reports mask the same values for a SAS dp-postage source", {
  root <- migration_study_fixture("dp-postage")
  source <- file.path(root, "descriptive", "dp.postage.sas")
  writeLines(c(setdiff(sas_planted_lines, "data drop; set nothing;"), "%let dta_filename = built;", "%let pref_time_var = iv_dead;",
               "%let variables = age bmi;"), source)
  job <- migrate_job(source, "cohort", "eda", "dp", "postage", dir = root)
  expect_no_sentinel(masked_report(job), sas_sentinels, info = "dp-postage sas")
})

test_that("reports withhold qmd prose and YAML and mask R literals and comments", {
  root <- migration_study_fixture("dp-postage")
  source <- file.path(root, "descriptive", "dp.postage.qmd")
  writeLines(c(
    "---", "title: \"SENTINEL_YAML sweep\"", "author: SENTINEL_AUTHOR", "---",
    "Patient SENTINEL_PROSE had an issue.",
    "```{r}",
    "dta_filename <- \"built.csv\"",
    "pref_time_var <- \"iv_dead\"",
    "variables <- c(\"age\", \"bmi\")",
    "d <- data.frame(mrn = c(\"SENTINEL_RDQ\", 'SENTINEL_RSQ'), id = 7654321) # SENTINEL_RCOMMENT",
    "# SENTINEL_RLINECOMMENT",
    "```",
    "More prose naming SENTINEL_PROSE2."
  ), source)
  job <- migrate_job(source, "cohort", "eda", "dp", "postage", dir = root)
  report <- masked_report(job)
  expect_no_sentinel(report, c("SENTINEL_YAML", "SENTINEL_AUTHOR", "SENTINEL_PROSE", "SENTINEL_RDQ",
                               "SENTINEL_RSQ", "7654321", "SENTINEL_RCOMMENT", "SENTINEL_RLINECOMMENT"))
  expect_match(report, "[prose withheld]", fixed = TRUE)
})

test_that("reports carry no planted value when no converter exists", {
  root <- migration_study_fixture()
  source <- file.path(root, "distributions", "hz.dead.sas")
  writeLines(sas_planted_lines, source)
  job <- migrate_job(source, "dead", "eda", dir = root)
  expect_no_sentinel(masked_report(job), sas_sentinels, info = "no converter")
})

test_that("masking keeps statement shape while hiding values", {
  sas <- .migration_mask_source(c(
    "if mrn = \"MRN0000001\" then delete;", "where name='O''Brien';", "%let study = x y;",
    "/* a; b' */ age", "* note;  bmi", "ccfid = 1234567", "plot y*year / haxis=axis1;"
  ), "sas")
  expect_identical(sas, c(
    "if mrn = \"[string]\" then delete;", "where name='[string]';", "%let study = [value];",
    "/* [comment] */ age", "* [comment];  bmi", "ccfid = [number]", "plot y*year / haxis=axis1;"
  ))
  r <- .migration_mask_source("x <- c(\"a\\\"b\", 'c') # note 12345", "r")
  expect_identical(r, "x <- c(\"[string]\", '[string]') # [comment]")
  expect_identical(.migration_mask_source("x = \"unterminated MRN", "sas"), "x = \"[string]")
})

test_that("dc-tables group headings reach the job but not the report", {
  root <- migration_study_fixture("dc-tables")
  source <- file.path(root, "descriptive", "dc.tables.sas")
  writeLines("%desc_tab(vartype=continuous,input=built,varlist=/* SENTINEL_HEADING */ age);", source)
  job <- migrate_job(source, "cohort", "eda", "dc", "tables", dir = root)
  expect_no_sentinel(masked_report(job), "SENTINEL_HEADING")
  expect_match(masked_report(job), "[heading]: age", fixed = TRUE)
  expect_true(any(grepl("SENTINEL_HEADING", readLines(job, warn = FALSE), fixed = TRUE)))
})
