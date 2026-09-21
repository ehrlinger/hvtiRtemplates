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
order the folders and are stripped from `folder`. The placement test
requires the job catalog and skips when it is absent. Its internal
lookup helper uses the catalog's `(prefix, qualifier)` row, falling back
to
[`hvti_taxonomy`](https://ehrlinger.github.io/hvtiRutilities/reference/hvti_taxonomy.html)
when the catalog or matching row is absent. A separate test checks that
every template directory names a taxonomy folder, including when the
catalog is absent.

## Examples

``` r
template_list()
#>           name prefix qualifier        folder
#> 1   dc-general     dc   general   descriptive
#> 2      dc-gfup     dc      gfup   descriptive
#> 3    dc-tables     dc    tables   descriptive
#> 4   dp-postage     dp   postage   descriptive
#> 5           ac     ac      <NA> distributions
#> 6           hz     hz      <NA> distributions
#> 7           bc     bc      <NA>      analyses
#> 8           bh     bh      <NA>      analyses
#> 9           bl     bl      <NA>      analyses
#> 10          br     br      <NA>      analyses
#> 11          hm     hm      <NA>      analyses
#> 12 rfc-explain    rfc   explain      analyses
#> 13     rfc-fit    rfc       fit      analyses
#> 14 rfr-explain    rfr   explain      analyses
#> 15     rfr-fit    rfr       fit      analyses
#> 16 rfs-explain    rfs   explain      analyses
#> 17     rfs-fit    rfs       fit      analyses
#> 18   dp-trends     dp    trends        graphs
#> 19          hp     hp      <NA>        graphs
#> 20          hs     hs      <NA>        graphs
#>                                                                                      file
#> 1  /home/runner/work/_temp/Library/hvtiRtemplates/templates/10_descriptive/dc-general.qmd
#> 2     /home/runner/work/_temp/Library/hvtiRtemplates/templates/10_descriptive/dc-gfup.qmd
#> 3   /home/runner/work/_temp/Library/hvtiRtemplates/templates/10_descriptive/dc-tables.qmd
#> 4  /home/runner/work/_temp/Library/hvtiRtemplates/templates/10_descriptive/dp-postage.qmd
#> 5        /home/runner/work/_temp/Library/hvtiRtemplates/templates/20_distributions/ac.qmd
#> 6        /home/runner/work/_temp/Library/hvtiRtemplates/templates/20_distributions/hz.qmd
#> 7             /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/bc.qmd
#> 8             /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/bh.qmd
#> 9             /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/bl.qmd
#> 10            /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/br.qmd
#> 11            /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/hm.qmd
#> 12   /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/rfc-explain.qmd
#> 13       /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/rfc-fit.qmd
#> 14   /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/rfr-explain.qmd
#> 15       /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/rfr-fit.qmd
#> 16   /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/rfs-explain.qmd
#> 17       /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/rfs-fit.qmd
#> 18       /home/runner/work/_temp/Library/hvtiRtemplates/templates/40_graphs/dp-trends.qmd
#> 19              /home/runner/work/_temp/Library/hvtiRtemplates/templates/40_graphs/hp.qmd
#> 20              /home/runner/work/_temp/Library/hvtiRtemplates/templates/40_graphs/hs.qmd
```
