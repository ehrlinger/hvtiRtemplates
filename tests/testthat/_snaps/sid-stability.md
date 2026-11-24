# the default refit code is unchanged, so refits cached before PAM_ON existed still load

    Code
      cat(deparse(env$.refit_code), sep = "\n")
    Output
      {
          dists <- lapply(seq_along(refit_x), function(m) {
              s <- refit_seed + m - 1L
              set.seed(s)
              o <- sidClustering(refit_x[[m]], method = "sid", ntree = refit_ntree, 
                  reduce = refit_reduce, seed = -abs(s))
              if (is.null(o$dist)) 
                  stop("sidClustering() failed on imputation ", m, 
                      " (it returned no distance).", call. = FALSE)
              o$dist
          })
          d <- stats::as.dist(Reduce(`+`, dists)/length(dists))
          vapply(refit_k, function(k) cluster::pam(d, k, cluster.only = TRUE), 
              integer(nrow(refit_x[[1L]])))
      }

