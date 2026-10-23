# The checks run_job() makes, each returning one record so the report and the tests read them the
# same way. Design: dev/specs/2026-10-22-run-job-design.md.
.check <- function(name, ok, message = NULL, fix = NULL, note = NULL) {
  list(name = name, ok = ok, message = if (!ok) paste0(name, ": ", message), fix = fix, note = note)
}

# TRUE when x is one number, not NA.
.num1 <- function(x) is.numeric(x) && length(x) == 1L && !is.na(x)

# Wrapped so tests can stand in for them; base functions cannot be mocked.
.session_r <- function() getRversion()
.r_home <- function() R.home("bin")
# Only the active libraries: packageVersion() without lib.loc reports a namespace already loaded from a library that
# is not on .libPaths(), which the render would not find. packageDescription() warns and gives NA for an absent one.
.installed_version <- function(p) {
  v <- tryCatch(suppressWarnings(utils::packageDescription(p, lib.loc = .libPaths(), fields = "Version")),
                error = function(e) NA_character_)
  if (is.character(v) && length(v) == 1L && !is.na(v)) v else NA_character_
}
.renv_project <- function() Sys.getenv("RENV_PROJECT")
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
  # The packages check reads this session's library, which is the study's only when this session runs renv for it.
  # hvti's route passes: Rscript starts in the root, where the study's .Rprofile activates renv and sets RENV_PROJECT.
  proj <- .renv_project()
  uses <- if (nzchar(proj)) {
    identical(normalizePath(proj, mustWork = FALSE), normalizePath(root, mustWork = FALSE))
  } else {
    !file.exists(file.path(root, "renv", "activate.R"))
  }
  if (!uses) {
    return(.check("r_version", FALSE,
                  sprintf(paste("this session is not using this study's renv library (%s), so the package check and",
                                "the render would read different libraries."),
                          if (nzchar(proj)) paste("it runs renv for", proj) else "renv is not active"),
                  "Run it from a terminal with `hvti run <job>`, or open the study's own project so renv activates."))
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
# HVTI_RUN_R is set by submit_job() for the runner. Setting it by hand (in ~/.Renviron, say) makes editor renders fail this check.
# HVTI_RUN_R_VERSION, set beside it, names the submitter's version; a runner started before it existed names paths only.
.check_render_r <- function(expected = Sys.getenv("HVTI_RUN_R"), expected_version = Sys.getenv("HVTI_RUN_R_VERSION")) {
  if (!nzchar(expected)) return(.check("render_r", TRUE))
  have <- normalizePath(.r_home(), mustWork = FALSE)
  want <- normalizePath(expected, mustWork = FALSE)
  if (identical(have, want)) return(.check("render_r", TRUE))
  named <- if (nzchar(expected_version)) {
    c(sprintf("R %s (%s)", as.character(.session_r()), have), sprintf("R %s (%s)", expected_version, want))
  } else {
    c(have, want)
  }
  .check("render_r", FALSE,
         sprintf("Quarto ran this render on %s, not the R that submitted it, %s.", named[1L], named[2L]),
         paste("A QUARTO_R setting, or another R first on the PATH, is overriding it:",
               "remove QUARTO_R from ~/.Renviron or the study's .Renviron, and check the PATH."))
}

.quarto_pkg <- function() requireNamespace("quarto", quietly = TRUE)
.quarto_found <- function() !is.null(tryCatch(quarto::quarto_path(), error = function(e) NULL))

# The spellings of this R that QUARTO_R may use: its bin directory, its R home, and, for an R installed
# under <prefix>/lib/R (as /opt/R/<version> is), <prefix>/bin, which holds the same R's front ends.
.same_r_dirs <- function(bin = .r_home()) {
  dirs <- c(bin, dirname(bin))
  if (grepl("/lib(64)?/R/bin/?$", bin)) dirs <- c(dirs, file.path(dirname(dirname(dirname(bin))), "bin"))
  normalizePath(dirs, mustWork = FALSE)
}

.check_quarto <- function() {
  if (!.quarto_pkg()) {
    return(.check("quarto", FALSE, "the quarto R package is not installed.", 'renv::restore(packages = "quarto")'))
  }
  if (!.quarto_found()) {
    return(.check("quarto", FALSE, "the Quarto command line tool cannot be found.",
                  "Ask the server administrator; on lri it ships with Workbench."))
  }
  q <- Sys.getenv("QUARTO_R")
  # QUARTO_R may name the Rscript itself rather than its directory.
  q_dir <- if (file.exists(q) && !dir.exists(q)) dirname(q) else q
  if (nzchar(q) && !normalizePath(q_dir, mustWork = FALSE) %in% .same_r_dirs()) {
    return(.check("quarto", FALSE, sprintf("QUARTO_R is set to %s, so Quarto would render on that R, not this one (%s).",
                                           q, .r_home()),
                  "Remove QUARTO_R from ~/.Renviron or the study's .Renviron."))
  }
  .check("quarto", TRUE)
}

# Stale progress is not proof: Quarto's knitr runs in a session of its own and can outlive the Workbench
# session, so the way out confirms on that host before abandoning (spec section 6). `rel` is the path hvti takes.
.abandon_route <- function(st, path, rel = "") {
  if (!.on_other_host(st)) return(sprintf('Stop it with `hvti cancel`, or cancel_job("%s").', path))
  confirm <- if (is.character(st$marker)) {
    sprintf("On %s, confirm nothing is left with `ps eww -u $USER | grep %s`. ", st$host, st$marker)
  } else {
    sprintf("From a session on %s, confirm with `%s` that nothing is left. ", st$host, trimws(paste("hvti status", rel)))
  }
  sprintf('%sOnly then run cancel_job("%s", other_host = "abandon") here.', confirm, path)
}

# The job's path from the study root, which is what `hvti status` takes there; the full path when it lies outside.
.study_rel <- function(job, root) {
  r <- .norm_path(root)
  p <- .norm_path(job)
  if (startsWith(p, paste0(r, "/"))) substring(p, nchar(r) + 2L) else p
}

# TRUE only when the status records a host and it is not this one.
.on_other_host <- function(st) {
  is.character(st$host) && length(st$host) == 1L && !is.na(st$host) && !identical(st$host, Sys.info()[["nodename"]])
}

# A path with its directory resolved, which normalizePath() alone does not do for a file that is not there
# (macOS /var against /private/var).
.norm_path <- function(p) file.path(normalizePath(dirname(p), mustWork = FALSE), basename(p))

# THIS job already running, a stale run recorded on another host, or a crashed submit's lock directory.
# `root` is the study root, for the path the fix gives hvti; the default names the job by its file name.
.check_run_state <- function(path, root = dirname(path)) {
  files <- .run_files(path)
  if (dir.exists(files$lock)) {
    age <- difftime(Sys.time(), file.info(files$lock)$mtime, units = "mins")
    if (!is.na(age) && age > 10) {
      return(.check("run_state", FALSE,
                    sprintf("%s is %.0f minutes old; a submit that crashed left it.", basename(files$lock), age),
                    sprintf("Delete the directory %s, then run again.", files$lock)))
    }
  }
  st <- job_status(path, quiet = TRUE)
  here <- Sys.info()[["nodename"]]
  if (identical(st$state, "running") && is.character(st$host) && !identical(st$host, here)) {
    stale <- isTRUE(st$progress$stale)
    abandon <- .abandon_route(st, path, .study_rel(path, root))
    return(.check("run_state", FALSE,
                  sprintf("this job is recorded running on host %s%s.", st$host,
                          if (stale) ", but its progress has not moved for over 30 minutes, so it is probably dead" else ""),
                  paste0(if (!stale) sprintf("Check it from a session on %s with `hvti status`. ", st$host), abandon)))
  }
  if (st$state %in% c("running", "submitted")) {
    return(.check("run_state", FALSE, sprintf("this job is already %s.", st$state),
                  sprintf("Follow it with `hvti status %s`, or stop it with `hvti cancel %s`.",
                          .study_rel(path, root), .study_rel(path, root))))
  }
  .check("run_state", TRUE)
}

# The directories a study keeps that never hold a job's run files (renv's library is large).
.run_scan_skip <- c("renv", ".git", ".hvtiR")

# The jobs under `root` that have run files, found without descending into the skipped directories.
.jobs_with_run_files <- function(root) {
  jobs <- character()
  todo <- root
  while (length(todo)) {
    dir <- todo[[1L]]
    todo <- todo[-1L]
    entries <- list.files(dir, all.files = TRUE, no.. = TRUE)
    full <- file.path(dir, entries)
    is_dir <- dir.exists(full)
    # Jobs under a symlinked folder are not scanned: a deliberate trade-off against loops.
    linked <- nzchar(Sys.readlink(full))  # a symlinked directory could loop back on the study
    todo <- c(todo, full[is_dir & !linked & !entries %in% .run_scan_skip])
    hits <- entries[!is_dir & grepl("[.]run[.](yml|progress)$", entries)]
    jobs <- c(jobs, file.path(dir, sub("[.]run[.](yml|progress)$", ".qmd", hits)))
  }
  unique(jobs)
}

# TRUE when no .run.yml exists or it records a run that ended, so a running state can only have come from progress.
.run_yml_ended <- function(file) {
  if (!file.exists(file)) return(TRUE)
  state <- tryCatch(yaml::read_yaml(file)$state, error = function(e) NULL)
  isTRUE(state %in% c("finished", "failed", "cancelled"))
}

# Quarto holds one render lock per study, so another job rendering there fails minutes in. This names it up front.
.check_study_render <- function(path, root) {
  jobs <- .jobs_with_run_files(root)
  jobs <- jobs[vapply(jobs, .norm_path, "") != .norm_path(path)]
  running <- list()
  for (job in jobs) {
    st <- tryCatch(job_status(job, quiet = TRUE), error = function(e) NULL)  # an unreadable file must not stop preflight
    if (!is.null(st) && identical(st$state, "running")) running[[job]] <- st
  }
  rel_of <- function(job) .study_rel(job, root)
  # An editor render that errored never ends its progress file, so from another host it reads running for good.
  # Stale, on another host and not a submit_job() run (no .run.yml, or one recording an earlier run that ended), it is
  # noted with its way out, not refused.
  editor_dead <- vapply(names(running), function(j) {
    st <- running[[j]]
    isTRUE(st$progress$stale) && .on_other_host(st) && .run_yml_ended(.run_files(j)$status)
  }, NA)
  note <- if (any(editor_dead)) {
    paste(vapply(names(running)[editor_dead], function(j) {
      sprintf(paste("%s has a progress record on %s that has not moved for over 30 minutes and no submit_job() run",
                    "in progress, so it is probably an editor render that stopped with an error. %s"),
              rel_of(j), running[[j]]$host, .abandon_route(running[[j]], j, rel_of(j)))
    }, ""), collapse = " ")
  }
  running <- running[!editor_dead]
  if (length(running)) {
    describe <- function(job) {
      st <- running[[job]]
      pr <- st$progress
      stage <- if (is.character(pr$stage) && length(pr$stage) == 1L) {
        paste0("in stage ", pr$stage,
               if (.num1(pr$stage_index) && .num1(pr$stage_count)) {
                 sprintf(" (%d of %d)", as.integer(pr$stage_index), as.integer(pr$stage_count))
               })
      }
      left <- if (isTRUE(pr$stale)) {
        "its progress has not moved for over 30 minutes"
      } else if (.num1(pr$eta_s)) {
        paste("about", .fmt_dur(pr$eta_s), "left")
      }
      host <- if (is.character(st$host) && length(st$host) == 1L) paste("on", st$host)
      detail <- c(host, stage, left)
      paste0(rel_of(job), if (length(detail)) paste0(", ", paste(detail, collapse = ", ")))
    }
    # Stale on a host other than this one is the only case the wait advice cannot resolve; a missing host gets the live wording.
    is_stale <- vapply(running, function(st) isTRUE(st$progress$stale) && .on_other_host(st), NA)
    live <- paste(vapply(names(running)[!is_stale], rel_of, ""), collapse = ", ")
    routes <- vapply(names(running)[is_stale], function(j) {
      st <- running[[j]]
      # Without a marker the abandon route's own confirmation is `hvti status` on that host, so it is not said twice.
      check <- if (is.character(st$marker)) {
        sprintf("Check %s from a session on %s with `hvti status %s`. ", rel_of(j), st$host, rel_of(j))
      }
      paste0(check, .abandon_route(st, j, rel_of(j)))
    }, "")
    fix <- c(if (any(!is_stale)) {
      sprintf("Wait for it to finish (hvti status %s), or stop it (hvti cancel %s), then run again.", live, live)
    }, routes)
    return(.check("study_render", FALSE,
                  sprintf("another job is rendering in this study: %s. Quarto renders one job at a time in a study.",
                          paste(vapply(names(running), describe, ""), collapse = "; ")),
                  paste(fix, collapse = " "), note))
  }
  lock <- .provenance_lock_path(root)
  owner_file <- file.path(lock, "owner.json")
  owner <- if (file.exists(owner_file)) tryCatch(jsonlite::read_json(owner_file), error = function(e) NULL)
  if (!is.null(owner) && .provenance_owner_alive(owner)) {
    return(.check("study_render", FALSE,
                  sprintf(paste("another Quarto render holds this study's render lock (process %s), started outside run_job(),",
                                "so its job is not known."), owner$pid),
                  "Wait for it to finish, then run again.", note))
  }
  .check("study_render", TRUE, note = note)
}
