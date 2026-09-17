# Migrate a legacy study to R jobs

Most studies already have a `datasets/` folder, SAS programs in
`descriptive/` and `graphs/`, and output in `documents/`. We will start
there. Adoption adds the study contract to that existing tree; the
legacy programs and their evidence remain in place.

This example creates its own disposable study with 40 synthetic
observations and a named 24-row subset. Every study file and job output
stays inside that temporary directory. During rendering, it is removed
after the R chunks run; the displayed figure is embedded before cleanup.
Run the chunks in order in one interactive session to inspect the files
yourself. For the statistical mapping behind these jobs, see [From SAS
descriptive jobs to
R](https://ehrlinger.github.io/hvtiRtemplates/articles/sas-to-r-descriptive.md).

The render steps require Quarto and the packages declared by the job
templates, including `hvtiRdatabuild >= 0.2.1`, `hvtiRtables >= 1.0.1`,
and `hvtiPlotR >= 2.7.14`. A missing or older dependency stops the
render and names the required version.

### Start with the legacy tree

The synthetic programs state the variables and dataset each job uses.
The listing, log, and small RTF supply evidence to read beside the first
migration report. They are newly written examples, so no patient records
are needed.

``` r

list.files(root, recursive = TRUE)
#>  [1] "datasets/built.csv"          "datasets/complete_cases.csv"
#>  [3] "descriptive/dc.gfup.sas"     "descriptive/dc.tables.log"  
#>  [5] "descriptive/dc.tables.lst"   "descriptive/dc.tables.sas"  
#>  [7] "descriptive/dp.postage.sas"  "distributions/ac.age.sas"   
#>  [9] "documents/general.rtf"       "graphs/dp.trends.sas"
```

### Adopt the study and register its data

The Study Tracker ID identifies the study. Here `42L` is part of the
synthetic example. Adoption keeps the bare folder names, then adds the
package-owned identity and environment files. Recovery of missing study
state is a separate operation.

``` r

study_setup(root, study = "Synthetic legacy study",
            study_tracker_id = 42L, adopt = TRUE)
#> Study: /tmp/RtmpNMyWdZ/file1c81628fe6f2
#> 
#> [x] _study.yml — study: Synthetic legacy study
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [ ] manifest.yaml — no manifest.yaml; register_data() creates it
#> [ ] dataset — no default dataset registered; run register_data()
#> [ ] cohort — requires a registered default dataset
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  5 .sas  |  0 provenance sidecars
register_data(root, built = "built.csv", event = "dead", time = "iv_dead",
              role = "study", population = "Synthetic full cohort")
#> Study: /tmp/RtmpNMyWdZ/file1c81628fe6f2
#> 
#> [x] _study.yml — study: Synthetic legacy study
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [x] manifest.yaml — 1 dataset entry verified by checksum
#> [x] dataset — built.csv
#> [x] cohort — N=40 / events=20 / censored=20
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  5 .sas  |  0 provenance sidecars
register_data(root, built = "complete_cases.csv", event = "dead",
              time = "iv_dead", dataset = "complete_cases",
              role = "named", population = "Synthetic complete cases")
#> Study: /tmp/RtmpNMyWdZ/file1c81628fe6f2
#> 
#> [x] _study.yml — study: Synthetic legacy study
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [x] manifest.yaml — 2 dataset entries verified by checksum
#> [x] dataset — built.csv
#> [x] cohort — N=40 / events=20 / censored=20
#> [x] dataset:complete_cases — complete_cases.csv
#> [x] cohort:complete_cases — N=24 / events=12 / censored=12
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  5 .sas  |  0 provenance sidecars
study_status(root)
#> Study: /tmp/RtmpNMyWdZ/file1c81628fe6f2
#> 
#> [x] _study.yml — study: Synthetic legacy study
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [x] manifest.yaml — 2 dataset entries verified by checksum
#> [x] dataset — built.csv
#> [x] cohort — N=40 / events=20 / censored=20
#> [x] dataset:complete_cases — complete_cases.csv
#> [x] cohort:complete_cases — N=24 / events=12 / censored=12
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  5 .sas  |  0 provenance sidecars
stopifnot(identical(unname(tools::md5sum(legacy_files)),
                    unname(legacy_checksums)))
```

Registration records the file checksum and cohort counts for each
dataset. The study cohort has 40 observations; the named subset has 24.
We use its first 24 rows only to make this example deterministic. A real
complete-case dataset needs a stated exclusion rule in its data build.

``` r

cfg <- study_config(root)
study_data <- read_built(cfg, dataset = "study")
subset_data <- read_built(cfg, dataset = "complete_cases")
study_counts <- cohort_counts(study_data, cfg, dataset = "study")
subset_counts <- cohort_counts(subset_data, cfg, dataset = "complete_cases")
cohorts <- data.frame(
  dataset = c("study", "complete_cases"),
  rows = c(study_counts$n, subset_counts$n),
  events = c(study_counts$n_events, subset_counts$n_events)
)
cohorts
#>          dataset rows events
#> 1          study   40     20
#> 2 complete_cases   24     12
```

The named registration preserves the study-wide counts. A job using
`complete_cases` must check that dataset’s contract; checking the 40-row
study contract cannot establish that a 24-row job cohort is correct.
Further filtering inside a job needs its own reference counts and
checks.

### Migrate one job at a time

Each call selects one template and its source-specific adapter. The
source supplies analysis choices; logs, listings and RTF/DOCX references
add evidence. Migration writes an editable QMD and a report beside it.
Existing jobs or reports stop the call, so keep your edited job when you
repeat this workflow.

#### Descriptive tables

The `%desc_tab` calls supply the variable groups and types. The migrated
job will write one editable Word table. Review the SAS presentation
choices before accepting its summary statistics and display.

``` r

tables <- migrate_job(
  file.path(root, "descriptive", "dc.tables.sas"), "cohort", "eda",
  reference = file.path(root, "documents", "general.rtf")
)
```

#### Goodness of follow-up

This job reads the registered event and follow-up fields. Confirm the
time units from the data build. Its recorded-interval checks do not
establish completeness against an administrative close date, and patient
identifiers remain disabled.

``` r

gfup <- migrate_job(file.path(root, "descriptive", "dc.gfup.sas"), "cohort", "eda")
```

#### Trends

The explicit year origin and interval expression define whole operation
years. `hv_trends()` owns the summaries and smoothing; compare these
figures with legacy output before treating a method change as
equivalent.

``` r

trends <- migrate_job(file.path(root, "graphs", "dp.trends.sas"), "cohort", "eda")
```

#### Postage stamps on the named subset

This source says `set complete_cases;`. The adapter resolves that name
to the registered subset, so this job reads 24 rows. It makes a panel
for each chosen variable and arranges the four panels on one PNG page.

``` r

postage <- migrate_job(file.path(root, "descriptive", "dp.postage.sas"), "cohort", "eda")
jobs <- c(tables = tables, gfup = gfup, trends = trends, postage = postage)
reports <- sub("[.]qmd$", "-migration.md", jobs)
```

### Read the reports and resolve the markers

Read all four reports before editing the jobs. They record translated
values, unresolved decisions, ignored source sections, checksums, and
evidence line numbers. This first report includes the synthetic listing,
log and RTF.

``` r

cat(paste(readLines(reports[["tables"]]), collapse = "\n"))
```

## Migration report

Template: hvtiRtemplates 1.2.0 / dc-tables

### Evidence (SHA-256)

- role=source; path=descriptive/dc.tables.sas;
  sha256=1aa30a2cc8b15d73e0f09f0f2a3bad2f0319f2d254e73ad11fe7f1841d5a3d2b

- role=lst; path=descriptive/dc.tables.lst;
  sha256=55a5ebd83a2506f36e1171a7864f1daaf3d5105aa949c1f6370c07d0d64c574e

- role=log; path=descriptive/dc.tables.log;
  sha256=4bfc496262d416507a38e7bfacda7d8e5ef3af9335a5ff0da608faa63f14aa8f

- role=reference; path=documents/general.rtf;
  sha256=aef1d9b9097bc8c16097eb50fb080ef50da3c8e65e4aafd39708e2e452f7fd18

- Listing: found beside source

- Log: found beside source

### Translated

- line=2; text=category: female, race_grp, repair; reason=Declared
  vartype and source row order.
- line=2; text=\[heading\]: female, race_grp; reason=Source comment
  heading and grouped rows.
- line=2; text=\[heading\]: repair; reason=Source comment heading and
  grouped rows.
- line=4; text=continuous: age, bmi, iv_dead; reason=Declared vartype
  and source row order.
- line=4; text=\[heading\]: age, bmi; reason=Source comment heading and
  grouped rows.
- line=4; text=\[heading\]: iv_dead; reason=Source comment heading and
  grouped rows.
- line=2; text=input=built; reason=Selected registered dataset study by
  key or filename stem.
- line=2; text=by=; reason=BY selects a column, not a comparison test or
  a subset of levels.
- line=2; text=BINARY: female, repair; CATEGORICAL: race_grp;
  reason=Classification from registered dataset study (binary requires
  observed numeric 0 and 1; categorical requires at least two other
  observed levels).

### Unresolved

- line=1; text=title “\[string\]”;; reason=Review title against the
  combined Word table.
- line=1; text=documents/general.rtf; reason=RTF content withheld;
  review the referenced source line locally.
- line=NA; text=compare, continuous_stat, percentiles, abbreviations,
  Word filename; reason=Template defaults require review; SAS options do
  not prove these choices.

### Ignored

None recorded.

### Log findings

- line=1; severity=note; category=observation_note; error_code=NA;
  observations=40; variables=NA; path=descriptive/dc.tables.log;
  text=SAS log message content withheld; review the source locally.

### Listing facts

- line=1; text=Nonblank listing line; content withheld. Review the
  source locally.
- line=2; text=Nonblank listing line; content withheld. Review the
  source locally.
- line=3; text=Nonblank listing line; content withheld. Review the
  source locally.
- line=4; text=Nonblank listing line; content withheld. Review the
  source locally.

### Completion checklist

Resolve every EDIT: marker using the source evidence.

Review log errors and warnings before interpreting results.

Confirm the registered dataset and the job’s analysis cohort.

Render the job and compare its outputs with the supplied references.

For this synthetic example we accept the migrated groups, the whole
cohort for the first three jobs, and the named subset for postage. We
choose no group comparison, median summaries with the 15th and 85th
percentiles, no table abbreviations or correlations, and
`dc-tables.docx` as the Word filename. Follow-up intervals are years and
no extra event cross-tabs are needed. The trend figures use the stated
year origin, breaks and variable labels with no subgroup filter. Postage
uses the four stated variables and a 2-by-2 grid.

The following helper acknowledges only exact, reviewed comment lines. It
is a way to repeat these synthetic decisions while rendering this
article. In a study job, edit each marked choice against the source and
protocol, then remove that marker. Replacing every marker without review
can turn an incomplete migration into a misleading finished report.

``` r

acknowledge <- function(job, reviewed_lines) {
  text <- readLines(job, warn = FALSE)
  stopifnot(all(reviewed_lines %in% text))
  selected <- text %in% reviewed_lines
  text[selected] <- gsub("EDIT:", "REVIEWED:", text[selected], fixed = TRUE)
  writeLines(text, job)
}
```

Code

``` r

acknowledge(tables, c(
  "<!-- EDIT: name the job this replaces (descriptive/dc.tables.*) and say whether it",
  "# EDIT: the built dataset this job reads. \"study\" is the file named by built:",
  "# EDIT: the analysis set this job reads: the columns and excluded rows declared",
  "# EDIT: the variables to report, grouped. Each name is a section heading and",
  "# EDIT: review SAS presentation choices in the migration report.",
  "# EDIT: confirm comparison, summaries, percentiles, abbreviations and Word filename.",
  "# EDIT: force a bucket where the data guess wrong, e.g. an ordinal score you",
  "# EDIT: NULL skips the correlation variant (dc.tables.ods_<topic>.sas). To run"
))
acknowledge(gfup, c(
  "<!-- EDIT: name the job this replaces (descriptive/dc.gfup). -->",
  "# EDIT: the built dataset this job reads. \"study\" is the file named by built:",
  "# EDIT: the analysis set this job reads: declare its columns and excluded rows",
  "# EDIT: review unresolved migration evidence and confirm follow-up units in years.",
  "# EDIT: optional event-coding cross-tabs, each a vector of column names."
))
acknowledge(trends, c(
  "<!-- EDIT: name the job this replaces (an older graphs/dp.trends job) and list",
  "# EDIT: the calendar year of operation, as a WHOLE year. hv_trends() puts one",
  "# EDIT: one entry per figure. `cols` are the columns drawn together: several",
  "# EDIT: optional. x-axis breaks shared by every figure, e.g. seq(1985, 2025, 5).",
  "# EDIT: optional. Each entry is a filter, given as a function of the data that",
  "# EDIT: review source filters and subgroup intent before accepting the whole cohort."
))
acknowledge(postage, c(
  "<!-- EDIT: name the job this replaces (tp.dp.EDA_barplots_scatterplots*.R). -->",
  "# EDIT: the built dataset this job reads. \"study\" is the file named by built:",
  "# EDIT: the analysis set this job reads: declare its columns and excluded rows",
  "# EDIT: review unresolved postage source choices in the migration report."
))
```

``` r

remaining <- vapply(jobs, function(job) {
  sum(grepl("EDIT:", readLines(job), fixed = TRUE))
}, integer(1L))
remaining
#>  tables    gfup  trends postage 
#>       0       0       0       0
stopifnot(all(remaining == 0L))
```

### Render and inspect the output

[`render_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/render_job.md)
renders each job from its own directory so its guard can read the
authored QMD. A job with a marker left renders as a draft by default;
`final = TRUE` makes an unresolved marker stop the render instead, which
is what an accepted result requires.

``` r

for (job in jobs) {
  render_job(job, final = TRUE, quiet = FALSE)
}
#> [31m
#> 
#> processing file: cohort-eda-dc-tables.qmd
#> [39m1/17              
#> 2/17 [setup]      
#> 3/17              
#> 4/17 [edit-guard] 
#> 5/17              
#> 6/17 [set]        
#> 7/17              
#> 8/17 [data]       
#> 9/17              
#> 10/17 [spec]       
#> 11/17              
#> 12/17 [helpers]    
#> 13/17              
#> 14/17 [table]      
#> 15/17              
#> 16/17 [correlation]
#> 17/17              
#> [31moutput file: cohort-eda-dc-tables.knit.md
#> 
#> [39m[1mpandoc [22m
#>   to: html
#>   output-file: cohort-eda-dc-tables.html
#>   standalone: true
#>   embed-resources: true
#>   section-divs: true
#>   html-math-method: mathjax
#>   wrap: none
#>   default-image-extension: png
#>   toc: true
#>   toc-depth: 3
#>   
#> [1mmetadata[22m
#>   document-css: false
#>   link-citations: true
#>   date-format: long
#>   lang: en
#>   title: Descriptive tables
#>   theme: cosmo
#>   
#> Output created: cohort-eda-dc-tables.html
#> 
#> [31m
#> 
#> processing file: cohort-eda-dc-gfup.qmd
#> [39m1/15             
#> 2/15 [setup]     
#> 3/15             
#> 4/15 [edit-guard]
#> 5/15             
#> 6/15 [set]       
#> 7/15             
#> 8/15 [data]      
#> 9/15             
#> 10/15 [spec]      
#> 11/15             
#> 12/15 [qc]        
#> 13/15             
#> 14/15 [checks]    
#> 15/15             
#> [31moutput file: cohort-eda-dc-gfup.knit.md
#> 
#> [39m[1mpandoc [22m
#>   to: html
#>   output-file: cohort-eda-dc-gfup.html
#>   standalone: true
#>   embed-resources: true
#>   section-divs: true
#>   html-math-method: mathjax
#>   wrap: none
#>   default-image-extension: png
#>   toc: true
#>   toc-depth: 3
#>   
#> [1mmetadata[22m
#>   document-css: false
#>   link-citations: true
#>   date-format: long
#>   lang: en
#>   title: Goodness of follow-up
#>   theme: cosmo
#>   
#> Output created: cohort-eda-dc-gfup.html
#> 
#> [31m
#> 
#> processing file: cohort-eda-dp-trends.qmd
#> [39m1/15             
#> 2/15 [setup]     
#> 3/15             
#> 4/15 [edit-guard]
#> 5/15             
#> 6/15 [set]       
#> 7/15             
#> 8/15 [data]      
#> 9/15             
#> 10/15 [trends]    
#> 11/15             
#> 12/15 [helpers]   
#> 13/15             
#> 14/15 [figures]   
#> 15/15             
#> [31moutput file: cohort-eda-dp-trends.knit.md
#> 
#> [39m[1mpandoc [22m
#>   to: html
#>   output-file: cohort-eda-dp-trends.html
#>   standalone: true
#>   embed-resources: true
#>   section-divs: true
#>   html-math-method: mathjax
#>   wrap: none
#>   default-image-extension: png
#>   toc: true
#>   toc-depth: 3
#>   
#> [1mmetadata[22m
#>   document-css: false
#>   link-citations: true
#>   date-format: long
#>   lang: en
#>   title: Trends over operation year
#>   theme: cosmo
#>   
#> Output created: cohort-eda-dp-trends.html
#> 
#> [31m
#> 
#> processing file: cohort-eda-dp-postage.qmd
#> [39m1/15             
#> 2/15 [setup]     
#> 3/15             
#> 4/15 [edit-guard]
#> 5/15             
#> 6/15 [set]       
#> 7/15             
#> 8/15 [data]      
#> 9/15             
#> 10/15 [spec]      
#> 11/15             
#> 12/15 [helpers]   
#> 13/15             
#> 14/15 [pages]     
#> 15/15             
#> [31moutput file: cohort-eda-dp-postage.knit.md
#> 
#> [39m[1mpandoc [22m
#>   to: html
#>   output-file: cohort-eda-dp-postage.html
#>   standalone: true
#>   embed-resources: true
#>   section-divs: true
#>   html-math-method: mathjax
#>   wrap: none
#>   default-image-extension: png
#>   toc: true
#>   toc-depth: 3
#>   
#> [1mmetadata[22m
#>   document-css: false
#>   link-citations: true
#>   date-format: long
#>   lang: en
#>   title: EDA postage stamps
#>   theme: cosmo
#>   
#> Output created: cohort-eda-dp-postage.html
```

The authored jobs and migration reports stay flat in their legacy
folders. Generated figures and the Word table go under the `cohort-eda/`
output set. Check both the artifact paths and their contents: a file
existing is only the first check. The Word structural check catches
document-format defects; it does not prove numerical agreement with SAS.

``` r

outputs <- list.files(root, pattern = "[.](html|docx|png)$", recursive = TRUE)
outputs
#> [1] "descriptive/cohort-eda-dc-gfup.html"        
#> [2] "descriptive/cohort-eda-dc-tables.html"      
#> [3] "descriptive/cohort-eda-dp-postage.html"     
#> [4] "documents/cohort-eda/dc-tables.docx"        
#> [5] "graphs/cohort-eda-dp-trends.html"           
#> [6] "graphs/cohort-eda/dp-postage-page-01.png"   
#> [7] "graphs/cohort-eda/dp-trends-hx_chf-all.png" 
#> [8] "graphs/cohort-eda/dp-trends-lvmassi-all.png"
word <- file.path(root, "documents", "cohort-eda", "dc-tables.docx")
png <- file.path(root, "graphs", "cohort-eda", "dp-postage-page-01.png")
stopifnot(file.exists(word), file.exists(png))
hvtiRtables::hv_check_docx(word)
#> [1] type     table    location detail  
#> <0 rows> (or 0-length row.names)
# Embed while the PNG exists; study cleanup runs before HTML conversion.
knitr::asis_output(paste0(
  '<img src="', knitr::image_uri(png),
  '" alt="Postage stamp plots for the named subset">'
))
```

![Postage stamp plots for the named
subset](data:image/png;base64,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5pjx48dv2bJljz32KCsrS7siAIBit/fee3//+99ft25d586du3XrlnY5AMCfEavxZ7p37969e/e0qwAA4A86der0qU99Ku0qAIBt8CVQAAAAAIgmVgMAAACAaGI1AAAAAIgmVgMAAACAaGI1AAAAAIgmVgMAAACAaGI1AAAAAIgmVgMAAACAaGI1AAAAAIiWp7HaP/3TP2UymWuuuabZ8rq6umnTpg0cOLBPnz7nnHPOhg0bUikPAKBAVVVVzZo169BDD+3WrdvIkSNvuumm2traZttEdVzaMwCgaOVjrLZkyZLZs2eXlJQ0NDQ0XZ7NZo8++ugFCxa8+eabK1eu7NGjx/77719dXZ1WnQAABWfKlCmzZs26++67N2zYMG/evCeffHLcuHFNm66ojkt7BgAUs7yL1erq6o455pj777+/a9euzVa9+OKLc+fOnT17dteuXcvLy6+44orNmzfPmTMnlToBAArRxIkT582bN3To0NLS0n79+s2ZM+eFF154+eWXGzeI6ri0ZwBAMcu7WO3aa68dOXLkuHHjtl71yCOPjBgxomfPnrmXpaWlxx9//IwZM9q1PgCAQjZhwoTS0j91gL179w4hLFu2rHFJVMelPQMAill+xWrLli279NJLZ82atc218+fPP+SQQ5ouGTt27MKFC7PZbLtUBwDQ0bzyyishhMGDBzcuieq4tGcAQDHrlHYBf9LQ0DBhwoQbb7zxU5/61DY3eO+998aPH990Sb9+/UIINTU1FRUVuSWrV6/+yU9+EkKoq6sbOnTo22+/nXDVAACFqq6ubvLkyaNGjTrggAMaF+5MxxW78c9//vOFCxeuWbNm6NCh69atW7NmTZt/FgCA9pdHsdqtt966YcOG7373u7FvbPrn0Orq6iVLluT+vfXd2QAAyMlms1OmTFm6dGllZWXTr4W2sH3Uzpu+XLFixZIlS2pra7t27bpp06boWgEA8lK+xGqffPLJOeecs3Dhwk6dtlvSPvvs8+GHHzZdsnr16hBC07+FDhw48L/+679CCF/4whdefPHFEMJbb7113HHHJVU3ANDhHHLIIRdeeGHaVSTuiiuumDlz5qJFiwYNGtR0+c50XLEbX3jhhRdeeOG8efMaL22bNm3a3Xff3QYfAwAoDtdff/2QIUPSrmIr2fywatWqEEJZWVn5H+XKKy8vX7ZsWW6b888/f9SoUU3fdeaZZ44dO3abOzz44INT/e8KABSq448/PvHWJ2133nlnCOGZZ57ZelVUxxW18a9+9au0zy0AUKhefPHFXW18EpQvsdrWevXqdeWVVzZd8pvf/CaEsH79+tzL+vr6vn373nbbbdt8++9+97uVK1cmekaHDh06YsSIRA9BwRkxYsSwYcPSroL8MnLkyKb3AocQwmc+85l999037SrYrg4fqz355JMhhIceemiba6M6rqiNq6urV65cefHFFyd37rp16zZ69Ojdd989uUNQcHr06DF69OjG59VCCGH33XcfPXp0t27d0i6EPNK7d+/Ro0d36dIl7ULYrvyM1fLlS6BbKykpaXabj4MOOuhLX/rSt7/97dmzZ5eXl1911VWlpaWTJ0/e5ttzT4tP9H9aunbtWlJS4v+LaKpz587ZbNaooKnddtutvLzcqKCpTCbTvXt3oyJv9e3bN+0SErRo0aKjjz56+vTpJ5xwwjY3aLnjeuedd0aMGLFgwYLPfe5zO9y4mUwms+eee+69997JDf7clx769u0rQ6FRblT069dP3kqjioqK8vLyvfbaq7a2Nu1ayBe5pr1///51dXVp18K2ZTKZtEvYhvyN1bZWUlLy7LPPXnXVVZ/+9Kc3b978tflFF3IAACAASURBVK997Y033ujcuXMLb3nnnXeSq+cf/uEfPvnkk0ceeSS5Q1BwTjzxxM6dO8+ePTvtQsgjRx111L777nvrrbemXQh5ZNy4cZ///Oevu+66tAuhGF100UUhhDPPPLPpc6J+9rOfnXHGGbl/t9xxZbPZ2tra7B+fSLAL7dlZZ5111llnJfLZQnjppZemTJlyww03HH300QkdgoLz/PPPn3feebfffnuzp9ZSzJ5++ulLL7303nvvPeigg9KuhXzxyCOPXH311b/4xS9GjRqVdi0UkvyN1dauXbv1wvLy8qlTp06dOrXdywEA6Aiee+65HW7TQsc1ePDg7J8/5VN7BgAUrZJszLPSaer//u//6uvrJdk09frrr5eWlu63335pF0Ieee211yoqKoYPH552IeSRV155pUePHm66B23uk08+qaysHDRoUO5+IBBCWL9+/dKlSwcPHtyrV6+0ayFfrF279t133x06dGiPHj3SroV88fHHH3/wwQcjRozo2rVr2rVQSMRqAAAAABCtdMebAAAAAAB/TqwG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b7752muvTbcqAIB8FtULbdq0aeLEibkr1GpqaqZPn37bbbfts88++++/f9jVZgwAIEqRxmq9evV67rnnQgjf+MY3evbsWVJSUlpa2qNHj8MOO+yFF15o/f7PPvvsEMJpp52WyWRKSkp69ep1/vnnX3bZZelWBQCQz6J6oW9+85tLlizp27dvSUlJRUXFlClTSktLn3jiidxXOHetGQMAiFKksVoI4dBDD129evWVV145ZsyYsrKyXr16feUrX5kxY8bjjz/e+p0PHjx4yZIlxx133G677da7d+9JkyZVVlYec8wx6VYFAJDndr4XGj58+OLFi88+++y+fft26dLl5JNPXrZsWe4ZoKEVzRgAwM4ryT22HAAACsLatWt79+79k5/85OKLL067FgCgqBXv1WoAAAAAsMvEagAAAAAQTawGAAAAANHcWw0AAAAAorlaDQAAAACiidUAAAAAIJpYDQAAAACiidUAAAAAIJpYDQAAAACiidUAAAAAIJpYDQAAAACiddhYbdKkSWPGjBkzZsykSZPSrgUAgPDiiy+O+aNf/epXaZcDANBandIuICmVlZWLFy8OIXTu3DntWgAACBs3bsy1ZyGEDRs2pFsMAEDrddir1QAAAAAgOWI1AAAAAIgmVgMAAACAaGI1AAAAAIgmVgMAAACAaGI1AAAAAIgmVgMAAACAaGI1AAAAAIgmVgMAAACAaGI1AAAAAIgmVgMAAACAaGI1AAAAAIgmVgMAAACAaGI1AAAAAIgmVgMAAACAaIUUqzU0NDzzzDPHHntsz549Bw4ceM4553z44YdpFwUAULy0ZwBAMSukWG3RokXvvvvuzJkzf//737/++us9e/b89Kc//bvf/S7tugAAipT2DAAoZoUUq/3lX/7l6aef3rt375KSku7du19++eXZbPaRRx5Juy4AgCKlPQMAilkhxWrNlJSUlJSUdO7cOe1CAAAIQXsGABSZTmkXsIuqq6tvueWWvn37fvWrX027FgAAtGcAQNEpvFjtG9/4xv33319fX7/33nu/+OKL3bp1a7p29erVV155ZQihrq5u6NChb7/9dkplAgAUi5bbsxDCfffdt2DBgrVr1w4dOnTdunVr1qxJpU4AgLZVeLHanDlz7rnnno0bN958882DBw9+/fXXBw0a1Li2urr6zTffDCFks9kuXbqkV2YKqi/6Xtol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9OnT2782AICEFN691e66667LLrvsmWee8YQpAIB8oD0DAIpTgcVqTz311Omnn/7QQw995StfSbsWAAC0ZwBA8SqkWG3RokVHH3309OnTcw8lAAAgXdozAKCYFVKsdtFFF4UQzjzzzEwTt99+e9p1AQAUKe0ZAFDMCumRBc8991zaJQAA8CfaMwCgmBXS1WoAAAAAkCfEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANHEagAAAAAQTawGAAAAANGSitU+//nPRy0HACCWjgsAIEVJxWqLFy+OWg4AQCwdFwBAitr1S6AfffTR3nvv3Z5HBAAoNjouAID20anN9zhkyJC6urra2tqBAweWlv4pttuyZcvq1aunTZvW5kcEACg2Oi4AgNS1faz24x//xW7kngAAIABJREFUuKGhYdKkSVdeeWXTJq9Tp04jR4787Gc/2+ZHBAAoNjouAIDUtX2sduqpp4YQNm3aNHny5DbfOQAAQccFAJAHkrq32hlnnJHQngEAyNFxAQCkqF0fWQAAAAAAHUPbfwm00QcffPDYY4/97//+75YtW5ouv//++5M7KABAUdFxAQCkJalY7fnnn//rv/7rv/iLvxg/fny/fv0SOgoAQDHTcQEApCipWO2cc855/PHHjz322IT2DwCAjgsAIEVJ3Vvt/fff//u///uEdg4AQNBxAQCkKqlY7bTTTlu5cmVCOwcAIOi4AABSlVSsdvXVV8+ePfu9995LaP8AAOi4AABSlNS91Q488MCqqqpLLrmkR48e/fv3Ly39U363ZMmShA4KAFBUdFwAAClK8JEFDQ0NCe0cAICg4wIASFVSsdrpp5+e0J4BAMjRcQEApCipe6sBAAAAQAeW1NVql1xySX19/TZXXX311QkdFACgqOi4AABSlFSs9v7779fV1eX+3dDQsHz58hdeeOGwww7r06dPQkcEACg2Oi4AgBQlFavNmTOn2ZLNmzdfd9113//+9xM6IgBAsdFxAQCkqP3urdalS5fzzz//jDPOaLcjAgAUGx0XAEC7addHFnTt2vXRRx9tzyMCABQbHRcAQPtov1gtm83ec889o0ePbrcjAgAUGx0XAEC7Sereal/72tcab6CbzWY3bdo0f/78qqqql156KaEjAgAUGx0XAECKkorVRo4c2fRx77vttttZZ501bty4nj17JnREAIBio+MCAEhRUrHa1KlTE9ozAAA5Oi4AgBS16yMLAAAAAKBjSDBWq66uvuOOO/7mb/5m+PDhhx122C233FJVVZXc4QAAipCOCwAgLUnFahs3bhw+fPj555+/9957f/3rXx80aNAPf/jDwYMHr1+/PqEjAgAUGx0XAECKEry32lFHHXXzzTd36vSHQ0yfPv3CCy/80Y9+dPPNNyd0UACAoqLjAgBIUVKx2s9//vOlS5c2dnghhLKysquvvnrAgAGaPACANqHjAgBIUVJfAq2qqiovL2+2sFOnTm72AQDQVnRcAAApSipWO/LII++7775mCx999NEjjjgioSMCABQbHRcAQIqS+hLotGnThgwZ8m//9m+nnnpq//79V61a9fDDDz/88MOVlZUJHREAoNjouAAAUpTU1WqDBg1aunRpaWnpSSed9Fd/9Vcnnnji5s2b33rrraFDhyZ0RACAYqPjAgBIUVJXq4UQBg0a9Pjjjzc0NNTU1GQymdLSpCI8AICipeMCAEhLgrFaTmlp6W677Zb0UQAAipmOCwCg/bXx3zOz2WxlZeUHH3yw9aoVK1ZUVlZms9m2PSIAQLHRcQEA5IM2jtUWLFjwuc99rqysbOtV5eXlBx544PPPP9+2RwQAKDY6LgCAfNDGsdodd9wxZ86c/v37b72qb9++DzzwwB133NG2RwQAKDY6LgCAfNDGsdpzzz13+OGHb2/tl7/85V/96ldte0QAgGKj4wIAyAdtHKutXr26S5cu21tbUVGxZs2atj0iAECx0XEBAOSDNo7VhgwZsn79+u2t3bRp07777tu2RwQAKDY6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/OXzzjtvypQpkWYJIouz9957v/DCC/fdd19tbe2ee+7Z2Ng4Y8aMXXbZJZ7emsRF9yJWPB1a0Vbbp4iu+j6PH5Go48TcoUURJ8EOLeqzkxNbhxbdvz2DomnP8iw4nxNUEu1ZnwuSas+CaG49/a09K89UhXX77bdfccUVCxcubG5u3mbXYYcdtmTJkp5bnnvuuUwmk3sjce9781kQhf85TlIF9y7qOL0cPyL/7RkLfnY+//nPP/fccwWt/RNEEWfTpk25BamPrFu37tJLL02lUq+99lrJxfnEJ6qqqorhtwyii9PS0rLNc8XwKhHD2fnJT36y//7757rSqEV361m8ePE2HyPd0tKyYsWKSN/VEl2cIAj222+/Rx55pKOj46233po+ffqyZct6fkouZSy6q76oOrTirLZPkV71vR8/ClHH6SmGDi2iOEl1aHGenRg6tOjiFFV7FhTuxa0k2rM+FyTSngVR3nr6V3v2SV8Pyv/38MMPB0Fwzz33fOLe3N+k9evX5x52dnaOHDmy+yuxe9+bz4KC2544+Rccz9e3Z6OP0/vxo9DLMxb8r1M6nT7zzDMLWv62YoszbNiwWbNmFbr8bcUWZ/369UEQ3HnnnYVO8B8ijfPyyy8HQfD66693b/ne977X2NgYSZJsNhvL2cmdl7vvvjuaBP8h0lvP5MmTm5ubex7wwgsv3GmnnQof4yORxtnG+++/X1lZ+corrxQ0AcUo0qu+qDq0AlZbEh1aPnFi7tDifBHLRt+hxRknhg4tzjgxdGiRximq9iyfgvM5QaXSnvW5IP72LBvjv27Kvj0zVuvN0qVLgyC47bbb/tuCrq6u8ePHT548efPmzR0dHTNnztx55527m5Xe9+azoKji5F9wPE1b1HH6PH7B9f6M2xnnpptueuWVVzo6OrLZ7LpfHmMJAAAGsUlEQVR166644opUKrVq1aoSjbONHXbY4eqrr44kxkcijfPTn/7073//e+7svPHGGxMmTBgzZszWrVtLNE7OSSeddNRRR61du7arq+upp56qrKx8/PHHSzdONpu96667giD44IMPIkrRLepbz/Lly4Mg+PnPf97W1tbZ2fnkk09WVlb+4he/KNE4//rXv+699962traurq6VK1c2NzdfddVVEWWheER91RdVh1bAakuiQ+szTswdWtRxYu7Qoo6zjag7tKjjxNyh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)

``` r

stopifnot(identical(unname(tools::md5sum(legacy_files)),
                    unname(legacy_checksums)))
```

Open the Word file to compare row order, labels, counts, summaries,
precision and footnotes with the legacy reference. Inspect each trend
and postage figure for variable selection, axes and cohort. Record any
methodological differences alongside the migration report before using
the output in a study document.

### A job with no converter

Not every prefix has a migration adapter yet.
[`migrate_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/migrate_job.md)
still scaffolds the template, keeps every `EDIT:` marker for manual
review, and its report says so plainly.

``` r

distribution <- migrate_job(file.path(root, "distributions", "ac.age.sas"), "cohort", "eda")
distribution_report <- sub("[.]qmd$", "-migration.md", distribution)
cat(head(readLines(distribution_report), 6L), sep = "\n")
#> # Migration report
#> 
#> Template: hvtiRtemplates 1.2.0 / ac
#> 
#> **No converter: every choice is manual.** This template has no migration adapter yet; 
#> the job is the plain scaffold and the evidence below is for porting by hand.
```
