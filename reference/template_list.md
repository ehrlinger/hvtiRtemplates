# List the supported R job templates

These templates are supported: they render, they are tested, and they
are the intended starting point for a new analysis job.

## Usage

``` r
template_list()
```

## Value

A data frame with columns `name`, `prefix`, `qualifier`, `folder` and
`file`. `folder` is the taxonomy name with the directory's ordering
digits stripped, so `20_distributions` reports as `distributions`.
`qualifier` is `NA` for a prefix carrying a single template, which is
every template shipped today.

## Details

A template is named `<prefix>.qmd`, or `<prefix>-<qualifier>.qmd` where
one prefix carries several job types, and lives in a numbered directory
named for the taxonomy folder it scaffolds into, so `folder` is read
from the tree rather than looked up. The directory's leading digits
order the folders and are stripped from `folder`.
[`hvti_taxonomy`](https://ehrlinger.github.io/hvtiRutilities/reference/hvti_taxonomy.html)
is a cross-check on that, enforced by the test suite, not a source for
it.

## Examples

``` r
template_list()
#>   name prefix qualifier        folder
#> 1   ac     ac      <NA> distributions
#> 2   hz     hz      <NA> distributions
#> 3   bc     bc      <NA>      analyses
#> 4   bh     bh      <NA>      analyses
#> 5   bl     bl      <NA>      analyses
#> 6   br     br      <NA>      analyses
#> 7   hm     hm      <NA>      analyses
#> 8   hp     hp      <NA>        graphs
#> 9   hs     hs      <NA>        graphs
#>                                                                               file
#> 1 /home/runner/work/_temp/Library/hvtiRtemplates/templates/20_distributions/ac.qmd
#> 2 /home/runner/work/_temp/Library/hvtiRtemplates/templates/20_distributions/hz.qmd
#> 3      /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/bc.qmd
#> 4      /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/bh.qmd
#> 5      /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/bl.qmd
#> 6      /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/br.qmd
#> 7      /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/hm.qmd
#> 8        /home/runner/work/_temp/Library/hvtiRtemplates/templates/40_graphs/hp.qmd
#> 9        /home/runner/work/_temp/Library/hvtiRtemplates/templates/40_graphs/hs.qmd
```
