# A set-up study (so .find_study_root() accepts it, which needs _study.yml) with a renv.lock.
lock_study <- function(r = "4.5.3", pkgs = list(quarto = "1.4.4", knitr = "1.48"), env = parent.frame()) {
  # study_setup() wants a root that does not exist yet, so build the study in a subdirectory.
  root <- file.path(withr::local_tempdir(.local_envir = env), "study")
  invisible(hvtiRutilities::study_setup(root, "Example", 1L, renv = FALSE))
  lock <- list(R = list(Version = r, Repositories = list()),
               Packages = lapply(names(pkgs), function(p) list(Package = p, Version = pkgs[[p]])))
  names(lock$Packages) <- names(pkgs)
  jsonlite::write_json(lock, file.path(root, "renv.lock"), auto_unbox = TRUE, pretty = TRUE)
  dir.create(file.path(root, "analyses"), showWarnings = FALSE)
  root
}

status_job <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  job <- file.path(dir, "nb.boostmtree.x.boost.qmd")
  writeLines("---\ntitle: x\n---", job)
  job
}

# A cgroup v1 tree: the session's leaf under the memory controller, optionally beneath a capped parent.
fake_cgroup_v1 <- function(limit_gib, usage_gib = 1, peak_gib = 2, parent_gib = NULL, env = parent.frame()) {
  d <- withr::local_tempdir(.local_envir = env)
  proc <- file.path(d, "cgroup")
  writeLines(c("12:cpu,cpuacct:/rstudio/s1", "7:memory:/rstudio/s1", "1:name=systemd:/x"), proc)
  b <- function(g) if (is.na(g)) "9223372036854771712" else format(round(g * 1024^3), scientific = FALSE)
  put <- function(dir, lim, use, peak) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    writeLines(b(lim), file.path(dir, "memory.limit_in_bytes"))
    writeLines(b(use), file.path(dir, "memory.usage_in_bytes"))
    writeLines(b(peak), file.path(dir, "memory.max_usage_in_bytes"))
  }
  put(file.path(d, "sys", "memory", "rstudio", "s1"), limit_gib, usage_gib, peak_gib)
  if (!is.null(parent_gib)) put(file.path(d, "sys", "memory", "rstudio"), parent_gib, usage_gib, peak_gib)
  list(proc = proc, sys = file.path(d, "sys"))
}
