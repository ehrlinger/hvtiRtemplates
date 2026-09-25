# Start a new study from a delivered dataset

This tutorial starts with an empty directory and an analysis dataset
that has just been delivered. It takes the study through setup, data
registration and a first descriptive job, then through one analysis
chain, so you can see how the templates hand work to one another.

If the study directory already exists and holds jobs and data, start
with [Adopt an existing
study](https://ehrlinger.github.io/hvtiRtemplates/articles/study-setup.md)
instead. That guide keeps the existing layout and files.

The executable example uses a 40-row synthetic dataset generated below.
Its files stay in a temporary directory and disappear after the article
renders.

## Before you start

A delivered dataset here means one analysis-ready file, CSV or SAS
transport, already built from the source extract. Building that file is
a separate step; this guide begins once it exists. Keep it on the study
share: patient data never enter a git repository.

The study itself must exist in Study Tracker before its directory does.
Create the study record there first and note its Study Tracker ID: every
later step takes its identity from that record.

## Create the study

Create the directory with the `study-setup` command from `qhsprograms`,
giving it the Study Tracker ID and the directory name. Preview first;
the dry run writes nothing:

``` sh
study-setup --dry-run 42 example_study
study-setup 42 example_study
```

`study-setup` reads the Tracker record, read-only, and turns the new
directory into a study. It writes `_study.yml`, which carries the
study’s name and Tracker ID, a README linking the Tracker record, an
RStudio project file, environment defaults, `renv`, and the numbered
folders every job is placed in:

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

Now open the directory in RStudio as a Project (**File \> New Project \>
Existing Directory**) and work from its `.Rproj` from then on. Select
the R version and load the hvtiR packages as described in [Adopt an
existing
study](https://ehrlinger.github.io/hvtiRtemplates/articles/study-setup.html#open-the-study-as-an-rstudio-project):

``` r

library(hvtiRutilities)
library(hvtiRtemplates)
```

Underneath, `study-setup` calls
[`hvtiRutilities::study_setup()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_setup.html)
with the Tracker record’s values. This article cannot reach Study
Tracker while it renders, so the executable example calls
[`study_setup()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_setup.html)
directly, in a temporary directory:

``` r

study_setup(new_root, study = "Synthetic new study", study_tracker_id = 42L)
#> Study: /tmp/RtmpGD1wmt/file1e5515995b1b/new-study
#> 
#> [x] _study.yml — study: Synthetic new study
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
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
  built = "built.csv",
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
  built = "built.csv",
  role = "study",
  population = "Synthetic full cohort"
)
#> Study: /tmp/RtmpGD1wmt/file1e5515995b1b/new-study
#> 
#> [x] _study.yml — study: Synthetic new study
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [x] manifest.yaml — 1 dataset entry verified by checksum
#> [x] dataset — built.csv
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
```

Registration names no endpoint and no cohort. Those belong to the jobs
that analyse them, so one registered dataset can serve every job in the
study.

## Scaffold the first EDA job

Start with the general descriptive checks:

``` r

general <- open_job("dc", subject = "cohort", type = "eda", qualifier = "general")
```

[`open_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/open_job.md)
creates the job and opens it in RStudio. The file is named
`<subject>-<type>-<prefix>-<qualifier>.qmd`, here
`10_descriptive/cohort-eda-dc-general.qmd`. The subject names what the
job is about and need not be a statistical endpoint: `cohort` describes
the whole registered population. The type names the stage, and the pair
keeps a set of related jobs and their outputs together.

The executable example scaffolds without opening an editor:

``` r

general <- add_job("dc", subject = "cohort", type = "eda", dir = new_root, qualifier = "general")
sub(paste0(new_root, "/"), "", general, fixed = TRUE)
#> [1] "10_descriptive/cohort-eda-dc-general.qmd"
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
sidecar beside it, `cohort-eda-dc-general.provenance.json`. An abridged
example from a synthetic study:

``` json
{
  "job": "cohort-eda-dc-general",
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
  "source": "10_descriptive/cohort-eda-dc-general.qmd",
  "subject": "cohort",
  "type": "eda",
  "output": { "file": "cohort-eda-dc-general.html", "sha256": "95455dd3..." }
}
```

Read it as a receipt. `data` names the registered file and the checksum
of the bytes the job read. `packages` and `renv_lock`, omitted here,
record every package version and the study’s lockfile. `output` carries
the checksum of the HTML it describes, so a sidecar can be matched to
its report and to nothing else.

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
#> "20_distributions/death-hz-ac.qmd" "20_distributions/death-hz-hz.qmd" 
#>                                 hp 
#>        "40_graphs/death-hz-hp.qmd"
```

The filenames read `death-hz-ac.qmd`, `death-hz-hz.qmd` and
`death-hz-hp.qmd`: subject, type, then the template. `hz` appears twice
in the second because the set is named for its method and the job is
that method’s template.

![](data:image/svg+xml;base64,PHN2ZyB2aWV3Ym94PSIwIDAgNjQwIDIxMCIgcm9sZT0iaW1nIiBhcmlhLWxhYmVsbGVkYnk9ImNoYWluLXRpdGxlIiBzdHlsZT0id2lkdGg6IDEwMCU7IGhlaWdodDogYXV0bzsgY29sb3I6IGluaGVyaXQ7IiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIGZvbnQtZmFtaWx5PSJzeXN0ZW0tdWksIHNhbnMtc2VyaWYiIGZvbnQtc2l6ZT0iMTMiPjx0aXRsZSBpZD0iY2hhaW4tdGl0bGUiPlRoZSBkZWF0aCBoYXphcmQgY2hhaW46IGFjIGFuZCBoeiBzYXZlIGhhbmRvZmZzIHRoYXQgaHAgcmVhZHM8L3RpdGxlPgo8ZGVmcz48bWFya2VyIGlkPSJhcnJvdyIgdmlld2JveD0iMCAwIDEwIDEwIiByZWZ4PSI5IiByZWZ5PSI1IiBtYXJrZXJ3aWR0aD0iNyIgbWFya2VyaGVpZ2h0PSI3IiBvcmllbnQ9ImF1dG8iPjxwYXRoIGQ9Ik0wLDAgTDEwLDUgTDAsMTAgeiIgZmlsbD0iY3VycmVudENvbG9yIiAvPjwvbWFya2VyPjwvZGVmcz48ZyBmaWxsPSJub25lIiBzdHJva2U9ImN1cnJlbnRDb2xvciIgc3Ryb2tlLXdpZHRoPSIxLjUiPjxyZWN0IHg9IjEwIiB5PSIyMCIgd2lkdGg9IjE1MCIgaGVpZ2h0PSI0NiIgcng9IjYiIC8+PHJlY3QgeD0iMTAiIHk9IjEzMCIgd2lkdGg9IjE1MCIgaGVpZ2h0PSI0NiIgcng9IjYiIC8+PHJlY3QgeD0iMjQ1IiB5PSIyMCIgd2lkdGg9IjE1MCIgaGVpZ2h0PSI0NiIgcng9IjYiIHN0cm9rZS1kYXNoYXJyYXk9IjQgMyIgLz48cmVjdCB4PSIyNDUiIHk9IjEzMCIgd2lkdGg9IjE1MCIgaGVpZ2h0PSI0NiIgcng9IjYiIHN0cm9rZS1kYXNoYXJyYXk9IjQgMyIgLz48cmVjdCB4PSI0ODAiIHk9Ijc1IiB3aWR0aD0iMTUwIiBoZWlnaHQ9IjQ2IiByeD0iNiIgLz48cGF0aCBkPSJNMTYwLDQzIEwyNDMsNDMiIG1hcmtlci1lbmQ9InVybCgjYXJyb3cpIiAvPjxwYXRoIGQ9Ik0xNjAsMTUzIEwyNDMsMTUzIiBtYXJrZXItZW5kPSJ1cmwoI2Fycm93KSIgLz48cGF0aCBkPSJNMzk1LDQzIEM0NDAsNDMgNDQwLDkwIDQ3OCw5NSIgbWFya2VyLWVuZD0idXJsKCNhcnJvdykiIC8+PHBhdGggZD0iTTM5NSwxNTMgQzQ0MCwxNTMgNDQwLDEwNiA0NzgsMTAxIiBtYXJrZXItZW5kPSJ1cmwoI2Fycm93KSIgLz48L2c+PGcgZmlsbD0iY3VycmVudENvbG9yIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIj48dGV4dCB4PSI4NSIgeT0iNDEiPmRlYXRoLWh6LWFjLnFtZDwvdGV4dD48dGV4dCB4PSI4NSIgeT0iNTgiIGZvbnQtc2l6ZT0iMTEiPmFjdHVhcmlhbCBsaWZlIHRhYmxlPC90ZXh0Pjx0ZXh0IHg9Ijg1IiB5PSIxNTEiPmRlYXRoLWh6LWh6LnFtZDwvdGV4dD48dGV4dCB4PSI4NSIgeT0iMTY4IiBmb250LXNpemU9IjExIj5wYXJhbWV0cmljIGhhemFyZDwvdGV4dD48dGV4dCB4PSIzMjAiIHk9IjQxIj5hYy5yZHM8L3RleHQ+PHRleHQgeD0iMzIwIiB5PSI1OCIgZm9udC1zaXplPSIxMSI+OTBfZXN0aW1hdGVzL2RlYXRoLWh6LzwvdGV4dD48dGV4dCB4PSIzMjAiIHk9IjE1MSI+aHoucmRzPC90ZXh0Pjx0ZXh0IHg9IjMyMCIgeT0iMTY4IiBmb250LXNpemU9IjExIj45MF9lc3RpbWF0ZXMvZGVhdGgtaHovPC90ZXh0Pjx0ZXh0IHg9IjU1NSIgeT0iOTYiPmRlYXRoLWh6LWhwLnFtZDwvdGV4dD48dGV4dCB4PSI1NTUiIHk9IjExMyIgZm9udC1zaXplPSIxMSI+b3ZlcmxheSBwbG90PC90ZXh0Pjx0ZXh0IHg9IjMyMCIgeT0iMjAwIiBmb250LXNpemU9IjExIj5lYWNoIGpvYiBhbHNvIHB1Ymxpc2hlcyBhIC5wcm92ZW5hbmNlLmpzb24gYmVzaWRlIGl0cyBIVE1MPC90ZXh0PjwvZz48L3N2Zz4=)

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
#> 1  dc-general     dc   general   descriptive
#> 2     dc-gfup     dc      gfup   descriptive
#> 3   dc-tables     dc    tables   descriptive
#> 4  dp-postage     dp   postage   descriptive
#> 5          ac     ac      <NA> distributions
#> 6          hz     hz      <NA> distributions
#> 7          bc     bc      <NA>      analyses
#> 8          bh     bh      <NA>      analyses
#> 9          bl     bl      <NA>      analyses
#> 10         br     br      <NA>      analyses
```

The other chains follow the same pattern: a fitting job saves a handoff
that later jobs read. The random forest jobs (`rfc`, `rfr`, `rfs`) pair
a `-fit` job with an `-explain` job; the logistic family (`lm`) fits and
validates outcome and propensity models; `bh` reports bootstrap variable
selection.
