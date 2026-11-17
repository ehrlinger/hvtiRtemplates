# Paste each item's Methods boilerplate into an ar report

Writes the Methods paragraph each cited job recorded into every
**empty** `::: methods` div of an `ar` analysis report, with a review
stamp, so the analyst edits text that starts from the job's own choices.
A div that already holds text is never touched.

## Usage

``` r
ar_paste_methods(path, root = NULL)
```

## Arguments

- path:

  Path to the `ar` job file.

- root:

  The study root. `NULL` finds it above `path`.

## Value

The ids of the items pasted, invisibly, in file order.

## Details

Run from the console, not from inside the render: a render that edits
its own source would break the checksum its provenance records. Every
item is resolved before anything is written, so an item that fails (a
draft source, a missing exhibit) leaves the file exactly as it was.

## See also

[`ar_review()`](https://ehrlinger.github.io/hvtiRtemplates/reference/ar_review.md),
[`ar_item()`](https://ehrlinger.github.io/hvtiRtemplates/reference/ar_item.md)

## Examples

``` r
# A copy of a small study shipped with the package: one finished hz job and
# an ar report citing two of its exhibits.
dir <- tempfile("ar-")
dir.create(dir)
src <- system.file("extdata", "ar-study", package = "hvtiRtemplates")
file.copy(src, dir, recursive = TRUE)
#> [1] TRUE
study <- file.path(dir, "ar-study")
report <- file.path(study, "50_documents", "ar.dead.question.qmd")
ar_paste_methods(report)
# Each methods slot now opens with its review stamp, then the job's paragraph.
writeLines(readLines(report)[10:14])
#> ::: methods
#> <!-- ar-stamp {"item":"hz.dead.hz#fig-fit","methods_sha256":"4a4773c1ea7eb6185c3e2dd54f6dc6ca62ac502cc153d69def7dc8f89f173e91","rendered":"2026-11-12T10:00:00Z","exhibit_sha256":"81329e0b8e6852fd718097a4614914961b87dc5fef18f7be487204a77622589e"} -->
#> 
#> The hazard of death was modeled in two phases, early and constant, with TemporalHazard, in 160 patients with 40 deaths.
#> :::
unlink(dir, recursive = TRUE)
```
