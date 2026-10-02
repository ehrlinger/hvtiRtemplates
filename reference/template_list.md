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
#>                     name prefix          qualifier        folder
#> 1                     bd     bd               <NA>      datasets
#> 2             dc-general     dc            general   descriptive
#> 3                dc-gfup     dc               gfup   descriptive
#> 4              dc-tables     dc             tables   descriptive
#> 5                 dp-eda     dp                eda   descriptive
#> 6             dp-postage     dp            postage   descriptive
#> 7                     ac     ac               <NA> distributions
#> 8                     hz     hz               <NA> distributions
#> 9                     bc     bc               <NA>      analyses
#> 10                    bh     bh               <NA>      analyses
#> 11                    bl     bl               <NA>      analyses
#> 12                    br     br               <NA>      analyses
#> 13                    hm     hm               <NA>      analyses
#> 14    lm-balancing_count     lm    balancing_count      analyses
#> 15             lm-binary     lm             binary      analyses
#> 16          lm-checkpred     lm          checkpred      analyses
#> 17            lm-nominal     lm            nominal      analyses
#> 18            lm-ordinal     lm            ordinal      analyses
#> 19  lm-propensity_binary     lm  propensity_binary      analyses
#> 20 lm-propensity_nominal     lm propensity_nominal      analyses
#> 21 lm-propensity_ordinal     lm propensity_ordinal      analyses
#> 22         nb-boostmtree     nb         boostmtree      analyses
#> 23           rfc-explain    rfc            explain      analyses
#> 24               rfc-fit    rfc                fit      analyses
#> 25           rfr-explain    rfr            explain      analyses
#> 26               rfr-fit    rfr                fit      analyses
#> 27           rfs-explain    rfs            explain      analyses
#> 28               rfs-fit    rfs                fit      analyses
#> 29               dp-gfup     dp               gfup        graphs
#> 30             dp-trends     dp             trends        graphs
#> 31                    hp     hp               <NA>        graphs
#> 32        hs-concordance     hs        concordance        graphs
#> 33              hs-setup     hs              setup        graphs
#>                                                                                              file
#> 1                     /home/runner/work/_temp/Library/hvtiRtemplates/templates/00_datasets/bd.qmd
#> 2          /home/runner/work/_temp/Library/hvtiRtemplates/templates/10_descriptive/dc-general.qmd
#> 3             /home/runner/work/_temp/Library/hvtiRtemplates/templates/10_descriptive/dc-gfup.qmd
#> 4           /home/runner/work/_temp/Library/hvtiRtemplates/templates/10_descriptive/dc-tables.qmd
#> 5              /home/runner/work/_temp/Library/hvtiRtemplates/templates/10_descriptive/dp-eda.qmd
#> 6          /home/runner/work/_temp/Library/hvtiRtemplates/templates/10_descriptive/dp-postage.qmd
#> 7                /home/runner/work/_temp/Library/hvtiRtemplates/templates/20_distributions/ac.qmd
#> 8                /home/runner/work/_temp/Library/hvtiRtemplates/templates/20_distributions/hz.qmd
#> 9                     /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/bc.qmd
#> 10                    /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/bh.qmd
#> 11                    /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/bl.qmd
#> 12                    /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/br.qmd
#> 13                    /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/hm.qmd
#> 14    /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/lm-balancing_count.qmd
#> 15             /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/lm-binary.qmd
#> 16          /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/lm-checkpred.qmd
#> 17            /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/lm-nominal.qmd
#> 18            /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/lm-ordinal.qmd
#> 19  /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/lm-propensity_binary.qmd
#> 20 /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/lm-propensity_nominal.qmd
#> 21 /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/lm-propensity_ordinal.qmd
#> 22         /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/nb-boostmtree.qmd
#> 23           /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/rfc-explain.qmd
#> 24               /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/rfc-fit.qmd
#> 25           /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/rfr-explain.qmd
#> 26               /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/rfr-fit.qmd
#> 27           /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/rfs-explain.qmd
#> 28               /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/rfs-fit.qmd
#> 29                 /home/runner/work/_temp/Library/hvtiRtemplates/templates/40_graphs/dp-gfup.qmd
#> 30               /home/runner/work/_temp/Library/hvtiRtemplates/templates/40_graphs/dp-trends.qmd
#> 31                      /home/runner/work/_temp/Library/hvtiRtemplates/templates/40_graphs/hp.qmd
#> 32          /home/runner/work/_temp/Library/hvtiRtemplates/templates/40_graphs/hs-concordance.qmd
#> 33                /home/runner/work/_temp/Library/hvtiRtemplates/templates/40_graphs/hs-setup.qmd
```
