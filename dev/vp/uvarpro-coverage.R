# Coverage of uvarpro() release rules, as vp-dependence calls it.
# Does uvarpro() at vp-dependence's settings build release rules for every variable?
# A variable with no rules is never examined, and "not examined" must never be read as "no effect".
# Run from the repo root: Rscript dev/vp/uvarpro-coverage.R   (local; simulated data, no study data)
#
# Settings are the template's own, read from it: ntree = NTREE (500) and seed = -abs(SEED), with the
# noise columns vp_add_noise() builds from NOISE_N (20). The noise function is parsed out of the template
# so this script cannot drift from it.
suppressPackageStartupMessages(library(varPro))
cat("varPro", as.character(utils::packageVersion("varPro")),
    "| randomForestSRC", as.character(utils::packageVersion("randomForestSRC")), "\n")

tpl <- "inst/templates/30_analyses/vp-dependence.qmd"
src <- readLines(tpl, warn = FALSE)
grab <- function(label) {
  i <- grep(sprintf("^#\\| label: %s$", label), src)
  stopifnot(length(i) == 1L)
  j <- which(src == "```")
  j <- j[j > i][1L]
  src[(i + 1L):(j - 1L)]
}
val <- function(name) as.numeric(sub(sprintf("^%s <- ([0-9.]+).*", name), "\\1", grep(sprintf("^%s <- ", name), src, value = TRUE)))
ntree_tpl <- val("NTREE")
noise_n_tpl <- val("NOISE_N")
cat(sprintf("template defaults: NTREE = %d, NOISE_N = %d\n", ntree_tpl, noise_n_tpl))
env <- new.env(parent = globalenv())
eval(parse(text = grab("noise")[seq_len(grep("^if \\(NOISE_N < 1", grab("noise"))[1L] - 1L)]), envir = env)

sim <- function(n, p, seed) {
  set.seed(seed)
  d <- as.data.frame(matrix(stats::rnorm(n * p), n, p, dimnames = list(NULL, sprintf("x%02d", seq_len(p)))))
  d$x02 <- d$x01 + stats::rnorm(n, 0, 0.3)
  d$f1 <- factor(sample(c("a", "b"), n, replace = TRUE))
  d
}
# The template-test fixture shape: five variables, c = a + noise, a two-level factor fs.
sim_fixture <- function(n, seed) {
  set.seed(seed)
  d <- data.frame(a = stats::rnorm(n), b = stats::rnorm(n), x2 = stats::rnorm(n),
                  fs = factor(sample(c("a", "b"), n, replace = TRUE)))
  d$c <- d$a + stats::rnorm(n, 0, 0.3)
  d
}

none_of <- function(all, have) if (all(all %in% have)) "(none)" else paste(setdiff(all, have), collapse = ", ")

cfgs <- list(
  list(label = "n = 200, p = 5 (+f1)", d = sim(200, 5, 2026), noise = FALSE),
  list(label = "n = 400, p = 30 (+f1)", d = sim(400, 30, 2026), noise = FALSE),
  list(label = "n = 1900, p = 30 (+f1)", d = sim(1900, 30, 2026), noise = FALSE),
  list(label = "fixture n = 200, a b x2 fs c, + noise", d = sim_fixture(200, 20261022L), noise = TRUE)
)
seed <- 2026
any_missing <- FALSE
for (cfg in cfgs) {
  d <- cfg$d
  src_vars <- names(d)
  if (cfg$noise) d <- env$vp_add_noise(d, src_vars, noise_n_tpl, seed)
  fit <- uvarpro(d, ntree = ntree_tpl, seed = -abs(seed))
  # fit$results$variable indexes the encoded columns (a factor is several 0/1 columns); xvar.map maps
  # each encoded column to its source variable, as the template's vpd_parent() reads it.
  map <- attr(fit$x, "xvar.map")
  stopifnot(identical(unname(names(map)), colnames(fit$x)))
  res <- fit$results
  enc <- names(map)[res$variable]
  src_of <- unname(map[enc])
  ruled <- unique(src_of)                      # at least one rule released the variable
  tested <- unique(src_of[!is.na(res$imp)])    # ... and at least one rule had oob patients to test
  all_vars <- names(d)
  cat(sprintf("\n%s: %d rules, %d variables\n", cfg$label, nrow(res), length(all_vars)))
  cat(sprintf("  with release rules: %d of %d; none for: %s\n", sum(all_vars %in% ruled), length(all_vars),
              none_of(all_vars, ruled)))
  cat(sprintf("  with a tested rule (imp not NA): %d of %d; untested: %s\n", sum(all_vars %in% tested), length(all_vars),
              none_of(all_vars, tested)))
  rc <- table(factor(src_of, levels = all_vars))
  cat("  rules per variable: min", min(rc), "median", stats::median(rc), "max", max(rc), "\n")
  if (length(setdiff(all_vars, ruled))) any_missing <- TRUE
}
cat("\nEvery variable has release rules in every configuration:", !any_missing, "\n")
