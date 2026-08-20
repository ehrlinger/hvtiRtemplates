# Scaffold a new analysis job from a template

Copies a supported job template into `dir`, named
`<prefix>.<basename>.qmd`. Refuses to overwrite an existing job: a job
file accumulates a study's edits, and silently replacing one would
discard them.

## Usage

``` r
new_job(prefix, basename, dir = "qmd")
```

## Arguments

- prefix:

  Job type: one of the prefixes reported by
  [`template_list`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_list.md).

- basename:

  Job name, appended after the prefix.

- dir:

  Directory to write into. Created if it does not exist.

## Value

The path written, invisibly. Errors if the copy fails, so the returned
path always names a file that exists.

## See also

[`template_list`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_list.md),
[`template_path`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_path.md)

## Examples

``` r
d <- file.path(tempdir(), "new-job-example")
new_job("ac", "dead", dir = d)
list.files(d)
#> [1] "ac.dead.qmd"
unlink(d, recursive = TRUE)
```
