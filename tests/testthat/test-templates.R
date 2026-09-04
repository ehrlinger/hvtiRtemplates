test_that("template_list() has the expected shape", {
  tl <- template_list()
  expect_s3_class(tl, "data.frame")
  expect_named(tl, c("name", "prefix", "qualifier", "folder", "file"))
})

test_that("template_list() finds templates in taxonomy subfolders", {
  # Templates live one level down, under the taxonomy folder they scaffold into,
  # so the glob must recurse. A non-recursive glob would report zero templates
  # and every downstream test would pass vacuously.
  tl <- template_list()
  expect_true("ac" %in% tl$prefix)
  i <- match("ac", tl$prefix)
  # `folder` is the taxonomy name, with the directory's ordering digits
  # stripped: the template sits in `20_distributions/`.
  expect_equal(tl$folder[[i]], "distributions")
  expect_equal(tl$name[[i]], "ac")
})

test_that("template_list() reads folder from the directory, not the taxonomy", {
  # The filesystem is the authority on where a template lives. Joining through
  # hvti_taxonomy() instead would report the folder the prefix is *filed* under
  # even when the file sits somewhere else -- hiding exactly the mistake the
  # cross-check in test-taxonomy.R exists to catch.
  # `folder` is the directory with its ordering digits stripped, so this
  # compares against the stripped name rather than the raw one.
  tl <- template_list()
  expect_equal(tl$folder,
               hvtiRtemplates:::.folder_name(basename(dirname(tl$file))))
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
  # A template is named "<prefix>[-<qualifier>].qmd". The ordinal was dropped
  # on 2026-09-03: `NN` duplicated the directory and `MM` asserted an order
  # among a folder's templates that does not exist. The digits now live on the
  # directory.
  expect_equal(hvtiRtemplates:::.template_fields("ac.qmd")$prefix, "ac")
  expect_true(is.na(hvtiRtemplates:::.template_fields("ac.qmd")$qualifier))
  expect_equal(hvtiRtemplates:::.template_fields("rfs.qmd")$prefix, "rfs")
})

test_that(".template_fields() no longer accepts an ordinal", {
  # The old shape must not keep parsing, or a file left over from before the
  # 2026-09-03 change would be read as a template whose prefix is "03".
  expect_true(is.na(hvtiRtemplates:::.template_fields("03.01-ac.qmd")$prefix))
})

test_that(".folder_name() strips the directory's ordering digits", {
  expect_equal(hvtiRtemplates:::.folder_name("20_distributions"), "distributions")
  expect_equal(hvtiRtemplates:::.folder_name("90_estimates"), "estimates")
  # A directory with no numeric prefix is returned unchanged, so the function
  # is safe on a hand-made path.
  expect_equal(hvtiRtemplates:::.folder_name("distributions"), "distributions")
})

test_that(".template_fields() returns NA for a name it cannot parse", {
  # NA rather than an error: template_list() reports what is on disk, and a
  # stray file should not stop it. The unclassified-prefix test in
  # test-taxonomy.R is what turns an unparsed name into a build failure.
  # `ac.qmd` now PARSES, so it cannot stand for an unparseable name any more.
  expect_true(is.na(hvtiRtemplates:::.template_fields("README.md")$prefix))
  expect_true(is.na(hvtiRtemplates:::.template_fields("ac.Rmd")$prefix))
  expect_true(is.na(hvtiRtemplates:::.template_fields("a c.qmd")$prefix))
})

test_that("no two templates share a (prefix, qualifier) pair", {
  # This asserted "no two templates share a prefix" until 2026-09-02, because
  # `template_path()` and `new_job()` resolved with `match()`, which takes the
  # first hit silently. Both now resolve on the pair and error rather than
  # guess, so a prefix carrying several job types is the intended state and
  # the old form would have blocked the first one from landing. What must
  # still hold is that the PAIR is unique, since that is what identifies a
  # template. Raised by Copilot on #76.
  # Duplicated() on the two COLUMNS, not on a pasted key. paste() coerces
  # NA_character_ to the literal "NA", so an unqualified template would
  # collide with one qualified `NA`, which `[A-Za-z0-9_]+` permits. That is
  # the same NA-versus-string collapse this branch has already fixed twice,
  # and baking a sentinel into the test would hide it a third time.
  tl <- template_list()
  named <- tl[!is.na(tl$prefix), c("prefix", "qualifier"), drop = FALSE]
  expect_false(any(duplicated(named)))
})

test_that("a prefix is either wholly qualified or wholly unqualified", {
  # A mixed prefix would offer `<none>` in the ambiguity menu while
  # `.select_template()` has no way to ask for it, so the error would name a
  # choice the API cannot honour. Decomposing a prefix means naming every job
  # under it, not just the new ones.
  tl <- template_list()
  mixed <- vapply(
    split(tl$qualifier, tl$prefix),
    function(q) any(is.na(q)) && any(!is.na(q)),
    logical(1)
  )
  expect_false(any(mixed))
})

test_that("every installed template's name parses", {
  # .template_fields() returns NA rather than erroring on a name it cannot
  # parse, so a stray file does not stop template_list(). But nothing on disk
  # should actually BE that stray file: an unparseable template name is a real
  # defect, and letting it through as an NA prefix produces three confusing
  # downstream failures (the taxonomy folder check, the taxonomy cross-check,
  # and the "every template exists" check) instead of one test that names the
  # actual problem. This is that one test.
  tl <- template_list()
  expect_false(any(is.na(tl$prefix)),
               info = "a template file name did not match <prefix>[-<qualifier>].qmd")
})

test_that("every template directory carries ordering digits", {
  # The digits are what order the folders now that no filename carries them.
  # A directory without them sorts arbitrarily among the rest.
  dirs <- list.dirs(system.file("templates", package = "hvtiRtemplates"),
                    full.names = FALSE, recursive = FALSE)
  skip_if(length(dirs) == 0, "templates are not installed")
  expect_true(all(grepl("^[0-9]{2}_", dirs)),
              info = paste("undigited:", paste(dirs[!grepl("^[0-9]{2}_", dirs)],
                                               collapse = ", ")))
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

# Pull the producer guard out of a template so it can be RUN, not just read.
# Every other template test here is static source analysis, and a static test
# could only assert that the words are present -- which would pass against a
# guard with its comparison inverted. This one is worth executing.
.producer_guard <- function(prefix) {
  src <- readLines(template_path(prefix), warn = FALSE)
  from <- grep('^\\.engine <- bag\\[\\["engine"\\]\\]', src)
  if (!length(from)) return(NULL)
  # Grow the block until it parses, rather than guessing where it ends. The
  # guard contains an inner `} else {` at column zero, so "the first line
  # starting with }" stops halfway through and yields a syntax error that
  # looks like a broken test rather than a truncated extraction.
  for (to in seq(from[[1L]], min(from[[1L]] + 40L, length(src)))) {
    got <- tryCatch(parse(text = src[from[[1L]]:to]), error = function(e) NULL)
    # Stop only once the block ENDS on the `if` that refuses the bag. Parsing
    # is not enough on its own: the two assignments above it parse cleanly by
    # themselves, and a block cut there evaluates without ever refusing
    # anything, so every expect_error below would fail for the wrong reason.
    if (!is.null(got) && length(got) >= 2L) {
      last <- got[[length(got)]]
      if (is.call(last) && identical(as.character(last[[1L]]), "if")) {
        return(got)
      }
    }
  }
  NULL
}

test_that("bl, br and bc refuse a bag PRODUCED below 0.9.3", {
  # The version guard at the top of each report checks the hvtiRbootstrap
  # installed HERE. That is not the one that matters: the report reads a bag
  # some runner wrote earlier, possibly under 0.9.2, where boot_select()
  # recorded `sle` and `sls` and then selected on AIC regardless.
  #
  # Such a bag survives 0.9.3's own documented migration -- renaming
  # boot$summary's `variable` to `parameter` -- and passes boot_validate(). It
  # would then render an AIC-selected screen underneath the entry and stay
  # criteria it never used, which is the single failure raising the floor was
  # meant to prevent. Found in review of #85, after the floor raise alone had
  # been called complete.
  for (prefix in c("bl", "br", "bc")) {
    guard <- .producer_guard(prefix)
    expect_false(is.null(guard), info = paste(prefix, "has no producer guard"))

    # NA and "" are in here because package_version(NA) does NOT error -- it
    # returns a length-1 NA, and comparing that gives NA, which makes the
    # guard's `if` crash rather than refuse. An unreadable engine field is the
    # case to refuse, not the case to fall over on.
    for (bad in list("0.9.2", "0.1.1", NULL, NA_character_, "", "garbage")) {
      env <- new.env(parent = baseenv())
      env$bag <- list(engine = bad)
      expect_error(eval(guard, env), "0\\.9\\.3",
                   info = paste(prefix, "accepted engine",
                                if (is.null(bad)) "NULL" else bad))
    }

    env <- new.env(parent = baseenv())
    env$bag <- list(engine = "0.9.3")
    expect_silent(eval(guard, env))
    env$bag <- list(engine = "0.10.0")
    expect_silent(eval(guard, env))
  }
})

test_that("bh has no producer guard, because its producer is TemporalHazard", {
  # bh's screen comes from hzr_bootstrap(), whose own stepwise has always
  # honoured slentry and slstay. bag$engine there is not an hvtiRbootstrap
  # version at all, so a guard demanding >= 0.9.3 of it would refuse every
  # valid hazard bag.
  expect_null(.producer_guard("bh"))
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

# ---- qualifier ------------------------------------------------------------
# `graphs/dp` is trends, spaghetti, procs and more under one prefix, so a
# template name has to be able to say which. See
# dev/specs/2026-09-02-dp-dc-decomposition-design.md, which decided this.

test_that("a qualified template name parses into three fields", {
  f <- hvtiRtemplates:::.template_fields("dp-trends.qmd")
  expect_equal(f$prefix, "dp")
  expect_equal(f$qualifier, "trends")
})

test_that("an unqualified name still parses, with qualifier NA", {
  # Every template shipped today is unqualified. NA and "" must stay
  # distinguishable: regexec returns "" for a group that did not participate,
  # which would read as a template qualified with the empty string.
  f <- hvtiRtemplates:::.template_fields("ac.qmd")
  expect_equal(f$prefix, "ac")
  expect_true(is.na(f$qualifier))
})

test_that("the prefix capture does not swallow the qualifier", {
  # It was `.+`, which is greedy, so "dp-trends.qmd" parsed as the single
  # prefix "dp-trends". That validates and is wrong.
  f <- hvtiRtemplates:::.template_fields("dp-trends.qmd")
  expect_false(identical(f$prefix, "dp-trends"))
})

test_that("a trailing separator with no qualifier is rejected", {
  f <- hvtiRtemplates:::.template_fields("dp-.qmd")
  expect_true(is.na(f$prefix))
})

test_that("template_list() reports a qualifier column", {
  expect_true("qualifier" %in% names(template_list()))
})

test_that(".select_template() refuses to guess when a prefix is ambiguous", {
  # The whole point. Taking the first row is how one `dp` bucket hid four job
  # types; an unanswered question must not get a confident answer.
  tl <- data.frame(
    prefix = c("dp", "dp", "ac"),
    qualifier = c("trends", "spaghetti", NA_character_),
    folder = c("graphs", "graphs", "distributions"),
    file = c("a.qmd", "b.qmd", "c.qmd"),
    stringsAsFactors = FALSE
  )
  expect_error(hvtiRtemplates:::.select_template(tl, "dp"),
               "carries 2 templates")
  expect_error(hvtiRtemplates:::.select_template(tl, "dp"), "trends")
  expect_error(hvtiRtemplates:::.select_template(tl, "dp"), "spaghetti")
})

test_that(".select_template() resolves a named qualifier, and rejects a wrong one", {
  tl <- data.frame(
    prefix = c("dp", "dp"), qualifier = c("trends", "spaghetti"), folder = c("graphs", "graphs"),
    file = c("a.qmd", "b.qmd"), stringsAsFactors = FALSE
  )
  expect_equal(hvtiRtemplates:::.select_template(tl, "dp", "trends")$file, "a.qmd")
  expect_error(hvtiRtemplates:::.select_template(tl, "dp", "nope"),
               "no template qualified")
})

test_that("a single unqualified template still resolves without a qualifier", {
  # Backwards compatibility for all nine shipped templates.
  tl <- data.frame(
    prefix = "ac", qualifier = NA_character_,
    folder = "distributions", file = "c.qmd", stringsAsFactors = FALSE
  )
  expect_equal(hvtiRtemplates:::.select_template(tl, "ac")$file, "c.qmd")
})

test_that(".select_template() refuses a (prefix, qualifier) pair that matches twice", {
  # Returning the first row here would be the same silent pick the function
  # exists to refuse, one level further in: the caller takes [[1L]] and never
  # learns there was a second.
  tl <- data.frame(
    prefix = c("dp", "dp"), qualifier = c("trends", "trends"), folder = c("graphs", "graphs"),
    file = c("a.qmd", "b.qmd"), stringsAsFactors = FALSE
  )
  expect_error(hvtiRtemplates:::.select_template(tl, "dp", "trends"),
               "must be unique")
})

test_that("a malformed qualifier is rejected before it is compared", {
  # `hit$qualifier == NA_character_` is NA, not FALSE, so an NA qualifier
  # produces NA-indexed rows and an error naming nothing useful; a length-2
  # qualifier recycles silently. new_job() screened its argument and
  # template_path() did not, so the guard belongs on the shared path.
  for (bad in list(NA_character_, c("a", "b"), "", 42, character(0))) {
    expect_error(template_path("ac", bad), "single non-empty, non-NA")
  }
})

test_that("a malformed prefix is rejected before it is compared", {
  # Validating `qualifier` and not its sibling is how a length-2 prefix
  # reaches `tl$prefix == prefix`, recycles, and selects rows nobody asked
  # for. The old match() path errored cleanly there.
  for (bad in list(NA_character_, c("ac", "hz"), "", 42, character(0))) {
    expect_error(template_path(bad), "single non-empty, non-NA")
  }
})

test_that("two unqualified templates are a duplicate pair, not a mixed prefix", {
  # `any(is.na())` alone reported these as mixed, which they are not: mixed
  # means both kinds present. Two faults, two fixes, so two messages.
  tl <- data.frame(
    prefix = c("dp", "dp"), qualifier = c(NA_character_, NA_character_), folder = c("graphs", "graphs"),
    file = c("a.qmd", "b.qmd"), stringsAsFactors = FALSE
  )
  expect_error(hvtiRtemplates:::.select_template(tl, "dp"),
               "unqualified templates")
  expect_error(hvtiRtemplates:::.select_template(tl, "dp"), "must be")
})

test_that("a genuinely mixed prefix still reports as mixed", {
  tl <- data.frame(
    prefix = c("dp", "dp"), qualifier = c(NA_character_, "trends"), folder = c("graphs", "graphs"),
    file = c("a.qmd", "b.qmd"), stringsAsFactors = FALSE
  )
  expect_error(hvtiRtemplates:::.select_template(tl, "dp", "trends"), "mixes")
})
