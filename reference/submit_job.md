# Render a job in the background, detached from the session

Starts
[`render_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/render_job.md)
on the job in a separate process that outlives the R session, the way
`nohup` from a terminal does, and returns at once. Use it for a job
whose fit runs for hours: a Workbench session that times out takes a
console run with it.

## Usage

``` r
submit_job(path, final = FALSE, params = NULL, output_file = NULL)
```

## Arguments

- path:

  Character(1). The job's `.qmd` file.

- final:

  Logical(1). Passed to
  [`render_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/render_job.md).

- params, output_file:

  Passed to
  [`render_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/render_job.md).

## Value

Invisibly, the job's status, as
[`job_status`](https://ehrlinger.github.io/hvtiRtemplates/reference/job_status.md)
returns it.

## Details

The process runs the `Rscript` of the R that called `submit_job()`, from
the study root, so the study's `renv` and `.Renviron` apply. It writes
`<job>.run.log` (everything the render prints) and `<job>.run.yml` (its
state) beside the job; read the state with
[`job_status`](https://ehrlinger.github.io/hvtiRtemplates/reference/job_status.md).
A job already running is not started twice: a `<job>.run.lock` directory
is taken while a submit is in progress, and a submit that crashed can
leave it behind, in which case delete it to try again. Stop a submitted
job with
[`cancel_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/cancel_job.md).
Not available on Windows, which cannot detach a process this way.

With `output_file`, the run files are named for the job and that whole
file name, extension included, so `job.qmd` rendered to `job.M1000.html`
keeps `job@job.M1000.html.run.log`, `job@job.M1000.html.run.yml` and the
rest beside the job. Another job given the same name is another run, and
the same job rendered to another name is another run: both can be
submitted, and each is followed and stopped by giving
[`job_status`](https://ehrlinger.github.io/hvtiRtemplates/reference/job_status.md)
or
[`cancel_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/cancel_job.md)
the same `output_file`. Quarto still renders one job at a time in a
study.

## Examples

``` r
# Not run by check: it would start a real render.
if (FALSE) { # \dontrun{
submit_job("analyses/nb.boostmtree.lvef.boost.qmd")
} # }
```
