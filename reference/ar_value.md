# Quote a saved value in an ar analysis report

Reads one field of a value a finished job saved for its report, so a
number in the Results text comes from the fit and goes stale with it,
rather than being retyped. The source run must be final and its file
unchanged, as for
[`ar_item()`](https://ehrlinger.github.io/hvtiRtemplates/reference/ar_item.md).
When the source job has been edited since its render, a final render
(`render_job(final = TRUE)`) stops, and a draft warns.

## Usage

``` r
ar_value(id, field)
```

## Arguments

- id:

  The value's item id, `"<job>#<label>"`.

- field:

  The field to return.

## Value

The field's value.

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
  # In a report this is inline R: `r hvtiRtemplates::ar_value("hz.dead.hz#methods", "n")`.
  # From the console it finds the study above the working directory.
  old <- setwd(study)
  print(ar_value("hz.dead.hz#methods", "n"))
  setwd(old)
  unlink(dir, recursive = TRUE)
}
#> [1] 160
```
