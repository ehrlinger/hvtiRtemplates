# A fresh exhibit state for one test: what .job_setup() would leave, pointed at
# a temporary study root. Restores the package's run state afterwards.
local_exhibit_state <- function(root = withr::local_tempdir(.local_envir = env), env = parent.frame()) {
  state <- hvtiRtemplates:::.run_state
  saved <- mget(intersect(c("root", "exhibits", "methods"), ls(state, all.names = TRUE)), envir = state)
  assign("root", normalizePath(root, winslash = "/"), envir = state)
  assign("exhibits", list(), envir = state)
  assign("methods", NULL, envir = state)
  withr::defer({
    rm(list = intersect(c("root", "exhibits", "methods"), ls(state, all.names = TRUE)), envir = state)
    list2env(saved, envir = state)
  }, envir = env)
  invisible(get("root", envir = state))
}

# A study holding one finished job, written by hand instead of rendered, so the
# ar helpers can be tested in milliseconds. `run` and `methods` override the
# sidecar's; `exhibits` names what the job saved.
ar_fake_study <- function(env = parent.frame()) {
  root <- withr::local_tempdir("ar-study-", .local_envir = env)
  writeLines("study: synthetic", file.path(root, "_study.yml"))
  normalizePath(root, winslash = "/")
}

ar_fake_job <- function(root, job = "hz.dead.hz", folder = "20_distributions",
                        run = list(status = "final", open_markers = 0L, skipped_chunks = 0L, stopped_early = FALSE),
                        methods = list(text = "A hazard was modeled.", sha256 = NULL),
                        rendered = "2026-11-12T10:00:00Z") {
  dir.create(file.path(root, folder), showWarnings = FALSE)
  set <- file.path(root, "graphs", "dead-hz")
  dir.create(set, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(root, "documents", "dead-hz"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(root, "estimates", "dead-hz"), recursive = TRUE, showWarnings = FALSE)
  qmd <- file.path(root, folder, paste0(job, ".qmd"))
  writeLines(c("---", "title: fake", "---"), qmd)
  html <- sub("[.]qmd$", ".html", qmd)
  writeLines("<html></html>", html)
  png <- file.path(set, "hz-fit.png")
  grDevices::png(png, width = 480, height = 480)
  graphics::plot(1)
  grDevices::dev.off()
  saveRDS(data.frame(term = "mu", estimate = 0.1), file.path(root, "documents", "dead-hz", "tbl-estimates.rds"))
  saveRDS(list(n = 160L, events = 40L), file.path(root, "estimates", "dead-hz", "hz-methods.rds"))
  rec <- function(label, kind, rel) {
    list(label = label, kind = kind, file = rel, sha256 = digest::digest(file.path(root, rel), algo = "sha256", file = TRUE))
  }
  if (!is.null(methods) && is.null(methods$sha256)) {
    methods$sha256 <- digest::digest(methods$text, algo = "sha256", serialize = FALSE)
  }
  sidecar <- Filter(Negate(is.null), list(
    job = job, rendered = rendered, r = list(version = "4.6.1"),
    packages = list(list(package = "base", version = "4.6.1", source = "base"),
                    list(package = "TemporalHazard", version = "1.2.8", source = "standard")),
    data = list(list(path = "datasets/built.csv", role = "study", dataset = "built")),
    run = run, source_sha256 = digest::digest(qmd, algo = "sha256", file = TRUE),
    exhibits = list(rec("fig-fit", "figure", "graphs/dead-hz/hz-fit.png"),
                    rec("tbl-estimates", "table", "documents/dead-hz/tbl-estimates.rds"),
                    rec("methods", "value", "estimates/dead-hz/hz-methods.rds")),
    methods = methods
  ))
  jsonlite::write_json(sidecar, hvtiRutilities::provenance_path(html), auto_unbox = TRUE, null = "null")
  invisible(qmd)
}
