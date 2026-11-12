work_a_job_vignette_path <- function() {
  source <- testthat::test_path("..", "..", "vignettes", "work-a-job.qmd")
  if (file.exists(source)) return(source)
  system.file("doc", "work-a-job.qmd", package = "hvtiRtemplates")
}

# 1 to 99 in words, as the guide writes a count in prose.
number_word <- function(n) {
  ones <- c("one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
            "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen")
  tens <- c("", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety")
  if (n < 20L) return(ones[[n]])
  paste0(tens[[n %/% 10L]], if (n %% 10L) paste0("-", ones[[n %% 10L]]))
}

test_that("the guide's dc-gfup marker count and quoted markers match the template", {
  # The count went stale twice in one release (#518 and #521 each added
  # markers) and no test saw it. Counted with the guard's own reader, so the
  # guide says what the DRAFT banner will.
  path <- work_a_job_vignette_path()
  skip_if_not(file.exists(path), "vignette source not available")
  article <- readLines(path, warn = FALSE)
  markers <- hvtiRtemplates:::.edit_marker_lines(readLines(template_path("dc", "gfup"), warn = FALSE))
  n <- nrow(markers)

  prose <- regmatches(article, regexpr("A new `dc-gfup` job starts with [a-z-]+", article))
  expect_length(prose, 1L)
  expect_identical(sub(".* starts with ", "", prose), number_word(n))

  banner <- grep("unresolved EDIT: marker\\(s\\) remain in this job:$", article)
  expect_length(banner, 1L)
  expect_identical(article[[banner]], paste(n, "unresolved EDIT: marker(s) remain in this job:"))

  # The banner lines the guide quotes are the template's first markers, in order.
  quoted <- sub("^  - ", "", article[seq(banner + 1L, length.out = 3L)])
  expect_identical(quoted, markers$text[1:3])
})
