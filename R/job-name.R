# A job's file name. add_job() writes the first spelling; both are read.
#
#   <prefix>[.<qualifier>].<subject>.<type>.qmd   since 2026-10
#   <subject>-<type>-<prefix>[-<qualifier>].qmd   before
#
# subject, type and qualifier match ^[A-Za-z0-9_]+$, so neither "." nor "-"
# can appear inside a field: the separator tells the spellings apart, and in
# the period form the field count says whether a qualifier is present. A
# runner adds .runner.R (or -runner.R). The design is in the hvtiR repository,
# under dev/specs, dated 2026-10-07: job naming, template first.

.job_stem <- function(prefix, qualifier, subject, type) {
  has_qualifier <- !is.null(qualifier) && !is.na(qualifier)
  paste(c(prefix, if (has_qualifier) qualifier, subject, type), collapse = ".")
}

# c(subject, type) from a job's path, or character(0) when the name is in
# neither spelling. Quarto knits through an intermediate (<stem>.rmarkdown),
# so the last extension is stripped whatever it is. Only an R script can be a
# runner, so only there is a trailing runner field dropped: a report whose
# type is "runner" keeps it. The dash spelling keeps the old check's
# leniency: it took the first two fields of any dashed name.
.job_name_fields <- function(path) {
  base <- basename(path)
  stem <- sub("[.][^.]+$", "", base)
  if (grepl("[.]R$", base)) stem <- sub("([.]|-)runner$", "", stem)
  if (grepl("-", stem, fixed = TRUE)) {
    parts <- strsplit(stem, "-", fixed = TRUE)[[1L]]
    return(if (length(parts) >= 2L) parts[1:2] else character(0))
  }
  parts <- strsplit(stem, ".", fixed = TRUE)[[1L]]
  if (length(parts) %in% 3:4 && all(grepl("^[A-Za-z0-9_]+$", parts))) {
    return(parts[(length(parts) - 1L):length(parts)])
  }
  character(0)
}

# The same job in the dash spelling, so add_job() can refuse a duplicate and
# open_job() can open a job scaffolded before 2026-10.
.job_path_legacy <- function(row, subject, type, root) {
  out_dir <- hvtiRutilities::study_dir(row$folder[[1L]], root = root)
  stem <- paste0(subject, "-", type, "-", row$prefix[[1L]],
                 if (!is.na(row$qualifier[[1L]])) paste0("-", row$qualifier[[1L]]) else "")
  file.path(out_dir, paste0(stem, ".qmd"))
}
