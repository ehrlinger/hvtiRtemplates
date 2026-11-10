#' A fingerprint of the data a SID forest was grown on
#'
#' sid-fit records one for each completed (imputed) dataset a forest was grown
#' on, and sid-stability checks the data it refits on against them, so a refit
#' never runs on values the reported forests did not see. Row names and the storage of
#' factors are left out: the two jobs rebuild the same rows by different routes,
#' so only the values, in column order, are compared.
#'
#' @param data A data frame of the clustering variables, one row per patient,
#'   in the order of the SID distance.
#' @return One string, an MD5 digest.
#' @noRd
.sid_data_fingerprint <- function(data) {
  cols <- lapply(as.list(as.data.frame(data)), function(v) {
    v <- if (is.factor(v)) as.character(v) else v
    attributes(v) <- NULL
    v
  })
  digest::digest(cols, algo = "md5")
}
