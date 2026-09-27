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
#> 1             dc-general     dc            general   descriptive
#> 2                dc-gfup     dc               gfup   descriptive
#> 3              dc-tables     dc             tables   descriptive
#> 4                 dp-eda     dp                eda   descriptive
#> 5             dp-postage     dp            postage   descriptive
#> 6                     ac     ac               <NA> distributions
#> 7                     hz     hz               <NA> distributions
#> 8                     bc     bc               <NA>      analyses
#> 9                     bh     bh               <NA>      analyses
#> 10                    bl     bl               <NA>      analyses
#> 11                    br     br               <NA>      analyses
#> 12                    hm     hm               <NA>      analyses
#> 13    lm-balancing_count     lm    balancing_count      analyses
#> 14             lm-binary     lm             binary      analyses
#> 15          lm-checkpred     lm          checkpred      analyses
#> 16            lm-nominal     lm            nominal      analyses
#> 17            lm-ordinal     lm            ordinal      analyses
#> 18  lm-propensity_binary     lm  propensity_binary      analyses
#> 19 lm-propensity_nominal     lm propensity_nominal      analyses
#> 20 lm-propensity_ordinal     lm propensity_ordinal      analyses
#> 21           rfc-explain    rfc            explain      analyses
#> 22               rfc-fit    rfc                fit      analyses
#> 23           rfr-explain    rfr            explain      analyses
#> 24               rfr-fit    rfr                fit      analyses
#> 25           rfs-explain    rfs            explain      analyses
#> 26               rfs-fit    rfs                fit      analyses
#> 27               dp-gfup     dp               gfup        graphs
#> 28             dp-trends     dp             trends        graphs
#> 29                    hp     hp               <NA>        graphs
#> 30                    hs     hs               <NA>        graphs
#>                                                                                              file
#> 1          /home/runner/work/_temp/Library/hvtiRtemplates/templates/10_descriptive/dc-general.qmd
#> 2             /home/runner/work/_temp/Library/hvtiRtemplates/templates/10_descriptive/dc-gfup.qmd
#> 3           /home/runner/work/_temp/Library/hvtiRtemplates/templates/10_descriptive/dc-tables.qmd
#> 4              /home/runner/work/_temp/Library/hvtiRtemplates/templates/10_descriptive/dp-eda.qmd
#> 5          /home/runner/work/_temp/Library/hvtiRtemplates/templates/10_descriptive/dp-postage.qmd
#> 6                /home/runner/work/_temp/Library/hvtiRtemplates/templates/20_distributions/ac.qmd
#> 7                /home/runner/work/_temp/Library/hvtiRtemplates/templates/20_distributions/hz.qmd
#> 8                     /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/bc.qmd
#> 9                     /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/bh.qmd
#> 10                    /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/bl.qmd
#> 11                    /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/br.qmd
#> 12                    /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/hm.qmd
#> 13    /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/lm-balancing_count.qmd
#> 14             /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/lm-binary.qmd
#> 15          /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/lm-checkpred.qmd
#> 16            /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/lm-nominal.qmd
#> 17            /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/lm-ordinal.qmd
#> 18  /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/lm-propensity_binary.qmd
#> 19 /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/lm-propensity_nominal.qmd
#> 20 /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/lm-propensity_ordinal.qmd
#> 21           /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/rfc-explain.qmd
#> 22               /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/rfc-fit.qmd
#> 23           /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/rfr-explain.qmd
#> 24               /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/rfr-fit.qmd
#> 25           /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/rfs-explain.qmd
#> 26               /home/runner/work/_temp/Library/hvtiRtemplates/templates/30_analyses/rfs-fit.qmd
#> 27                 /home/runner/work/_temp/Library/hvtiRtemplates/templates/40_graphs/dp-gfup.qmd
#> 28               /home/runner/work/_temp/Library/hvtiRtemplates/templates/40_graphs/dp-trends.qmd
#> 29                      /home/runner/work/_temp/Library/hvtiRtemplates/templates/40_graphs/hp.qmd
#> 30                      /home/runner/work/_temp/Library/hvtiRtemplates/templates/40_graphs/hs.qmd
```
