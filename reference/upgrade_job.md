# Rewrite a job from the current version of its template

Upgrades **one job**: the file you name in `path`. It does not look for
other jobs, so to upgrade several, call it once for each.

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

  The one job to upgrade: its `.qmd` file, relative to the working
  directory or absolute, such as
  `"10_descriptive/dc.general.cohort.eda.qmd"`.

- dir:

  Any directory in the study, used only to locate the study root.
  Defaults to the directory of `path`, which is right for any job inside
  its study.

## Value

The upgraded job's path, invisibly. The report is in the `_archive`
folder beside it.

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
edit, and every comment line above a carried choice that the current
template's comment lacks.

The one exception is the job's description. Where the template opens
with an `EDIT:` comment asking for it, the text the old job has in that
place is carried instead, once the study has deleted the comment's
marker. While the marker stands, the report names those lines for
review.

Both files go to `_archive` in the upgraded job's folder, created if it
is missing. Quarto renders nothing in a folder whose name starts with
`_`, and the old job's `.pre-upgrade` extension keeps it from being
rendered by hand too, which would write its figures over the current
job's. The old job keeps its own name before the stamp; the report takes
the upgraded job's. The upgraded job takes the name
[`add_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
would give it today, so a job named before 2026-10 moves to the
`.`-separated spelling. The report records the template, the package
version, the old job's checksum, and the choices carried, not placed and
new, with the chunks to review. It names choices and lines but never
quotes their values, since a value can identify a patient. The upgrade
refuses to overwrite any existing file.

## Upgrading a job

Name the job's `.qmd` file. From the study root, a cohort EDA job is

    upgrade_job("10_descriptive/dc.general.cohort.eda.qmd")

and several jobs are upgraded one call each:

    for (job in c("10_descriptive/dc.general.cohort.eda.qmd",
                  "10_descriptive/dc.general.cohort.gfup.qmd")) {
      upgrade_job(job)
    }

You never name the template: the job's file name says which one it is.
The job must sit inside its study; leave `dir` out unless you want to
name a different directory of the same study.

Afterwards, render the job and read its report, in the `_archive` folder
beside it as `<job>.<stamp>-upgrade.md`, for the chunks to check. The
old job is kept there too, as `<job>.<stamp>.pre-upgrade`, and the
stamp, the date and time of the upgrade, pairs the two. The job's own
folder is left holding the job, and the same job can be upgraded again
with nothing moved aside: each upgrade adds its own pair. A pair whose
stamp is already used, from an upgrade in the same second, takes a
shared `-2`, `-3` suffix after the stamp.

An upgrade before version 1.5.1 left its pair beside the job instead, as
`<job>.qmd.pre-upgrade` and `<job>-upgrade.md`. The next upgrade moves
such a pair into `_archive` under the same names, stamped with the time
of the upgrade that wrote it, read from the report. A copy renamed by
hand, such as `<job>.qmd.pre-upgrade-20261020`, is left where it is.

## See also

[`add_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md),
[`migrate_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/migrate_job.md)

## Examples

``` r
# \donttest{
root <- file.path(tempdir(), "upgrade-job-example")
invisible(hvtiRutilities::study_setup(root, "Example", 1L, renv = FALSE))
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
