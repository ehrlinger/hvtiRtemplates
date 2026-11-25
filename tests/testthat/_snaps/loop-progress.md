# the looped fits key on the same code as before, so fits cached by earlier copies still load (#631)

    Code
      cat(cached_code("vp", "fit", "tbl-stability", "vp-repeat-"), sep = "\n")
    Output
      varpro(model, dr, ntree = NTREE, nvar = NVAR, split.weight = SPLIT_WEIGHT, sparse = SPARSE, mtry = .mtry, nodesize.external = .nodesize_external, max.tree = .max_tree, max.rules.tree = MAX_RULES_TREE, verbose = FALSE, cores = 1L, seed = -abs(SEED + r))
    Code
      cat(cached_code("vp", "dependence", "tbl-stability",
        "\"vp-dependence-repeat-%02d\""), sep = "\n")
    Output
      uvarpro(dr, ntree = NTREE, max.tree = min(MAX_TREE, NTREE), max.rules.tree = MAX_RULES_TREE, seed = -abs(SEED + r))
    Code
      cat(cached_code("vp", "dependence", "tbl-stability",
        "\"vp-dependence-repeat-%02d-beta\""), sep = "\n")
    Output
      get.beta.entropy(fr, pre.filter = FALSE, papply = lapply)
    Code
      cat(cached_code("sid", "fit", "impute", "\"sid-fit-impute-\""), sep = "\n")
    Output
      mice::mice(.to_impute, m = 1, maxit = MICE_MAXIT, method = "pmm", printFlag = FALSE)
      randomForestSRC::impute(data = .to_impute, ntree = 250, verbose = FALSE)
    Code
      cat(cached_code("sid", "fit", "fit", "\"sid-fit-\""), sep = "\n")
    Output
      {
          o <- sidClustering(d_complete[[m]], method = "sid", ntree = NTREE, reduce = SID_REDUCE, seed = -abs(s))
          if (is.null(o$dist)) {
              stop("sidClustering() failed on imputation ", m, " (it returned no distance). Look above for the message ", "randomForestSRC gave, and check the clustering variables for a constant or near-empty factor.", call. = FALSE)
          }
          o[c("dist", "outcome.names")]
      }

