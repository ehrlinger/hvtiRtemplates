# Report a background job's state

Reads the status
[`submit_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/submit_job.md)
keeps beside a job, `<job>.run.yml`. A job whose process was killed
never records its end, so a recorded `running` is checked against the
process itself. A render also keeps `<job>.run.progress`, read here; a
render started without
[`submit_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/submit_job.md),
after the last submitted run or with none, is reported from that file
alone. A progress file older than the run the status file records is
ignored.

## Usage

``` r
job_status(path, quiet = FALSE)
```

## Arguments

- path:

  Character(1). The job's `.qmd` file.

- quiet:

  Logical(1). `FALSE` prints a one-line summary.

## Value

Invisibly, a list: `state` is one of `"none"`, `"submitted"`,
`"running"`, `"finished"`, `"failed"` or `"vanished"`; the other
elements are what the status file recorded (`pid`, `created`, `host`,
`started`, `ended`, `exit_code`, `elapsed_s`, `r_version`), and `log`,
the log file's path. `progress`, the render's progress record when there
is one, with `eta_s`, the estimated seconds left in the current stage,
and `stale`, `TRUE` when it has not changed for three reporting
intervals and at least 30 minutes.

## Details

A long step writes a line to the render log at most every
`getOption("hvtiRtemplates.progress_every", 10)` minutes.

## Examples

``` r
job <- file.path(tempdir(), "example.qmd")
writeLines("---\ntitle: example\n---", job)
job_status(job)
#> example.qmd: none
```
