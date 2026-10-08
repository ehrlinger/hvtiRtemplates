# Scaffold a new analysis job from a template

Copies a supported job template into the taxonomy folder it belongs to,
named `<subject>-<type>-<prefix>[-<qualifier>].qmd`. Refuses to
overwrite an existing job: a job file accumulates a study's edits, and
silently replacing one would discard them.

## Usage

``` r
add_job(prefix, subject, type, dir = NULL, qualifier = NULL)
```

## Arguments

- prefix:

  Job type: one of the prefixes reported by
  [`template_list`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_list.md),
  or a template's full name as reported in its `name` column, e.g.
  `"dp-trends"`. A full name carries the qualifier, so `qualifier` must
  then be left `NULL`.

- subject:

  Grouping topic for the job set, e.g. `"death"` or `"cohort"`. A
  subject names a statistical endpoint only when the job analyses one.
  Your choice: there is no list of valid values, and every job of one
  analysis should share it (see Details). Must match `^[A-Za-z0-9_]+$`:
  `-` separates the filename's fields and `.` separates the extension,
  so neither may appear here.

- type:

  The analysis type the job's set belongs to, e.g. `"hz"`. Your choice,
  like `subject`, and shared the same way. Must match `^[A-Za-z0-9_]+$`,
  for the same reason as `subject`.

- dir:

  The study root to write into. The taxonomy folder beneath it is
  created if it does not exist. `NULL`, the default, finds the study
  root by walking up from the working directory, and is an error outside
  a study, so a job is never written somewhere that is not a study.

- qualifier:

  Job type within the prefix, e.g. `"trends"` for `dp`. Required only
  where a prefix carries more than one template; omitting it there is an
  error naming the choices, never a silent pick. Restricted to
  `[A-Za-z0-9_]+`, because `-` separates the filename's fields.

## Value

The job's path, invisibly. On any failure – including one after the
copy, while substituting the set markers – no file is left behind, the
runner included, so a returned path always names a complete,
correctly-declared job.

## Details

**What each argument decides.** `prefix` chooses the template, together
with `qualifier` where a prefix carries several job types. `subject` and
`type` are yours to choose. The catalog holds no list of valid values
for either, only the rule that each matches `^[A-Za-z0-9_]+$`. They are
more than a filename, though. Together they name the job's set, and the
set is used in four places:

- the job's filename, `<subject>-<type>-<prefix>[-<qualifier>].qmd`;

- the job's own `SUBJECT` and `TYPE` lines, which `add_job()` rewrites
  to your values;

- the render, which stops when the filename and those two lines
  disagree, so a job renamed by hand cannot quietly write its results
  into another set;

- the folder the job saves its results in, a `<subject>-<type>` folder
  under the study's `estimates` (and, for some templates, `graphs`),
  which is where the next job in the chain looks for them.

The last of these is the one that bites. `hm` reads the `hz.rds` that
`hz` saved, and finds it only when both jobs carry the same subject and
type. Give every job of one analysis the same pair, e.g.
`subject = "death", type = "hz"` for `ac`, `hz`, `hm` and `hp`, and give
a different analysis a different pair. The `call` column of
[`template_list`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_list.md)
shows each template's own example values, which are a starting point,
not a requirement.

A job is identified by three or four fields. One or two come from the
template, its `prefix` and, where the prefix carries several job types,
its `qualifier`; two come from the caller. The pair `(subject, type)`
names the **set** the job belongs to, and both are required. The subject
is the grouping topic, not necessarily a statistical endpoint. An
endpoint-driven job may use `"death"`; an endpoint-free job may use
`"cohort"`, `"treatment"`, or `"labs"` without inventing an outcome. One
subject can be analyzed by several methods, and the jobs those chains
share would otherwise collide. A death-hazard set and a death
random-forest-survival set both begin from the same life table, so keyed
on the subject alone both would be written to one filename.

Scaffolding also installs the study's Quarto provenance hooks. Existing
pre-render and post-render commands and unrelated project settings are
preserved, while the provenance publisher is kept last. Repeated calls
are idempotent.

A template whose job runs from a companion script also writes that
script beside the job, from `inst/runners/<name>-runner.R`: today the
bootstrap reports `bl`, `br`, `bc` and `bh`, whose runner screens and
saves the bag the report reads. The runner is named
`<subject>-<type>-<prefix>-runner.R`, gets the same `SUBJECT` and `TYPE`
substitution, and is refused, like the job, if it already exists. Its
study choices carry `EDIT:` markers for the author to work.

A template the catalog marks deprecated, such as `dp-postage`, still
scaffolds, with a warning naming its replacement; see
[`template_catalog`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_catalog.md).

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

# A qualified template by its full name, the form template_list()$call prints.
add_job("dc-gfup", subject = "cohort", type = "eda", dir = d)

# A deprecated template still scaffolds, and the warning names its replacement.
tryCatch(add_job("dp-gfup", subject = "cohort", type = "eda", dir = d),
         warning = conditionMessage)
#> [1] "add_job(): dp-gfup is deprecated in favor of dc-gfup. It will be removed in a later release. add_job(\"dc-gfup\", subject = \"cohort\", type = \"eda\") draws the same panels with the same choices, beside the follow-up tables."

# A job accumulates a study's edits, so an existing one is never overwritten.
try(add_job(prefix = "ac", subject = "death", type = "hz", dir = d))
#> Error : add_job(): '/tmp/Rtmp9F51Ka/add-job-example/20_distributions/death-hz-ac.qmd' already exists; refusing to overwrite.

list.files(d, pattern = "[.]qmd$", recursive = TRUE)
#> [1] "10_descriptive/cohort-eda-dc-gfup.qmd"
#> [2] "20_distributions/death-hz-ac.qmd"     
unlink(d, recursive = TRUE)
```
