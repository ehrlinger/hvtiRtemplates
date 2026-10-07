# At most two cores, as CRAN asks, wherever a test fits a model that would
# otherwise take every core: randomForestSRC uses all OpenMP threads unless
# rf.cores is set, and CI's two-core runners hide it. Restored when the suite
# ends.
withr::local_options(rf.cores = 2L, mc.cores = 2L, .local_envir = teardown_env())
withr::local_envvar(OMP_THREAD_LIMIT = "2", .local_envir = teardown_env())
