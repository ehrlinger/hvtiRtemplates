# The analysis-prefix taxonomy lives in hvtiRutilities.
#
# It moved there because it is shared vocabulary -- which prefix means what,
# which folder it belongs in -- rather than template machinery, and
# hvtiRutilities is the lower layer. Re-exported here so this package's
# public surface is unchanged: R/templates.R, the test suite and
# inst/templates/README.md all still call hvti_taxonomy() unqualified.

#' @importFrom hvtiRutilities hvti_taxonomy
#' @export
hvtiRutilities::hvti_taxonomy

#' @importFrom hvtiRutilities hvti_non_prefixes
#' @export
hvtiRutilities::hvti_non_prefixes
