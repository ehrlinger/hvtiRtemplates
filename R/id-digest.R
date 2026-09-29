#' The study's secret key for patient-ID digests
#'
#' Reads the key from \code{<root>/.hvti/id_key}, creating it on first use from
#' 32 cryptographically random bytes, hex encoded. The file is made readable by
#' its owner only where the operating system supports that. The key is never
#' printed: an error names the file, not its contents.
#'
#' @param root The study root.
#' @return The key, one string of 64 hex characters.
#' @noRd
.study_id_key <- function(root) {
  path <- file.path(root, ".hvti", "id_key")
  if (!file.exists(path)) {
    dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE, mode = "0700")
    # A restrictive umask closes the window between writing the file and chmod.
    old <- Sys.umask("077")
    on.exit(Sys.umask(old), add = TRUE)
    tmp <- tempfile("id_key", tmpdir = dirname(path))
    writeLines(paste(as.character(openssl::rand_bytes(32L)), collapse = ""), tmp)
    Sys.chmod(tmp, "0600")
    # Written aside and renamed, so a reader never sees a half-written key.
    if (!file.exists(path)) file.rename(tmp, path) else unlink(tmp)
  }
  key <- tryCatch(readLines(path, warn = FALSE), error = function(e) NULL, warning = function(w) NULL)
  if (length(key) != 1L || !grepl("^[0-9a-f]{64}$", key)) {
    stop("The study's patient-ID key at ", path, " cannot be read or is not a key. Restore it from backup: ",
         "without it, saved models cannot be matched to patients.", call. = FALSE)
  }
  key
}

#' A study-keyed digest of patient identifiers
#'
#' HMAC-SHA256 of each identifier under the study key, so an ID can be
#' compared and joined on without being stored. A whole number is written
#' without an exponent first, so \code{100000} and \code{100000L} digest alike.
#'
#' @param x A vector of identifiers.
#' @param key The key from \code{.study_id_key()}.
#' @return A character vector as long as \code{x}, \code{NA} where \code{x} is.
#' @noRd
.id_digest <- function(x, key) {
  text <- if (is.factor(x)) as.character(x) else x
  if (is.numeric(text)) {
    whole <- !is.na(text) & is.finite(text) & text == trunc(text)
    text <- ifelse(whole, sprintf("%.0f", text), as.character(text))
  }
  text <- as.character(text)
  seen <- unique(text[!is.na(text)])
  hashed <- vapply(seen, function(v) digest::hmac(key, v, "sha256"), character(1L), USE.NAMES = FALSE)
  hashed[match(text, seen)]
}

#' Replace the patient IDs in a bundle with their study-keyed digest
#'
#' Every data frame in the bundle that carries \code{id_col}, the fitted
#' models' own copies of their data included, has that column replaced by
#' \code{.id_digest()}. The bundle's \code{meta$id_digest} is set to
#' \code{TRUE} so a reader knows to digest its own IDs before comparing.
#' Attributes, such as the carried lineage, are kept and not searched.
#'
#' @param bundle A fitted bundle such as an \code{lm_fit}.
#' @param root The study root, whose key is used.
#' @param id_col The ID column's name.
#' @param skip Names of top-level elements to leave alone, such as models
#'   whose data were digested when they were saved.
#' @return The bundle with digested IDs.
#' @noRd
.digest_bundle_ids <- function(bundle, root, id_col = bundle$meta$id_col, skip = character()) {
  if (!is.character(id_col) || length(id_col) != 1L || is.na(id_col) || !nzchar(id_col)) {
    stop("The model bundle names no patient-ID column, so its IDs cannot be digested.", call. = FALSE)
  }
  key <- .study_id_key(root)
  walk <- function(x) {
    if (is.data.frame(x)) {
      if (id_col %in% names(x)) x[[id_col]] <- .id_digest(x[[id_col]], key)
      return(x)
    }
    if (is.list(x) && length(x)) x[] <- lapply(x, walk)
    x
  }
  todo <- setdiff(names(bundle), skip)
  bundle[todo] <- lapply(bundle[todo], walk)
  bundle$meta$id_digest <- TRUE
  bundle
}
