# The Key printed under a manuscript table. House rule: every abbreviation a
# table prints is defined in that table's own Key. The Abbreviations list at
# the top of a manuscript carries only the abbreviations its text uses, from
# the Introduction through the Conclusions, so a table cannot lean on it.
#
# The key was once only what a job typed into ABBREVIATIONS, which a new job
# starts empty, so a table printing NYHA or LVEF went out with no key at all.
# It is built here from the table's own printed text instead: every
# abbreviation the study's list can expand is keyed, and ABBREVIATIONS adds to
# it or overrides an expansion.
#
# `text` is every string the table prints: header, body and footer.
# `known` is hvtiRutilities::study_abbreviations(), phrase to abbreviation with
# attribute "expansion". `extra` is the job's own c(ABBR = "expansion").
# Returns `key`, c(ABBR = "expansion") for every abbreviation the table prints,
# and `missing`, the acronym-shaped words it prints that nothing expands.
.table_key <- function(text, known = character(0), extra = character(0)) {
  if (length(extra) && (is.null(names(extra)) || any(!nzchar(names(extra))) || anyNA(names(extra)))) {
    stop('ABBREVIATIONS must name each expansion by its abbreviation, c(ABBR = "expansion").', call. = FALSE)
  }
  # A blank or missing expansion would replace the study's and key nothing.
  if (length(extra) && (anyNA(extra) || any(!nzchar(trimws(extra))))) {
    stop("ABBREVIATIONS must give every abbreviation an expansion; blank or NA: ",
         paste(names(extra)[is.na(extra) | !nzchar(trimws(extra))], collapse = ", "), call. = FALSE)
  }
  text <- gsub("[~^][^~^]*[~^]", "", as.character(text[!is.na(text)])) # ^2^ and ~2~ markup
  words <- unique(unlist(regmatches(text, gregexpr("[[:alpha:]][[:alnum:]]*", text))))
  expansion <- attr(known, "expansion", exact = TRUE) %||% names(known)
  from_study <- stats::setNames(as.character(expansion), unname(known))
  from_study <- from_study[!duplicated(names(from_study))]
  # An abbreviation is matched as a whole word in the printed text, as written,
  # or as its plural: a key that defines AVR covers "Prior AVRs".
  # A list entry such as "S. aureus" or "Std. Diff." holds a space or a stop, so
  # it is looked for as a phrase.
  printed <- function(abbreviation) {
    pattern <- paste0("(?<![[:alnum:]])\\Q", abbreviation, "\\E(?:s)?(?![[:alnum:]])")
    any(grepl(pattern, text, perl = TRUE))
  }
  candidates <- c(extra, from_study[setdiff(names(from_study), names(extra))])
  key <- candidates[vapply(names(candidates), printed, logical(1))]
  key <- key[order(toupper(names(key)))]
  # The same test .sentence_case() uses for a word that is plainly an acronym:
  # upper case past its first letter, or holding a digit. Here a word with a
  # digit must also carry a capital: a variable name such as hba1c, printed in
  # the report's variable column, is not an abbreviation. Roman numerals are
  # level text (NYHA class I to IV), and units are not keyed.
  acronym <- grepl("^.[[:alnum:]]*[[:upper:]]", words) |
    grepl("[[:digit:]]", words) & grepl("[[:alpha:]]{2}", words) & grepl("[[:upper:]]", words)
  roman <- grepl("^[IVX]+$", words)
  # A surname or eponym is capitalized inside, McNemar, MacDonald, DeBakey,
  # DiGeorge, but is a name, not an abbreviation: a short prefix, one capital,
  # then lower case only. An acronym has a second capital or a digit after it.
  surname <- grepl("^(Mc|Mac|De|Di|Da|Du|La|Le)[[:upper:]][[:lower:]]{2,}$", words)
  missing <- words[acronym & !roman & !surname & !words %in% c(names(key), paste0(names(key), "s"), .table_key_units)]
  list(key = key, missing = sort(missing))
}

# Units a table prints that are not abbreviations to key.
.table_key_units <- c("mL", "dL", "mmHg", "mEq", "IU", "kPa", "pH")

# The text of each cell a flextable prints, from information_data_chunk(). That
# returns formatted runs, not cells: a label with markup, HbA~1c~, comes back as
# "HbA" and "1c", which match neither the abbreviation nor anything else. The
# runs of one cell are joined again before any word is read.
.table_cells_text <- function(chunks) {
  cell <- paste(chunks$.part, chunks$.row_id, chunks$.col_id, sep = "\r")
  unname(vapply(split(chunks$txt, factor(cell, unique(cell))), paste, "", collapse = ""))
}
