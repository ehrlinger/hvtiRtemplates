* Every template now follows one figure standard. A single-panel figure is 6 in wide by 4 in
  tall, in the report through `fig-width` and `fig-height` in each template's `format:` block
  and in the saved PNG and PDF through `save_figure()`'s default. Faceted figures and plots
  with one row per variable keep a size of their own, and say why. Type is 12 pt in
  hvtiPlotR's theme, `theme_hv_manuscript(base_size = 12)`, on every ggplot, including those
  returned by a package's `plot()` method; `theme_minimal()` and `dc-eda`'s 8 pt type are gone.
  Every figure's numbered caption now names the shape or line and the color of each mark, so
  the figure can be read from its legend alone. `test-figure-standard.R` guards the size, the
  theme and the captions (`dev/specs/2026-10-13-figure-standard-design.md`).
