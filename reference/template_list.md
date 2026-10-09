# List the supported R job templates

These templates are supported: they render, they are tested, and they
are the intended starting point for a new analysis job.

## Usage

``` r
template_list()

# S3 method for class 'hvti_template_list'
print(x, ...)
```

## Arguments

- x:

  A data frame returned by `template_list()`.

- ...:

  Passed to the data frame print method.

## Value

A data frame, of class `hvti_template_list`, with columns `name`,
`prefix`, `qualifier`, `folder`, `call` and `file`. `call` is the
[`add_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
call that scaffolds the template, with only the arguments it requires
and runnable as printed, e.g.
`add_job("dc.gfup", subject = "cohort", type = "eda")`. The `subject`
and `type` shown are the template's own defaults; change them to name
the job. `folder` is the taxonomy name with the directory's ordering
digits stripped, so `20_distributions` reports as `distributions`.
`qualifier` is `NA` for a prefix carrying a single template. Printed
whole, it shows only `name`, `prefix`, `qualifier` and `folder`, since
`call` and `file` would wrap every row; both are still in the data, and
a selection of columns prints as selected.

## Details

A template is named `<prefix>.qmd`, or `<prefix>-<qualifier>.qmd` where
one prefix carries several job types, and lives in a numbered directory
named for the taxonomy folder it scaffolds into, so `folder` is read
from the tree rather than looked up. A qualified template is shown, and
selected, as `<prefix>.<qualifier>`, e.g. `dp.trends`, the spelling a
job's name uses; the file keeps its dash, and `"dp-trends"` is still
accepted as input. The directory's leading digits order the folders and
are stripped from `folder`. The placement test requires the job catalog
and skips when it is absent. Its internal lookup helper uses the
catalog's `(prefix, qualifier)` row, falling back to
[`hvti_taxonomy`](https://ehrlinger.github.io/hvtiRutilities/reference/hvti_taxonomy.html)
when the catalog or matching row is absent. A separate test checks that
every template directory names a taxonomy folder, including when the
catalog is absent.

## Examples

``` r
tl <- template_list()
# Printed whole: name, prefix, qualifier and folder.
tl
#>                     name prefix          qualifier        folder
#> 1                     bd     bd               <NA>      datasets
#> 2             dc.general     dc            general   descriptive
#> 3                dc.gfup     dc               gfup   descriptive
#> 4             dc.stddiff     dc            stddiff   descriptive
#> 5              dc.tables     dc             tables   descriptive
#> 6                 dp.eda     dp                eda   descriptive
#> 7             dp.postage     dp            postage   descriptive
#> 8                     ac     ac               <NA> distributions
#> 9                     hz     hz               <NA> distributions
#> 10                    bc     bc               <NA>      analyses
#> 11                    bh     bh               <NA>      analyses
#> 12                    bl     bl               <NA>      analyses
#> 13                    br     br               <NA>      analyses
#> 14                    hm     hm               <NA>      analyses
#> 15    lm.balancing_count     lm    balancing_count      analyses
#> 16             lm.binary     lm             binary      analyses
#> 17          lm.checkpred     lm          checkpred      analyses
#> 18            lm.nominal     lm            nominal      analyses
#> 19            lm.ordinal     lm            ordinal      analyses
#> 20  lm.propensity_binary     lm  propensity_binary      analyses
#> 21 lm.propensity_nominal     lm propensity_nominal      analyses
#> 22 lm.propensity_ordinal     lm propensity_ordinal      analyses
#> 23         nb.boostmtree     nb         boostmtree      analyses
#> 24           rfc.explain    rfc            explain      analyses
#> 25               rfc.fit    rfc                fit      analyses
#> 26           rfr.explain    rfr            explain      analyses
#> 27               rfr.fit    rfr                fit      analyses
#> 28           rfs.explain    rfs            explain      analyses
#> 29               rfs.fit    rfs                fit      analyses
#> 30               dp.gfup     dp               gfup        graphs
#> 31             dp.trends     dp             trends        graphs
#> 32                    hp     hp               <NA>        graphs
#> 33        hs.concordance     hs        concordance        graphs
#> 34              hs.setup     hs              setup        graphs
#> # 34 templates; `call` and `file` not shown. Read them with $call and $file.

# Every template, where its job is written, and the call that scaffolds it.
tl[, c("name", "folder", "call")]
#>                     name        folder
#> 1                     bd      datasets
#> 2             dc.general   descriptive
#> 3                dc.gfup   descriptive
#> 4             dc.stddiff   descriptive
#> 5              dc.tables   descriptive
#> 6                 dp.eda   descriptive
#> 7             dp.postage   descriptive
#> 8                     ac distributions
#> 9                     hz distributions
#> 10                    bc      analyses
#> 11                    bh      analyses
#> 12                    bl      analyses
#> 13                    br      analyses
#> 14                    hm      analyses
#> 15    lm.balancing_count      analyses
#> 16             lm.binary      analyses
#> 17          lm.checkpred      analyses
#> 18            lm.nominal      analyses
#> 19            lm.ordinal      analyses
#> 20  lm.propensity_binary      analyses
#> 21 lm.propensity_nominal      analyses
#> 22 lm.propensity_ordinal      analyses
#> 23         nb.boostmtree      analyses
#> 24           rfc.explain      analyses
#> 25               rfc.fit      analyses
#> 26           rfr.explain      analyses
#> 27               rfr.fit      analyses
#> 28           rfs.explain      analyses
#> 29               rfs.fit      analyses
#> 30               dp.gfup        graphs
#> 31             dp.trends        graphs
#> 32                    hp        graphs
#> 33        hs.concordance        graphs
#> 34              hs.setup        graphs
#>                                                                            call
#> 1                              add_job("bd", subject = "study", type = "build")
#> 2                       add_job("dc.general", subject = "cohort", type = "eda")
#> 3                          add_job("dc.gfup", subject = "cohort", type = "eda")
#> 4                   add_job("dc.stddiff", subject = "cohort", type = "balance")
#> 5                        add_job("dc.tables", subject = "cohort", type = "eda")
#> 6                           add_job("dp.eda", subject = "cohort", type = "eda")
#> 7                       add_job("dp.postage", subject = "cohort", type = "eda")
#> 8                               add_job("ac", subject = "dead_pa", type = "hz")
#> 9                               add_job("hz", subject = "dead_pa", type = "hz")
#> 10                              add_job("bc", subject = "dead_pa", type = "hz")
#> 11                              add_job("bh", subject = "dead_pa", type = "hz")
#> 12                              add_job("bl", subject = "dead_pa", type = "hz")
#> 13                              add_job("br", subject = "dead_pa", type = "hz")
#> 14                              add_job("hm", subject = "dead_pa", type = "hz")
#> 15      add_job("lm.balancing_count", subject = "exposure", type = "balancing")
#> 16                 add_job("lm.binary", subject = "outcome", type = "analysis")
#> 17              add_job("lm.checkpred", subject = "outcome", type = "analysis")
#> 18                add_job("lm.nominal", subject = "outcome", type = "analysis")
#> 19                add_job("lm.ordinal", subject = "outcome", type = "analysis")
#> 20  add_job("lm.propensity_binary", subject = "treatment", type = "propensity")
#> 21 add_job("lm.propensity_nominal", subject = "treatment", type = "propensity")
#> 22 add_job("lm.propensity_ordinal", subject = "treatment", type = "propensity")
#> 23                   add_job("nb.boostmtree", subject = "lvef", type = "boost")
#> 24                       add_job("rfc.explain", subject = "dead", type = "rfc")
#> 25                           add_job("rfc.fit", subject = "dead", type = "rfc")
#> 26                        add_job("rfr.explain", subject = "los", type = "rfr")
#> 27                            add_job("rfr.fit", subject = "los", type = "rfr")
#> 28                       add_job("rfs.explain", subject = "dead", type = "rfs")
#> 29                           add_job("rfs.fit", subject = "dead", type = "rfs")
#> 30                         add_job("dp.gfup", subject = "cohort", type = "eda")
#> 31                       add_job("dp.trends", subject = "cohort", type = "eda")
#> 32                              add_job("hp", subject = "dead_pa", type = "hz")
#> 33                  add_job("hs.concordance", subject = "dead_pa", type = "hz")
#> 34                        add_job("hs.setup", subject = "dead_pa", type = "hz")

# Find a template by its qualifier, then copy its call: the follow-up jobs.
subset(tl, qualifier == "gfup", c(name, folder, call))
#>       name      folder                                                 call
#> 3  dc.gfup descriptive add_job("dc.gfup", subject = "cohort", type = "eda")
#> 30 dp.gfup      graphs add_job("dp.gfup", subject = "cohort", type = "eda")
```
