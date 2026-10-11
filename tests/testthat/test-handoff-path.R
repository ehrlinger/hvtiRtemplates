# .handoff_path() and .bundle_ids(): the MODEL_FILE/MODEL_SET check and the ID
# comparison lm-checkpred and lp-mirror share. Synthetic studies only.

test_that(".handoff_path() finds a bundle in the job's own set or a named one, and nowhere else", {
  root <- lm_study()
  estimates <- hvtiRutilities::study_dir("estimates", root)
  dir.create(file.path(estimates, "own-set"))
  dir.create(file.path(estimates, "other-set"))
  file.create(file.path(estimates, "own-set", "up.rds"))
  file.create(file.path(estimates, "other-set", "up.rds"))
  own <- function(file) file.path(estimates, "own-set", file)
  path <- function(file = "up.rds", set = NULL) {
    hvtiRtemplates:::.handoff_path(file, set, root, own, upstream = "up", set_example = "other-set")
  }
  expect_identical(path(), file.path(estimates, "own-set", "up.rds"))
  expect_identical(path(set = "other-set"), file.path(estimates, "other-set", "up.rds"))
  for (bad in list("../own-set/up.rds", "up.csv", c("up.rds", "up.rds"), NA_character_, 1)) {
    expect_error(path(file = bad), "^MODEL_FILE must name one [.]rds file, such as \"up[.]rds\", with no folder")
  }
  for (bad in list("../other-set", "other", c("a-b", "c-d"), NA_character_)) {
    expect_error(path(set = bad), "^MODEL_SET must be NULL or one set name, \"<subject>-<type>\", such as \"other-set\"")
  }
  expect_error(path(set = "absent-set"),
               "^Saved model not found: .*absent-set/up[.]rds[.] Render the up job first, or set MODEL_FILE and MODEL_SET")
})

test_that(".bundle_ids() digests IDs for a digested bundle and leaves them as text otherwise", {
  root <- lm_study()
  bundle <- hvtiRtemplates:::.digest_bundle_ids(list(data = data.frame(ccfid = 1:3), meta = list(id_col = "ccfid")),
                                                root)
  key <- hvtiRtemplates:::.study_id_key(root)
  expect_identical(hvtiRtemplates:::.bundle_ids(bundle, c(1L, 3L), root), hvtiRtemplates:::.id_digest(c(1L, 3L), key))
  expect_identical(hvtiRtemplates:::.bundle_ids(bundle, c(1L, 3L), root), bundle$data$ccfid[c(1L, 3L)])
  expect_identical(hvtiRtemplates:::.bundle_ids(list(meta = list()), c(1L, 3L), root), c("1", "3"))
})
