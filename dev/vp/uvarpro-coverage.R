# Coverage of uvarpro() release rules, as vp-dependence calls it.
# Does uvarpro() at vp-dependence's settings build release rules for every variable?
# A variable with no rules is never examined, and "not examined" must never be read as "no effect".
# Run from the repo root: Rscript dev/vp/uvarpro-coverage.R   (local; simulated data, no study data)
#
# Settings are the template's own, read from it: ntree = NTREE (500) and seed = -abs(SEED), with the
# noise columns vp_add_noise() builds from NOISE_N (20). The noise function is parsed out of the template
# so this script cannot drift from it.
#
# It sweeps uvarpro()'s rule limits: max.tree in c(200, NTREE) and max.rules.tree in c(20, 50, 100, 150),
# varPro's defaults being 200 and 20. For each pair and configuration it prints the real variables and the
# noise columns with no release rule, and the seconds the fit took. The template's defaults are the
# smallest pair that leaves no REAL variable without rules in any configuration.
#
# Measured 2026-11-14, varPro 3.3.0, randomForestSRC 3.10.0, one thread (configurations 1-5 are in `cfgs`):
#
#   config  max.tree  max.rules.tree  rules   real variables with no rule   noise with none  seconds
#   1       200       20 / 50 / 100 / 150  ~1940  none                          0                0.2
#   1       500       20 / 50 / 100 / 150  ~4860  none                          0                0.5
#   2       200       20                   1915   x07, x25                      0                0.9
#   2       200       50 / 100 / 150       ~1960  none                          0                1.0
#   2       500       20 / 50 / 100 / 150  ~4890  none                          0                2.0
#   3       200       20                   1708   none                          0                2.6
#   3       200       50 / 100 / 150       ~1710  x14; x05, x28; x08, x10, x12, x28  0           2.6
#   3       500       20 / 50 / 100 / 150  ~4320  none                          0                4.1
#   4       200       20                   1983   b, x2                         6                0.6
#   4       200       50 / 100 / 150       ~1970  b; x2; b                      4-5              0.6
#   4       500       20 / 50 / 100 / 150  ~4930  none                          2-5              1.5
#   5       200       20 / 50 / 100 / 150  ~1920  23-26 of 31                   7-9              1.6
#   5       500       20 / 50 / 100 / 150  ~4820  15-19 of 31                   4-6              3.2
#
# No pair covers every real variable in every configuration. Configurations 1-3 carry no noise
# columns, which the template always adds; there every pair at 500 trees (all of NTREE) covers, and
# the defaults MAX_TREE = 500, MAX_RULES_TREE = 20 were chosen from them before configuration 5 was
# added. Configuration 5 is configuration 2 as the template runs it, with 20 noise columns, and at
# 500 trees about half its real variables still had no rule. Its one factor is the only categorical
# source, so 10 noise columns are binary copies of it. In a separate check over SEED = 1 to 3 those
# copies took 2,089 to 2,132 of about 4,800 rules, and with NTREE = MAX_TREE = 1,000 the configuration
# left 12 to 17 of 31 real variables without a rule, with 2,000 trees 7 to 10.
#
# The rule count follows max.tree, about 10 rules a tree, and barely moves with max.rules.tree from 20
# up, which at these sizes is not the binding limit. Which variable misses moves with R's random state
# (between two runs of this script configurations 2 and 3 changed which, and whether, a variable
# missed), so one run is one draw: on the fixture shape (configuration 4) with the template's own
# seeding, 200 trees left a real variable without a rule at 23 of SEED = 1 to 30, and 500 trees at 7.
#
# The forest is not the cost. get.beta.entropy() fits a lasso for every rule, so it scales with the rule
# count: on configuration 4 it took 20 s at 200 trees and 51 s at 500, against 0.7 s and 1.5 s for
# uvarpro(). A render pays that once for the full fit and once for each of REPEATS refits.
suppressPackageStartupMessages(library(varPro))
# One thread, as the template runs, so the elapsed seconds are the ones a render pays.
options(rf.cores = 1L, mc.cores = 1L)
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

# Names up to four, then a count, so a wide configuration keeps the table on one line.
short <- function(missing, of) {
  if (!length(missing)) return("(none)")
  if (length(missing) <= 4L) paste(missing, collapse = ", ") else sprintf("%d of %d", length(missing), of)
}

cfgs <- list(
  list(label = "n = 200, p = 5 (+f1)", d = sim(200, 5, 2026), noise = FALSE),
  list(label = "n = 400, p = 30 (+f1)", d = sim(400, 30, 2026), noise = FALSE),
  list(label = "n = 1900, p = 30 (+f1)", d = sim(1900, 30, 2026), noise = FALSE),
  list(label = "fixture n = 200, a b x2 fs c, + noise", d = sim_fixture(200, 20261022L), noise = TRUE),
  # Configuration 2 as the template runs it: with its noise columns. Added after the defaults were chosen.
  list(label = "n = 400, p = 30 (+f1), + noise", d = sim(400, 30, 2026), noise = TRUE)
)
seed <- 2026
grid <- expand.grid(max.rules.tree = c(20, 50, 100, 150), max.tree = c(200, ntree_tpl))
grid <- grid[order(grid$max.tree, grid$max.rules.tree), c("max.tree", "max.rules.tree")]
rows <- list()
for (k in seq_along(cfgs)) {
  cfg <- cfgs[[k]]
  d <- cfg$d
  src_vars <- names(d)
  if (cfg$noise) d <- env$vp_add_noise(d, src_vars, noise_n_tpl, seed)
  all_vars <- names(d)
  noise <- grepl("^noise", all_vars)
  for (g in seq_len(nrow(grid))) {
    mt <- grid$max.tree[g]
    mrt <- grid$max.rules.tree[g]
    secs <- system.time(
      fit <- uvarpro(d, ntree = ntree_tpl, max.tree = min(mt, ntree_tpl), max.rules.tree = mrt, seed = -abs(seed))
    )[["elapsed"]]
    # fit$results$variable indexes the encoded columns (a factor is several 0/1 columns); xvar.map maps
    # each encoded column to its source variable, as the template's vpd_parent() reads it.
    map <- attr(fit$x, "xvar.map")
    stopifnot(identical(unname(names(map)), colnames(fit$x)))
    res <- fit$results
    ruled <- unique(unname(map[names(map)[res$variable]]))  # at least one rule released the variable
    rows[[length(rows) + 1L]] <- data.frame(
      config = k, max.tree = mt, max.rules.tree = mrt, rules = nrow(res),
      real_none = short(setdiff(all_vars[!noise], ruled), sum(!noise)), noise_none = sum(!all_vars[noise] %in% ruled),
      seconds = round(secs, 1)
    )
  }
}
tab <- do.call(rbind, rows)
cat("\nConfigurations:\n")
for (k in seq_along(cfgs)) cat(sprintf("  %d: %s\n", k, cfgs[[k]]$label))
cat("\nreal_none: real variables with no release rule; noise_none: noise columns with none.\n\n")
print(tab, row.names = FALSE)
covers <- aggregate(real_none ~ max.tree + max.rules.tree, tab, function(x) all(x == "(none)"))
covers <- covers[order(covers$max.tree, covers$max.rules.tree), ]
cat("\nEvery real variable has rules in every configuration:\n")
print(covers, row.names = FALSE)
ok <- covers[covers$real_none, ]
best <- if (nrow(ok)) sprintf("max.tree = %d, max.rules.tree = %d", ok$max.tree[1L], ok$max.rules.tree[1L]) else "none"
cat("\nSmallest covering pair:", best, "\n")
