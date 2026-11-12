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
