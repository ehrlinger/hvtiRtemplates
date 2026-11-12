# The variable sets dc-eda's VARIABLE_SET names: the house ODS list, the house
# modules the SAS ODS template carries commented out, and a study's own, declared
# under variable_sets: in _study.yml. Asked for at the 2026-11-11 Biostats training.

test_that("the house sets are the ODS list and the SAS template's modules, each grouped by section", {
  sets <- hvtiRtemplates:::.variable_sets()
  expect_identical(names(sets), c("ods", "ie", "pericardiectomy", "cabg", "valve"))
  expect_identical(sets$ods, hvtiRtemplates:::.ods_groups())
  expect_identical(sets$cabg, list("Procedure: CABG detail" = c("comp_rev", "lc_diag", "lc_lad", "lc_lcx", "lc_rca")))
  expect_identical(names(sets$ie), c("Infectious endocarditis", "Infectious endocarditis: organisms"))
  # Every name is a lowercase column name, as read_built() returns them.
  every <- unlist(sets, use.names = FALSE)
  expect_true(all(grepl("^[a-z][a-z0-9_]*$", every)))
  # No surgeon columns: they are named for people, and this package is public.
  expect_false(any(grepl("^sgn_|^surgeon$", every)))
})

test_that("a study's sets follow the house sets, as a plain list or grouped by section", {
  cfg <- list(variable_sets = list(redcap = c("RC_Status", "rc_score"),
                                   mitral = list("Mitral repair" = c("mv_ring", "mv_lflt"), "Mitral echo" = "mr_grade")))
  sets <- hvtiRtemplates:::.variable_sets(cfg)
  expect_identical(names(sets), c("ods", "ie", "pericardiectomy", "cabg", "valve", "redcap", "mitral"))
  # A plain list is one section, named for the set; names are matched in lowercase.
  expect_identical(sets$redcap, list(redcap = c("rc_status", "rc_score")))
  expect_identical(sets$mitral, list("Mitral repair" = c("mv_ring", "mv_lflt"), "Mitral echo" = "mr_grade"))
})

test_that("a study's sets are refused when they cannot be read one way", {
  bad <- function(sets) hvtiRtemplates:::.variable_sets(list(variable_sets = sets))
  expect_error(bad(c("a", "b")), "must map each set's name to its columns")
  expect_error(bad(list(ods = "x")), "ods is a house variable set")
  expect_error(bad(list(all = "x")), "all")
  expect_error(bad(list("my-set" = "x")), "letters, digits and _")
  expect_error(bad(list(empty = character())), "empty names no column")
  expect_error(bad(list(numbers = 1:2)), "numbers names no column")
  expect_error(bad(list(grouped = list(a = "x", "y"))), "grouped")
})
