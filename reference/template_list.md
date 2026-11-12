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
`prefix`, `qualifier`, `folder`, `title`, `description`, `call` and
`file`. `title` and `description` say what the template is for, from the
template catalog
([`template_catalog`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_catalog.md)),
and are `NA` for a template it does not list. `call` is the
[`add_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
call that scaffolds the template, with only the arguments it requires
and runnable as printed, e.g.
`add_job("dc.gfup", subject = "cohort", type = "eda")`. The `subject`
and `type` shown are the template's own defaults; change them to name
the job. `folder` is the taxonomy name with the directory's ordering
digits stripped, so `20_distributions` reports as `distributions`.
`qualifier` is `NA` for a prefix carrying a single template. Printed
whole, it shows only `name`, `folder` and `title`, the title cut to fit
the console's width, since the other columns would wrap every row. In a
console too narrow for the three, `folder` is left out, then `title`.
The other columns are still in the data, and a selection of columns
prints as selected.

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
# Printed whole: name, folder and title.
tl
#>    name                    folder        title                                 
#> 1  bd                      datasets      Build                                 
#> 2  dc.eda                  descriptive   Descriptive plot: EDA report          
#> 3  dc.general              descriptive   Descriptive: general                  
#> 4  dc.gfup                 descriptive   Descriptive: follow-up                
#> 5  dc.stddiff              descriptive   Descriptive: standardized differences 
#> 6  dc.tables               descriptive   Descriptive: formatted tables         
#> 7  dc.trends               descriptive   Descriptive plot: trends              
#> 8  lg                      descriptive   Logit calibration                     
#> 9  ac                      distributions Actuarial                             
#> 10 hz                      distributions Hazard fit                            
#> 11 bc                      analyses      Bootstrap Cox                         
#> 12 bh                      analyses      Bootstrap hazard                      
#> 13 bl                      analyses      Bootstrap logistic                    
#> 14 br                      analyses      Bootstrap regression                  
#> 15 hm                      analyses      Hazard model                          
#> 16 lm.balancing_count      analyses      Logistic model: count balancing score 
#> 17 lm.binary               analyses      Logistic model: binary outcome        
#> 18 lm.checkpred            analyses      Logistic model: validate saved pred...
#> 19 lm.nominal              analyses      Logistic model: nominal outcome       
#> 20 lm.ordinal              analyses      Logistic model: ordinal outcome       
#> 21 lm.propensity_binary    analyses      Logistic model: binary propensity s...
#> 22 lm.propensity_nominal   analyses      Logistic model: nominal propensity ...
#> 23 lm.propensity_ordinal   analyses      Logistic model: ordinal propensity ...
#> 24 nb.boostmtree           analyses      Boosting: boostmtree                  
#> 25 rfc.explain             analyses      Random forest classifier: explain     
#> 26 rfc.fit                 analyses      Random forest classifier: fit         
#> 27 rfr.explain             analyses      Random forest regression: explain     
#> 28 rfr.fit                 analyses      Random forest regression: fit         
#> 29 rfs.explain             analyses      Random forest survival: explain       
#> 30 rfs.fit                 analyses      Random forest survival: fit           
#> 31 rhf.explain             analyses      Random hazard forest: explain         
#> 32 rhf.fit                 analyses      Random hazard forest: fit             
#> 33 rm.balancing_continuous analyses      Regression model: continuous balanc...
#> 34 rm.linear               analyses      Regression model: continuous outcome  
#> 35 sid.clusters            analyses      SID clustering: clusters              
#> 36 sid.fit                 analyses      SID clustering: fit                   
#> 37 sid.stability           analyses      SID clustering: stability             
#> 38 vp.dependence           analyses      VarPro: dependence                    
#> 39 vp.explain              analyses      VarPro: explain                       
#> 40 vp.fit                  analyses      VarPro: fit                           
#> 41 vp.individual           analyses      VarPro: individual                    
#> 42 vt.explain              analyses      Virtual twins: explain                
#> 43 vt.fit                  analyses      Virtual twins: fit                    
#> 44 hp                      graphs        Hazard plot                           
#> 45 hs.concordance          graphs        Hazard concordance                    
#> 46 hs.score                graphs        Hazard segment score                  
#> 47 hs.setup                graphs        Hazard setup                          
#> 48 lp.mirror               graphs        Logistic plot: mirrored propensity ...
#> 49 ar                      documents     Analysis report                       
#> # 49 templates. Read any column with $, such as $description or $call.

# Every template, where its job is written, and the call that scaffolds it.
tl[, c("name", "folder", "call")]
#>                       name        folder
#> 1                       bd      datasets
#> 2                   dc.eda   descriptive
#> 3               dc.general   descriptive
#> 4                  dc.gfup   descriptive
#> 5               dc.stddiff   descriptive
#> 6                dc.tables   descriptive
#> 7                dc.trends   descriptive
#> 8                       lg   descriptive
#> 9                       ac distributions
#> 10                      hz distributions
#> 11                      bc      analyses
#> 12                      bh      analyses
#> 13                      bl      analyses
#> 14                      br      analyses
#> 15                      hm      analyses
#> 16      lm.balancing_count      analyses
#> 17               lm.binary      analyses
#> 18            lm.checkpred      analyses
#> 19              lm.nominal      analyses
#> 20              lm.ordinal      analyses
#> 21    lm.propensity_binary      analyses
#> 22   lm.propensity_nominal      analyses
#> 23   lm.propensity_ordinal      analyses
#> 24           nb.boostmtree      analyses
#> 25             rfc.explain      analyses
#> 26                 rfc.fit      analyses
#> 27             rfr.explain      analyses
#> 28                 rfr.fit      analyses
#> 29             rfs.explain      analyses
#> 30                 rfs.fit      analyses
#> 31             rhf.explain      analyses
#> 32                 rhf.fit      analyses
#> 33 rm.balancing_continuous      analyses
#> 34               rm.linear      analyses
#> 35            sid.clusters      analyses
#> 36                 sid.fit      analyses
#> 37           sid.stability      analyses
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
#> 49                      ar     documents
#>                                                                            call
#> 1                              add_job("bd", subject = "study", type = "build")
#> 2                           add_job("dc.eda", subject = "cohort", type = "eda")
#> 3                       add_job("dc.general", subject = "cohort", type = "eda")
#> 4                          add_job("dc.gfup", subject = "cohort", type = "eda")
#> 5                   add_job("dc.stddiff", subject = "cohort", type = "balance")
#> 6                        add_job("dc.tables", subject = "cohort", type = "eda")
#> 7                        add_job("dc.trends", subject = "cohort", type = "eda")
#> 8                         add_job("lg", subject = "dead", type = "calibration")
#> 9                               add_job("ac", subject = "dead_pa", type = "hz")
#> 10                              add_job("hz", subject = "dead_pa", type = "hz")
#> 11                              add_job("bc", subject = "dead_pa", type = "hz")
#> 12                              add_job("bh", subject = "dead_pa", type = "hz")
#> 13                              add_job("bl", subject = "dead_pa", type = "hz")
#> 14                              add_job("br", subject = "dead_pa", type = "hz")
#> 15                              add_job("hm", subject = "dead_pa", type = "hz")
#> 16      add_job("lm.balancing_count", subject = "exposure", type = "balancing")
#> 17                 add_job("lm.binary", subject = "outcome", type = "analysis")
#> 18              add_job("lm.checkpred", subject = "outcome", type = "analysis")
#> 19                add_job("lm.nominal", subject = "outcome", type = "analysis")
#> 20                add_job("lm.ordinal", subject = "outcome", type = "analysis")
#> 21  add_job("lm.propensity_binary", subject = "treatment", type = "propensity")
#> 22 add_job("lm.propensity_nominal", subject = "treatment", type = "propensity")
#> 23 add_job("lm.propensity_ordinal", subject = "treatment", type = "propensity")
#> 24                   add_job("nb.boostmtree", subject = "lvef", type = "boost")
#> 25                       add_job("rfc.explain", subject = "dead", type = "rfc")
#> 26                           add_job("rfc.fit", subject = "dead", type = "rfc")
#> 27                        add_job("rfr.explain", subject = "los", type = "rfr")
#> 28                            add_job("rfr.fit", subject = "los", type = "rfr")
#> 29                       add_job("rfs.explain", subject = "dead", type = "rfs")
#> 30                           add_job("rfs.fit", subject = "dead", type = "rfs")
#> 31                       add_job("rhf.explain", subject = "dead", type = "rhf")
#> 32                           add_job("rhf.fit", subject = "dead", type = "rhf")
#> 33 add_job("rm.balancing_continuous", subject = "exposure", type = "balancing")
#> 34                   add_job("rm.linear", subject = "outcome", type = "linear")
#> 35                add_job("sid.clusters", subject = "morphology", type = "sid")
#> 36                     add_job("sid.fit", subject = "morphology", type = "sid")
#> 37               add_job("sid.stability", subject = "morphology", type = "sid")
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
#> 49                        add_job("ar", subject = "dead_pa", type = "question")

# Find a template by its qualifier, then copy its call: the follow-up jobs.
subset(tl, qualifier == "gfup", c(name, folder, call))
#>      name      folder                                                 call
#> 4 dc.gfup descriptive add_job("dc.gfup", subject = "cohort", type = "eda")
```
