# Path to a supported template

Path to a supported template

## Usage

``` r
template_path(prefix)
```

## Arguments

- prefix:

  Analysis prefix, e.g. `"ac"`. See
  [`template_list`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_list.md).

## Value

The full path, as `character(1)`.

## Examples

``` r
try(template_path("ac"))
#> [1] "/home/runner/work/_temp/Library/hvtiRtemplates/templates/distributions/03.01-ac.qmd"
```
