# What a manuscript reader could learn about one patient. An identifier in a report is
# an error, and display-guard.R stops it. Identifiability is a judgment the author makes,
# so this flags and never changes a number, as bd's cross-tabs do ("flagged, never
# suppressed"). A finding names a column and a count, and never a value or a level.

.identifiability_date_pattern <- "(^|_)(dt|dttm|date|datetime)($|_)|_dt$"
.identifiability_age_pattern <- "^age($|_)|_age$"

# `vars` are the columns a table or figure shows and `by` its groups, all read for ages and
# dates. `cells` are the columns it shows by level, which only the template can say, and
# `tables` the cross-tabs it prints, each a character vector counted jointly with its
# missing values. `age` and `dates` add to what the names and classes find. `extremes` are
# the columns whose minimum or maximum is shown; a finding counts the patients more than
# 3 IQR beyond the quartiles, because every column has a maximum and only an outlying one
# points to a patient. `sparse` are year columns a figure draws each patient at: a finding
# counts the patients in a calendar year of fewer than `small`, because a point in a crowded
# year cannot be told from its neighbors and a point alone can. One row per finding: check,
# column, count.
.identifiability_check <- function(d, vars = character(), by = NULL, small = 5L, age = NULL, dates = NULL,
                                   extremes = NULL, cells = NULL, tables = list(), sparse = NULL) {
  cells <- intersect(cells, names(d))
  by <- intersect(by, names(d))
  tables <- Filter(function(cc) all(cc %in% names(d)), tables)
  shown <- intersect(unique(c(vars, cells, by, unlist(tables, use.names = FALSE))), names(d))
  rows <- list()
  add <- function(check, column, count) {
    if (count > 0L) rows[[length(rows) + 1L]] <<- data.frame(check = check, column = column, count = as.integer(count))
  }
  for (v in cells) {
    x <- d[[v]]
    if (inherits(x, c("Date", "POSIXt"))) next
    tab <- if (length(by)) table(x, d[[by[[1L]]]]) else table(x)
    add("small", v, sum(tab > 0L & tab < small))
  }
  for (cc in tables) {
    tab <- table(d[cc], useNA = "ifany")
    add("small", paste(cc, collapse = " by "), sum(tab > 0L & tab < small))
  }
  # A group is shown whatever the rows are: its N heads the column even over continuous rows alone.
  for (v in by) {
    tab <- table(d[[v]])
    add("group", v, sum(tab > 0L & tab < small))
  }
  ages <- intersect(union(age, grep(.identifiability_age_pattern, shown, ignore.case = TRUE, value = TRUE)), names(d))
  for (v in ages) if (is.numeric(d[[v]])) add("age", v, sum(d[[v]] > 89, na.rm = TRUE))
  named <- grep(.identifiability_date_pattern, shown, ignore.case = TRUE, value = TRUE)
  classed <- shown[vapply(d[shown], inherits, logical(1L), what = c("Date", "POSIXt"))]
  for (v in intersect(unique(c(dates, named, classed)), names(d))) add("date", v, sum(!is.na(d[[v]])))
  for (v in intersect(extremes, names(d))) {
    x <- suppressWarnings(as.numeric(d[[v]]))
    q <- stats::quantile(x, c(0.25, 0.75), na.rm = TRUE, names = FALSE, type = 2)
    add("extreme", v, sum(x < q[[1L]] - 3 * (q[[2L]] - q[[1L]]) | x > q[[2L]] + 3 * (q[[2L]] - q[[1L]]), na.rm = TRUE))
  }
  for (v in intersect(sparse, names(d))) {
    tab <- table(floor(suppressWarnings(as.numeric(d[[v]]))))
    add("position", v, sum(tab[tab < small]))
  }
  if (length(rows)) do.call(rbind, rows) else data.frame(check = character(), column = character(), count = integer())
}

# The same finding from counts a report already holds, for a count no column of the data
# gives: patients at risk at a time, or a table of a saved result. `column` names what was
# counted. A count of zero shows no patient.
.identifiability_counts <- function(counts, column, small = 5L, check = "small") {
  counts <- as.vector(counts)
  n <- sum(!is.na(counts) & counts > 0 & counts < small)
  if (!n) return(data.frame(check = character(), column = character(), count = integer()))
  data.frame(check = check, column = column, count = as.integer(n))
}

.identifiability_sentence <- function(check, column, count, small) {
  col <- paste0("`", column, "`")
  switch(check,
         small = paste0(.n_of(count, "cell"), " of ", col, " hold fewer than ", small, " patients. Combine levels, or ",
                        "decide that the count can be shown."),
         at_risk = paste0("Fewer than ", small, " patients are at risk at ", .n_of(count, "time"), " shown for ", col,
                          ". End the table or figure sooner, or decide that the count can be shown."),
         position = paste0(.n_of(count, "patient"), " in ", col, " had their operation in a calendar year of fewer than ",
                           small, " patients, so the follow-up figure's point can be read as that patient's operation ",
                           "date and follow-up. Leave those years off the published figure, or decide that it can be shown."),
         group = paste0(col, " has ", .n_of(count, "group"), " of fewer than ", small, " patients. Combine groups, or ",
                        "decide that the count can be shown."),
         age = paste0(.n_of(count, "patient"), " in ", col, " are older than 89. Wherever age is shown, report ages 90 ",
                      "and older as one group."),
         date = paste0(col, " holds an exact date for ", .n_of(count, "patient"), ". Show the year only."),
         extreme = paste0(col, "'s minimum or maximum is shown, and ", .n_of(count, "patient"), " lie far beyond the ",
                          "rest. Check that the shown value does not point to one patient."))
}

# The callout above a manuscript table or figure, and the same counts in the run record.
# Silent when nothing is found.
.identifiability_notice <- function(findings, small = 5L) {
  if (!nrow(findings)) return(invisible(""))
  .run_state$identifiability <- rbind(.run_state$identifiability, findings)
  lines <- paste0("- ", mapply(.identifiability_sentence, findings$check, findings$column, findings$count,
                               MoreArgs = list(small = small), USE.NAMES = FALSE))
  paste0("\n::: {.callout-warning title=\"Before this goes in a manuscript\"}\n", paste(lines, collapse = "\n"), "\n:::\n\n")
}
