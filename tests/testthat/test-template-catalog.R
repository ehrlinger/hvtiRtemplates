test_that("the template catalog ships every owed job type", {
  catalog <- template_catalog()
  expect_s3_class(catalog, "data.frame")
  expect_equal(nrow(catalog), 77L)
  expect_equal(length(unique(catalog$prefix)), 45L)
  expect_false(any(c("destination", "replaced_by") %in% names(catalog)))
  expect_true(all(c("uses", "upstream", "downstream", "workflows") %in% names(catalog)))
  expect_type(catalog$uses, "list")
  expect_type(catalog$sas_breadth_jobs, "integer")
  expect_false(any(c("rf", "rfsrc") %in% catalog$prefix))
  expect_false(anyNA(catalog$status))
  rf <- catalog[catalog$prefix %in% c("rfs", "rfc", "rfr"), ]
  expect_setequal(paste(rf$prefix, rf$qualifier),
                  paste(rep(c("rfs", "rfc", "rfr"), each = 2L), c("fit", "explain")))
  # Explain rows carry no census counts: the counts describe the prefix, and
  # repeating them on both halves would double its breadth in the ledger.
  expect_true(all(is.na(rf$r_exemplars[rf$qualifier == "explain"])))

  # nb's census describes boostmtree: the exemplar survey found no BoostMLR job.
  nb <- catalog[catalog$prefix == "nb", ]
  expect_setequal(nb$qualifier, c("boostmtree", "boostmtree_fit", "boostmtree_explain", "boostmlr"))
  census <- c("sas_breadth", "sas_breadth_jobs", "r_exemplars", "r_jobs")
  expect_true(all(is.na(unlist(nb[nb$qualifier == "boostmlr", census]))))
  expect_false(anyNA(unlist(nb[nb$qualifier == "boostmtree", census])))

  lm <- catalog[catalog$prefix == "lm", ]
  expected <- c("binary", "ordinal", "nominal", "propensity_binary",
                "propensity_ordinal", "propensity_nominal", "checkpred",
                "balancing_count")
  expect_setequal(lm$qualifier, expected)
  expect_false(anyNA(lm$qualifier))
  expect_true(all(lm$status == "shipped"))
})

test_that("a missing catalog is an error", {
  expect_error(.read_template_catalog(tempfile(fileext = ".json")), "not found")
})

test_that("malformed scalar fields name the row and field", {
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path))
  writeLines(jsonlite::toJSON(list(templates = list(
    list(prefix = "ab", status = c("queued", "shipped"))
  )), auto_unbox = TRUE), path)
  expect_error(.template_catalog_from(path), "row 1.*status")
  writeLines(jsonlite::toJSON(list(templates = list(
    list(prefix = "ab", sas_breadth = "many")
  )), auto_unbox = TRUE), path)
  expect_error(.template_catalog_from(path), "row 1.*sas_breadth")
  writeLines(jsonlite::toJSON(list(templates = list(
    list(prefix = "ab", sas_breadth = 1.5)
  )), auto_unbox = TRUE), path)
  expect_error(.template_catalog_from(path), "row 1.*sas_breadth")
  # A JSON boolean or a numeric string is not an integer count, although
  # as.integer() turns TRUE into 1 and "3" into 3 without complaint.
  writeLines(jsonlite::toJSON(list(templates = list(
    list(prefix = "ab", r_jobs = TRUE)
  )), auto_unbox = TRUE), path)
  expect_error(.template_catalog_from(path), "row 1.*r_jobs")
  writeLines(jsonlite::toJSON(list(templates = list(
    list(prefix = "ab", r_jobs = "3")
  )), auto_unbox = TRUE), path)
  expect_error(.template_catalog_from(path), "row 1.*r_jobs")
})

test_that("every template on disk has a catalog description", {
  # The template-catalog vignette prints this as the template's one line; a
  # shipped template without one would print a blank row.
  catalog <- template_catalog()
  on_disk <- template_list()
  key <- function(prefix, qualifier) paste(prefix, ifelse(is.na(qualifier), "", qualifier))
  desc <- catalog$description[match(key(on_disk$prefix, on_disk$qualifier),
                                    key(catalog$prefix, catalog$qualifier))]
  expect_false(anyNA(desc), info = paste(on_disk$name[is.na(desc)], collapse = ", "))
  expect_true(all(nzchar(trimws(desc[!is.na(desc)]))))
})

test_that("every function a shipped template's `uses` names appears in that template", {
  # `uses` names the functions a template is built on, not every call (#584), so
  # this checks one direction only: a name listed there must be in the file. hp
  # once listed four hvtiPlotR drawing functions it never called.
  catalog <- template_catalog()
  on_disk <- template_list()
  key <- function(prefix, qualifier) paste(prefix, ifelse(is.na(qualifier), "", qualifier))
  rows <- match(key(on_disk$prefix, on_disk$qualifier), key(catalog$prefix, catalog$qualifier))
  missing <- character()
  for (i in seq_len(nrow(on_disk))) {
    qualifier <- if (is.na(on_disk$qualifier[i])) NULL else on_disk$qualifier[i]
    text <- paste(readLines(template_path(on_disk$prefix[i], qualifier = qualifier)), collapse = "\n")
    for (fn in catalog$uses[[rows[i]]]) {
      if (!grepl(paste0("\\b", sub("^.*::", "", fn), "\\b"), text, perl = TRUE)) {
        missing <- c(missing, paste0(on_disk$name[i], ": ", fn))
      }
    }
  }
  expect_identical(missing, character())
})
