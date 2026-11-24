# Memory a fit needs against the memory its session is allowed. Design:
# dev/specs/2026-10-22-run-job-design.md section 5.2.

# Workbench enforces about 1.2 times the profile's memory (measured 2026-10-22).
.workbench_profiles <- data.frame(profile = c("Default", "Small", "Medium", "Large"),
                                  cap_gib = c(19.2, 38.4, 76.8, 153.6))

.profile_for <- function(need_gib) {
  i <- which(.workbench_profiles$cap_gib * 0.9 >= need_gib)[1L]
  if (is.na(i)) "none" else .workbench_profiles$profile[i]
}

.read_bytes_gib <- function(f) {
  if (!file.exists(f)) return(NA_real_)
  x <- trimws(readLines(f, n = 1L, warn = FALSE))
  v <- suppressWarnings(as.numeric(x))
  # v1 writes a value near 2^63 for "no limit"; v2 writes "max".
  if (is.na(v) || v > 2^60) NA_real_ else v / 1024^3
}

# A detached job counts against its submitting session's cgroup, so this is the cap the fit will hit.
# An unlimited leaf can sit beneath a capped ancestor, so the binding cap is the smallest finite one
# from the leaf up to the controller's root; usage and peak are read at that same cgroup.
.cgroup_memory <- function(proc = "/proc/self/cgroup", sys = "/sys/fs/cgroup") {
  lines <- if (file.exists(proc)) readLines(proc, warn = FALSE) else character()
  parts <- strsplit(lines, ":", fixed = TRUE)
  v1 <- Filter(function(p) length(p) >= 3L && "memory" %in% strsplit(p[2L], ",", fixed = TRUE)[[1L]], parts)
  v2 <- Filter(function(p) length(p) >= 3L && p[1L] == "0" && p[2L] == "", parts)
  spec <- if (length(v1)) {
    # The path is everything after the second ':', which a cgroup's own name may contain.
    list(base = file.path(sys, "memory"), rel = paste(v1[[1L]][-(1:2)], collapse = ":"), source = "cgroup v1",
         files = c("memory.limit_in_bytes", "memory.usage_in_bytes", "memory.max_usage_in_bytes"))
  } else if (length(v2)) {
    list(base = sys, rel = paste(v2[[1L]][-(1:2)], collapse = ":"), source = "cgroup v2",
         files = c("memory.max", "memory.current", "memory.peak"))
  }
  out <- list(limit_gib = NA_real_, usage_gib = NA_real_, peak_gib = NA_real_, source = "physical")
  if (!is.null(spec)) {
    segs <- strsplit(sub("^/", "", spec$rel), "/", fixed = TRUE)[[1L]]
    for (i in rev(seq_len(length(segs) + 1L) - 1L)) {   # leaf first, then each ancestor, then the root
      d <- do.call(file.path, as.list(c(spec$base, segs[seq_len(i)])))
      lim <- .read_bytes_gib(file.path(d, spec$files[1L]))
      if (!is.na(lim) && (is.na(out$limit_gib) || lim < out$limit_gib)) {
        out <- list(limit_gib = lim, usage_gib = .read_bytes_gib(file.path(d, spec$files[2L])),
                    peak_gib = .read_bytes_gib(file.path(d, spec$files[3L])), source = spec$source)
      }
    }
  }
  if (is.na(out$limit_gib)) {
    out$limit_gib <- tryCatch(as.numeric(ps::ps_system_memory()$total) / 1024^3, error = function(e) NA_real_)
    out$source <- "physical"
  }
  out
}

# ORDINAL: need = 1 GiB base + cores * 0.5 * (patients / 1000)^1.7 + growth. Memory follows PATIENTS, not
# visits: a visits term cannot reach Penny's kill (5,500 patients but only 13,900 visits) and also match
# the 2.0.4 table, where a patients term matches both. Calibrated 2026-10-22; John reviews it in the PR.
#  - p = 1.7: the shape of the template's 2.0.4 CORES table (2026-10-19, ordinal, ~9 visits/patient, M = 10):
#    per-worker memory 1.25 GB at 1,000 patients, 3.6 at 2,000 (p ~ 1.5), 17 at 4,000 (p ~ 1.9).
#  - a[ordinal] = 0.5: 2.0.8 workers use about a third of 2.0.4's (1.25 / 3 ~ 0.42), raised to 0.5 so Penny's
#    fit (2026-10-22, 2.0.8, 5,500 patients / 13,900 visits / ordinal / 8 cores, killed at iteration 2 in a
#    Medium session, 76.8 GiB cap) estimates above 0.9 x 76.8.
#  - growth: 0.35e-3 GiB per boosting step per 1,000 visits, ordinal only (the CORES comment's term).
# The ordinal estimate above is unmeasured on boostmtree 2.0.13 and is left as calibrated.
#
# CONTINUOUS, recalibrated on boostmtree 2.0.13 (#601, 2026-11-24):
#   need = 1 GiB base + cores * (patients / 1000)^1.4 * (0.5 + 1.3e-3 * M)
# Measured peaks, the fit and its workers together sampled every 2 s (an upper bound: shared pages count
# once per process), randomForestSRC 3.10.0, NU = 0.05, 5 shadow copies:
#   simulated, M = 500, 24 real predictors: 1,000 patients x 4 cores 5.0 GiB; 2,000 x 8 18.3 GiB
#   (4 real predictors: 4.2 and 17.1); M = 10: 1,000 x 4 2.6, 1,000 x 8 3.2, 2,000 x 8 8.3, 4,000 x 4 10.6.
#   COMMENCE (1,391 patients / 4,771 visits / 52 predictors / 8 cores): 3.7 GiB at M = 10, 9.2 at M = 500.
#  - M: memory grows through the fit, 2.1 to 2.5 times from M = 10 to M = 500 and steadily in between, so the
#    per-worker term rises with M. A short trial run understates the fit.
#  - p = 1.4: per-worker memory scaled as patients^1.1 to ^1.6 across the cells, against 1.7 on 2.0.4.
#  - 0.5 and 1.3e-3: every measured peak sits 1.1 to 2.0 times under its estimate, the tightest at
#    1,000 x 4 and M = 500 with 24 predictors; the guard refuses at 0.9 of the cap besides.
#  - Predictors: 24 real predictors against 4 raised the peak 7% to 30%, inside that margin, so the estimate
#    has no predictor term. Shadows alone moved it -14% to +26% (2026-11-20 retime).
#  - COMMENCE was killed in a Default session (19.2 GiB) at its first CV step on 2.0.8 (2026-10-22); on 2.0.13
#    the same fit needs a fifth of that at M = 10, so the kill belongs to the older version.
#  - Unmeasured: factor predictors with many levels (COMMENCE has none), and 4,000 patients at M = 500.
#  - Any other family takes the larger of the two estimates, conservatively; that is unmeasured.
# The ordinal upper bound is unknown: Penny's Large run (started 2026-10-22 13:26 on lri-r03) has not recorded a
# peak, so whether 8 cores fits Large (threshold 138.2 GiB) is not asserted anywhere.
# The 2.0.13 continuous estimate applies only to the version it was measured on. An older boostmtree, which
# the deprecated nb-boostmtree template and jobs already copied into studies still accept (a study's own
# library held 2.0.11 on 2026-11-24), keeps the 2.0.8 estimate: 1 + cores * 2.6 * (patients / 1000)^1.7, the one
# that named Medium for COMMENCE after its Default kill. So does a version that cannot be read.
.boostmtree_need_gib <- function(patients, visits, family, cores, m, version = NULL) {
  for (x in list(patients, visits, cores, m)) {
    if (!is.numeric(x) || length(x) != 1L || (!is.na(x) && x < 0)) {
      stop("patients, visits, cores and m must be non-negative numbers.", call. = FALSE)
    }
  }
  if (is.null(version)) version <- tryCatch(utils::packageVersion("boostmtree"), error = function(e) NA)
  measured <- !is.na(version) && package_version(version) >= "2.0.13"
  ordinal <- 1 + cores * 0.5 * (patients / 1000)^1.7 + 0.35e-3 * m * visits / 1000
  continuous <- if (measured) {
    1 + cores * (patients / 1000)^1.4 * (0.5 + 1.3e-3 * m)
  } else {
    1 + cores * 2.6 * (patients / 1000)^1.7
  }
  switch(family, ordinal = ordinal, continuous = continuous, max(ordinal, continuous))
}

#' Refuse a fit that this session's memory cap cannot hold
#'
#' @description
#' Call this at the top of a fit chunk, with the memory the fit is expected to need. It reads the
#' memory limit of the session (the Linux cgroup, falling back to the machine's physical memory) and
#' stops, in the first minutes of a render, when the need exceeds 90 percent of it. The refusal names the
#' Workbench profile that would hold the fit and, when `cores_fit` is given, the largest
#' `cores` that would fit in this session.
#'
#' @param need_gib Expected peak memory of the fit, in GiB. `0` (a cached re-render) and
#'   `NA` (no estimate) pass.
#' @param why Character(1). What needs the memory, in a few words, for the message, best with the
#'   counts the estimate was made from ("this boostmtree fit (1,391 patients, 4,771 visits, continuous)").
#' @param cores Number of parallel workers the fit would use, a whole number of at least 1, or `NULL`.
#' @param cores_fit A function taking a number of cores and returning the GiB the fit would need, or
#'   `NULL`. Used only to name a core count that fits.
#' @param proc,sys Paths of the cgroup files, for tests. The defaults read the running session.
#'
#' @return The session's memory limit in GiB, invisibly, when the fit fits. Otherwise an error whose
#'   text begins `memory:`.
#'
#' @details
#' A detached job counts against its submitting session's cgroup, so this is the cap the fit will hit.
#' On cgroup v1 the recorded peak is the session's, not the job's alone. Workbench enforces about 1.2
#' times the memory its profile advertises, and the profile caps used here are those enforced values.
#'
#' @examples
#' \donttest{
#' # Without a cgroup (macOS, Windows) this falls back to the machine's physical memory.
#' guard_memory(1, "a small fit")
#' }
#' @export
guard_memory <- function(need_gib, why, cores = NULL, cores_fit = NULL,
                         proc = "/proc/self/cgroup", sys = "/sys/fs/cgroup") {
  if (!(length(need_gib) == 1L && (is.numeric(need_gib) || identical(need_gib, NA)))) {
    stop("guard_memory(): `need_gib` must be a single number of GiB, or NA.", call. = FALSE)
  }
  if (!is.character(why) || length(why) != 1L || is.na(why)) {
    stop("guard_memory(): `why` must be a single string.", call. = FALSE)
  }
  if (!is.null(cores)) {
    if (!is.numeric(cores) || length(cores) != 1L || is.na(cores) || cores < 1 || cores != round(cores)) {
      stop("guard_memory(): `cores` must be NULL or a single whole number, 1 or more.", call. = FALSE)
    }
    cores <- as.integer(cores)
  }
  m <- .cgroup_memory(proc, sys)
  # Recorded so job_status() can name the right profile if the fit dies anyway (spec section 6).
  if (!is.na(need_gib) && !is.null(.progress_state$file)) .progress_state$mem_need_gib <- round(need_gib, 1)
  if (is.na(need_gib) || is.na(m$limit_gib) || need_gib <= 0.9 * m$limit_gib) {
    .progress_check_passed("memory")
    return(invisible(m$limit_gib))
  }
  here <- .workbench_profiles$profile[match(TRUE, abs(.workbench_profiles$cap_gib - m$limit_gib) < 0.5)]
  where <- if (identical(m$source, "physical")) {
    sprintf("%.1f GiB (physical memory: no cgroup limit found)", m$limit_gib)
  } else if (is.na(here)) {
    sprintf("%.1f GiB", m$limit_gib)
  } else {
    sprintf("%.1f GiB (Workbench \"%s\")", m$limit_gib, here)
  }
  to <- .profile_for(need_gib)
  k <- if (is.function(cores_fit) && !is.null(cores)) {
    ok <- Filter(function(k) isTRUE(cores_fit(k) <= 0.9 * m$limit_gib), seq_len(cores - 1L))  # an NA estimate never fits
    if (length(ok)) max(unlist(ok))
  }
  .abort(.check("memory", FALSE,
                sprintf("%s needs about %.0f GiB%s and this session is capped at %s. %s%s",
                        why, need_gib, if (!is.null(cores)) sprintf(" with %d cores", cores) else "", where,
                        if (to == "none") "No Workbench profile holds it: reduce CORES or the data." else
                          sprintf("Start a \"%s\" session (%.1f GiB) or larger.", to,
                                  .workbench_profiles$cap_gib[.workbench_profiles$profile == to]),
                        if (!is.null(k)) sprintf(" Or set CORES <- %d to fit in this one.", k) else ""))$message,
         class = "memory")
}

# The memory fields .run.yml records at a run's end; list() when nothing can be read.
.run_memory_fields <- function() {
  m <- tryCatch(.cgroup_memory(), error = function(e) list())
  num <- function(x) if (.num1(x)) round(x, 1)
  Filter(Negate(is.null), list(mem_peak_gib = num(m$peak_gib), mem_limit_gib = num(m$limit_gib)))
}

# TRUE when hvtiRutilities::cache_fit() would compute rather than load, given the same arguments, so a template guards
# memory only for a fit that will run. It follows cache_fit()'s own decision: no file computes; a file whose key matches
# loads, REFIT or not; a stale or unkeyed file stops cache_fit() before any fit without REFIT, and computes with it.
# hvtiRutilities exports no such test, so the key comes from cache_fit()'s own internals (unchanged since the 1.5.7
# floor). Were they ever renamed, the answer falls back to "REFIT computes", which over-guards but never under-guards.
# A matching file under REFIT is read here and again by cache_fit(): the cost of that one case, against refusing a
# session for memory it would not use.
.cache_would_fit <- function(name, code, seed = NULL, dir, refit = FALSE, packages = NULL, env = parent.frame()) {
  # Kept for jobs scaffolded before 1.5.0, which call hvtiRtemplates:::.cache_would_fit() with a quoted call.
  # The decision is hvtiRutilities::cache_would_fit()'s (>= 1.5.11), the one cache_fit() itself makes.
  call <- bquote(hvtiRutilities::cache_would_fit(.(name), .(code), seed = .(seed), dir = .(dir),
                                                 refit = .(refit), packages = .(packages)))
  eval(call, env)
}
