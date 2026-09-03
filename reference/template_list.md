# List the supported R job templates

These templates are supported: they render, they are tested, and they
are the intended starting point for a new analysis job.

## Usage

``` r
template_list()
```

## Value

A data frame with columns `name`, `prefix`, `qualifier`, `ordinal`,
`folder` and `file`. `qualifier` is `NA` for a prefix carrying a single
template, which is every template shipped today.

## Details

A template is named `<NN.MM>-<prefix>.qmd`, or
`<NN.MM>-<prefix>-<qualifier>.qmd` where one prefix carries several job
types, and lives in the taxonomy folder it scaffolds into, so `folder`
and `ordinal` are read from the tree rather than looked up.
[`hvti_taxonomy`](https://ehrlinger.github.io/hvtiRutilities/reference/hvti_taxonomy.html)
is a cross-check on that, enforced by the test suite, not a source for
it.

## Examples

``` r
template_list()
#>       name prefix qualifier ordinal        folder
#> 1 04.01-hm     hm      <NA>   04.01      analyses
#> 2 04.02-bl     bl      <NA>   04.02      analyses
#> 3 04.03-br     br      <NA>   04.03      analyses
#> 4 04.04-bc     bc      <NA>   04.04      analyses
#> 5 04.05-bh     bh      <NA>   04.05      analyses
#> 6 03.01-ac     ac      <NA>   03.01 distributions
#> 7 03.02-hz     hz      <NA>   03.02 distributions
#> 8 06.01-hp     hp      <NA>   06.01        graphs
#> 9 06.02-hs     hs      <NA>   06.02        graphs
#>                                                                                  file
#> 1      /home/runner/work/_temp/Library/hvtiRtemplates/templates/analyses/04.01-hm.qmd
#> 2      /home/runner/work/_temp/Library/hvtiRtemplates/templates/analyses/04.02-bl.qmd
#> 3      /home/runner/work/_temp/Library/hvtiRtemplates/templates/analyses/04.03-br.qmd
#> 4      /home/runner/work/_temp/Library/hvtiRtemplates/templates/analyses/04.04-bc.qmd
#> 5      /home/runner/work/_temp/Library/hvtiRtemplates/templates/analyses/04.05-bh.qmd
#> 6 /home/runner/work/_temp/Library/hvtiRtemplates/templates/distributions/03.01-ac.qmd
#> 7 /home/runner/work/_temp/Library/hvtiRtemplates/templates/distributions/03.02-hz.qmd
#> 8        /home/runner/work/_temp/Library/hvtiRtemplates/templates/graphs/06.01-hp.qmd
#> 9        /home/runner/work/_temp/Library/hvtiRtemplates/templates/graphs/06.02-hs.qmd
```
