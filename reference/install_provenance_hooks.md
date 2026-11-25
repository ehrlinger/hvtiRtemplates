# Install a study's Quarto provenance hooks

Adds the pre-render and post-render hooks that record a job's provenance
to the study's Quarto project file, and copies the hook scripts beside
it.
[`add_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
and
[`upgrade_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/upgrade_job.md)
do this themselves; call it directly for a study whose jobs came from
elsewhere, as
[`render_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/render_job.md)'s
message says when a job that records its provenance is stopped for want
of the hooks.

## Usage

``` r
install_provenance_hooks(root = NULL)
```

## Arguments

- root:

  Character. Any directory inside the study. `NULL`, the default, starts
  from the working directory, and is an error outside a study.

## Value

The path to the study's project file, `_quarto.yml` or `_quarto.yaml`,
invisibly.

## Details

The study root is the nearest directory at or above `root` holding
`_study.yml`, so this can be called from anywhere inside a study. The
project file is the one Quarto reads at the study root, `_quarto.yml` or
`_quarto.yaml`, and it is updated in place; a study with both is
refused, since which one Quarto reads is not this function's to guess.
The hooks are added last in each list, after any the study already has,
and every other setting in the file is kept. Running it again changes
nothing. If any file cannot be written, the files already changed are
restored.

A study with neither file gets a `_quarto.yml`, which makes the study
one Quarto project and can change how its other documents render.

## See also

[`add_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md),
[`render_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/render_job.md)

## Examples

``` r
root <- file.path(tempdir(), "hooks-example")
suppressMessages(hvtiRutilities::study_setup(
  root, study = "Example", study_tracker_id = 1L, renv = FALSE
))
#> Study: /tmp/RtmpWNkSK2/hooks-example
#> 
#> [x] _study.yml — study: Example
#> [ ] renv.lock — no renv.lock; set the study up with hvtiR::setup(study = "Example", study_tracker_id = 1L, root = "/tmp/RtmpWNkSK2/hooks-example", adopt = TRUE), run with no project open, not renv::init(). Adopting deletes tp.* files: see hvtiR's "Start here" first
#> [ ] manifest.yaml — no manifest.yaml; register_data() creates it
#> [ ] dataset — no default dataset registered; run register_data()
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
install_provenance_hooks(root)
unlink(root, recursive = TRUE)
```
