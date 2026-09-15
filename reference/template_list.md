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
`qualifier` is `NA` for a prefix carrying a single template.

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
#>          name prefix qualifier        folder
#> 1     dc-gfup     dc      gfup   descriptive
#> 2   dc-tables     dc    tables   descriptive
#> 3  dp-postage     dp   postage   descriptive
#> 4          ac     ac      <NA> distributions
#> 5          hz     hz      <NA> distributions
#> 6          bc     bc      <NA>      analyses
#> 7          bh     bh      <NA>      analyses
#> 8          bl     bl      <NA>      analyses
#> 9          br     br      <NA>      analyses
#> 10         hm     hm      <NA>      analyses
#> 11  dp-trends     dp    trends        graphs
#> 12         hp     hp      <NA>        graphs
#> 13         hs     hs      <NA>        graphs
#>                                                                                      file
#> 1     /home/runner/work/_temp/Library/hvtiRtemplates/templates/10_descriptive/dc-gfup.qmd
#> 2   /home/runner/work/_temp/Library/hvtiRtemplates/templates/10_descriptive/dc-tables.qmd
#> 3  /home/runner/work/_temp/Library/hvtiRtemplates/templates/10_descriptive/dp-postage.qmd
#> 4        /home/runner/work/_temp/Library/hvtiRtemplates/templates/20_distributions/ac.qmd
#> 5        /home/runner/work/_temp/Library/hvtiRtemplates/templates/20_distributions/hz.qmd
#> 6             /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/bc.qmd
#> 7             /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/bh.qmd
#> 8             /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/bl.qmd
#> 9             /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/br.qmd
#> 10            /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/hm.qmd
#> 11       /home/runner/work/_temp/Library/hvtiRtemplates/templates/40_graphs/dp-trends.qmd
#> 12              /home/runner/work/_temp/Library/hvtiRtemplates/templates/40_graphs/hp.qmd
#> 13              /home/runner/work/_temp/Library/hvtiRtemplates/templates/40_graphs/hs.qmd
```
