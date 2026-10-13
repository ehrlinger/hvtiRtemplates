# Rewrite a job from the current version of its template

A job is a copy of its template as it stood on the day
[`add_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
wrote it. `upgrade_job()` writes the job again from the template as it
stands now and carries the study's choices across, so a job keeps up
with its template without re-entering every choice by hand.

## Usage

``` r
upgrade_job(path, dir = NULL)
```

## Arguments

- path:

  Path to the job, relative to the working directory or absolute.

- dir:

  Any directory in the study, used only to locate the study root.
  Defaults to the directory of `path`.

## Value

The upgraded job's path, invisibly. The report is written beside it.

## Details

The template is read from the job's file name, in either spelling
[`add_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
has used. A study's choices are the top-level assignments to an
upper-case name, such as `DATASET <- "built"`, in the job's `edit-*`
chunks. Each choice the current template also has replaces the
template's assignment, its source text unchanged, multi-line values
included. `SUBJECT` and `TYPE` are not carried: the file name owns them.
Where the job had resolved a choice's `EDIT:` marker, the upgraded job
drops the template's marker for it too.

Nothing is dropped silently. A choice the current template no longer has
is written, commented out, at the end of the template's
`edit-study-choices` chunk under a new `EDIT:` marker, so the job
renders as a draft until someone decides. Prose and code outside the
choices come from the current template, because without the template the
job was copied from an analyst's edit cannot be told from the old
template's text. The report lists every chunk that may hold such an
edit.

The old job is kept beside the new one as `<file>.pre-upgrade`, a name
nothing renders. The upgraded job takes the name
[`add_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
would give it today, so a job named before 2026-10 moves to the
`.`-separated spelling. The report is written beside the job, with the
`.qmd` extension replaced by `-upgrade.md`. It records the template, the
package version, the old job's checksum, and the choices carried, not
placed and new, with the chunks to review. It names choices and lines
but never quotes their values, since a value can identify a patient. The
upgrade refuses to overwrite any existing file.

## See also

[`add_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md),
[`migrate_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/migrate_job.md)

## Examples

``` r
# \donttest{
root <- file.path(tempdir(), "upgrade-job-example")
invisible(hvtiRutilities::study_setup(root, "Example", 1L))
job <- add_job("dc", "cohort", "eda", dir = root, qualifier = "general")
# A study choice, made in the job.
lines <- readLines(job)
lines <- sub('^DATASET <- "built"', 'DATASET <- "built_r"', lines)
writeLines(lines, job)
upgraded <- upgrade_job(job)
grep("^DATASET <- ", readLines(upgraded), value = TRUE)
#> [1] "DATASET <- \"built_r\""
unlink(root, recursive = TRUE)
# }
```
