# Show one item of an ar analysis report

Called once per item in an `ar` job. Finds the exhibit a finished job
recorded under `id`, checks that the job last rendered as final and that
the file still holds the bytes it recorded, and shows the exhibit with a
link to the job's report. Callouts above it say what to check: a job
edited since its render, Methods boilerplate that changed, or text
written against an earlier run.

## Usage

``` r
ar_item(id)
```

## Arguments

- id:

  The item, `"<job>#<label>"`: the source job's file name without
  `.qmd`, and the chunk label it saved the exhibit under.

## Value

A `knit_asis` object holding the item's Markdown.

## See also

[`ar_value()`](https://ehrlinger.github.io/hvtiRtemplates/reference/ar_value.md),
[`ar_paste_methods()`](https://ehrlinger.github.io/hvtiRtemplates/reference/ar_paste_methods.md),
[`ar_review()`](https://ehrlinger.github.io/hvtiRtemplates/reference/ar_review.md)

## Examples

``` r
if (requireNamespace("knitr", quietly = TRUE)) {
  # A copy of a small study shipped with the package: one finished hz job and
  # an ar report citing two of its exhibits.
  dir <- tempfile("ar-")
  dir.create(dir)
  src <- system.file("extdata", "ar-study", package = "hvtiRtemplates")
  file.copy(src, dir, recursive = TRUE)
  study <- file.path(dir, "ar-study")
  report <- file.path(study, "50_documents", "ar.dead.question.qmd")
  # ar_item() runs inside the report's chunks, so knit the report.
  md <- knitr::knit(report, output = tempfile(fileext = ".md"), quiet = TRUE)
  writeLines(grep("^[*][*]Item|^[[]The full", readLines(md), value = TRUE))
  unlink(dir, recursive = TRUE)
}
#> **Item 1** · `hz.dead.hz#fig-fit`
#> [The full report of `hz.dead.hz`, in the study folder](../20_distributions/hz.dead.hz.html)
#> **Item 2** · `hz.dead.hz#tbl-estimates`
#> [The full report of `hz.dead.hz`, in the study folder](../20_distributions/hz.dead.hz.html)
```
