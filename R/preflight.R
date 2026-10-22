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

.minor <- function(v) paste(unlist(numeric_version(v))[1:2], collapse = ".")

# renv keeps one library per major.minor, so only that has to agree.
.check_r_version <- function(root) {
  lock <- .lock_r_version(root)
  have <- as.character(.session_r())
  if (is.na(lock)) return(.check("r_version", TRUE))
  if (.minor(lock) != .minor(have)) {
    return(.check("r_version", FALSE,
                  sprintf("this study's renv.lock records R %s, but this session is R %s, so it would use a different library.",
                          lock, have),
                  sprintf("Run it from a terminal with `hvti run <job>`, or start R %s (/opt/R/%s/bin/R).", lock, lock)))
  }
  .check("r_version", TRUE, note = if (lock != have) sprintf("renv.lock records R %s; this session is %s (same library).", lock, have))
}

# What the job's own setup chunk loads, read the way .template_packages() reads a template.
.job_packages <- function(path) {
  pk <- tryCatch(.template_packages(path)$package, error = function(e) character())
  unique(c(pk, .always_needed()))
}

.check_packages <- function(path, root) {
  lock <- .lock_read(root)
  if (is.null(lock)) return(.check("packages", TRUE, note = "no renv.lock; packages not checked."))
  locked <- vapply(lock$Packages, function(p) p$Version, "")
  need <- .job_packages(path)
  have <- vapply(need, .installed_version, "")
  bad <- character()
  fix <- character()
  for (p in need) {
    l <- if (p %in% names(locked)) locked[[p]] else NA_character_
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
    } else if (h != l) {
      bad <- c(bad, sprintf("%s %s installed, %s locked", p, h, l))
      fix <- c(fix, if (numeric_version(h) > numeric_version(l)) "hvtiR::update()" else sprintf('renv::restore(packages = "%s")', p))
    }
  }
  other <- setdiff(names(locked), need)
  drift <- other[vapply(other, function(p) !identical(.installed_version(p), locked[[p]]), NA)]
  note <- if (length(drift)) sprintf("%d package(s) this job does not load differ from renv.lock: %s.",
                                     length(drift), paste(drift, collapse = ", "))
  if (length(bad)) return(.check("packages", FALSE, paste0(paste(bad, collapse = "; "), "."),
                                 paste(unique(fix), collapse = "\n"), note))
  .check("packages", TRUE, note = note)
}
