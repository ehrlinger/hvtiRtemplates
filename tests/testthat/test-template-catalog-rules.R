catalog_rows <- function() {
  path <- system.file("extdata", "templates.json", package = "hvtiRtemplates")
  jsonlite::fromJSON(path, simplifyVector = FALSE)$templates
}

test_that("every catalog row has a unique template key and a live disposition", {
  rows <- catalog_rows()
  expect_length(rows, 66L)
  keys <- vapply(rows, function(r) paste(r$prefix, r$qualifier, sep = "\r"), character(1))
  expect_identical(anyDuplicated(keys), 0L)
  expect_true(all(vapply(rows, function(r) {
    r$disposition %in% c("scaffold", "thin", "build")
  }, logical(1))))
  expect_true(all(vapply(rows, function(r) !is.null(r$status), logical(1))))
  expect_true(all(vapply(rows, function(r) {
    is.null(r$destination) && is.null(r$replaced_by)
  }, logical(1))))
})

test_that("build rows name a real function blocker", {
  rows <- Filter(function(r) identical(r$disposition, "build"), catalog_rows())
  expect_length(rows, 8L)
  for (row in rows) {
    expect_match(row$blocked_on, "^[A-Za-z][A-Za-z0-9.]*#[0-9]+$",
                 label = row$prefix)
  }
})

test_that("uses entries are declared package exports", {
  rows <- catalog_rows()
  refs <- unique(unlist(lapply(rows, function(r) r$uses), use.names = FALSE))
  expect_gt(length(refs), 0L)
  expect_true(all(grepl("^[A-Za-z][A-Za-z0-9.]*::[A-Za-z._][A-Za-z0-9._]*$", refs)))
  pkgs <- unique(sub("::.*$", "", refs))
  desc <- read.dcf(system.file("DESCRIPTION", package = "hvtiRtemplates"),
                   fields = c("Imports", "Suggests"))[1L, ]
  declared <- trimws(sub("\\(.*\\)", "", unlist(strsplit(desc, ","))))
  expect_true(all(pkgs %in% declared), info = paste(setdiff(pkgs, declared), collapse = ", "))
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    if (identical(Sys.getenv("CI"), "true")) {
      stop("Cannot validate uses exports; packages not installed: ",
           paste(missing, collapse = ", "))
    }
    skip(paste("Cannot validate uses exports; packages not installed:",
               paste(missing, collapse = ", ")))
  }
  for (pkg in pkgs) {
    want <- sub("^.*::", "", refs[sub("::.*$", "", refs) == pkg])
    expect_true(all(want %in% getNamespaceExports(pkg)),
                info = paste(pkg, paste(setdiff(want, getNamespaceExports(pkg)),
                                        collapse = ", ")))
  }
})
