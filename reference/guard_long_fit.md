# Stop a long fit from starting in an interactive session

A template calls this just before an expensive `cache_fit()`. In an
interactive session (the console, or running chunks one by one) with no
cached result yet, it stops and says to run the job with
[`submit_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/submit_job.md)
instead, because a fit that runs for hours dies with the session. A
render, a cached result, or
`options(hvtiRtemplates.allow_interactive_fit = TRUE)` lets it pass.

## Usage

``` r
guard_long_fit(name, dir, why, refit = FALSE)
```

## Arguments

- name:

  Character(1). The `cache_fit()` name; the cache file is
  `<dir>/<name>.rds`.

- dir:

  Character(1). The `cache_fit()` directory.

- why:

  Character(1). Why the fit is long, shown in the error.

- refit:

  Logical(1). `TRUE` when the job will recompute the fit even though a
  cached file exists (the template's `REFIT`); the cached file then does
  not make the call safe, so it is refused too.

## Value

`invisible(FALSE)` when the fit may proceed; otherwise an error.

## Examples

``` r
guard_long_fit("example-fit", dir = tempdir(), why = "it takes hours")
```
