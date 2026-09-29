# The study root for a template's setup chunk, with a message a new analyst can
# act on. hvtiRutilities::study_root()'s own message points to a server-side
# recovery command, which is the wrong first step for a study never set up.
.find_study_root <- function(start) {
  tryCatch(hvtiRutilities::study_root(start), error = function(e) {
    stop("This job is not inside a set-up study (no _study.yml above it). Create one with ",
         "hvtiRutilities::study_setup(\"<study folder>\", ...), register its data with register_data(), ",
         "then scaffold jobs with add_job() or open_job() from inside it. If this study had a ",
         "_study.yml and lost it, recover it with study-setup --recover.", call. = FALSE)
  })
}
