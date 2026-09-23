# Scaffold a new analysis job from a template

Copies a supported job template into the taxonomy folder it belongs to,
named `<subject>-<type>-<prefix>[-<qualifier>].qmd`. Refuses to
overwrite an existing job: a job file accumulates a study's edits, and
silently replacing one would discard them.

## Usage

``` r
add_job(prefix, subject, type, dir = ".", qualifier = NULL)
```

## Arguments

- prefix:

  Job type: one of the prefixes reported by
  [`template_list`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_list.md).

- subject:

  Grouping topic for the job set, e.g. `"death"` or `"cohort"`. A
  subject names a statistical endpoint only when the job analyses one.
  Must match `^[A-Za-z0-9_]+$`: `-` separates the filename's fields and
  `.` separates the extension, so neither may appear here.

- type:

  The analysis type the job's set belongs to, e.g. `"hz"`. Must match
  `^[A-Za-z0-9_]+$`, for the same reason as `subject`.

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

A job is identified by three or four fields. One or two come from the
template, its `prefix` and, where the prefix carries several job types,
its `qualifier`; two come from the caller. The pair `(subject, type)`
names the **set** the job belongs to, and both are required. The subject
is the grouping topic, not necessarily a statistical endpoint. An
endpoint-driven job may use `"death"`; an endpoint-free job may use
`"cohort"`, `"treatment"`, or `"labs"` without inventing an outcome. One
subject can be analysed by several methods, and the jobs those chains
share would otherwise collide. A death-hazard set and a death
random-forest-survival set both begin from the same life table, so keyed
on the subject alone both would be written to one filename.

Scaffolding also installs the study's Quarto provenance hooks. Existing
pre-render and post-render commands and unrelated project settings are
preserved, while the provenance publisher is kept last. Repeated calls
are idempotent.

## See also

[`template_list`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_list.md),
[`template_path`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_path.md)

## Examples

``` r
d <- file.path(tempdir(), "add-job-example")
invisible(hvtiRutilities::study_setup(
  d, study = "Example", study_tracker_id = 1L
))
add_job(prefix = "ac", subject = "death", type = "hz", dir = d)
list.files(d, recursive = TRUE)
#> [1] "20_distributions/death-hz-ac.qmd" "_quarto.yml"                     
#> [3] "_study.yml"                       "add-job-example.Rproj"           
unlink(d, recursive = TRUE)
```
