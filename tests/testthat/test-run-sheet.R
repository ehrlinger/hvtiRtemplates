# Run sheets: the generated "before you run" page each template gets in the
# gallery. Design: dev/specs/2026-10-26-run-sheets-design.md.

test_that(".edit_marker_lines() finds the token and cuts each line as the draft banner does", {
  tok <- paste0("ED", "IT", ":")
  src <- c("x <- 1", paste("  #", tok, "set x"), paste("#", tok, strrep("a", 200)))
  m <- .edit_marker_lines(src)
  expect_identical(m$line, c(2L, 3L))
  expect_identical(m$text[1L], paste("#", tok, "set x"))
  expect_identical(nchar(m$text[2L]), 96L)
  expect_identical(nrow(.edit_marker_lines("nothing here")), 0L)
})
