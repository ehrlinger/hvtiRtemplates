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
selected, as `<prefix>.<qualifier>`, e.g. `dc.trends`, the spelling a
job's name uses; the file keeps its dash, and `"dc-trends"` is still
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
#>                       name prefix            qualifier        folder
#> 1                       bd     bd                 <NA>      datasets
#> 2                       dt     dt                 <NA>      datasets
#> 3                   dc.eda     dc                  eda   descriptive
#> 4               dc.general     dc              general   descriptive
#> 5                  dc.gfup     dc                 gfup   descriptive
#> 6               dc.stddiff     dc              stddiff   descriptive
#> 7                dc.tables     dc               tables   descriptive
#> 8                dc.trends     dc               trends   descriptive
#> 9                       lg     lg                 <NA>   descriptive
#> 10                      ac     ac                 <NA> distributions
#> 11                      hz     hz                 <NA> distributions
#> 12                      bc     bc                 <NA>      analyses
#> 13                      bh     bh                 <NA>      analyses
#> 14                      bl     bl                 <NA>      analyses
#> 15                      br     br                 <NA>      analyses
#> 16                      hm     hm                 <NA>      analyses
#> 17      lm.balancing_count     lm      balancing_count      analyses
#> 18               lm.binary     lm               binary      analyses
#> 19            lm.checkpred     lm            checkpred      analyses
#> 20              lm.nominal     lm              nominal      analyses
#> 21              lm.ordinal     lm              ordinal      analyses
#> 22    lm.propensity_binary     lm    propensity_binary      analyses
#> 23   lm.propensity_nominal     lm   propensity_nominal      analyses
#> 24   lm.propensity_ordinal     lm   propensity_ordinal      analyses
#> 25           nb.boostmtree     nb           boostmtree      analyses
#> 26             rfc.explain    rfc              explain      analyses
#> 27                 rfc.fit    rfc                  fit      analyses
#> 28             rfr.explain    rfr              explain      analyses
#> 29                 rfr.fit    rfr                  fit      analyses
#> 30             rfs.explain    rfs              explain      analyses
#> 31                 rfs.fit    rfs                  fit      analyses
#> 32             rhf.explain    rhf              explain      analyses
#> 33                 rhf.fit    rhf                  fit      analyses
#> 34 rm.balancing_continuous     rm balancing_continuous      analyses
#> 35               rm.linear     rm               linear      analyses
#> 36            sid.clusters    sid             clusters      analyses
#> 37                 sid.fit    sid                  fit      analyses
#> 38           vp.dependence     vp           dependence      analyses
#> 39              vp.explain     vp              explain      analyses
#> 40                  vp.fit     vp                  fit      analyses
#> 41           vp.individual     vp           individual      analyses
#> 42              vt.explain     vt              explain      analyses
#> 43                  vt.fit     vt                  fit      analyses
#> 44                      hp     hp                 <NA>        graphs
#> 45          hs.concordance     hs          concordance        graphs
#> 46                hs.score     hs                score        graphs
#> 47                hs.setup     hs                setup        graphs
#> 48               lp.mirror     lp               mirror        graphs
#> # 48 templates; `call` and `file` not shown. Read them with $call and $file.

# Every template, where its job is written, and the call that scaffolds it.
tl[, c("name", "folder", "call")]
#>                       name        folder
#> 1                       bd      datasets
#> 2                       dt      datasets
#> 3                   dc.eda   descriptive
#> 4               dc.general   descriptive
#> 5                  dc.gfup   descriptive
#> 6               dc.stddiff   descriptive
#> 7                dc.tables   descriptive
#> 8                dc.trends   descriptive
#> 9                       lg   descriptive
#> 10                      ac distributions
#> 11                      hz distributions
#> 12                      bc      analyses
#> 13                      bh      analyses
#> 14                      bl      analyses
#> 15                      br      analyses
#> 16                      hm      analyses
#> 17      lm.balancing_count      analyses
#> 18               lm.binary      analyses
#> 19            lm.checkpred      analyses
#> 20              lm.nominal      analyses
#> 21              lm.ordinal      analyses
#> 22    lm.propensity_binary      analyses
#> 23   lm.propensity_nominal      analyses
#> 24   lm.propensity_ordinal      analyses
#> 25           nb.boostmtree      analyses
#> 26             rfc.explain      analyses
#> 27                 rfc.fit      analyses
#> 28             rfr.explain      analyses
#> 29                 rfr.fit      analyses
#> 30             rfs.explain      analyses
#> 31                 rfs.fit      analyses
#> 32             rhf.explain      analyses
#> 33                 rhf.fit      analyses
#> 34 rm.balancing_continuous      analyses
#> 35               rm.linear      analyses
#> 36            sid.clusters      analyses
#> 37                 sid.fit      analyses
#> 38           vp.dependence      analyses
#> 39              vp.explain      analyses
#> 40                  vp.fit      analyses
#> 41           vp.individual      analyses
#> 42              vt.explain      analyses
#> 43                  vt.fit      analyses
#> 44                      hp        graphs
#> 45          hs.concordance        graphs
#> 46                hs.score        graphs
#> 47                hs.setup        graphs
#> 48               lp.mirror        graphs
#>                                                                            call
#> 1                              add_job("bd", subject = "study", type = "build")
#> 2                              add_job("dt", subject = "study", type = "check")
#> 3                           add_job("dc.eda", subject = "cohort", type = "eda")
#> 4                       add_job("dc.general", subject = "cohort", type = "eda")
#> 5                          add_job("dc.gfup", subject = "cohort", type = "eda")
#> 6                   add_job("dc.stddiff", subject = "cohort", type = "balance")
#> 7                        add_job("dc.tables", subject = "cohort", type = "eda")
#> 8                        add_job("dc.trends", subject = "cohort", type = "eda")
#> 9                         add_job("lg", subject = "dead", type = "calibration")
#> 10                              add_job("ac", subject = "dead_pa", type = "hz")
#> 11                              add_job("hz", subject = "dead_pa", type = "hz")
#> 12                              add_job("bc", subject = "dead_pa", type = "hz")
#> 13                              add_job("bh", subject = "dead_pa", type = "hz")
#> 14                              add_job("bl", subject = "dead_pa", type = "hz")
#> 15                              add_job("br", subject = "dead_pa", type = "hz")
#> 16                              add_job("hm", subject = "dead_pa", type = "hz")
#> 17      add_job("lm.balancing_count", subject = "exposure", type = "balancing")
#> 18                 add_job("lm.binary", subject = "outcome", type = "analysis")
#> 19              add_job("lm.checkpred", subject = "outcome", type = "analysis")
#> 20                add_job("lm.nominal", subject = "outcome", type = "analysis")
#> 21                add_job("lm.ordinal", subject = "outcome", type = "analysis")
#> 22  add_job("lm.propensity_binary", subject = "treatment", type = "propensity")
#> 23 add_job("lm.propensity_nominal", subject = "treatment", type = "propensity")
#> 24 add_job("lm.propensity_ordinal", subject = "treatment", type = "propensity")
#> 25                   add_job("nb.boostmtree", subject = "lvef", type = "boost")
#> 26                       add_job("rfc.explain", subject = "dead", type = "rfc")
#> 27                           add_job("rfc.fit", subject = "dead", type = "rfc")
#> 28                        add_job("rfr.explain", subject = "los", type = "rfr")
#> 29                            add_job("rfr.fit", subject = "los", type = "rfr")
#> 30                       add_job("rfs.explain", subject = "dead", type = "rfs")
#> 31                           add_job("rfs.fit", subject = "dead", type = "rfs")
#> 32                       add_job("rhf.explain", subject = "dead", type = "rhf")
#> 33                           add_job("rhf.fit", subject = "dead", type = "rhf")
#> 34 add_job("rm.balancing_continuous", subject = "exposure", type = "balancing")
#> 35                   add_job("rm.linear", subject = "outcome", type = "linear")
#> 36                add_job("sid.clusters", subject = "morphology", type = "sid")
#> 37                     add_job("sid.fit", subject = "morphology", type = "sid")
#> 38              add_job("vp.dependence", subject = "dead", type = "dependence")
#> 39                         add_job("vp.explain", subject = "dead", type = "vp")
#> 40                             add_job("vp.fit", subject = "dead", type = "vp")
#> 41                      add_job("vp.individual", subject = "dead", type = "vp")
#> 42                         add_job("vt.explain", subject = "dead", type = "vt")
#> 43                             add_job("vt.fit", subject = "dead", type = "vt")
#> 44                              add_job("hp", subject = "dead_pa", type = "hz")
#> 45                  add_job("hs.concordance", subject = "dead_pa", type = "hz")
#> 46                        add_job("hs.score", subject = "dead_pa", type = "hz")
#> 47                        add_job("hs.setup", subject = "dead_pa", type = "hz")
#> 48             add_job("lp.mirror", subject = "treatment", type = "propensity")

# Find a template by its qualifier, then copy its call: the follow-up jobs.
subset(tl, qualifier == "gfup", c(name, folder, call))
#>      name      folder                                                 call
#> 5 dc.gfup descriptive add_job("dc.gfup", subject = "cohort", type = "eda")
```
