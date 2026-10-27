# Files holding patient-level rows, such as a saved forest, which keeps every
# interval it was grown on, are kept readable by their owner only.

# Evaluates `expr` with a umask of 0077, so a file it creates is owner-only from
# the first byte rather than after a chmod, then sets each of `files` that exists
# to 0600. Files already present are set first: umask governs only creation, so a
# file written over keeps its old mode, and an interrupted write would leave it
# there. A mode that cannot be set stops, naming the file.
.owner_only <- function(files, expr) {
  protect <- function() {
    present <- files[file.exists(files)]
    ok <- Sys.chmod(present, mode = "0600", use_umask = FALSE)
    if (!all(ok)) {
      stop("Could not make ", paste(present[!ok], collapse = ", "), " readable by its owner only. ",
           "It holds patient-level rows; check the folder's ownership before rendering again.", call. = FALSE)
    }
  }
  protect()
  old <- Sys.umask("0077")
  on.exit(Sys.umask(old), add = TRUE)
  value <- expr
  protect()
  value
}
