# The recommendation under the rf learning curve. The rows stand in for summary(gg_learning()).
st <- function(jaccard, kendall, low = FALSE) {
  data.frame(fraction = c(0.25, 0.5, 1)[seq_along(jaccard)], events = c(50, 100, 200)[seq_along(jaccard)],
             jaccard = jaccard, kendall = kendall, low_events = c(rep(FALSE, length(jaccard) - 1L), low))
}

test_that("both measures over the threshold and level is enough", {
  v <- hvtiRtemplates:::.learning_verdict(st(c(0.6, 0.83, 0.85), c(0.5, 0.82, 0.84)), 12, k = 5)
  expect_identical(v$events, "enough")
  expect_true(v$features)
  expect_match(v$text, ".callout-tip", fixed = TRUE)
  expect_match(v$text, "leveled off", fixed = TRUE)
})

test_that("one measure under the threshold is not yet", {
  v <- hvtiRtemplates:::.learning_verdict(st(c(0.6, 0.85), c(0.5, 0.7)), 12, k = 5)
  expect_identical(v$events, "not yet")
  expect_match(v$text, ".callout-warning", fixed = TRUE)
})

test_that("over the threshold but still rising is borderline", {
  v <- hvtiRtemplates:::.learning_verdict(st(c(0.6, 0.7, 0.85), c(0.5, 0.8, 0.84)), 12, k = 5)
  expect_identical(v$events, "borderline")
  expect_match(v$text, "still rising, by 0.15", fixed = TRUE)
})

test_that("over the threshold on too few events is borderline", {
  v <- hvtiRtemplates:::.learning_verdict(st(c(0.85, 0.85), c(0.84, 0.84), low = TRUE), 12, k = 5)
  expect_identical(v$events, "borderline")
  expect_match(v$text, "fewer than 50", fixed = TRUE)
  expect_match(hvtiRtemplates:::.learning_verdict(st(c(0.85, 0.85), c(0.84, 0.84), low = TRUE), 12, k = 5,
                                                  min_events = 30)$text, "fewer than 30", fixed = TRUE)
})

test_that("an optimistic or filled rightmost point is at most borderline", {
  s <- st(c(0.6, 0.85, 0.85), c(0.5, 0.84, 0.84))
  s$optimistic <- c(FALSE, FALSE, TRUE)
  v <- hvtiRtemplates:::.learning_verdict(s, 12, k = 5)
  expect_identical(v$events, "borderline")
  expect_match(v$text, "rightmost point is optimistic", fixed = TRUE)
  s$optimistic <- FALSE
  expect_identical(hvtiRtemplates:::.learning_verdict(s, 12, k = 5)$events, "enough")
  expect_identical(hvtiRtemplates:::.learning_verdict(s, 12, k = 5, filled = TRUE)$events, "borderline")
})

test_that("a large fall is not a plateau", {
  # The reproduction from review: 0.99 to 0.81 and 0.82.
  v <- hvtiRtemplates:::.learning_verdict(st(c(0.99, 0.81), c(0.99, 0.82)), 12, k = 5)
  expect_identical(v$events, "borderline")
  expect_match(v$text, "still falling, by 0.18", fixed = TRUE)
  expect_false(grepl("leveled off", v$text, fixed = TRUE))
  # A small move either way is still flat.
  expect_identical(hvtiRtemplates:::.learning_verdict(st(c(0.86, 0.83), c(0.85, 0.84)), 12, k = 5)$events, "enough")
})

test_that("a plateau that cannot be assessed is not enough", {
  # One fraction and no bootstrap: no earlier point.
  v <- hvtiRtemplates:::.learning_verdict(st(0.85, 0.84), 12, k = 5)
  expect_identical(v$events, "borderline")
  expect_match(v$text, "cannot be assessed", fixed = TRUE)
  expect_match(v$text, "no earlier point to show it has leveled off", fixed = TRUE)
  # A missing value at the earlier point.
  v <- hvtiRtemplates:::.learning_verdict(st(c(NA, 0.85), c(0.5, 0.84)), 12, k = 5)
  expect_identical(v$events, "borderline")
  expect_match(v$text, "cannot be assessed", fixed = TRUE)
})

test_that("an unknown event count is not enough", {
  s <- st(c(0.85, 0.85), c(0.84, 0.84))
  s$low_events <- NA
  expect_identical(hvtiRtemplates:::.learning_verdict(s, 12, k = 5)$events, "borderline")
})

test_that("the threshold is the study's", {
  s <- st(c(0.6, 0.7, 0.72), c(0.5, 0.68, 0.7))
  expect_identical(hvtiRtemplates:::.learning_verdict(s, 12, k = 5)$events, "not yet")
  expect_identical(hvtiRtemplates:::.learning_verdict(s, 12, k = 5, agreement = 0.6)$events, "enough")
})

test_that("few predictors point to the regression model and warn", {
  v <- hvtiRtemplates:::.learning_verdict(st(c(0.6, 0.85, 0.85), c(0.5, 0.84, 0.84)), 6, k = 5,
                                          model = "a Cox model")
  expect_identical(v$events, "enough")
  expect_false(v$features)
  expect_match(v$text, ".callout-warning", fixed = TRUE)
  expect_match(v$text, "a Cox model on the same predictors", fixed = TRUE)
})

test_that("one predictor is not assessed rather than judged", {
  v <- hvtiRtemplates:::.learning_verdict(st(c(NA, NA), c(NA, NA)), 1, k = 1)
  expect_identical(v$events, "not assessed")
  expect_match(v$text, "With one predictor", fixed = TRUE)
  v <- hvtiRtemplates:::.learning_verdict(st(c(0.6, 0.8), c(0.5, NA)), 6, k = 5)
  expect_identical(v$events, "not assessed")
  expect_match(v$text, "could not be computed", fixed = TRUE)
})

test_that("the learning note is carried into the callout", {
  v <- hvtiRtemplates:::.learning_verdict(st(c(0.85, 0.85), c(0.84, 0.84)), 12, k = 5, note = "Gaps were filled.")
  expect_match(v$text, "Gaps were filled.\n:::", fixed = TRUE)
})

test_that("the Jaccard steps follow k", {
  expect_identical(hvtiRtemplates:::.jaccard_steps(5),
                   "With the top 5, a pair sharing 4 of them scores 0.67, 3 scores 0.43, 2 scores 0.25, 1 scores 0.11.")
  expect_identical(hvtiRtemplates:::.jaccard_steps(2), "With the top 2, a pair sharing 1 of them scores 0.33.")
  expect_identical(hvtiRtemplates:::.jaccard_steps(1), "")
})

test_that("the error boxes span the 15th to 85th percentile and never overlap", {
  skip_if_not_installed("ggplot2")
  learning <- data.frame(events = rep(c(10, 20, 40), each = 21), error = rep(0:20 / 100, 3))
  layer <- hvtiRtemplates:::.learning_error_box(learning)
  box <- layer$data
  expect_equal(box$events, c(10, 20, 40))
  expect_equal(box$lower, rep(0.03, 3))
  expect_equal(box$middle, rep(0.10, 3))
  expect_equal(box$upper, rep(0.17, 3))
  # Half the narrowest gap, 10 to 20, so the boxes are 5 events wide.
  drawn <- function(l, d) {
    built <- ggplot2::ggplot_build(ggplot2::ggplot(d, ggplot2::aes(events, error)) + ggplot2::geom_point() + l)
    built$data[[2L]]$xmax - built$data[[2L]]$xmin
  }
  expect_equal(drawn(layer, learning), rep(5, 3))
  # One fraction: no gap to halve, so a tenth of its events.
  one <- learning[learning$events == 40, ]
  expect_equal(drawn(hvtiRtemplates:::.learning_error_box(one), one), 4)
})
