# List the supported R job templates

These templates are supported: they render, they are tested, and they
are the intended starting point for a new analysis job.

## Usage

``` r
template_list()
```

## Value

A data frame with columns `name`, `prefix`, `ordinal`, `folder` and
`file`.

## Details

A template is named `<NN.MM>-<prefix>.qmd` and lives in the taxonomy
folder it scaffolds into, so `folder` and `ordinal` are read from the
tree rather than looked up.
[`hvti_taxonomy`](https://ehrlinger.github.io/hvtiRutilities/reference/hvti_taxonomy.html)
is a cross-check on that, enforced by the test suite, not a source for
it.

## Examples

``` r
template_list()
#>       name prefix ordinal        folder
#> 1 03.01-ac     ac   03.01 distributions
#> 2 03.02-hz     hz   03.02 distributions
#>                                                                                  file
#> 1 /home/runner/work/_temp/Library/hvtiRtemplates/templates/distributions/03.01-ac.qmd
#> 2 /home/runner/work/_temp/Library/hvtiRtemplates/templates/distributions/03.02-hz.qmd
```
