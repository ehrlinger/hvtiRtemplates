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

[`ar_review`](https://ehrlinger.github.io/hvtiRtemplates/reference/ar_review.md),
[`ar_item`](https://ehrlinger.github.io/hvtiRtemplates/reference/ar_item.md)

## Examples

``` r
# \donttest{
# ar_paste_methods("documents/ar.dead.question.qmd")
# }
```
