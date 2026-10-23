# SID clustering family, in flight: sid-fit grows the unsupervised SID forest
# and saves its distance, and sid-clusters cuts that distance into lettered
# solutions. Both share the echo-phenotype set, and family-vt.R reads it: vt-fit
# for SID eligibility, vt-explain for its strata. This file sorts before
# family-vt.R, so the set exists when the twins are built.
#
# Clustering on the demo covariates alone would find nothing: they carry no
# groups. columns() adds five preoperative echocardiographic measurements drawn
# from three latent phenotypes, a compensated ventricle, a dilated failing one
# and a small stiff one with a large atrium, so the clusters have something to
# recover. The phenotype itself is never saved. About 5% of each measurement is
# missing, so the imputation step has work to do.

sid_columns <- function(d) {
  withr::with_seed(20261023, {
    n <- nrow(d)
    phenotype <- sample.int(3L, n, TRUE, c(0.5, 0.3, 0.2))
    at <- function(means, sd) stats::rnorm(n, means[phenotype], sd)
    lvedd <- at(c(5.0, 6.4, 4.5), 0.35)
    lvesd <- lvedd * (1 - at(c(0.36, 0.20, 0.38), 0.04))
    la_diam <- at(c(3.8, 4.6, 5.0), 0.35)
    rvsp <- at(c(30, 44, 52), 7)
    e_e <- at(c(9, 14, 18), 2.5)
    # Drawn here, under the seed, so the missing cells are the same every build.
    missing <- matrix(stats::runif(5L * n) < 0.05, n)
  })
  d$lvedd <- replace(round(lvedd, 1), missing[, 1L], NA)
  d$lvesd <- replace(round(lvesd, 1), missing[, 2L], NA)
  d$la_diam <- replace(round(la_diam, 1), missing[, 3L], NA)
  d$rvsp <- replace(round(rvsp), missing[, 4L], NA)
  d$e_e <- replace(round(e_e, 1), missing[, 5L], NA)
  labels <- c(
    lvedd = "LV end-diastolic dimension (cm)", lvesd = "LV end-systolic dimension (cm)",
    la_diam = "Left atrial diameter (cm)", rvsp = "RV systolic pressure (mmHg)", e_e = "Mitral E/e' ratio"
  )
  for (v in names(labels)) attr(d[[v]], "label") <- labels[[v]]
  d
}

gallery_family(
  "sid",
  columns = sid_columns,
  jobs = list(
    # 1000 trees, not the template's 5000, keep the render short.
    "sid-fit" = list(subject = "echo", type = "sid", choices = list(
      "^ID <- \"ccfid\"$" = "ID <- \"patient_id\"",
      "^VARS <- c\\(" = "VARS <- c(\"lvedd\", \"lvesd\", \"la_diam\", \"rvsp\", \"e_e\", \"lvef\")",
      "^NTREE <- " = "NTREE <- 1000"
    )),
    # K = 3, the number of phenotypes drawn above. A study reads the K metrics
    # and the sizes table before it chooses.
    "sid-clusters" = list(subject = "echo", type = "sid", choices = list(
      "^K_RANGE <- " = "K_RANGE <- 2:6",
      "^K <- NULL$" = "K <- 3"
    ))
  )
)
