# List the supported R job templates

These templates are supported: they render, they are tested, and they
are the intended starting point for a new analysis job.

## Usage

``` r
template_list()
```

## Value

A data frame with columns \`name\`, \`prefix\`, \`folder\` and \`file\`.

## Details

Returns zero rows until the templates are added in stage 3 of the
templates-and-provenance design.

## Examples

``` r
template_list()
#> [1] name   prefix folder file  
#> <0 rows> (or 0-length row.names)
```
