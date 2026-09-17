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

## See also

[`open_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/open_job.md)
