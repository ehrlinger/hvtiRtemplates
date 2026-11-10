# Start a new study from a delivered dataset

This tutorial starts before the study directory exists, with an analysis
dataset that has just been delivered. It sets the study up with
`hvtiR::setup()`, then takes it through data registration and a first
descriptive job, then through one analysis chain, so you can see how the
templates hand work to one another.

[Start here](https://ehrlinger.github.io/hvtiR/articles/start-here.html)
is the family’s getting-started page and explains `setup()` in full.
This tutorial gives the call for a new study.

If the study directory already exists and holds jobs and data, start
with [Adopt an existing
study](https://ehrlinger.github.io/hvtiRtemplates/articles/study-setup.md)
instead. That guide keeps the existing layout, and says which files
adoption deletes, `tp.*` among them.

The executable example uses a 40-row synthetic dataset generated below.
Its files stay in a temporary directory and disappear after the article
renders.

## Before you start

A delivered dataset here means one analysis-ready file, CSV or SAS
transport, already built from the source extract. Building that file is
a separate step; this guide begins once it exists. Keep it on the study
share: patient data never enter a git repository.

The study itself must exist in Study Tracker before its directory does.
Create the study record there first and note its title and ID. You type
both during setup: nothing reads them from Study Tracker when the study
is created.

An exploration of a registered study that Study Tracker has not
registered yet is the exception. Set it up with the registered study’s
ID as `derived_from`, in place of `study_tracker_id`, as [An exploration
of a registered
study](https://ehrlinger.github.io/hvtiR/articles/start-here.html#an-exploration)
describes.

## Create the study

On Posit Workbench, start a new RStudio Pro session and pick the latest
R version listed. If a project is open, close it (**File \> Close
Project**), so that R starts outside the study. Then name the new
directory with `root`:

``` r

install.packages("pak")  # once per machine
pak::pak("ehrlinger/hvtiR")

hvtiR::setup(
  study = "Example study",
  study_tracker_id = 42L,
  root = "/studies/example_study",
  identity_source = "manual"
)
```

`identity_source = "manual"` records that you typed the title and ID, so
`_study.yml` marks the identity unverified rather than checked against
Study Tracker.

Leave out `adopt` only when the directory does not exist yet. A
directory that already exists needs `adopt = TRUE`, even an empty one,
or `setup()` stops. An empty directory still gets the folders below.

`setup()` writes `_study.yml`, which carries the study’s name and
Tracker ID, a README, an RStudio project file and environment defaults.
It installs the family and the standard analysis packages into the
study’s own library, records them in `renv.lock`, restarts RStudio
inside the project, and makes the numbered folders every job is placed
in:

| folder             | holds                                     |
|--------------------|-------------------------------------------|
| `00_datasets`      | the registered data                       |
| `10_descriptive`   | descriptive tables and checks             |
| `20_distributions` | life tables and hazard models             |
| `30_analyses`      | multivariable and machine-learning models |
| `40_graphs`        | figures                                   |
| `50_documents`     | Word tables and manuscript material       |
| `90_estimates`     | saved output that other jobs read         |

`90_estimates` is numbered last on purpose. It holds results, not jobs,
and a job that needs another job’s result reads it from there.

Open the study’s `.Rproj` from then on, and attach the packages this
tutorial uses:

``` r

library(hvtiRutilities)
library(hvtiRtemplates)
```

### The `study-setup` command

The `study-setup` command from `qhsprograms` does the same job from a
terminal, through `hvtiR::setup()`. Preview first; the dry run writes
nothing:

``` sh
study-setup --dry-run --title "Example study" 42 example_study
study-setup --title "Example study" 42 example_study
```

It does not read Study Tracker, because that stopped on 2026-10-21. The
title and ID are what you typed, and the study records its identity as
manual and unverified. Only `study-setup --verify` reads Study Tracker,
to check that identity against the record:

``` sh
study-setup --verify /studies/example_study
```

This article has no server to install on while it renders, so the
executable example calls
[`hvtiRutilities::study_setup()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_setup.html)
directly, in a temporary directory, which makes the same study without a
package environment:

``` r

# A vignette builds a throwaway study; in a real study, run hvtiR::setup().
study_setup(new_root, study = "Synthetic new study", study_tracker_id = 42L,
            renv = FALSE)
#> Study: /tmp/RtmpbzJypP/file1fc721ddc2b9/new-study
#> 
#> [x] _study.yml — study: Synthetic new study
#> [ ] renv.lock — no renv.lock; set the study up with hvtiR::setup(study = "Synthetic new study", study_tracker_id = 42L, root = "/tmp/RtmpbzJypP/file1fc721ddc2b9/new-study", adopt = TRUE), run with no project open, not renv::init(). Adopting deletes tp.* files: see hvtiR's "Start here" first
#> [ ] manifest.yaml — no manifest.yaml; register_data() creates it
#> [ ] dataset — no default dataset registered; run register_data()
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
sort(list.files(new_root))
#> [1] "_study.yml"       "00_datasets"      "10_descriptive"   "20_distributions"
#> [5] "30_analyses"      "40_graphs"        "50_documents"     "90_estimates"    
#> [9] "new-study.Rproj"
```

## Register the dataset

Copy the delivered file into `00_datasets`, then register it.
Registration records the file’s size, checksum and the population it
describes in `manifest.yaml`:

``` r

register_data(
  file = "built.csv",
  role = "study",
  population = "Patients meeting the study inclusion criteria"
)
```

Every job reads data through this registration rather than through a
file path. That is what lets a rendered job record exactly which bytes
it read: a job that opens a path directly cannot tell you, a year later,
which version of the file it saw.

``` r

utils::write.csv(
  delivered, file.path(study_dir("datasets", new_root), "built.csv"), row.names = FALSE
)
register_data(
  new_root,
  file = "built.csv",
  role = "study",
  population = "Synthetic full cohort"
)
#> Study: /tmp/RtmpbzJypP/file1fc721ddc2b9/new-study
#> 
#> [x] _study.yml — study: Synthetic new study
#> [ ] renv.lock — no renv.lock; set the study up with hvtiR::setup(study = "Synthetic new study", study_tracker_id = 42L, root = "/tmp/RtmpbzJypP/file1fc721ddc2b9/new-study", adopt = TRUE), run with no project open, not renv::init(). Adopting deletes tp.* files: see hvtiR's "Start here" first
#> [x] manifest.yaml — 1 dataset entry verified by checksum
#> [x] dataset — built.csv, registered as built_20261110.parquet
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
```

Registration names no endpoint and no cohort. Those belong to the jobs
that analyze them, so one registered dataset can serve every job in the
study.

## Scaffold the first EDA job

Start with the general descriptive checks:

``` r

general <- open_job("dc", subject = "cohort", type = "eda", qualifier = "general")
```

[`open_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/open_job.md)
creates the job and opens it in RStudio. The file is named
`<prefix>.<qualifier>.<subject>.<type>.qmd`, here
`10_descriptive/dc.general.cohort.eda.qmd`. The subject names what the
job is about and need not be a statistical endpoint: `cohort` describes
the whole registered population. The type names the stage, and the pair
keeps a set of related jobs and their outputs together.

The executable example scaffolds without opening an editor:

``` r

general <- add_job("dc", subject = "cohort", type = "eda", dir = new_root, qualifier = "general")
sub(paste0(new_root, "/"), "", general, fixed = TRUE)
#> [1] "10_descriptive/dc.general.cohort.eda.qmd"
```

Each job carries `EDIT:` markers where the template cannot know the
study’s answer: variables, labels, groups. Work through them from the
top. A job that still contains one is unfinished.

The first
[`add_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
in a study also installs its provenance hooks. It adds pre-render and
post-render entries to `_quarto.yml`, keeping any settings already
there, and copies the hook scripts into `.hvtiR/hooks/`:

``` r

cat(readLines(file.path(new_root, "_quarto.yml")), sep = "\n")
#> project:
#>   pre-render:
#>     - ".hvtiR/hooks/hvti-provenance-pre-render.R"
#>   post-render:
#>     - ".hvtiR/hooks/hvti-provenance-post-render.R"
list.files(file.path(new_root, ".hvtiR"), recursive = TRUE)
#> [1] "hooks/hvti-provenance-post-render.R" "hooks/hvti-provenance-pre-render.R"
```

## Render and read the provenance

Render the job with the **Render** button, or from the Console:

``` r

render_job(general, final = TRUE)
```

Both run the same hooks. While the job executes it records what it read;
once Quarto has written the HTML, the post-render hook publishes a
sidecar beside it, `dc.general.cohort.eda.provenance.json`. An abridged
example from a synthetic study:

``` json
{
  "job": "dc.general.cohort.eda",
  "rendered": "2026-09-23T14:42:04Z",
  "study": { "name": "Synthetic new study", "file": "_study.yml", "sha256": "35f29fb1..." },
  "r": { "version": "4.6.1", "platform": "aarch64-apple-darwin23" },
  "data": [
    {
      "dataset": "study",
      "path": "00_datasets/built.csv",
      "role": "study",
      "bytes": 1051,
      "sha256": "3d6f6b0c..."
    }
  ],
  "artifacts": [],
  "source": "10_descriptive/dc.general.cohort.eda.qmd",
  "subject": "cohort",
  "type": "eda",
  "output": { "file": "dc.general.cohort.eda.html", "sha256": "95455dd3..." }
}
```

Read it as a receipt. `data` names the registered file and the checksum
of the bytes the job read. Its `dataset` says `"study"` although the job
says `DATASET <- "built"`: the two names mean the same dataset, and
records always use `"study"`, so a sidecar written by an older job
compares equal. `packages` and `renv_lock`, omitted here, record every
package version and the study’s lockfile. `output` carries the checksum
of the HTML it describes, so a sidecar can be matched to its report and
to nothing else.

If a render fails, the report and sidecar already on disk are left as
they were. A new sidecar is only ever published beside the HTML it
describes. One job renders at a time in a study; a second render started
while one is running stops and asks you to wait.

## A first analysis chain: death

Most analyses are chains: one job saves a result that the next reads.
The hazard chain has three jobs. `ac` computes the actuarial life table,
`hz` fits the parametric hazard model, and `hp` plots the two together.

``` r

open_job("ac", subject = "death", type = "hz")
open_job("hz", subject = "death", type = "hz")
open_job("hp", subject = "death", type = "hz")
```

All three share one subject and one type, and that is what connects
them. The pair `("death", "hz")` names a set, and each job writes and
reads its saved results in the set’s own folder,
`90_estimates/death-hz/`. `hp` finds `ac.rds` and `hz.rds` there without
a path to edit. A second analysis of the same endpoint, a random
survival forest say, takes a different type and so a different folder;
the two chains cannot overwrite each other’s life table.

``` r

chain <- c(
  ac = add_job("ac", subject = "death", type = "hz", dir = new_root),
  hz = add_job("hz", subject = "death", type = "hz", dir = new_root),
  hp = add_job("hp", subject = "death", type = "hz", dir = new_root)
)
sub(paste0(new_root, "/"), "", chain, fixed = TRUE)
#>                                 ac                                 hz 
#> "20_distributions/ac.death.hz.qmd" "20_distributions/hz.death.hz.qmd" 
#>                                 hp 
#>        "40_graphs/hp.death.hz.qmd"
```

The filenames read `ac.death.hz.qmd`, `hz.death.hz.qmd` and
`hp.death.hz.qmd`: the template, then subject and type, so a study’s
jobs sort by template. `hz` appears twice in the second because the set
is named for its method and the job is that method’s template.

![](data:image/svg+xml;base64,PHN2ZyB2aWV3Ym94PSIwIDAgNjQwIDIxMCIgcm9sZT0iaW1nIiBhcmlhLWxhYmVsbGVkYnk9ImNoYWluLXRpdGxlIiBzdHlsZT0id2lkdGg6IDEwMCU7IGhlaWdodDogYXV0bzsgY29sb3I6IGluaGVyaXQ7IiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIGZvbnQtZmFtaWx5PSJzeXN0ZW0tdWksIHNhbnMtc2VyaWYiIGZvbnQtc2l6ZT0iMTMiPjx0aXRsZSBpZD0iY2hhaW4tdGl0bGUiPlRoZSBkZWF0aCBoYXphcmQgY2hhaW46IGFjIGFuZCBoeiBzYXZlIGhhbmRvZmZzIHRoYXQgaHAgcmVhZHM8L3RpdGxlPgo8ZGVmcz48bWFya2VyIGlkPSJhcnJvdyIgdmlld2JveD0iMCAwIDEwIDEwIiByZWZ4PSI5IiByZWZ5PSI1IiBtYXJrZXJ3aWR0aD0iNyIgbWFya2VyaGVpZ2h0PSI3IiBvcmllbnQ9ImF1dG8iPjxwYXRoIGQ9Ik0wLDAgTDEwLDUgTDAsMTAgeiIgZmlsbD0iY3VycmVudENvbG9yIiAvPjwvbWFya2VyPjwvZGVmcz48ZyBmaWxsPSJub25lIiBzdHJva2U9ImN1cnJlbnRDb2xvciIgc3Ryb2tlLXdpZHRoPSIxLjUiPjxyZWN0IHg9IjEwIiB5PSIyMCIgd2lkdGg9IjE1MCIgaGVpZ2h0PSI0NiIgcng9IjYiIC8+PHJlY3QgeD0iMTAiIHk9IjEzMCIgd2lkdGg9IjE1MCIgaGVpZ2h0PSI0NiIgcng9IjYiIC8+PHJlY3QgeD0iMjQ1IiB5PSIyMCIgd2lkdGg9IjE1MCIgaGVpZ2h0PSI0NiIgcng9IjYiIHN0cm9rZS1kYXNoYXJyYXk9IjQgMyIgLz48cmVjdCB4PSIyNDUiIHk9IjEzMCIgd2lkdGg9IjE1MCIgaGVpZ2h0PSI0NiIgcng9IjYiIHN0cm9rZS1kYXNoYXJyYXk9IjQgMyIgLz48cmVjdCB4PSI0ODAiIHk9Ijc1IiB3aWR0aD0iMTUwIiBoZWlnaHQ9IjQ2IiByeD0iNiIgLz48cGF0aCBkPSJNMTYwLDQzIEwyNDMsNDMiIG1hcmtlci1lbmQ9InVybCgjYXJyb3cpIiAvPjxwYXRoIGQ9Ik0xNjAsMTUzIEwyNDMsMTUzIiBtYXJrZXItZW5kPSJ1cmwoI2Fycm93KSIgLz48cGF0aCBkPSJNMzk1LDQzIEM0NDAsNDMgNDQwLDkwIDQ3OCw5NSIgbWFya2VyLWVuZD0idXJsKCNhcnJvdykiIC8+PHBhdGggZD0iTTM5NSwxNTMgQzQ0MCwxNTMgNDQwLDEwNiA0NzgsMTAxIiBtYXJrZXItZW5kPSJ1cmwoI2Fycm93KSIgLz48L2c+PGcgZmlsbD0iY3VycmVudENvbG9yIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIj48dGV4dCB4PSI4NSIgeT0iNDEiPmFjLmRlYXRoLmh6LnFtZDwvdGV4dD48dGV4dCB4PSI4NSIgeT0iNTgiIGZvbnQtc2l6ZT0iMTEiPmFjdHVhcmlhbCBsaWZlIHRhYmxlPC90ZXh0Pjx0ZXh0IHg9Ijg1IiB5PSIxNTEiPmh6LmRlYXRoLmh6LnFtZDwvdGV4dD48dGV4dCB4PSI4NSIgeT0iMTY4IiBmb250LXNpemU9IjExIj5wYXJhbWV0cmljIGhhemFyZDwvdGV4dD48dGV4dCB4PSIzMjAiIHk9IjQxIj5hYy5yZHM8L3RleHQ+PHRleHQgeD0iMzIwIiB5PSI1OCIgZm9udC1zaXplPSIxMSI+OTBfZXN0aW1hdGVzL2RlYXRoLWh6LzwvdGV4dD48dGV4dCB4PSIzMjAiIHk9IjE1MSI+aHoucmRzPC90ZXh0Pjx0ZXh0IHg9IjMyMCIgeT0iMTY4IiBmb250LXNpemU9IjExIj45MF9lc3RpbWF0ZXMvZGVhdGgtaHovPC90ZXh0Pjx0ZXh0IHg9IjU1NSIgeT0iOTYiPmhwLmRlYXRoLmh6LnFtZDwvdGV4dD48dGV4dCB4PSI1NTUiIHk9IjExMyIgZm9udC1zaXplPSIxMSI+b3ZlcmxheSBwbG90PC90ZXh0Pjx0ZXh0IHg9IjMyMCIgeT0iMjAwIiBmb250LXNpemU9IjExIj5lYWNoIGpvYiBhbHNvIHB1Ymxpc2hlcyBhIC5wcm92ZW5hbmNlLmpzb24gYmVzaWRlIGl0cyBIVE1MPC90ZXh0PjwvZz48L3N2Zz4=)

Solid boxes are jobs; dashed boxes are the saved handoffs they share
through the set's folder.

Render in chain order: `ac`, then `hz`, then `hp`. Each saved handoff
carries its own lineage, the registered data it was built from, so `hp`
can check its inputs before it plots them. It stops, with a message
saying which job to rerun, when a handoff has no lineage or when `ac`
and `hz` were built from different data. Rerender both upstream jobs
after the registered data change. `hp`’s sidecar then lists the data
both handoffs were built from and each handoff’s checksum.

## Where to go next

[`template_list()`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_list.md)
lists every template with its prefix, qualifier and folder:

``` r

head(template_list()[, c("name", "prefix", "qualifier", "folder")], 10)
#>          name prefix qualifier        folder
#> 1          bd     bd      <NA>      datasets
#> 2      dc.eda     dc       eda   descriptive
#> 3  dc.general     dc   general   descriptive
#> 4     dc.gfup     dc      gfup   descriptive
#> 5  dc.stddiff     dc   stddiff   descriptive
#> 6   dc.tables     dc    tables   descriptive
#> 7   dc.trends     dc    trends   descriptive
#> 8          lg     lg      <NA>   descriptive
#> 9          ac     ac      <NA> distributions
#> 10         hz     hz      <NA> distributions
```

The other chains follow the same pattern: a fitting job saves a handoff
that later jobs read. The random forest jobs (`rfc`, `rfr`, `rfs`) pair
a `-fit` job with an `-explain` job; the logistic family (`lm`) fits and
validates outcome and propensity models; `bh` reports bootstrap variable
selection.
