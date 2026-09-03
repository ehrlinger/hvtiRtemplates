# Scaffold a new analysis job from a template

Copies a supported job template into the taxonomy folder it belongs to,
named `<endpoint>-<type>-<NN.MM>-<prefix>[-<qualifier>].qmd`. Refuses to
overwrite an existing job: a job file accumulates a study's edits, and
silently replacing one would discard them.

## Usage

``` r
new_job(prefix, endpoint, type, dir = ".", qualifier = NULL)
```

## Arguments

- prefix:

  Job type: one of the prefixes reported by
  [`template_list`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_list.md).

- endpoint:

  The endpoint this job analyses, e.g. `"dead_pa"`. Must match
  `^[A-Za-z0-9_]+$`: `-` separates the filename's fields and `.` is
  reserved to the ordinal, so neither may appear here.

- type:

  The analysis type the job's set belongs to, e.g. `"hz"`. Must match
  `^[A-Za-z0-9_]+$`, for the same reason as `endpoint`.

- dir:

  The study root to write into. The taxonomy folder beneath it is
  created if it does not exist.

- qualifier:

  Job type within the prefix, e.g. `"trends"` for `dp`. Required only
  where a prefix carries more than one template; omitting it there is an
  error naming the choices, never a silent pick. Restricted to
  `[A-Za-z0-9_]+`, because `-` separates the filename's fields.

## Value

The path written, invisibly. On any failure – including one after the
copy, while substituting the set markers – no file is left behind, so a
returned path always names a complete, correctly-declared job.

## Details

A job is identified by four fields. Two come from the template — its
`ordinal` and `prefix` — and two from the caller. The pair
`(endpoint, type)` names the **set** the job belongs to, and both are
required: one endpoint is analysed by several methods, and the jobs
those chains share would otherwise collide. A death-hazard set and a
death random-forest-survival set both begin from the same life table, so
keyed on the endpoint alone both would be written to one filename.

## See also

[`template_list`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_list.md),
[`template_path`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_path.md)

## Examples

``` r
d <- file.path(tempdir(), "new-job-example")
new_job("ac", "dead_pa", "hz", dir = d)
list.files(d, recursive = TRUE)
#> [1] "distributions/dead_pa-hz-03.01-ac.qmd"
unlink(d, recursive = TRUE)
```
