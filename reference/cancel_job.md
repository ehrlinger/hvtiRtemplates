# Stop a background job

Stops a job
[`submit_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/submit_job.md)
started, and records the end the killed process could not:
`<job>.run.yml` then reads `cancelled`, and `<job>.run.progress` is
removed, so
[`job_status`](https://ehrlinger.github.io/hvtiRtemplates/reference/job_status.md)
stops reporting the run and the job can be submitted again.

## Usage

``` r
cancel_job(
  path,
  grace = 30,
  other_host = c("refuse", "abandon"),
  quiet = FALSE
)
```

## Arguments

- path:

  Character(1). The job's `.qmd` file.

- grace:

  Numeric(1). Seconds to wait after `SIGTERM` before `SIGKILL`.

- other_host:

  Character(1). For a job recorded running on another host, `"refuse"`
  (the default) stops with an error naming that host, and `"abandon"`
  records the run ended without signalling anything. Ignored for a job
  on this host.

- quiet:

  Logical(1). `FALSE` prints the job's state afterwards, as
  [`job_status`](https://ehrlinger.github.io/hvtiRtemplates/reference/job_status.md)
  does.

## Value

Invisibly, the job's status afterwards, as
[`job_status`](https://ehrlinger.github.io/hvtiRtemplates/reference/job_status.md)
returns it.

## Details

The render and every process it started are sent `SIGTERM`, given
`grace` seconds to exit, then sent `SIGKILL`. They are found by a marker
[`submit_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/submit_job.md)
puts in the render's environment, which reaches processes Quarto starts
in sessions of their own, and by descent from the recorded process,
which is signalled only while it is still the one the status file
records: it must carry the run's marker or, recorded without one, match
its creation time to the second, so a pid since reused by another
process is left alone, and an identity in doubt is refused. The job is
scanned afresh until no process of it remains, so one started while it
shuts down is stopped too. A run recorded without a creation time, such
as a render started without
[`submit_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/submit_job.md),
is refused rather than signalled by its pid alone.

A process can only be checked and signalled on the host it runs on, so a
job recorded on another host is refused, naming the host to cancel it
from, unless `other_host = "abandon"`: then nothing is signalled, and
the run is recorded `cancelled`, with a reason saying so, and its
progress file removed. Use it only once that host's session is gone and
the job is confirmed not running there, for a render left running there
is not stopped and would go on writing the job's output. A job whose
process is already gone without recording its end is recorded `failed`,
with that as its reason, once any of its render still running has been
stopped. A job that has finished, failed or never run is left as it is.
A submit or cancel in progress holds `<job>.run.lock`, as
[`submit_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/submit_job.md)
describes, and a cancel is refused while it is held. Not available on
Windows.

## Examples

``` r
job <- file.path(tempdir(), "example.qmd")
writeLines("---\ntitle: example\n---", job)
if (.Platform$OS.type != "windows") cancel_job(job)
#> example.qmd: none
```
