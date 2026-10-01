test_that("add_job scaffolds nb-boostmtree with its subject and type", {
  dir <- withr::local_tempdir("nb-job-")
  job <- add_job("nb", subject = "lvef", type = "boost", dir = dir, qualifier = "boostmtree")
  expect_match(basename(job), "^lvef-boost-nb-boostmtree[.]qmd$")
  txt <- readLines(job)
  expect_identical(grep("^SUBJECT <- ", txt, value = TRUE), "SUBJECT <- \"lvef\"")
  expect_identical(grep("^TYPE\\s+<- ", txt, value = TRUE), "TYPE    <- \"boost\"")
})

test_that("the data chunk keeps the model's columns and drops rows with no response", {
  nb_skip_unless_stack()
  data <- nb_data()
  data$lvef[c(1, 5)] <- NA
  root <- nb_study(data)
  env <- nb_env(root)
  out <- utils::capture.output(nb_run(c("edit-study-choices", "data"), env, nb_choices()))
  expect_identical(sort(names(env$d)), sort(c("ccfid", "iv_echo", "lvef", "age", "female", "grp")))
  expect_identical(nrow(env$d), nrow(data) - 2L)
  expect_true(is.factor(env$d$grp))
  expect_true(any(grepl("2 visit(s) have no lvef", out, fixed = TRUE)))
  expect_true(any(grepl("Text predictors converted to factors: grp", out, fixed = TRUE)))
})

test_that("KEY defaults to ID and TIME, so a duplicated visit stops the read", {
  nb_skip_unless_stack()
  data <- nb_data()
  data <- rbind(data, data[1, ])
  root <- nb_study(data)
  env <- nb_env(root)
  expect_error(utils::capture.output(nb_run(c("edit-study-choices", "data"), env, nb_choices())), "unique")
})

test_that("the ID and TIME cannot be predictors, nor the ID the response", {
  nb_skip_unless_stack()
  root <- nb_study()
  run <- function(...) {
    env <- nb_env(root)
    utils::capture.output(nb_run(c("edit-study-choices", "data"), env, nb_choices(...)))
  }
  expect_error(run(PREDICTORS = c("age", "ccfid")), "identifier or the visit time")
  expect_error(run(PREDICTORS = c("age", "iv_echo")), "identifier or the visit time")
  expect_error(run(RESPONSE = "ccfid"), "cannot be the response")
})

test_that("TIME and RESPONSE resolve against the data ignoring case", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_env(root)
  utils::capture.output(nb_run(c("edit-study-choices", "data"), env, nb_choices(TIME = "IV_ECHO", RESPONSE = "LVEF")))
  expect_identical(env$.time, "iv_echo")
  expect_identical(env$.response, "lvef")
  expect_identical(sort(names(env$d)), sort(c("ccfid", "iv_echo", "lvef", "age", "female", "grp")))
  expect_identical(sort(env$.predictors), sort(c("age", "female", "grp")))
  env <- nb_env(root)
  expect_error(utils::capture.output(nb_run(c("edit-study-choices", "data"), env,
                                            nb_choices(TIME = "IV_ECHO", PREDICTORS = c("age", "IV_ECHO")))),
               "identifier or the visit time")
})

test_that("the setup chunk passes when both packages meet their floors", {
  nb_skip_unless_stack()
  expect_no_error(nb_mocked_setup("neither", "0.0.0"))
})

test_that("boostmtree older than 2.0.2 is refused with the fork's install line", {
  nb_skip_unless_stack()
  expect_error(nb_mocked_setup("boostmtree", "2.0.0"), "ehrlinger/boostmtree_src", fixed = TRUE)
})

test_that("ggBoostedTrees older than 0.0.7 is refused with its install line", {
  nb_skip_unless_stack()
  expect_error(nb_mocked_setup("ggBoostedTrees", "0.0.6"), "remotes::install_github(\"ehrlinger/ggBoostedTrees\")", fixed = TRUE)
})
