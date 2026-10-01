#' One response component of a multi-response boostmtree partial plot
#'
#' An ordinal or nominal \code{boostmtree} fit has one response component per
#' level after the first, and \code{boostmtree::partial.plot(output = "data")}
#' then nests its \code{$curves} by component, then by variable. In
#' ggBoostedTrees 0.0.7 \code{gg_boost_effect()} takes only the single-response
#' shape, a list of data frames by variable, and refuses the nested one. This
#' returns component \code{k} in that single-response shape, so the
#' \code{nb-boostmtree} template can draw each component on its own. Only the
#' fields that differ between the shapes change: \code{$curves} and
#' \code{$response.labels}. Everything else, the time points included, is shared
#' by every component and is kept.
#'
#' @param pp A \code{partial.plot.boostmtree} object from a multi-response fit.
#' @param k The response component to keep, by position.
#' @return \code{pp}, holding component \code{k} alone.
#' @noRd
.nb_single_response <- function(pp, k) {
  if (is.data.frame(pp$curves[[1L]])) {
    stop("This partial.plot already holds one response; pass it to gg_boost_effect() as it is.", call. = FALSE)
  }
  if (length(k) != 1L || is.na(k) || k < 1L || k > length(pp$curves)) {
    stop("This partial.plot has ", length(pp$curves), " response component(s), so there is no component ", k, ".",
         call. = FALSE)
  }
  pp$curves <- pp$curves[[k]]
  pp$response.labels <- pp$response.labels[[k]]
  pp
}
