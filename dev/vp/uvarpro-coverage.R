# Coverage of uvarpro() release rules, as vp-dependence calls it.
# Does uvarpro() at vp-dependence's settings build release rules for every variable?
# A variable with no rules is never examined, and "not examined" must never be read as "no effect".
# Run from the repo root: Rscript dev/vp/uvarpro-coverage.R   (local; simulated data, no study data)
#
# Settings are the template's own, read from it: ntree = NTREE and seed = -abs(SEED), with the noise
# columns vp_add_noise() builds from NOISE_N (20). The noise function is parsed out of the template so this
# script cannot drift from it.
#
# It sweeps uvarpro()'s rule limits: max.tree in c(200, NTREE) and max.rules.tree in c(20, 50, 100, 150),
# varPro's defaults being 200 and 20. For each pair and configuration it prints the real variables and the
# noise columns with no release rule, and the seconds the fit took. Then, because one run is one draw, it
# refits configurations 4 and 5 over seeds at 500 trees and at the template's MAX_TREE.
#
# History. Measured first on 2026-11-14 with the noise drawn half categorical whenever any candidate was:
# configuration 5 left 15-19 of 31 real variables without a rule at 500 trees (7-10 at 2,000), because its
# one factor made 10 of the 20 noise columns binary copies, and those took about 2,100 of 4,800 rules.
# vp_add_noise() now draws the kinds in proportion to the candidates, at least one of each kind present
# (one categorical column there, four on the fixture). A binary column still draws several times its share
# of rules: the one in configuration 5 took 480-720.
#
# Each fit seeds R's generator first, as cache_fit(seed = SEED) does in the template, because uvarpro()
# draws from it as well as from its own seed: a first version of this sweep did not, and its counts of
# which seeds missed did not reproduce through the template.
#
# Measured 2026-11-14, proportional noise, NTREE = MAX_TREE = 1,000, varPro 3.3.0, randomForestSRC 3.10.0,
# one thread. max.rules.tree changed nothing at all from 20 up: every pair gave the same rules.
#
#   config  max.tree  rules   real variables with no rule  noise with none  seconds
#   1       200       1882    none                         0                0.2
#   1       1000      9555    none                         0                1.1
#   2       200       1924    x23                          0                1.2
#   2       1000      9655    none                         0                4.1
#   3       200       1742    none                         0                4.1
#   3       1000      8634    none                         0                8.0
#   4       200       2056    none                         2                0.7
#   4       1000      9995    none                         0                3.0
#   5       200       1982    x04, x21                     2                2.3
#   5       1000     10004    none                         0                7.1
#
#   across seeds   max.tree (of 1,000)  seeds  seeds leaving a real variable without a rule  most left by one
#   config 4       500                  30     0                                             0
#   config 4       750                  30     0                                             0
#   config 4       1000                 30     0                                             0
#   config 5       500                  20     9                                             2 of 31
#   config 5       750                  20     2                                             1 of 31
#   config 5       1000                 20     0                                             0
#
# A scratch run of configuration 5 at 1,000 trees over SEED = 21 to 40 also left none. So the template's
# MAX_TREE = NTREE = 1,000 is the smallest tried that gave every real variable a rule at every seed, and
# MAX_UNTESTED = 0.1 is on as the guard for data unlike these. The rule count follows max.tree, about
# 10 rules a tree.
#
# The forest is not the cost. get.beta.entropy() fits a lasso for every rule, so it scales with the rule
# count: on configuration 4 it took 20 s at 200 trees, 56 s at 500, 83 s at 750 and 110 s at 1,000, against
# 0.7 s to 3.6 s for uvarpro() (a separate scratch timing, one fit each). A render pays that once for the full fit
# and once for each of REPEATS refits.
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
    set.seed(seed)  # as cache_fit(seed = SEED) does before the call: uvarpro() also draws from R's generator
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

# Across seeds: one run is one draw, so the configurations the template runs with noise (4 and 5) are refitted
# at SEED = 1 to 30 (4) and 1 to 20 (5), seeding the noise and the forest as the template does, at 500 trees
# and at the template's MAX_TREE. Every row is one fit; the summary counts the seeds that left a real variable
# without a rule and the most any one seed left.
max_tree_tpl <- val("MAX_TREE")
sweep <- list()
for (k in c(4L, 5L)) {
  d0 <- cfgs[[k]]$d
  for (mt in unique(c(500, 750, max_tree_tpl))) {
    for (s in if (k == 4L) 1:30 else 1:20) {
      d <- env$vp_add_noise(d0, names(d0), noise_n_tpl, s)
      set.seed(s)
      fit <- uvarpro(d, ntree = max(mt, ntree_tpl), max.tree = mt, max.rules.tree = 20, seed = -abs(s))
      map <- attr(fit$x, "xvar.map")
      ruled <- unique(unname(map[names(map)[fit$results$variable]]))
      real <- names(d)[!grepl("^noise", names(d))]
      sweep[[length(sweep) + 1L]] <- data.frame(config = k, max.tree = mt, seed = s, missed = length(setdiff(real, ruled)),
                                                of = length(real))
    }
  }
}
sweep <- do.call(rbind, sweep)
cat("\nAcross seeds (real variables with no rule):\n")
print(do.call(rbind, lapply(split(sweep, sweep[c("config", "max.tree")], drop = TRUE), function(x) {
  data.frame(config = x$config[1L], max.tree = x$max.tree[1L], seeds = nrow(x), seeds_missing = sum(x$missed > 0L),
             most_missed = max(x$missed), of = x$of[1L])
})), row.names = FALSE)
