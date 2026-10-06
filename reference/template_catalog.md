# Catalog of analysis templates owed by this package

The catalog records one row per job type, including templates still
queued or blocked on functions in other packages. \`template_list()\`
reports the files already shipped; this catalog records the full work
plan.

## Usage

``` r
template_catalog()
```

## Value

A data frame. \`uses\`, \`upstream\`, \`downstream\`, and \`workflows\`
are list columns of character vectors. Unmeasured counts are
\`NA_integer\_\`. `description` is a one-sentence summary, given for
every template on disk and `NA` for most queued ones. `deprecated_by`
names the template replacing a deprecated one, such as `"dp-eda"`, and
`deprecation_note` says how to move to it; both are `NA` for a supported
template. A deprecated template still ships, and
[`add_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
warns when it is used.

## Examples

``` r
catalog <- template_catalog()
table(catalog$status)
#> 
#> in-flight    queued   revisit   shipped 
#>         1        34         1        32 

# Templates that still scaffold but name a replacement.
catalog[!is.na(catalog$deprecated_by), c("prefix", "qualifier", "deprecated_by")]
#>    prefix qualifier deprecated_by
#> 61     dp      gfup       dc-gfup
#> 65     dp   postage        dp-eda

# Queued templates waiting on work in another package.
queued <- catalog[catalog$status == "queued" & !is.na(catalog$blocked_on), ]
queued[, c("prefix", "qualifier", "blocked_on")]
#>    prefix qualifier        blocked_on
#> 8      bq      <NA> hvtiRbootstrap#16
#> 11     ce      <NA>     hvtiPlotR#134
#> 13     cp      <NA>     hvtiPlotR#135
#> 14     dt      <NA>    hvtiRdatabuild
#> 15     fp      <NA>     hvtiPlotR#133
#> 17     gp      <NA>     hvtiPlotR#136
#> 48   vars      <NA>    hvtiRdatabuild
#> 50     mi      <NA>   hvtiRimputation
#> 53    sid      <NA>    hvtiRforests#1
#> 54     vt      <NA>    hvtiRforests#1
```
