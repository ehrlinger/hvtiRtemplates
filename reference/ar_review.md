# Mark ar report items as reviewed against their sources' current runs

After rereading an item's methods, results and interpretation against a
source job that has been rendered again, `ar_review()` moves that item's
review stamp to the job's current run, which clears the report's
callout. The analyst's text is not changed.

## Usage

``` r
ar_review(path, item = NULL, root = NULL)
```

## Arguments

- path:

  Path to the `ar` job file.

- item:

  Item ids to stamp, such as `"hz.dead.hz#fig-fit"`. `NULL` stamps every
  item.

- root:

  The study root. `NULL` finds it above `path`.

## Value

The ids of the items stamped, invisibly.

## See also

[`ar_paste_methods`](https://ehrlinger.github.io/hvtiRtemplates/reference/ar_paste_methods.md)

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
# After rereading the figure's text against the job's latest run:
ar_review(report, "hz.dead.hz#fig-fit")
unlink(dir, recursive = TRUE)
```
