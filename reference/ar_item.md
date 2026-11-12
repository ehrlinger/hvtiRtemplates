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

[`ar_value`](https://ehrlinger.github.io/hvtiRtemplates/reference/ar_value.md),
[`ar_paste_methods`](https://ehrlinger.github.io/hvtiRtemplates/reference/ar_paste_methods.md),
[`ar_review`](https://ehrlinger.github.io/hvtiRtemplates/reference/ar_review.md)

## Examples

``` r
# \donttest{
# In an ar job's chunk:
# hvtiRtemplates::ar_item("hz.dead.hz#fig-fit")
# }
```
