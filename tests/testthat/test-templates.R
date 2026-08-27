test_that("template_list() has the expected shape", {
  tl <- template_list()
  expect_s3_class(tl, "data.frame")
  expect_named(tl, c("name", "prefix", "ordinal", "folder", "file"))
})

test_that("template_list() finds templates in taxonomy subfolders", {
  # Templates live one level down, under the taxonomy folder they scaffold into,
  # so the glob must recurse. A non-recursive glob would report zero templates
  # and every downstream test would pass vacuously.
  tl <- template_list()
  expect_true("ac" %in% tl$prefix)
  i <- match("ac", tl$prefix)
  expect_equal(tl$folder[[i]], "distributions")
  expect_equal(tl$ordinal[[i]], "03.01")
  expect_equal(tl$name[[i]], "03.01-ac")
})

test_that("template_list() reads folder from the directory, not the taxonomy", {
  # The filesystem is the authority on where a template lives. Joining through
  # hvti_taxonomy() instead would report the folder the prefix is *filed* under
  # even when the file sits somewhere else -- hiding exactly the mistake the
  # cross-check in test-taxonomy.R exists to catch.
  tl <- template_list()
  expect_equal(tl$folder, basename(dirname(tl$file)))
})

test_that("every listed template exists and every template file is listed", {
  tl <- template_list()
  dir <- system.file("templates", package = "hvtiRtemplates")
  skip_if(dir == "", "templates not installed")
  on_disk <- list.files(dir, pattern = "[.]qmd$", recursive = TRUE)
  expect_setequal(tl$file, file.path(dir, on_disk))
  expect_true(all(file.exists(tl$file)))
})

test_that("template_path() resolves a prefix", {
  expect_true(file.exists(template_path("ac")))
  expect_error(template_path("zz"), "unknown template")
})

test_that("every template prefix is in the taxonomy", {
  tl <- template_list()
  expect_true(all(tl$prefix %in% hvti_taxonomy()$prefix))
})

test_that(".template_fields() parses a structured template name", {
  # A template is named "<NN>.<MM>-<prefix>.qmd". The name is parsed by pattern
  # rather than by splitting on separators, because `.` is both a field
  # separator inside the ordinal and the extension separator -- a split cannot
  # tell the two apart.
  expect_equal(hvtiRtemplates:::.template_fields("03.01-ac.qmd")$ordinal, "03.01")
  expect_equal(hvtiRtemplates:::.template_fields("03.01-ac.qmd")$prefix, "ac")
  expect_equal(hvtiRtemplates:::.template_fields("04.19-rfs.qmd")$prefix, "rfs")
})

test_that(".template_fields() returns NA for a name it cannot parse", {
  # NA rather than an error: template_list() reports what is on disk, and a
  # stray file should not stop it. The unclassified-prefix test in
  # test-taxonomy.R is what turns an unparsed name into a build failure.
  expect_true(is.na(hvtiRtemplates:::.template_fields("ac.qmd")$prefix))
  expect_true(is.na(hvtiRtemplates:::.template_fields("README.md")$prefix))
})

test_that("no two templates share a prefix", {
  # `template_path()` and `new_job()` both resolve with `match()`, which takes
  # the first hit silently. Under the old flat layout one directory guaranteed
  # one file per prefix; a recursive glob does not, so the invariant has to be
  # asserted rather than assumed.
  tl <- template_list()
  expect_false(any(duplicated(stats::na.omit(tl$prefix))))
})

test_that("every installed template's name parses", {
  # .template_fields() returns NA rather than erroring on a name it cannot
  # parse, so a stray file does not stop template_list(). But nothing on disk
  # should actually BE that stray file: an unparseable template name is a real
  # defect, and letting it through as an NA prefix/ordinal produces three
  # confusing downstream failures (the taxonomy folder check, the taxonomy
  # cross-check, and the "every template exists" check) instead of one test
  # that names the actual problem. This is that one test.
  tl <- template_list()
  expect_false(any(is.na(tl$ordinal)),
               info = "a template file name did not match <NN.MM>-<prefix>.qmd")
  expect_false(any(is.na(tl$prefix)),
               info = "a template file name did not match <NN.MM>-<prefix>.qmd")
})

test_that(".template_fields() rejects an unpadded ordinal", {
  # The zero-padding is what makes `ls` sort a set in run order past nine
  # entries. Accepting "3.1" here would let an unsortable name into the tree
  # silently, so the parser is where the padding rule is enforced.
  expect_true(is.na(hvtiRtemplates:::.template_fields("3.1-ac.qmd")$ordinal))
  expect_true(is.na(hvtiRtemplates:::.template_fields("03.1-ac.qmd")$ordinal))
})

test_that("every template carries an edit-guard chunk", {
  # The EDIT: markers are only a convention until something checks them.
  # README.md claims a job still containing one has not been finished; the
  # guard chunk in each template is what makes that true. Issue #27: an
  # unedited job rendered green over a single dummy stratum because the derive
  # chunk indexed a placeholder column and R treats a zero-length index as a
  # silent no-op.
  #
  # This test is what stops a FUTURE template shipping without the guard.
  tl <- template_list()
  skip_if(nrow(tl) == 0L, "no templates installed")
  for (f in tl$file) {
    src <- readLines(f, warn = FALSE)
    expect_true(any(grepl("label: edit-guard", src, fixed = TRUE)),
                info = paste("no edit-guard chunk in", basename(f)))
    expect_true(any(grepl("HVTI_TEMPLATE_DRAFT", src, fixed = TRUE)),
                info = paste("edit-guard has no draft escape in", basename(f)))
  }
})

test_that("no template writes the edit marker token literally", {
  # A regression test for a trap that is invisible on inspection. Quarto knits
  # through an intermediate and knitr::current_input() returns THAT file, so a
  # guard scanning it reads its own chunk too. A guard that searches for the
  # token as a bare string literal therefore matches its OWN source line, and
  # fires on every render, finished or not. Measured when the guard was
  # written: a probe found three markers in a file containing two.
  #
  # So the token must be constructed, e.g. paste0("ED", "IT", ":"), and no
  # template may contain the literal outside a genuine marker. A genuine marker
  # is followed by prose; the literal inside a grep()/gsub()/pattern argument
  # is not. This test will look pointless later. It is not: without it the
  # obvious "cleanup" edit silently makes every finished job unrenderable.
  tl <- template_list()
  skip_if(nrow(tl) == 0L, "no templates installed")
  tok <- paste0("ED", "IT", ":")
  for (f in tl$file) {
    src <- readLines(f, warn = FALSE)
    quoted <- grepl(paste0("[\"']", tok), src)
    expect_false(any(quoted),
                 info = paste0("template ", basename(f), " contains the marker ",
                               "token as a string literal at line(s) ",
                               paste(which(quoted), collapse = ", "),
                               " -- its guard will match its own source"))
  }
})

test_that("the hvtiRutilities helpers templates call are declared and exported", {
  # The trigger this exists for: adding a template that calls a NEWER helper
  # silently leaves DESCRIPTION's `hvtiRutilities (>= x.y.z)` behind. An install
  # then satisfies DESCRIPTION and ships a template whose helper does not
  # exist -- and it fails at RENDER time, in a study, far from the install.
  #
  # This cannot check the version bound itself (CI installs the latest, not the
  # declared minimum). What it does is make the trigger loud: a template that
  # starts calling a helper outside this list fails here, and whoever adds it
  # is standing in the right place to ask whether DESCRIPTION needs bumping.
  declared <- c(
    "read_built", "study_config", "assert_cohort", "cohort_counts",  # >= 1.0.0
    "hvti_taxonomy", "sas_path",
    "sas_variable_block", "covariate_audit", "covariates_to_numeric",
    "imputed_levels", "pool_collinear_pairs", "selection_crowding",  # >= 1.1.4
    "concept_map"
  )
  skip_if_not_installed("hvtiRutilities")
  ns <- getNamespaceExports("hvtiRutilities")
  expect_true(all(declared %in% ns),
              info = paste("declared but not exported:",
                           paste(setdiff(declared, ns), collapse = ", ")))

  tl <- template_list()
  skip_if(nrow(tl) == 0L, "no templates installed")
  used <- character(0)
  for (f in tl$file) {
    src <- readLines(f, warn = FALSE)
    # CODE CHUNKS ONLY. Scanning the whole file matches prose too -- these
    # templates discuss `read_clinical_data()` in their narrative without
    # calling it -- and a test that fires on a comment is a test that gets
    # deleted.
    fence <- grepl("^```", src)
    in_chunk <- cumsum(fence) %% 2 == 1 & !fence
    code <- src[in_chunk]
    code <- sub("#.*$", "", code)          # and not in a code comment either
    hits <- gregexpr("[A-Za-z_][A-Za-z0-9_.]*(?=\\()", code, perl = TRUE)
    calls <- unlist(regmatches(code, hits))
    used <- c(used, intersect(unique(calls), ns))
  }
  expect_true(all(unique(used) %in% declared),
              info = paste("template calls an hvtiRutilities helper not in the",
                           "declared list -- check DESCRIPTION's version bound:",
                           paste(setdiff(unique(used), declared), collapse = ", ")))
})
