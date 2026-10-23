# Check a job, run it in the background, and wait for its own checks

Starts a job the way a long fit should be started, and tells you at once
if it is going to fail. Before it submits anything, `run_job()` checks
the things that otherwise fail minutes or hours in: that this session's
R is the one the study's `renv.lock` records, that the packages the job
needs are installed at the versions locked, that Quarto can be found,
that the job is not already running, and that no other job is rendering
in the same study (Quarto allows one render per study). Every failure is
listed with how to fix it, and nothing is started until all of them are
cleared.

Then it submits the job with
[`submit_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/submit_job.md)
and waits for the render's own checks, the R it runs on and, where the
job calls
[`guard_memory`](https://ehrlinger.github.io/hvtiRtemplates/reference/guard_memory.md),
the memory its fit needs. Those can only run inside the render. If one
fails, the diagnosis is printed here rather than left in a log.

## Usage

``` r
run_job(path, final = FALSE, wait = 300, quiet = FALSE)
```

## Arguments

- path:

  Character(1). The job's `.qmd` file.

- final:

  Logical(1). Passed to
  [`submit_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/submit_job.md).

- wait:

  Numeric(1), seconds, at least 0. How long to wait for the render's own
  checks. `0` submits and returns at once.

- quiet:

  Logical(1). `TRUE` prints nothing: not the checks, the note for a
  legacy job, or the lines the wait ends on. A refusal is still an
  error, and its message then lists the failed checks and their fixes.

## Value

Invisibly, the job's status, as
[`job_status`](https://ehrlinger.github.io/hvtiRtemplates/reference/job_status.md)
returns it. A job refused by the checks is an error and returns nothing.

## Details

A job scaffolded before the setup consolidation has no in-render checks
to wait for. `run_job()` says so and names
[`upgrade_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/upgrade_job.md),
which adds them. The wait ends early when the render finishes, fails or
is cancelled. If the checks have not all reported when `wait` runs out,
the render carries on regardless; follow it with
[`job_status`](https://ehrlinger.github.io/hvtiRtemplates/reference/job_status.md).
Stop it with
[`cancel_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/cancel_job.md).
Not available on Windows, as for
[`submit_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/submit_job.md).

## See also

[`submit_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/submit_job.md),
[`job_status`](https://ehrlinger.github.io/hvtiRtemplates/reference/job_status.md),
[`cancel_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/cancel_job.md),
[`guard_memory`](https://ehrlinger.github.io/hvtiRtemplates/reference/guard_memory.md)

## Examples

``` r
# Not run by check: it would start a real render.
if (FALSE) { # \dontrun{
run_job("analyses/nb.boostmtree.lvef.boost.qmd")
} # }
```
