# The checks run_job() makes, each returning one record so the report and the tests read them the
# same way. Design: dev/specs/2026-10-22-run-job-design.md.
.check <- function(name, ok, message = NULL, fix = NULL, note = NULL) {
  list(name = name, ok = ok, message = if (!ok) paste0(name, ": ", message), fix = fix, note = note)
}

# Wrapped so tests can stand in for them; base functions cannot be mocked.
.session_r <- function() getRversion()
.r_home <- function() R.home("bin")
.installed_version <- function(p) {
  tryCatch(as.character(utils::packageVersion(p)), error = function(e) NA_character_)
}
.always_needed <- function() c("quarto", "knitr", "rmarkdown", "hvtiRtemplates", "hvtiRutilities")

.lock_read <- function(root) {
  f <- file.path(root, "renv.lock")
  if (!file.exists(f)) return(NULL)
  jsonlite::read_json(f, simplifyVector = FALSE)
}

.lock_r_version <- function(root) {
  v <- .lock_read(root)$R$Version
  if (is.character(v) && length(v) == 1L) v else NA_character_
}

# NULL for anything that is not at least major.minor ("", "devel", "4").
.parse_r <- function(v) {
  nv <- tryCatch(numeric_version(v), error = function(e) NULL)
  if (is.null(nv) || length(nv) != 1L || is.na(nv) || length(unlist(nv)) < 2L) NULL else nv
}

.minor <- function(nv) paste(unlist(nv)[1:2], collapse = ".")

# renv keeps one library per major.minor, so only that has to agree.
.check_r_version <- function(root) {
  lock <- .lock_r_version(root)
  have <- as.character(.session_r())
  if (is.na(lock)) return(.check("r_version", TRUE))
  nv <- .parse_r(lock)
  if (is.null(nv)) {
    return(.check("r_version", TRUE, note = sprintf("the R version in renv.lock (\"%s\") could not be read; not checked.", lock)))
  }
  if (.minor(nv) != .minor(numeric_version(have))) {
    return(.check("r_version", FALSE,
                  sprintf("this study's renv.lock records R %s, but this session is R %s, so it would use a different library.",
                          lock, have),
                  sprintf("Run it from a terminal with `hvti run <job>`, or start R %s (/opt/R/%s/bin/R).", lock, lock)))
  }
  .check("r_version", TRUE, note = if (lock != have) sprintf("renv.lock records R %s; this session is %s (same library).", lock, have))
}

# What the job's own setup chunk loads, read the way .template_packages() reads a template.
.job_packages <- function(path) {
  pk <- tryCatch(.template_packages(path)$package, error = function(e) NULL)
  structure(unique(c(pk, .always_needed())), unread = is.null(pk))
}

.check_packages <- function(path, root) {
  lock <- .lock_read(root)
  if (is.null(lock)) return(.check("packages", TRUE, note = "no renv.lock; packages not checked."))
  # GitHub and local sources can carry no Version; they count as unrecorded.
  locked <- vapply(lock$Packages, function(p) if (is.character(p$Version) && length(p$Version) == 1L) p$Version else NA_character_, "")
  need <- .job_packages(path)
  have <- vapply(as.vector(need), .installed_version, "")
  bad <- character()
  fix <- character()
  for (p in as.vector(need)) {
    l <- if (p %in% names(locked)) locked[[p]] else NA_character_  # NA: absent or no Version
    h <- have[[p]]
    if (is.na(h) && is.na(l)) {
      bad <- c(bad, sprintf("%s is neither installed nor recorded in renv.lock", p))
      fix <- c(fix, "hvtiR::update()")
    } else if (is.na(l)) {
      bad <- c(bad, sprintf("%s %s is installed but not recorded in renv.lock", p, h))
      fix <- c(fix, "hvtiR::update()")
    } else if (is.na(h)) {
      bad <- c(bad, sprintf("%s %s is recorded in renv.lock but not installed", p, l))
      fix <- c(fix, sprintf('renv::restore(packages = "%s")', p))
    } else if (numeric_version(h) != numeric_version(l)) {
      bad <- c(bad, sprintf("%s %s installed, %s locked", p, h, l))
      fix <- c(fix, if (numeric_version(h) > numeric_version(l)) "hvtiR::update()" else sprintf('renv::restore(packages = "%s")', p))
    }
  }
  other <- setdiff(names(locked), as.vector(need))
  drift <- other[vapply(other, function(p) .drifts(.installed_version(p), locked[[p]]), NA)]
  note <- c(if (length(drift)) sprintf("%d package(s) this job does not load differ from renv.lock: %s.",
                                       length(drift), paste(drift, collapse = ", ")),
            if (isTRUE(attr(need, "unread"))) "the job's own packages could not be read, so only the always-needed set was checked.")
  note <- if (length(note)) paste(note, collapse = " ")
  if (length(bad)) return(.check("packages", FALSE, paste0(paste(bad, collapse = "; "), "."),
                                 paste(unique(fix), collapse = "\n"), note))
  .check("packages", TRUE, note = note)
}

# TRUE when the installed and locked versions differ; "3.5.8" and "3.5-8" are the same version.
.drifts <- function(have, lock) {
  if (is.na(lock)) return(FALSE)
  if (is.na(have)) return(TRUE)
  numeric_version(have) != numeric_version(lock)
}

# Quarto starts its own R for knitr; QUARTO_R or the PATH can point it at another one.
.check_render_r <- function(expected = Sys.getenv("HVTI_RUN_R")) {
  if (!nzchar(expected)) return(.check("render_r", TRUE))
  have <- normalizePath(.r_home(), mustWork = FALSE)
  want <- normalizePath(expected, mustWork = FALSE)
  if (identical(have, want)) return(.check("render_r", TRUE))
  .check("render_r", FALSE,
         sprintf("Quarto ran this render on %s, not the R that submitted it, %s.", have, want),
         "A QUARTO_R setting is overriding it: remove QUARTO_R from ~/.Renviron or the study's .Renviron.")
}
