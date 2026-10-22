# The three-way merge upgrade_job() carries a study's edits with. See
# dev/specs/2026-10-22-upgrade-job-merge-design.md, decision 6.

merge3 <- function(job, base, template) {
  hvtiRtemplates:::.merge3(job, base, template, base_label = "template 1.0.0", template_label = "template 1.0.1")
}

test_that(".line_diff() matches the longest common subsequence", {
  m <- hvtiRtemplates:::.line_diff(c("a", "b", "c", "d"), c("a", "x", "c", "d", "e"))
  expect_identical(m, cbind(a = c(1L, 3L, 4L), b = c(1L, 3L, 4L)))
  expect_identical(nrow(hvtiRtemplates:::.line_diff(character(), "a")), 0L)
})

test_that("a change on one side only is taken, and both sides' separate changes land", {
  base <- c("a", "b", "c", "d", "e")
  job <- c("a", "B", "c", "d", "e")
  template <- c("a", "b", "c", "d", "E", "f")
  m <- merge3(job, base, template)
  expect_identical(m$lines, c("a", "B", "c", "d", "E", "f"))
  expect_identical(nrow(m$conflicts), 0L)
  expect_identical(m$carried$start, 2L)
})

test_that("both sides changing one region is a conflict with diff3 markers", {
  m <- merge3(c("a", "J", "c"), c("a", "b", "c"), c("a", "T", "c"))
  expect_identical(m$lines, c("a", "<<<<<<< job", "J", "||||||| template 1.0.0", "b", "=======", "T",
                              ">>>>>>> template 1.0.1", "c"))
  expect_identical(m$conflicts$start, 2L)
  expect_identical(m$conflicts$end, 8L)
})

test_that("hand-written cases: inserts at one place, delete against edit, adjacent edits, ends, empty base", {
  # Both insert different lines at the same place.
  m <- merge3(c("a", "J", "b"), c("a", "b"), c("a", "T", "b"))
  expect_identical(nrow(m$conflicts), 1L)
  # Both insert the same line: no conflict.
  expect_identical(merge3(c("a", "X", "b"), c("a", "b"), c("a", "X", "b"))$lines, c("a", "X", "b"))
  # The job deletes a line the template edits.
  expect_identical(nrow(merge3(c("a", "c"), c("a", "b", "c"), c("a", "B", "c"))$conflicts), 1L)
  # Adjacent edits with no unchanged line between them conflict, as in diff3.
  expect_identical(nrow(merge3(c("a", "B", "c", "d"), c("a", "b", "c", "d"), c("a", "b", "C", "d"))$conflicts), 1L)
  # One unchanged line between them is enough.
  expect_identical(merge3(c("B", "x", "c"), c("b", "x", "c"), c("b", "x", "C"))$lines, c("B", "x", "C"))
  # Edits at the first and last lines.
  expect_identical(merge3(c("A", "m", "z"), c("a", "m", "z"), c("a", "m", "Z"))$lines, c("A", "m", "Z"))
  # An empty base: identical additions merge, different ones conflict.
  expect_identical(merge3("x", character(), "x")$lines, "x")
  expect_identical(nrow(merge3("x", character(), "y")$conflicts), 1L)
})

test_that("the merge obeys diff3's laws over generated texts", {
  withr::local_seed(20261022)
  alphabet <- c(letters[1:6], "", "```")
  mutate <- function(x) {
    for (k in seq_len(sample(0:3, 1L))) {
      i <- sample(seq_len(length(x) + 1L), 1L)
      op <- sample(c("insert", "delete", "edit"), 1L)
      if (op == "insert" || !length(x) || i > length(x)) {
        x <- append(x, sample(alphabet, 1L), after = i - 1L)
      } else if (op == "delete") {
        x <- x[-i]
      } else {
        x[[i]] <- paste0(x[[i]], "'")
      }
    }
    x
  }
  for (case in seq_len(300L)) {
    b <- sample(alphabet, sample(0:12, 1L), replace = TRUE)
    x <- mutate(b)
    y <- mutate(b)
    expect_identical(merge3(x, b, b)$lines, x)
    expect_identical(merge3(b, b, y)$lines, y)
    expect_identical(merge3(x, b, x)$lines, x)
    xy <- merge3(x, b, y)
    yx <- merge3(y, b, x)
    expect_identical(nrow(xy$conflicts), nrow(yx$conflicts))
    expect_identical(sum(xy$lines == "<<<<<<< job"), nrow(xy$conflicts))
    if (!nrow(xy$conflicts)) {
      # Clean both ways round, and the same text.
      expect_identical(xy$lines, yx$lines)
    }
  }
})

test_that("repeated lines: a delete at the end and an insert at the start both land", {
  m <- merge3(c("a", "a"), c("a", "a", "a"), c("b", "a", "a", "a"))
  expect_identical(m$lines, c("b", "a", "a"))
  expect_identical(nrow(m$conflicts), 0L)
})

test_that("edits with known provenance, separated by an untouched line, merge to the expected text", {
  # Tested against the edits themselves, not by re-diffing the result against
  # base: repeated lines let a fresh diff align one result as different hunks.
  # Base mixes repeated lines (blank, fences) with unique ones, and the edits
  # land on unique lines: an edit to one of several identical lines has no
  # single right answer (see the next test).
  withr::local_seed(20261023)
  alphabet <- c("a", "b", "", "```")
  for (case in seq_len(300L)) {
    n <- sample(3:14, 1L)
    base <- ifelse(stats::runif(n) < 0.5, sample(alphabet, n, replace = TRUE), paste0("u", seq_len(n)))
    unique_at <- which(!base %in% base[duplicated(base)])
    # Edit sites at least two apart, so an untouched line separates any two.
    sites <- integer()
    for (i in sample(unique_at, length(unique_at))) if (all(abs(sites - i) >= 2L)) sites <- c(sites, i)
    sites <- sort(sites[seq_len(sample(0:min(4L, length(sites)), 1L))])
    side <- sample(c("job", "template"), length(sites), replace = TRUE)
    new <- lapply(seq_along(sites), function(k) {
      paste0(side[[k]], case, "-", k, "-", seq_len(sample(0:2, 1L)), recycle0 = TRUE)
    })
    apply_edits <- function(which) {
      out <- as.list(base)
      for (k in seq_along(sites)) if (side[[k]] %in% which) out[[sites[[k]]]] <- new[[k]]
      unlist(out, use.names = FALSE)
    }
    m <- merge3(apply_edits("job"), base, apply_edits("template"))
    expect_identical(nrow(m$conflicts), 0L, info = paste("case", case))
    expect_identical(m$lines, apply_edits(c("job", "template")), info = paste("case", case))
  }
})

test_that("identical lines are indistinguishable: each side deleting one of a run reads as one deletion", {
  # A limit of every line-based diff3, git's included, written down so a change
  # to it is noticed. Each side deletes one `x` of three; the merge sees the
  # same deletion twice and keeps two. See the design's decision 6.
  m <- merge3(c("a", "x", "x", "z"), c("a", "x", "x", "x", "z"), c("a", "x", "x", "z"))
  expect_identical(m$lines, c("a", "x", "x", "z"))
  expect_identical(nrow(m$conflicts), 0L)
})
