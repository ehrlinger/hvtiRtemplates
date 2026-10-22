# A three-way merge of lines, the engine upgrade_job() carries a study's edits
# with. It is written in R because git is not used at run time (John,
# 2026-10-22). See dev/specs/2026-10-22-upgrade-job-merge-design.md, decision 6.

# The lines of `a` and `b` that a longest common subsequence pairs, as an
# integer matrix with columns `a` and `b`, both increasing. The common prefix
# and suffix are paired first, so the quadratic search below sees only the few
# lines a job and its template differ around.
.line_diff <- function(a, b) {
  na <- length(a)
  nb <- length(b)
  pre <- 0L
  while (pre < na && pre < nb && a[[pre + 1L]] == b[[pre + 1L]]) pre <- pre + 1L
  suf <- 0L
  while (suf < na - pre && suf < nb - pre && a[[na - suf]] == b[[nb - suf]]) suf <- suf + 1L
  mid_a <- pre + seq_len(na - pre - suf)
  mid_b <- pre + seq_len(nb - pre - suf)
  mid <- .lcs(a[mid_a], b[mid_b])
  cbind(a = c(seq_len(pre), mid_a[mid[, 1L]], na - suf + seq_len(suf)),
        b = c(seq_len(pre), mid_b[mid[, 2L]], nb - suf + seq_len(suf)))
}

# Index pairs of a longest common subsequence, by dynamic programming. The
# lines are compared as integer codes, which is all the table needs.
.lcs <- function(a, b) {
  n <- length(a)
  m <- length(b)
  if (!n || !m) return(matrix(integer(), ncol = 2L))
  codes <- unique(c(a, b))
  a <- match(a, codes)
  b <- match(b, codes)
  len <- matrix(0L, n + 1L, m + 1L)
  for (i in seq_len(n)) {
    for (j in seq_len(m)) {
      len[i + 1L, j + 1L] <- if (a[[i]] == b[[j]]) len[i, j] + 1L else max(len[i, j + 1L], len[i + 1L, j])
    }
  }
  pairs <- matrix(0L, len[n + 1L, m + 1L], 2L)
  k <- nrow(pairs)
  i <- n
  j <- m
  while (k > 0L) {
    if (a[[i]] == b[[j]]) {
      pairs[k, ] <- c(i, j)
      k <- k - 1L
      i <- i - 1L
      j <- j - 1L
    } else if (len[i, j + 1L] >= len[i + 1L, j]) {
      i <- i - 1L
    } else {
      j <- j - 1L
    }
  }
  pairs
}

# Merge `job` and `template`, both descended from `base`, by diff3's rule. A
# base line both sides kept separates the regions between them. In a region
# the side that did not change gives way to the side that did; where both made
# the same change it is taken once; where they made different changes the
# region is a conflict, written with diff3-style markers. Two changes with no
# kept line between them are one region, so adjacent edits conflict, as they
# do in diff3: the merge errs toward stopping.
#
# Returns list(lines, conflicts, carried): `conflicts` gives each conflict's
# first and last line in `lines`, and `carried` each region where the job's
# own change was kept against an unchanged template (end < start for a line
# the job deleted).
.merge3 <- function(job, base, template, base_label, template_label) {
  at_job <- at_template <- integer(length(base))
  d <- .line_diff(base, job)
  at_job[d[, "a"]] <- d[, "b"]
  d <- .line_diff(base, template)
  at_template[d[, "a"]] <- d[, "b"]
  kept <- which(at_job > 0L & at_template > 0L)
  o <- c(0L, kept, length(base) + 1L)
  a <- c(0L, at_job[kept], length(job) + 1L)
  t <- c(0L, at_template[kept], length(template) + 1L)
  between <- function(lines, from, to) lines[seq_len(to - from - 1L) + from]
  none <- data.frame(start = integer(), end = integer())
  out <- character()
  conflicts <- carried <- list(none)
  for (k in seq_len(length(o) - 1L)) {
    r_base <- between(base, o[[k]], o[[k + 1L]])
    r_job <- between(job, a[[k]], a[[k + 1L]])
    r_template <- between(template, t[[k]], t[[k + 1L]])
    start <- length(out) + 1L
    if (identical(r_job, r_base)) {
      out <- c(out, r_template)
    } else if (identical(r_template, r_base) || identical(r_job, r_template)) {
      if (identical(r_template, r_base)) carried[[length(carried) + 1L]] <- data.frame(start = start, end = start + length(r_job) - 1L)
      out <- c(out, r_job)
    } else {
      out <- c(out, "<<<<<<< job", r_job, paste("|||||||", base_label), r_base, "=======", r_template,
               paste(">>>>>>>", template_label))
      conflicts[[length(conflicts) + 1L]] <- data.frame(start = start, end = length(out))
    }
    if (k < length(o) - 1L) out <- c(out, base[[o[[k + 1L]]]])
  }
  list(lines = out, conflicts = do.call(rbind, conflicts), carried = do.call(rbind, carried))
}
