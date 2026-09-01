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

test_that("the bh template reports through hvtiRbootstrap, not its own copy", {
  src <- readLines(template_path("bh"), warn = FALSE)
  code <- sub("#.*$", "", src)          # and not in a code comment either

  # The reporting layer is the point of Batch 2a: bl, br and bc are thin only
  # because these calls live in the package. A hand-edit that inlines one of
  # them back into this file makes four reports to hand-sync again.
  for (fn in c("boot_validate", "boot_provenance", "boot_seeds", "boot_dropped",
               "boot_health", "boot_frequencies", "boot_concepts")) {
    expect_true(any(grepl(paste0(fn, "("), code, fixed = TRUE)),
                info = paste(fn, "is not called by the bh template"))
  }

  # boot_health() reports and never stops, so the two refusals are the
  # template's own. A report that renders green over a screen which selected
  # nothing is the failure these prevent.
  expect_true(any(grepl("The screen selected NOTHING", code, fixed = TRUE)))
  expect_true(any(grepl("returned the SAME fit", code, fixed = TRUE)))
})

test_that("the thin bootstrap templates report through hvtiRbootstrap", {
  for (prefix in c("bl", "br", "bc")) {
    src <- readLines(template_path(prefix), warn = FALSE)
    # Comments stripped first. These templates NARRATE the reporting layer --
    # the setup chunk's version-floor comment names boot_bag() -- so matching
    # raw source would let a hand-edit delete a live call, leave the comment,
    # and keep this green.
    code <- sub("#.*$", "", src)

    for (fn in c("boot_validate", "boot_provenance", "boot_seeds",
                 "boot_dropped", "boot_health", "boot_frequencies",
                 "boot_concepts")) {
      expect_true(any(grepl(paste0(fn, "("), code, fixed = TRUE)),
                  info = paste(fn, "is not called by the", prefix, "template"))
    }

    # The refusals boot_health() cannot make for itself. It reports and never
    # stops, so a screen that selected nothing renders green without these.
    expect_true(any(grepl("selected NOTHING", code, fixed = TRUE)),
                info = paste(prefix, "lost the empty-screen refusal"))
    expect_true(any(grepl("returned the SAME fit", code, fixed = TRUE)),
                info = paste(prefix, "lost the flat-bootstrap refusal"))
  }
})

test_that("the thin bootstrap templates carry no phase dimension", {
  for (prefix in c("bl", "br", "bc")) {
    src <- readLines(template_path(prefix), warn = FALSE)
    fence <- grepl("^```", src)
    in_chunk <- cumsum(fence) %% 2 == 1 & !fence
    code <- sub("#.*$", "", src[in_chunk])

    # PHASE_OF must be NULL and must stay NULL. A splitting rule that matches
    # nothing still adds a phase column of empty strings, and every grouped
    # table would then group by a column that says nothing -- silently, since
    # no count changes and no error is raised.
    ph <- grep("^\\s*PHASE_OF\\s*<-", code, value = TRUE)
    expect_length(ph, 1L)
    expect_match(ph, "NULL", info = paste(prefix, "supplies a phase rule"))

    # No table may select or order by a phase column: with phase = NULL the
    # reporting layer returns none, so a reference is an error at render time.
    # `phase = PHASE_OF` is the argument, not a column, and is excluded.
    cols <- sub("phase = PHASE_OF", "", code, fixed = TRUE)
    expect_false(any(grepl("\\$phase|\"phase\"|~phase", cols)),
                 info = paste(prefix, "references a phase column"))
  }
})

test_that("the thin bootstrap templates read one screen, not pooled chunks", {
  # bh pools chunks because a hazard screen is days of compute. These are not,
  # and a chunked run is pooled in the RUNNER -- the only place that knows how
  # many chunks it launched. A template that grew a pooling branch has taken on
  # a decision it cannot make correctly.
  for (prefix in c("bl", "br", "bc")) {
    src <- readLines(template_path(prefix), warn = FALSE)
    fence <- grepl("^```", src)
    code <- sub("#.*$", "", src[cumsum(fence) %% 2 == 1 & !fence])
    expect_false(any(grepl("boot_pool_chunks(", code, fixed = TRUE)),
                 info = paste(prefix, "pools chunks in the template"))
    expect_true(any(grepl("BOOT_FILE", code, fixed = TRUE)),
                info = paste(prefix, "has no BOOT_FILE edit point"))
  }
})

test_that("DESCRIPTION's hvtiRbootstrap bound matches what the templates enforce", {
  # These two drifted apart for NINE releases. `hvtiRbootstrap (>= 0.1.1)`
  # entered DESCRIPTION at 1.0.13 while 04.05-bh.qmd's own guard demanded
  # 0.1.2, then 0.9.0 from 1.0.18. Nothing compared them: the bound is in
  # DESCRIPTION, the floor is a string inside a .qmd, and no check read both.
  #
  # A repomap would not have caught it either -- the generated maps list
  # Suggests with the version bounds stripped, and do not index
  # inst/templates/ at all, so neither side of this comparison appears in one.
  # packageDescription(), not read.dcf("../../DESCRIPTION"). The relative path
  # resolves under devtools::test(), which runs from tests/testthat, and NOT
  # under R CMD check, which tests an INSTALLED copy -- so the first version of
  # this test passed locally and errored in check.
  desc <- utils::packageDescription("hvtiRtemplates", fields = "Suggests")
  skip_if(is.na(desc) || is.null(desc), "Suggests is not readable here")
  bound <- regmatches(desc,
                      regexpr("hvtiRbootstrap\\s*\\(>=\\s*[0-9.]+\\)", desc))
  skip_if(length(bound) == 0L, "hvtiRbootstrap is not a versioned Suggests")
  declared <- package_version(gsub("[^0-9.]", "", sub(".*>=", "", bound)))

  floors <- package_version(character(0))
  for (f in template_list()$file) {
    code <- sub("#.*$", "", readLines(f, warn = FALSE))
    pat <- 'packageVersion\\("hvtiRbootstrap"\\)\\s*<\\s*"[0-9.]+"'
    hit <- unlist(regmatches(code, regexpr(pat, code)))
    if (length(hit)) {
      floors <- c(floors,
                  package_version(gsub('.*<\\s*"([0-9.]+)".*', "\\1", hit)))
    }
  }
  skip_if(length(floors) == 0L, "no template enforces a floor")

  # The declared bound must be at least the highest floor any template
  # enforces. Lower means a study can satisfy DESCRIPTION and still be refused
  # by the template it just scaffolded, with the message arriving mid-render.
  expect_gte(declared, max(floors),
             label = paste0("DESCRIPTION declares hvtiRbootstrap >= ", declared,
                            " but a template refuses below ", max(floors)))
})
