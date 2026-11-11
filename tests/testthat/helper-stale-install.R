# A render runs in a fresh R process: quarto_render() starts one, and so does the
# process submit_job() and run_job() launch. That process loads the INSTALLED
# hvtiRtemplates, not the source devtools::load_all() loaded, so a stale install
# makes a render test answer for old code. It fails with the old code's output,
# or passes over code that is not the code under test.
# setup.R wraps both render paths in skip_if_stale_install().
#
# The version alone cannot tell: it stays the same across many merged pull
# requests. So the fingerprint is the content a render reads: every binding in
# the namespace, deparsed without its source reference, and every installed file
# under the inst/ folders the jobs use. Two kinds of binding are left out:
# environments, which hold run state (.run_state and the like) rather than code,
# and the .__*__ bindings R and devtools::load_all() add to a namespace. The code
# carries no backslash, which Rscript -e rewrites, and sorts by radix: testthat sets the
# C collation, which a child inherits, so a locale-aware sort orders the two copies differently.
.install_fingerprint_code <- '
if (!requireNamespace("hvtiRtemplates", quietly = TRUE)) {
  cat("NOT-INSTALLED", "\n")
  quit(save = "no")
}
ns <- asNamespace("hvtiRtemplates")
nm <- sort(ls(ns, all.names = TRUE), method = "radix")
nm <- nm[!startsWith(nm, ".__") & !vapply(nm, function(n) is.environment(get(n, envir = ns)), logical(1))]
txt <- vapply(nm, function(n) paste(deparse(get(n, envir = ns)), collapse = "\n"), character(1))
files <- character(0)
for (d in c("bin", "extdata", "hooks", "runners", "templates")) {
  dir <- system.file(d, package = "hvtiRtemplates")
  if (!nzchar(dir)) next
  f <- sort(list.files(dir, recursive = TRUE), method = "radix")
  files <- c(files, paste0(d, "/", f, ":", unname(tools::md5sum(file.path(dir, f)))))
}
tmp <- tempfile()
writeLines(c(paste0(nm, ":", txt), files), tmp)
# The hash is what is compared; the version and library only name the copy in the skip.
cat("FINGERPRINT", unname(tools::md5sum(tmp)), as.character(utils::packageVersion("hvtiRtemplates")),
    dirname(system.file(package = "hvtiRtemplates")), "\n")
'

.install_state <- new.env(parent = emptyenv())

# The fingerprint of the code under test, taken by setup.R before it installs its
# wrappers: a mocked binding changes the namespace, and would read as stale.
.fingerprint_here <- function() {
  out <- utils::capture.output(eval(parse(text = .install_fingerprint_code), envir = new.env()))
  strsplit(trimws(out), " ")[[1L]]
}
.record_fingerprint_here <- function() assign("here", .fingerprint_here(), envir = .install_state)

# The fingerprint of the copy a render's R process loads: `rscript` started in `dir`, with this
# process's environment (RENV_PROJECT among it) and the usual startup files, so a study's
# .Rprofile and renv activation choose the library as they do for the render. character(0)
# when that process finds no hvtiRtemplates. Any other outcome stops: a check that could not
# run must not read as an answer, either way.
.fingerprint_there <- function(dir, rscript) {
  args <- c("-e", shQuote(.install_fingerprint_code))
  out <- withr::with_dir(dir, suppressWarnings(system2(rscript, args, stdout = TRUE, stderr = TRUE)))
  there <- grep("^FINGERPRINT ", out, value = TRUE)
  if (length(there)) {
    there <- strsplit(trimws(utils::tail(there, 1L)), " ")[[1L]]
    if (length(there) >= 4L) return(there)
  }
  if (any(grepl("^NOT-INSTALLED", out))) return(character(0))
  stop("could not read the installed hvtiRtemplates with ", rscript, " in ", dir, ":\n",
       paste(utils::tail(out, 10L), collapse = "\n"), call. = FALSE)
}

# NULL when the copy that R process loads matches the code under test, else the reason it does not.
# Asked once per R, directory and RENV_PROJECT: two studies can resolve different installs.
.stale_install_reason <- function(dir, rscript) {
  here <- .install_state$here
  if (is.null(here)) stop("setup.R did not record the fingerprint of the code under test", call. = FALSE)
  if (!nzchar(rscript)) stop("no Rscript to check the installed hvtiRtemplates with", call. = FALSE)
  key <- paste(normalizePath(rscript, mustWork = FALSE), normalizePath(dir, mustWork = FALSE),
               Sys.getenv("RENV_PROJECT"), sep = "\r")
  cache <- .install_state$reasons
  if (is.null(cache)) cache <- list()
  if (key %in% names(cache)) return(cache[[key]])
  there <- .fingerprint_there(dir, rscript)
  fix <- "Install this source (devtools::install() or R CMD INSTALL .), then run the tests again."
  reason <- if (!length(there)) {
    paste0("hvtiRtemplates is not installed where a render's R process looks, and a render loads it. ", fix)
  } else if (!identical(there[[2L]], here[[2L]])) {
    paste0("the installed hvtiRtemplates ", there[[3L]], " in ", paste(there[-(1:3)], collapse = " "),
           " is not the code under test, and a render loads it. ", fix)
  }
  cache[key] <- list(reason)
  assign("reasons", cache, envir = .install_state)
  reason
}

# `dir` and `rscript` are where the render's R process starts and which R it is.
skip_if_stale_install <- function(dir = getwd(), rscript = file.path(R.home("bin"), "Rscript")) {
  reason <- .stale_install_reason(dir, rscript)
  if (!is.null(reason)) testthat::skip(reason)
  invisible(TRUE)
}

# The R Quarto's knitr engine starts, found as Quarto's rBinaryPath() finds it: QUARTO_R (an R
# binary, or the directory holding one), else R_HOME/bin, else PATH. Under R CMD check the
# Rscript on PATH is a stub that refuses to run, and Quarto never reaches it, for R_HOME is set.
.quarto_rscript <- function() {
  # Windows names the binary Rscript.exe, and R_HOME/bin holds a launcher by that name.
  rscript <- if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
  q <- Sys.getenv("QUARTO_R")
  if (nzchar(q) && file.exists(q)) return(file.path(if (dir.exists(q)) q else dirname(q), rscript))
  h <- Sys.getenv("R_HOME")
  if (nzchar(h) && file.exists(file.path(h, "bin", rscript))) return(file.path(h, "bin", rscript))
  unname(Sys.which("Rscript"))
}

# For test-stale-install.R. Runs `code` as if the installed copy were stale, whatever is installed: the recorded fingerprint
# of the code under test is replaced with one no install has, and the per-context answers cleared.
with_fake_stale <- function(code) {
  here <- .install_state$here
  reasons <- .install_state$reasons
  withr::defer({
    assign("here", here, envir = .install_state)
    assign("reasons", reasons, envir = .install_state)
  })
  assign("here", replace(here, 2L, "not-a-real-fingerprint"), envir = .install_state)
  assign("reasons", NULL, envir = .install_state)
  force(code)
}
