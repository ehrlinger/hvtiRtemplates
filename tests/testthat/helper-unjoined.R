# A long join that leaves cohort patients out warns, with class
# hvtiRtemplates_unjoined (#613). A test about something else wraps its body in
# this, so that one warning, and no other, does not count against WARN 0; the
# tests about the warning assert it with expect_warning(), whose handler runs
# first.
without_unjoined_warning <- function(code) {
  withCallingHandlers(code, hvtiRtemplates_unjoined = function(w) invokeRestart("muffleWarning"))
}
