# Adopt an existing study for descriptive and EDA work

This tutorial starts with an existing study directory and an existing
dataset. It takes the study through identity setup, data registration,
descriptive tables and EDA plots. A later tutorial can then begin with a
specific analysis type instead of repeating this setup.

Adoption is additive. It creates the hvtiR study contract without
renaming the legacy working directories or deleting old files.

If the study does not exist yet and you are starting from a newly
delivered dataset, follow [Start a new
study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.md)
instead.

The executable example uses one 40-row synthetic dataset. Its files stay
in a temporary directory and disappear after the article renders. For
translating existing SAS descriptive jobs, see [From SAS descriptive
jobs to
R](https://ehrlinger.github.io/hvtiRtemplates/articles/sas-to-r-descriptive.md).

## Open the study as an RStudio Project

In RStudio, choose **File \> New Project \> Existing Directory** and
select the study directory. Open that `.Rproj` whenever you work on the
study. RStudio starts the session in the project directory, so there is
no working-directory step to remember or repeat.

Confirm the location before changing the study:

``` r

normalizePath(".")
```

When the Console is already at the study root, use `"."` anywhere a
function asks for `root`. The executable example below uses an explicit
temporary path only because it cannot open an RStudio Project while
pkgdown renders the page.

### Select the R version

If the study already has an `renv.lock`, its `R` `Version` entry records
the R version to preserve. Select that version in RStudio and restart
the session. Do not silently upgrade an already pinned study.

If the study is not already pinned, select **R 4.6** instead of the
older 4.4.1 default, restart the session and confirm the active version:

``` r

R.version.string
```

### Load the study packages

Install or update the hvtiR family, then check whether anything else is
missing or out of date:

``` r

pak::pak("ehrlinger/hvtiR")
hvtiR::status()
```

In the study session, attach the two packages used throughout this
tutorial:

``` r

library(hvtiRutilities)
library(hvtiRtemplates)
```

## Adopt the existing study

[`study_setup()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_setup.html)
writes `_study.yml`, environment defaults and a project file when one is
missing. With `adopt = TRUE`, it keeps the existing directory layout and
every existing study file. Use the title and ID from Study Tracker:

``` r

study_setup(
  root = ".",
  study = "Study title from Study Tracker",
  study_tracker_id = 42L,
  adopt = TRUE
)
study_root()
study_status()
```

The current API requires `root` for this first call. Here `"."` is the
project directory that RStudio established. Once `_study.yml` exists,
[`study_root()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_root.html),
[`open_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/open_job.md)
and
[`render_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/render_job.md)
find it from anywhere inside the project.

The executable example uses its temporary directory instead:

``` r

study_setup(
  adopted_root,
  study = "Synthetic legacy study",
  study_tracker_id = 42L,
  adopt = TRUE
)
#> Study: /tmp/RtmpRucm18/file21315db2ff15/legacy-study
#> 
#> [x] _study.yml — study: Synthetic legacy study
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [ ] manifest.yaml — no manifest.yaml; register_data() creates it
#> [ ] dataset — no default dataset registered; run register_data()
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
root <- adopted_root
```

## Pin the package environment

[`study_status()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.html)
reports a missing `renv.lock` until the study initializes its package
environment. For an unpinned study, do this after selecting R 4.6 and
restarting RStudio.

First open RStudio’s Terminal tab at the study root and run:

``` sh
organize_templates.sh
```

This `qhsprograms` script creates `templates/` under each first-level
study folder, moves that folder’s `tp*` files into it and replaces the
root `.renvignore` with the centrally managed copy used for dependency
discovery. Before running it, make sure a destination `templates/`
directory does not already contain a same-named file. Then return to the
Console:

``` r

renv::init()

# Install or update the packages used by the study, then record them.
renv::snapshot()
```

Snapshot again when an accepted result needs a new reproducible package
state. The temporary example does not run `renv::init()` because it
changes the active R project while the article renders.

## Register the existing dataset

Registration records the input filename, checksum and population. It
does not declare a study-wide endpoint or cohort: an endpoint-free
descriptive job and an event-time analysis can read the same dataset
with different valid job definitions.

``` r

register_data(
  built = "built.csv",
  role = "study",
  population = "Patients meeting the study inclusion criteria"
)
verify_manifest()
```

Do not invent an outcome or follow-up field during setup. Each analysis
job declares its own outcome variables, coding, filters and cohort
checks. The descriptive jobs below depend only on a registered study
dataset.

``` r

register_data(
  adopted_root,
  built = "built.csv",
  role = "study",
  population = "Synthetic full cohort"
)
#> Study: /tmp/RtmpRucm18/file21315db2ff15/legacy-study
#> 
#> [x] _study.yml — study: Synthetic legacy study
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [x] manifest.yaml — 1 dataset entry verified by checksum
#> [x] dataset — built.csv
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
verify_manifest(file.path(adopted_root, "manifest.yaml"))
cfg <- study_config(adopted_root)
study_data <- read_built(cfg)
nrow(study_data)
#> [1] 40
```

Compare the registered file and its manifest checksum with the data
build before proceeding. A job that filters this data, or analyses an
event and follow-up time, must derive and check its own reference
counts.

### If EDA uses a subset

The jobs can read the registered study dataset directly. If EDA needs a
subset, create it with a stated rule, save it as a separate dataset and
register that file too. For example:

``` r

study_data <- read_built(study_config())
eda <- subset(study_data, age >= 50)  # Replace with the study's actual rule.
utils::write.csv(
  eda, file.path(study_dir("datasets"), "eda.csv"), row.names = FALSE
)
register_data(
  built = "eda.csv",
  dataset = "eda",
  role = "named",
  population = "Patients age 50 or older"
)
```

In a job that uses this subset, set `DATASET <- "eda"` and
`ANALYSIS_SET <- NULL`. When the whole registered study dataset is the
intended population, use `DATASET <- "study"` and `ANALYSIS_SET <- NULL`
instead.

## Create the descriptive and EDA jobs

[`open_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/open_job.md)
creates a missing job and opens it in RStudio. If the job already
exists, it opens the study-authored file without replacing any edits.

### Understand the name

Each call supplies four fields. `prefix` and `qualifier` select a
template; the other two fields keep related outputs together:

- `dc` means descriptive computation and `dp` means descriptive plot.
- Qualifiers such as `general`, `tables` and `postage` select one
  template in that family.
- During EDA there may be no modeled endpoint or analysis method.
  `cohort` names the subject being described and `eda` names the stage.
  These are organizational labels, not invented analysis choices.

For example, `open_job("dc", "cohort", "eda", qualifier = "tables")`
creates `descriptive/cohort-eda-dc-tables.qmd` in an adopted legacy
study. Its HTML report stays beside the QMD, while its Word table goes
under `documents/cohort-eda/`. Plot jobs follow the same naming pattern,
but trend QMDs and HTML reports belong in `graphs/`, and plot PNGs go
under `graphs/cohort-eda/`.

### Start with the generally applicable jobs

Create general checks and descriptive tables for every registered study:

``` r

general <- open_job("dc", "cohort", "eda", qualifier = "general")
tables <- open_job("dc", "cohort", "eda", qualifier = "tables")
```

The EDA postage template is also part of this stage, but it requires a
meaningful `X_VAR` for the horizontal axis. Create it when the dataset
has an appropriate reference date, calendar year or follow-up measure:

``` r

postage <- open_job("dp", "cohort", "eda", qualifier = "postage")
```

Two additional jobs are conditional. Add `dc-gfup` only when the
registered event and follow-up fields answer a real completeness
question. Add `dp-trends` only when the data have a meaningful calendar
or operation-time field:

``` r

gfup <- open_job("dc", "cohort", "eda", qualifier = "gfup")
trends <- open_job("dp", "cohort", "eda", qualifier = "trends")
```

The synthetic data have all of those fields, so the executable example
scaffolds all five jobs without opening editor windows:

``` r

study_jobs <- c(
  general = add_job("dc", "cohort", "eda", adopted_root, "general"),
  tables = add_job("dc", "cohort", "eda", adopted_root, "tables"),
  gfup = add_job("dc", "cohort", "eda", adopted_root, "gfup"),
  trends = add_job("dp", "cohort", "eda", adopted_root, "trends"),
  postage = add_job("dp", "cohort", "eda", adopted_root, "postage")
)
study_jobs
#>                                                                               general 
#> "/tmp/RtmpRucm18/file21315db2ff15/legacy-study/descriptive/cohort-eda-dc-general.qmd" 
#>                                                                                tables 
#>  "/tmp/RtmpRucm18/file21315db2ff15/legacy-study/descriptive/cohort-eda-dc-tables.qmd" 
#>                                                                                  gfup 
#>    "/tmp/RtmpRucm18/file21315db2ff15/legacy-study/descriptive/cohort-eda-dc-gfup.qmd" 
#>                                                                                trends 
#>       "/tmp/RtmpRucm18/file21315db2ff15/legacy-study/graphs/cohort-eda-dp-trends.qmd" 
#>                                                                               postage 
#> "/tmp/RtmpRucm18/file21315db2ff15/legacy-study/descriptive/cohort-eda-dp-postage.qmd"
```

## Work the jobs and generate output

Each new job contains `EDIT:` markers for decisions that cannot come
from the template: variables, labels, groups, units and output choices.
[`open_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/open_job.md)
opens the QMD in RStudio’s file editor. Edit the file there, working
from the top marker downward. Use the chunk Run button as you work, then
choose **Run \> Run All** to generate the output in one interactive
pass.

When every marker is resolved, click **Render**. Rendering starts at the
top in a clean session, much like running a SAS job from beginning to
end. It catches a job that only worked because an object was left in the
interactive session. Render every edited job before leaving the study so
the saved QMD is still in an executable state. If you want the same
final check from the Console, run `render_job(tables, final = TRUE)`,
substituting the job you edited.

The HTML report stays beside its QMD in `descriptive/` or `graphs/`. The
descriptive Word table is filed under `documents/cohort-eda/`; trend and
postage PNGs are filed under `graphs/cohort-eda/`. Open those artifacts
and check the population, variables, labels, counts, summaries and
axes—not merely that the files exist.

If the study has older SAS jobs, continue with [From SAS descriptive
jobs to
R](https://ehrlinger.github.io/hvtiRtemplates/articles/sas-to-r-descriptive.md).
That article owns the detailed source mapping and migration workflow so
adoption itself remains short and non-destructive.

### When registered data change

Registration is endpoint-neutral: it records the dataset file, its
population description and manifest facts, but does not declare a
study-wide endpoint or cohort. For a catalog-pinned registration, first
review a published candidate with
[`hvtiRutilities::review_data_update()`](https://ehrlinger.github.io/hvtiRutilities/reference/review_data_update.html),
supplying its exact release ID. The review describes structural drift
without changing either manifest. After reviewing the candidate, call
[`hvtiRutilities::adopt_data_update()`](https://ehrlinger.github.io/hvtiRutilities/reference/adopt_data_update.html)
with that same exact release ID. Adoption repeats the review and updates
`_study.yml` and `manifest.yaml` together as a recoverable pair. Then
review dependent analysis sets and rerender their jobs.
