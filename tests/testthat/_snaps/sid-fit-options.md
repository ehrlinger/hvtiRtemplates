# with SID_ARGS = list(), the cached call is the one sid-fit made before SID_ARGS

    Code
      cat(text)
    Output
      {
          o <- sidClustering(d_complete[[m]], method = "sid", ntree = NTREE, reduce = SID_REDUCE, seed = -abs(s))
          if (is.null(o$dist)) {
              stop("sidClustering() failed on imputation ", m, " (it returned no distance). Look above for the message ", "randomForestSRC gave, and check the clustering variables for a constant or near-empty factor.", call. = FALSE)
          }
          o[c("dist", "outcome.names")]
      }

