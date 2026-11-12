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
# indicator, as mrn_num can be. Also the columns whose values look like record numbers,
# kept apart in the "by_values" attribute because only those can be a mistake: a
# measurement can have that shape, and options(hvtiRtemplates.not_identifiers =) lets a
# job say so, by name. It clears nothing else.
.no_values <- function(d, id, key = character(), also = character()) {
  present <- intersect(c(id, key), names(d))
  named <- grep(.display_name_pattern, names(d), ignore.case = TRUE, value = TRUE)
  named <- named[!vapply(d[named], .is_indicator, logical(1L))]
  listed <- unique(c(id, key, also, .drop_identifiers(d, present)$dropped, named))
  shaped <- names(d)[vapply(d, .looks_like_identifier_values, logical(1L))]
  shaped <- setdiff(shaped, getOption("hvtiRtemplates.not_identifiers"))
  by_values <- setdiff(shaped, listed)
  # The KEY columns refused for being in KEY and nothing else, such as the surgery date that
  # tells one patient's operations apart. .refuse_display() names KEY as the reason for those,
  # since "identifies patients" sent a team looking at the column rather than at KEY. A KEY
  # column whose values look like record numbers is an identifier in its own right, so it is
  # checked against `shaped`, which still holds the listed columns.
  key_only <- setdiff(key, c(id, also, .drop_identifiers(d, present)$dropped, named, shaped))
  structure(c(listed, by_values), by_values = by_values, key_only = key_only)
}

# A column of record numbers under a name nobody listed: whole numbers of four
# digits or more, nearly all different, in ten values or more. Age and a lab value
# repeat; a small sequential number is not a record number; nor is a calendar year,
# which a small cohort can hold once each.
.looks_like_identifier_values <- function(x) {
  if (!is.numeric(x)) return(FALSE)
  seen <- x[!is.na(x)]
  length(seen) >= 10L && all(seen == floor(seen)) && min(abs(seen)) >= 1000 &&
    length(unique(seen)) >= 0.9 * length(seen) && !all(seen >= 1900 & seen <= 2100)
}

# Stops when a setting names a column no report may show. The message names the
# column and never a value.
.refuse_display <- function(vars, no_values, setting) {
  hit <- unique(unlist(vars, use.names = FALSE))
  hit <- hit[tolower(hit) %in% tolower(no_values)]
  shaped <- hit[hit %in% attr(no_values, "by_values")]
  if (length(shaped)) {
    stop(setting, " names ", toString(shaped), ", whose values look like record numbers: whole numbers of four digits ",
         "or more that nearly all differ. Remove it from ", setting, ". If it is a measurement, say so above this chunk: ",
         "options(hvtiRtemplates.not_identifiers = \"", shaped[[1L]], "\").", call. = FALSE)
  }
  # An identifier is reported before a column refused only for being in KEY, so taking
  # the KEY column out never reveals an identifier the first message left unnamed.
  keyed <- hit[tolower(hit) %in% tolower(attr(no_values, "key_only"))]
  identifying <- setdiff(hit, keyed)
  if (length(identifying)) {
    stop(setting, " names ", toString(identifying), ", which identifies patients: its values cannot appear in a ",
         "table or figure. Remove it from ", setting, ".", call. = FALSE)
  }
  if (length(keyed)) {
    stop(setting, " names ", toString(keyed), ", which is in KEY: no report shows a KEY column's values, because KEY ",
         "tells one patient's rows apart. Use another column in ", setting, ", or take it out of KEY and put in its ",
         "place a column no report shows, such as a record number.", call. = FALSE)
  }
  invisible(TRUE)
}

# Splits the columns a sweep reached into those it may show and those it leaves out.
.displayable <- function(vars, no_values) {
  out <- tolower(vars) %in% tolower(no_values)
  list(keep = vars[!out], left_out = vars[out])
}
