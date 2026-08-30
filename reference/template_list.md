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
#> 1 04.01-hm     hm   04.01      analyses
#> 2 04.06-bh     bh   04.06      analyses
#> 3 03.01-ac     ac   03.01 distributions
#> 4 03.02-hz     hz   03.02 distributions
#> 5 06.01-hp     hp   06.01        graphs
#> 6 06.02-hs     hs   06.02        graphs
#>                                                                                  file
#> 1      /home/runner/work/_temp/Library/hvtiRtemplates/templates/analyses/04.01-hm.qmd
#> 2      /home/runner/work/_temp/Library/hvtiRtemplates/templates/analyses/04.06-bh.qmd
#> 3 /home/runner/work/_temp/Library/hvtiRtemplates/templates/distributions/03.01-ac.qmd
#> 4 /home/runner/work/_temp/Library/hvtiRtemplates/templates/distributions/03.02-hz.qmd
#> 5        /home/runner/work/_temp/Library/hvtiRtemplates/templates/graphs/06.01-hp.qmd
#> 6        /home/runner/work/_temp/Library/hvtiRtemplates/templates/graphs/06.02-hs.qmd
```
