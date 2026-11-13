# Adopt an existing study for descriptive and EDA work

This tutorial starts with an existing study directory and an existing
dataset. It sets the study up with `hvtiR::setup()`, then takes it
through data registration, descriptive tables and EDA plots. A later
tutorial can then begin with a specific analysis type instead of
repeating this setup.

[Start here](https://ehrlinger.github.io/hvtiR/articles/start-here.html)
is the family’s getting-started page and explains `setup()` in full.
This tutorial gives the call for a study that already exists.

Adoption keeps the study’s folder names and does not rename the legacy
working directories. It does delete files, including any file named
`tp.*`, even one you edited, so read [what adoption
deletes](#what-adoption-deletes) before you run it.

If the study does not exist yet and you are starting from a newly
delivered dataset, follow [Start a new
study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.md)
instead.

The executable example uses one 40-row synthetic dataset. Its files stay
in a temporary directory and disappear after the article renders. For
translating existing SAS descriptive jobs, see [From SAS descriptive
jobs to
R](https://ehrlinger.github.io/hvtiRtemplates/articles/sas-to-r-descriptive.md).

## Set up the study

### Select the R version

If the study already has an `renv.lock`, its `R` `Version` entry records
the R version to preserve. Select that version in RStudio and restart
the session. Do not silently upgrade an already pinned study. If the
study is not pinned, select **R 4.6** instead of the older 4.4.1
default, restart the session and confirm the active version:

``` r

R.version.string
```

### Run `hvtiR::setup()`

Close any open project first (**File \> Close Project**), so that R
starts outside the study. `setup()` replaces packages in the study’s
library, and a session inside the project has those packages loaded.
That is why the call names the directory with `root`.

#### What adoption deletes

Adopting deletes three kinds of file anywhere in the study, and makes no
backup:

- every file whose name starts with `tp.`, **matched by name alone**, so
  an edited or study-specific `tp.*` file goes too;
- every `binder.summaries.doc`;
- every other file whose name and exact content match one in the
  template corpus.

Before you run it, look through the study for `tp.*` files that hold
work of your own, and rename or copy any you need. To adopt without
deleting anything, add `cleanup = FALSE` to the call.

#### The call

``` r

install.packages("pak")  # once per machine
pak::pak("ehrlinger/hvtiR")

hvtiR::setup(
  study = "EDIT: the Study Tracker title",
  study_tracker_id = 0L,  # EDIT: the Study Tracker ID
  root = "EDIT: the study directory",
  adopt = TRUE,
  identity_source = "manual"
)
```

An existing directory needs `adopt = TRUE`, even an empty one, or
`setup()` stops. A study in revision needs `upgrade = FALSE` as well, so
that the versions its lockfile pins cannot move.

`identity_source = "manual"` records that you typed the title and ID, so
a new `_study.yml` is marked unverified rather than checked against
Study Tracker. A `_study.yml` the study already has is not rewritten,
and keeps its recorded source.

`setup()` writes `_study.yml` and a project file when one is missing,
declares the family and the standard analysis packages in the study’s
`DESCRIPTION`, installs them into the study’s own library and records
them in `renv.lock`, then restarts RStudio inside the project. If it
stops partway, fix what it names and run the same command again.

Do not run `renv::init()` or `organize_templates.sh` on the study:
`setup()` replaces both, and `renv::init()` starts the library over.

## Open the study as an RStudio Project

From here on, open the study’s `.Rproj` whenever you work on it. RStudio
starts the session in the project directory, so there is no
working-directory step to remember or repeat, and
[`study_root()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_root.html),
[`open_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/open_job.md)
and
[`render_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/render_job.md)
find `_study.yml` from anywhere inside the project.

Ask the study what it still needs, then attach the two packages used
throughout this tutorial:

``` r

library(hvtiRutilities)
library(hvtiRtemplates)

normalizePath(".")
study_root()
study_status()
hvtiR::status()
```

Expect
[`study_status()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_status.html)
to report that no dataset is registered yet. That is the next step.

When the Console is already at the study root, use `"."` anywhere a
function asks for `root`. The executable example below uses an explicit
temporary path only because it cannot open an RStudio Project while
pkgdown renders the page.

The executable example needs no package environment, so it calls
[`study_setup()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_setup.html),
the step of `setup()` that writes the study’s identity, in its temporary
directory:

``` r

# A vignette builds a throwaway study; in a real study, run hvtiR::setup().
study_setup(
  adopted_root,
  study = "Synthetic legacy study",
  study_tracker_id = 42L,
  adopt = TRUE,
  cleanup = FALSE,
  renv = FALSE
)
#> Study: /tmp/RtmpakMH5h/file20637bb4dc8f/legacy-study
#> 
#> [x] _study.yml — study: Synthetic legacy study
#> [ ] renv.lock — no renv.lock; set the study up with hvtiR::setup(study = "Synthetic legacy study", study_tracker_id = 42L, root = "/tmp/RtmpakMH5h/file20637bb4dc8f/legacy-study", adopt = TRUE), run with no project open, not renv::init(). Adopting deletes tp.* files: see hvtiR's "Start here" first
#> [ ] manifest.yaml — no manifest.yaml; register_data() creates it
#> [ ] dataset — no default dataset registered; run register_data()
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
root <- adopted_root
```

## Add a package the study needs

`setup()` has already pinned the package environment. When a study needs
a package the family and the standard set do not bring, add it from
inside the project. That installs it, declares it and records it in
`renv.lock`:

``` r

hvtiRutilities::study_need("cmprsk")
```

## Register the existing dataset

Registration records the input filename, checksum and population. It
does not declare a study-wide endpoint or cohort: an endpoint-free
descriptive job and an event-time analysis can read the same dataset
with different valid job definitions.

``` r

register_data(
  file = "built.csv",
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
  file = "built.csv",
  role = "study",
  population = "Synthetic full cohort"
)
#> Study: /tmp/RtmpakMH5h/file20637bb4dc8f/legacy-study
#> 
#> [x] _study.yml — study: Synthetic legacy study
#> [ ] renv.lock — no renv.lock; set the study up with hvtiR::setup(study = "Synthetic legacy study", study_tracker_id = 42L, root = "/tmp/RtmpakMH5h/file20637bb4dc8f/legacy-study", adopt = TRUE), run with no project open, not renv::init(). Adopting deletes tp.* files: see hvtiR's "Start here" first
#> [x] manifest.yaml — 1 dataset entry verified by checksum
#> [x] dataset — built.csv, registered as built_20261113.parquet
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
  file = "eda.csv",
  dataset = "eda",
  role = "named",
  kind = "subset",
  population = "Patients age 50 or older"
)
```

In a job that uses this subset, set `DATASET <- "eda"` and
`ANALYSIS_SET <- NULL`. When the whole registered study dataset is the
intended population, use `DATASET <- "built"` and `ANALYSIS_SET <- NULL`
instead. For a subset of the study dataset that several jobs share, an
analysis set is the alternative: write it with
[`hvtiRdatabuild::write_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/write_analysis_set.html)
and read it with `DATASET <- "built"` and the set’s name in
`ANALYSIS_SET`.

## Create the descriptive and EDA jobs

[`open_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/open_job.md)
creates a missing job and opens it in RStudio. If the job already
exists, it opens the study-authored file without replacing any edits.

### Understand the name

Each call supplies four fields. `prefix` and `qualifier` select a
template; the other two fields keep related outputs together:

- `dc` means descriptive: the checks, tables and EDA plots. Legacy
  studies also hold `dp` (descriptive plot) jobs, which these templates
  replace.
- Qualifiers such as `general`, `tables` and `eda` select one template
  in that family.
- During EDA there may be no modeled endpoint or analysis method.
  `cohort` names the subject being described and `eda` names the stage.
  These are organizational labels, not invented analysis choices.

For example, `open_job("dc", "cohort", "eda", qualifier = "tables")`
creates `descriptive/dc.tables.cohort.eda.qmd` in an adopted legacy
study. Its HTML report stays beside the QMD, while its Word table goes
under `documents/cohort-eda/`. The trends and EDA report jobs sit in
`descriptive/` too, and their plot PNGs go under `graphs/cohort-eda/`.

### Start with the generally applicable jobs

Create general checks and descriptive tables for every registered study:

``` r

general <- open_job("dc", "cohort", "eda", qualifier = "general")
tables <- open_job("dc", "cohort", "eda", qualifier = "tables")
```

The EDA report template is also part of this stage, but it requires a
meaningful `X_VAR` for the horizontal axis. Create it when the dataset
has an appropriate reference date, calendar year or follow-up measure:

``` r

eda <- open_job("dc", "cohort", "eda", qualifier = "eda")
```

Its follow-up section needs the death and follow-up fields; take
`"followup"` out of `SECTIONS` when the data do not have them;
`SECTIONS <- c("continuous", "percent", "count")` draws the variable
sections alone.

Two additional jobs are conditional. Add `dc-gfup` only when the
registered event and follow-up fields answer a real completeness
question. Add `dc-trends` only when the data have a meaningful calendar
or operation-time field:

``` r

gfup <- open_job("dc", "cohort", "eda", qualifier = "gfup")
trends <- open_job("dc", "cohort", "eda", qualifier = "trends")
```

The synthetic data have all of those fields, so the executable example
scaffolds all five jobs without opening editor windows:

``` r

study_jobs <- c(
  general = add_job("dc", "cohort", "eda", adopted_root, "general"),
  tables = add_job("dc", "cohort", "eda", adopted_root, "tables"),
  gfup = add_job("dc", "cohort", "eda", adopted_root, "gfup"),
  trends = add_job("dc", "cohort", "eda", adopted_root, "trends"),
  eda = add_job("dc", "cohort", "eda", adopted_root, "eda")
)
study_jobs
#>                                                                               general 
#> "/tmp/RtmpakMH5h/file20637bb4dc8f/legacy-study/descriptive/dc.general.cohort.eda.qmd" 
#>                                                                                tables 
#>  "/tmp/RtmpakMH5h/file20637bb4dc8f/legacy-study/descriptive/dc.tables.cohort.eda.qmd" 
#>                                                                                  gfup 
#>    "/tmp/RtmpakMH5h/file20637bb4dc8f/legacy-study/descriptive/dc.gfup.cohort.eda.qmd" 
#>                                                                                trends 
#>  "/tmp/RtmpakMH5h/file20637bb4dc8f/legacy-study/descriptive/dc.trends.cohort.eda.qmd" 
#>                                                                                   eda 
#>     "/tmp/RtmpakMH5h/file20637bb4dc8f/legacy-study/descriptive/dc.eda.cohort.eda.qmd"
```

## Work the jobs and generate output

Each new job contains `EDIT:` markers for decisions that cannot come
from the template: variables, labels, groups, units and output choices.
[`open_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/open_job.md)
opens the QMD in RStudio’s file editor. Edit the file there, working
from the top marker downward, and **Render** to see what your choices
do. A draft render carries a DRAFT banner while any marker remains.

Always render; do not run the chunks by hand with **Run All**. Rendering
starts at the top in a clean session, much like running a SAS job from
beginning to end, so the report comes from this job alone. Run All works
in your current session, where an object or a setting left by another
job can stand in for one this job does not make. Render every edited job
before leaving the study so the saved QMD is still in an executable
state. If you want the same final check from the Console, run
`render_job(tables, final = TRUE)`, substituting the job you edited.

The HTML report stays beside its QMD in `descriptive/`. The descriptive
Word table is filed under `documents/cohort-eda/`; trend and EDA PNGs
are filed under `graphs/cohort-eda/`. Open those artifacts and check the
population, variables, labels, counts, summaries and axes—not merely
that the files exist.

If the study has older SAS jobs, continue with [From SAS descriptive
jobs to
R](https://ehrlinger.github.io/hvtiRtemplates/articles/sas-to-r-descriptive.md).
That article owns the detailed source mapping and migration workflow so
adoption itself remains short.

### When registered data change

Registration is endpoint-neutral: it records the dataset file, its
population description and manifest facts, but does not declare a
study-wide endpoint or cohort. After the study dataset is rebuilt,
review the rebuilt file before registering it.
[`hvtiRutilities::review_built()`](https://ehrlinger.github.io/hvtiRutilities/reference/review_built.html)
compares the working file in the datasets folder with its registered
version and describes how the data changed, without writing anything. It
does not certify that the new file is analytically or clinically
correct; that judgment stays with you. When the review reads as
expected, `hvtiRutilities::update_manifest(dataset = "study")` registers
the rebuilt file as the next dated version, keeps every earlier version
and records the change in `manifest.yaml`. Jobs read the new version
from then on, so review dependent analysis sets and rerender their jobs.
