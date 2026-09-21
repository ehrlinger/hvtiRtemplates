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
\`NA_integer\_\`.

## Examples

``` r
table(template_catalog()$status)
#> 
#>  queued revisit shipped 
#>      38       1      19 
```
