# Render a job

Renders a job from its own directory. By default the render is a draft:
open `EDIT:` markers appear in the report's DRAFT banner. With
`final = TRUE` an unfinished job stops instead, as the render of an
accepted result should.

## Usage

``` r
render_job(path, final = FALSE, quiet = FALSE)
```

## Arguments

- path:

  Character. Path to a job `.qmd` file.

- final:

  Logical. `TRUE` for the accepted result.

- quiet:

  Logical. Passed to
  [`quarto::quarto_render()`](https://quarto-dev.github.io/quarto-r/reference/quarto_render.html).

## Value

`path`, invisibly.

## Details

`final = TRUE` sets `HVTI_TEMPLATE_STRICT` to `1` for this render only
and restores its previous value afterwards, including after an error.
The job's own edit guard decides whether it is finished; this function
does not search for markers itself, so it cannot disagree with a render
started from the editor or from Quarto.

Jobs scaffolded by
[`add_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
capture their data provenance while executing and embed it in the
completed HTML. The same project hooks used by the Render button and
bare Quarto commands then publish a same-stem `.provenance.json` sidecar
beside the actual output. A failed execution that leaves the prior HTML
untouched also leaves its sidecar in place. If publication fails after
an output changes, the hooks expose a prior sidecar only when its
recorded output hash still matches. Otherwise they withhold the sidecar
and retain its recovery backup with a warning.

One job renders at a time in a study. A render started while another is
still running in the same study stops with a message naming the running
Quarto process; render again once it finishes. A lock left by a render
that crashed is taken over automatically.

## See also

[`open_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/open_job.md)
