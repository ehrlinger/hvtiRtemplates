# Build inst/extdata/ar-study: a small study holding one finished hz job, as a
# final render would have left it, and an ar report that cites two of its
# exhibits. The ar_* examples copy it to tempdir() and run against the copy.
#
# Run from the package root: Rscript dev/ar-example/build.R
# The digests in the sidecar are taken from the files written here, so edit
# this script and rebuild rather than editing the fixture by hand.
# .gitattributes marks the fixture -text: a CRLF checkout of the job's .qmd
# would no longer match its source_sha256.

root <- file.path("inst", "extdata", "ar-study")
unlink(root, recursive = TRUE)
dirs <- file.path(root, c("20_distributions", "40_graphs/dead-hz", "50_documents/dead-hz", "90_estimates/dead-hz"))
for (d in dirs) dir.create(d, recursive = TRUE)

lf <- function(lines, path) {
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeLines(lines, con)
}

lf("study: ar-example", file.path(root, "_study.yml"))

qmd <- file.path(root, "20_distributions", "hz.dead.hz.qmd")
lf(c("---", "title: Hazard of death", "---", "",
     "A stand-in for a rendered hz job. Only its provenance record is read."), qmd)
lf("<html><body><p>The hz job's report.</p></body></html>", sub("[.]qmd$", ".html", qmd))

png <- file.path(root, "40_graphs", "dead-hz", "hz-fit.png")
grDevices::png(png, width = 240, height = 240)
graphics::par(mar = c(4, 4, 1, 1))
t <- seq(0, 10, by = 0.1)
graphics::plot(t, 0.02 + 0.01 * exp(-t), type = "l", xlab = "Years", ylab = "Hazard")
grDevices::dev.off()

saveRDS(data.frame(term = c("early", "constant"), estimate = c(0.012, 0.021)),
        file.path(root, "50_documents", "dead-hz", "tbl-estimates.rds"))
saveRDS(list(n = 160L, events = 40L), file.path(root, "90_estimates", "dead-hz", "hz-methods.rds"))

sha <- function(rel) digest::digest(file.path(root, rel), algo = "sha256", file = TRUE)
rec <- function(label, kind, rel) list(label = label, kind = kind, file = rel, sha256 = sha(rel))
methods <- paste("The hazard of death was modeled in two phases, early and constant,",
                 "with TemporalHazard, in 160 patients with 40 deaths.")
sidecar <- list(
  job = "hz.dead.hz", rendered = "2026-11-12T10:00:00Z", r = list(version = "4.6.1"),
  packages = list(list(package = "TemporalHazard", version = "1.3.0", source = "standard")),
  data = list(list(path = "00_datasets/built.parquet", role = "study", dataset = "built")),
  run = list(status = "final", open_markers = 0L, skipped_chunks = 0L, stopped_early = FALSE),
  source_sha256 = sha("20_distributions/hz.dead.hz.qmd"),
  exhibits = list(rec("fig-fit", "figure", "40_graphs/dead-hz/hz-fit.png"),
                  rec("tbl-estimates", "table", "50_documents/dead-hz/tbl-estimates.rds"),
                  rec("methods", "value", "90_estimates/dead-hz/hz-methods.rds")),
  methods = list(text = methods, sha256 = digest::digest(methods, algo = "sha256", serialize = FALSE))
)
json <- jsonlite::toJSON(sidecar, auto_unbox = TRUE, pretty = TRUE)
lf(json, hvtiRutilities::provenance_path(sub("[.]qmd$", ".html", qmd)))

# The ar report: two items, each with an empty methods slot for ar_paste_methods().
item <- function(id) {
  c("```{r}", paste0('hvtiRtemplates::ar_item("', id, '")'), "```", "",
    "::: methods", "", ":::", "")
}
lf(c("---", "title: Does early hazard explain the deaths?", "---", "",
     item("hz.dead.hz#fig-fit"), item("hz.dead.hz#tbl-estimates")),
   file.path(root, "50_documents", "ar.dead.question.qmd"))
