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
table(template_catalog()$status)
#> 
#>  queued revisit shipped 
#>      36       1      31 
```
