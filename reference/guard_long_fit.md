# Stop a long fit from starting anywhere but a background run

A template calls this just before an expensive `cache_fit()`, once
[`hvtiRutilities::cache_would_fit()`](https://ehrlinger.github.io/hvtiRutilities/reference/cache_would_fit.html)
has said the fit will be computed rather than loaded. With no cached
result it stops and says to run the job with
[`run_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/run_job.md),
because a fit that runs for hours dies with the Workbench session that
started it: the console, a chunk run by hand, the Render button, and a
`quarto render` typed in the Terminal tab, which is a child of the
session too, `nohup` or not. Only a render started by
[`run_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/run_job.md)
or
[`submit_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/submit_job.md)
passes, with a cached result or an explicit opt-in. Once the fit is
cached, the Render button works again and re-renders the job from the
cache.

## Usage

``` r
guard_long_fit(name, dir, why, refit = FALSE)
```

## Arguments

- name:

  Character. The `cache_fit()` name, or several when one long step
  writes several caches; each cache file is `<dir>/<name>.rds`, and the
  call is refused while any of them is missing.

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

## Details

A render started by
[`submit_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/submit_job.md)
carries `HVTI_JOB_MARKER`, which is how it is told apart. The opt-in is
`options(hvtiRtemplates.allow_interactive_fit = TRUE)` in the session,
or `HVTI_ALLOW_LONG_FIT` set to `"true"`, which a render's own R process
inherits where an option set in the session does not: the package's
tests and the template gallery render small fits that way. Set either
only for a fit you know to be short.

## Examples

``` r
dir <- file.path(tempdir(), "guard-long-fit-example")
dir.create(dir, showWarnings = FALSE)
# Outside run_job(), with no cached fit, it refuses and names run_job().
try(guard_long_fit("example-fit", dir = dir, why = "it takes hours"))
#> Error : This fit is not cached yet, and it takes hours: run from the console, the Render button or a terminal it dies with the Workbench session. Run the job in the background instead, from the study's R console:
#>   hvtiRtemplates::run_job("<this job>.qmd")
#> then check it with hvtiRtemplates::job_status(). Once the fit is cached, the Render button and these chunks work again and load it. For a fit you know to be short, set options(hvtiRtemplates.allow_interactive_fit = TRUE).
# Once the fit is cached, it lets the job load it.
saveRDS(1, file.path(dir, "example-fit.rds"))
guard_long_fit("example-fit", dir = dir, why = "it takes hours")
unlink(dir, recursive = TRUE)
```
