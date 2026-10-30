# What a report may not show. An identifier may stay in a job's data, so a patient
# can be found to correct follow-up, but no table or figure shows its values (John,
# 2026-10-30). read_job_data() keeps the ID and KEY, and a name it does not know,
# such as pt_mrn; these helpers decide what those columns may do in a report. The
# data are not touched: every helper here only reads names and values.
#
# A column named on purpose stops the job: .refuse_display(). A column reached by a
# sweep, such as "every numeric column", is left out and listed: .displayable().

# The names read_job_data() leaves alone but a report must not show. mrn is a token,
# so hosp_mrn and mrn_old match and bnp_mrna does not.
.display_name_pattern <- paste0(
  "(^|_)e?mrn[0-9]*(_|$)|ccfid|med_?rec|medical_?record|(^|_)ssn[0-9]*(_|$)|^(pat|patient|pt)_?(id|num|no)$|^cnum$"
)

# The columns whose values no report shows: the ID, every KEY column, `also`, what
# read_job_data() would drop, and the names above, unless the column is a 0/1 or Y/N
# indicator, as mrn_num can be.
.no_values <- function(d, id, key = character(), also = character()) {
  present <- intersect(c(id, key), names(d))
  named <- grep(.display_name_pattern, names(d), ignore.case = TRUE, value = TRUE)
  named <- named[!vapply(d[named], .is_indicator, logical(1L))]
  unique(c(id, key, also, .drop_identifiers(d, present)$dropped, named))
}

# A column of record numbers under a name nobody listed: whole numbers of four
# digits or more, nearly all different, in ten values or more. Age and a lab value
# repeat; a small sequential number is not a record number.
.looks_like_identifier_values <- function(x) {
  if (!is.numeric(x)) return(FALSE)
  seen <- x[!is.na(x)]
  length(seen) >= 10L && all(seen == floor(seen)) && min(abs(seen)) >= 1000 &&
    length(unique(seen)) >= 0.9 * length(seen)
}

# Stops when a setting names a column no report may show. The message names the
# column and never a value.
.refuse_display <- function(vars, no_values, setting) {
  hit <- unique(unlist(vars, use.names = FALSE))
  hit <- hit[tolower(hit) %in% tolower(no_values)]
  if (length(hit)) {
    stop(setting, " names ", toString(hit), ", which identifies patients: its values cannot appear in a table or ",
         "figure. Remove it from ", setting, ".", call. = FALSE)
  }
  invisible(TRUE)
}

# Splits the columns a sweep reached into those it may show and those it leaves out.
.displayable <- function(vars, d, no_values) {
  out <- tolower(vars) %in% tolower(no_values) |
    vapply(vars, function(v) .looks_like_identifier_values(d[[v]]), logical(1L))
  list(keep = vars[!out], left_out = vars[out])
}
