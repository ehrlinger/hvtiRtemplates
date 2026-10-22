# Rebuild inst/extdata/template-history.rds from this repository's git history.
# Run from the repository root in the version-bump commit, beside
# `python3 .github/scripts/news.py collect`:
#
#   Rscript dev/template-history/build.R
#
# Reads every first-parent commit from d3b741e (the first that stamps its jobs)
# to HEAD, with no path filter, so a bump that changes no template still maps
# its texts to the new version. This is the only place git is used; the
# installed package reads the archive with readRDS(). See
# dev/specs/2026-10-22-upgrade-job-merge-design.md, decision 2.

source("R/templates.R")
source("R/template-history.R")

git <- function(...) {
  out <- system2("git", c(...), stdout = TRUE)
  if (!is.null(attr(out, "status"))) stop("git ", paste(c(...), collapse = " "), " failed")
  out
}
blob <- function(id) {
  f <- tempfile()
  on.exit(unlink(f))
  status <- system2("git", c("cat-file", "blob", id), stdout = f)
  if (status != 0L) stop("git cat-file blob ", id, " failed")
  readBin(f, "raw", file.size(f))
}

commits <- git("rev-list", "--first-parent", "--reverse", "d3b741e~1..HEAD")
cache <- list()
states <- lapply(commits, function(commit) {
  version <- sub("^Version:\\s*", "", grep("^Version:", git("show", paste0(commit, ":DESCRIPTION")), value = TRUE))
  tree <- git("ls-tree", "-r", commit, "inst/templates")
  tree <- tree[grepl("[.]qmd$", tree)]
  ids <- sub("^\\S+ blob (\\S+)\t.*$", "\\1", tree)
  paths <- sub("^[^\t]+\t", "", tree)
  files <- lapply(ids, function(id) {
    if (is.null(cache[[id]])) cache[[id]] <<- blob(id)
    cache[[id]]
  })
  names(files) <- paths
  list(version = version, date = git("show", "-s", "--format=%cI", commit), files = files)
})
history <- .history_from_states(states)
saveRDS(history, "inst/extdata/template-history.rds", compress = "xz")
cat(length(commits), "commits,", length(history$texts), "texts,", nrow(history$index), "index rows,",
    file.size("inst/extdata/template-history.rds"), "bytes\n")
