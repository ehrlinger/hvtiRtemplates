# Path to a supported template

Path to a supported template

## Usage

``` r
template_path(prefix, qualifier = NULL)
```

## Arguments

- prefix:

  Analysis prefix, e.g. `"ac"`, or a template's full name, e.g.
  `"dp.trends"` (or `"dp-trends"`), which carries its qualifier and
  leaves `qualifier` `NULL`. See
  [`template_list`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_list.md).

- qualifier:

  Job type within the prefix, e.g. `"trends"` for `dp`. Required only
  where a prefix carries more than one template; omitting it there is an
  error naming the choices, never a silent pick.

## Value

The full path, as `character(1)`. A template the catalog marks
deprecated, such as `dp.postage`, still resolves, with a warning naming
its replacement.

## Examples

``` r
template_path("ac")
#> [1] "/home/runner/work/_temp/Library/hvtiRtemplates/templates/20_distributions/ac.qmd"

# A qualified template, by its full name or as prefix plus qualifier.
template_path("dc.gfup")
#> [1] "/home/runner/work/_temp/Library/hvtiRtemplates/templates/10_descriptive/dc-gfup.qmd"
template_path("dc", qualifier = "gfup")
#> [1] "/home/runner/work/_temp/Library/hvtiRtemplates/templates/10_descriptive/dc-gfup.qmd"

# A prefix carrying several templates is never resolved by guessing: this
# is an error that lists the choices.
try(template_path("dc"))
#> Error : prefix 'dc' carries 4 templates; name one with `qualifier`, or by its full name. Available: dc.general, dc.gfup, dc.stddiff, dc.tables
```
