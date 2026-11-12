# Quote a saved value in an ar analysis report

Reads one field of a value a finished job saved for its report, so a
number in the Results text comes from the fit and goes stale with it,
rather than being retyped. The source run must be final and its file
unchanged, as for
[`ar_item`](https://ehrlinger.github.io/hvtiRtemplates/reference/ar_item.md).

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
# \donttest{
# Inline in an ar job: `r hvtiRtemplates::ar_value("hz.dead.hz#methods", "n")` patients
# }
```
