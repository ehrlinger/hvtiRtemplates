# A render runs in a fresh R process: quarto_render() starts one, and so does the
# hvti command behind submit_job() and run_job(). That process loads the
# INSTALLED hvtiRtemplates, not the source devtools::load_all() loaded, so a
# stale install makes a render test answer for old code. It fails with the old
# code's output, or passes over code that is not the code under test.
# setup.R wraps both render paths in skip_if_stale_install().
#
# The version alone cannot tell: it stays the same across many merged pull
# requests. So the fingerprint is the content a render reads: every function in
# the namespace, deparsed without its source reference, and every installed file
# under the inst/ folders the jobs use.
.install_fingerprint_code <- '
ns <- asNamespace("hvtiRtemplates")
nm <- sort(ls(ns, all.names = TRUE))
fn <- nm[vapply(nm, function(n) is.function(get(n, envir = ns)), logical(1))]
txt <- vapply(fn, function(n) paste(deparse(get(n, envir = ns)), collapse = "\n"), character(1))
files <- character(0)
for (d in c("bin", "extdata", "hooks", "runners", "templates")) {
  dir <- system.file(d, package = "hvtiRtemplates")
  if (!nzchar(dir)) next
  f <- sort(list.files(dir, recursive = TRUE))
  files <- c(files, paste0(d, "/", f, ":", unname(tools::md5sum(file.path(dir, f)))))
}
tmp <- tempfile()
writeLines(c(paste0(fn, ":", txt), files), tmp)
# The hash is what is compared; the version and library only name the copy in the skip.
cat("FINGERPRINT", unname(tools::md5sum(tmp)), as.character(utils::packageVersion("hvtiRtemplates")),
    dirname(system.file(package = "hvtiRtemplates")), "\n")
'

.install_state <- new.env(parent = emptyenv())

# The fingerprint of the code under test, taken by setup.R before it installs its
# wrappers: a mocked binding changes the namespace, and would read as stale.
.record_fingerprint_here <- function() {
  out <- utils::capture.output(eval(parse(text = .install_fingerprint_code), envir = new.env()))
  assign("here", strsplit(trimws(out), " ")[[1L]], envir = .install_state)
}

# NULL when the installed copy matches the code under test, else the reason it does not.
# Asked once per run, on the first render.
.stale_install_reason <- function() {
  if (exists("reason", envir = .install_state, inherits = FALSE)) return(.install_state$reason)
  here <- .install_state$here
  if (is.null(here)) stop("setup.R did not record the fingerprint of the code under test", call. = FALSE)
  # Started as the render's R process is: this process's environment, the usual startup files.
  out <- tryCatch(suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
                                           c("-e", shQuote(.install_fingerprint_code)),
                                           stdout = TRUE, stderr = FALSE)),
                  error = function(e) character(0))
  there <- strsplit(trimws(utils::tail(grep("^FINGERPRINT ", out, value = TRUE), 1L)), " ")
  there <- if (length(there)) there[[1L]] else character(0)
  reason <- if (length(there) < 2L) {
    paste0("hvtiRtemplates is not installed where a render's R process looks, and a render loads it. ",
           "Install this source (devtools::install() or R CMD INSTALL .), then run the tests again.")
  } else if (!identical(there[[2L]], here[[2L]])) {
    paste0("the installed hvtiRtemplates ", there[[3L]], " in ", paste(there[-(1:3)], collapse = " "),
           " is not the code under test, and a render loads it. ",
           "Install this source (devtools::install() or R CMD INSTALL .), then run the tests again.")
  }
  assign("reason", reason, envir = .install_state)
  reason
}

skip_if_stale_install <- function() {
  reason <- .stale_install_reason()
  if (!is.null(reason)) testthat::skip(reason)
  invisible(TRUE)
}
