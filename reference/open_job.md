# Open a job, creating it from its template if needed

Finds the study root from `dir`, creates the job with
[`add_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
when it does not exist, and opens it in the editor. An existing job is
opened as it stands, never overwritten.

## Usage

``` r
open_job(prefix, endpoint, type, dir = ".", qualifier = NULL)
```

## Arguments

- prefix:

  Job type: one of the prefixes reported by
  [`template_list`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_list.md).

- endpoint:

  The endpoint this job analyses, e.g. `"dead_pa"`. Must match
  `^[A-Za-z0-9_]+$`: `-` separates the filename's fields and `.`
  separates the extension, so neither may appear here.

- type:

  The analysis type the job's set belongs to, e.g. `"hz"`. Must match
  `^[A-Za-z0-9_]+$`, for the same reason as `endpoint`.

- dir:

  Character. Any directory inside the study. Defaults to the working
  directory.

- qualifier:

  Job type within the prefix, e.g. `"trends"` for `dp`. Required only
  where a prefix carries more than one template; omitting it there is an
  error naming the choices, never a silent pick. Restricted to
  `[A-Za-z0-9_]+`, because `-` separates the filename's fields.

## Value

The path to the job file, invisibly.

## Details

The study root is the nearest directory at or above `dir` holding
`_study.yml`, so this can be called from anywhere inside a study.
Naming, prefix and qualifier rules are those of
[`add_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md).
The editor is opened only in an interactive session.

## See also

[`add_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md),
[`render_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/render_job.md)

## Examples

``` r
root <- file.path(tempdir(), "open-job-example")
suppressMessages(hvtiRutilities::study_setup(
  root, study = "Example", study_tracker_id = 1L
))
#> Study: /tmp/RtmpgJKDQv/open-job-example
#> 
#> [x] _study.yml — study: Example
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [ ] manifest.yaml — no manifest.yaml; register_data() creates it
#> [ ] dataset — no default dataset registered; run register_data()
#> [ ] cohort — requires a registered default dataset
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
open_job("ac", "dead", "eda", dir = root)
unlink(root, recursive = TRUE)
```
