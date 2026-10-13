* `bl`, `br` and `bc` name the bag they read with `BOOT_PREFIX`, as `bh` does,
  in place of `BOOT_FILE`: each reads `<BOOT_PREFIX>.rds`, defaulting to its own
  prefix, and its runner in `inst/runners/` now writes `bl.rds`, `br.rds` or
  `bc.rds` rather than `bagging.rds`. One setting across the family lets a runner
  write where every report looks, and the three no longer overwrite one another
  when they share a subject and type. A job scaffolded earlier keeps its own
  `BOOT_FILE`; a runner still writing `bagging.rds` is read by setting
  `BOOT_PREFIX <- "bagging"` (#189).
