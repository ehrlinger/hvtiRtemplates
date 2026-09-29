# Path to a supported template

Path to a supported template

## Usage

``` r
template_path(prefix, qualifier = NULL)
```

## Arguments

- prefix:

  Analysis prefix, e.g. `"ac"`, or a template's full name, e.g.
  `"dp-trends"`, which carries its qualifier and leaves `qualifier`
  `NULL`. See
  [`template_list`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_list.md).

- qualifier:

  Job type within the prefix, e.g. `"trends"` for `dp`. Required only
  where a prefix carries more than one template; omitting it there is an
  error naming the choices, never a silent pick.

## Value

The full path, as `character(1)`. A template the catalog marks
deprecated, such as `dp-postage`, still resolves, with a warning naming
its replacement.

## Examples

``` r
try(template_path("ac"))
#> [1] "/home/runner/work/_temp/Library/hvtiRtemplates/templates/20_distributions/ac.qmd"
```
