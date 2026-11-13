# A directory link for a test, removed before the test's temporary folders are.
#
# R's recursive unlink() on Windows deletes a directory reparse point as a junction
# and warns on a true symbolic link, so the link itself is removed first; rmdir
# removes a directory link without touching its target. withr runs deferred
# expressions LIFO, so call this after the local_tempdir() calls whose folders the
# link sits in or points at: its cleanup then runs before theirs. The path is built
# from `link` itself, never normalizePath(), which follows an existing link to its
# target and would have rmdir remove the target instead (#124). A non-zero status is
# reported rather than discarded. Skips where links cannot be created.
local_dir_link <- function(target, link, env = parent.frame()) {
  linked <- suppressWarnings(file.symlink(target, link))
  testthat::skip_if_not(linked, "This platform does not permit creating symbolic links.")
  if (.Platform$OS.type == "windows") {
    windows_link <- chartr("/", "\\", link)
    withr::defer({
      status <- system2("cmd", c("/c", "rmdir", shQuote(windows_link)))
      if (!identical(as.integer(status), 0L)) warning("rmdir on the test link returned ", status, call. = FALSE)
    }, envir = env)
  }
  invisible(link)
}
