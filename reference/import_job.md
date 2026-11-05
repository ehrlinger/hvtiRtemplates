# Bring a job from another study into this one

Copies a job `.qmd` from another study into the current study, keeping
the source study's edits, so a job adapted once, such as an
aorta-specific `ac` job, can be adapted again rather than rebuilt from
the template.

## Usage

``` r
import_job(from, subject = NULL, type = NULL, dir = NULL)
```

## Arguments

- from:

  The job to import: a `.qmd` file in another study, named as
  [`add_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
  names jobs.

- subject, type:

  The job's set in this study. `NULL`, the default, keeps the source
  job's. See
  [`add_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
  for what they decide.

- dir:

  The study root to import into. `NULL`, the default, finds it by
  walking up from the working directory, as
  [`add_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
  does.

## Value

The imported job's path, invisibly. On any failure no file is left
behind, the runner included.

## Details

The job is written where
[`add_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
would write a new job from the same template, under the name it would
give it, and with the same setup: the template's packages and any
further packages the job's own setup chunk attaches are installed into
the study's renv library, the Quarto provenance hooks are installed, and
an existing job is never overwritten. The template is read from the
job's file name, in either spelling
[`add_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
has used.

`subject` and `type` default to the source job's own. Either can be
changed on the way in, and the job's `SUBJECT` and `TYPE` lines are
rewritten to match its new name, as
[`add_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
does.

A job that runs from a companion runner script brings its runner too,
when one sits beside it. Without one, the job gets the template's
runner, and the message says so.

**What to review.** Everything else is carried as the source study left
it, including choices that were right for that study and may be wrong
for this one. `import_job()` rewrites none of them. Instead its message
lists, by line number, each one to check:

- the `DATASET` the job reads;

- a `WHERE` row selection, unless it is `NULL`;

- every `EDIT:` marker still in the job;

- every absolute file path, such as `"/studies/aorta/..."` or
  `"C:/..."`, which names a file in the other study or on another
  machine.

Values are never quoted in the message, because a selection can name a
patient. Paths relative to the study, which is how a template refers to
its study's files, are not listed.

The job keeps the template version it was written from, so
[`upgrade_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/upgrade_job.md)
can bring an older job up to the current template afterwards:
`upgrade_job(import_job(from))`.

## See also

[`add_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md),
[`upgrade_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/upgrade_job.md)

## Examples

``` r
other <- file.path(tempdir(), "import-job-other")
here <- file.path(tempdir(), "import-job-here")
for (d in c(other, here)) {
  invisible(hvtiRutilities::study_setup(d, study = "Example", study_tracker_id = 1L, renv = FALSE))
}
job <- add_job("ac", subject = "death", type = "hz", dir = other)
# The other study's edit.
lines <- readLines(job)
lines <- sub("^DATASET <- \"built\"", "DATASET <- \"built_aorta\"", lines)
writeLines(lines, job)

imported <- import_job(job, subject = "reop", dir = here)
#> import_job(): wrote '/tmp/RtmpaCi98t/import-job-here/20_distributions/ac.reop.hz.qmd' from '/tmp/RtmpaCi98t/import-job-other/20_distributions/ac.death.hz.qmd'.
#> Review in ac.reop.hz.qmd:
#>   DATASET: line 117
#>   EDIT: markers: lines 33, 116, 119, 122, 127, 132, 157, 162
grep("^(DATASET|SUBJECT) ", readLines(imported), value = TRUE)
#> [1] "SUBJECT <- \"reop\""        "DATASET <- \"built_aorta\""

# An existing job is never overwritten.
try(import_job(job, subject = "reop", dir = here))
#> Error : import_job(): '/tmp/RtmpaCi98t/import-job-here/20_distributions/ac.reop.hz.qmd' already exists; refusing to overwrite.
unlink(c(other, here), recursive = TRUE)
```
