# Figure standard: size, type and captions

Decided 2026-10-13. Applies to every template in `inst/templates/`, and afterwards to the
hvtiGraphics book, which gets a pull request of its own.

## The rule

1. **A single-panel figure is saved 6 in wide by 4 in tall**, as PNG, PDF and TIFF, and **drawn
   in the report at 9 by 6 in**, the same 3:2, at the same 12 pt type (2026-10-23, see
   "Report size" below). <sub>History (superseded 2026-10-23): "6 in wide by 4 in tall, both in
   the report and in the saved PNG and PDF."</sub>
2. **A faceted or multi-panel figure is sized freely** for now. Facets, small multiples, a
   scatter-plot matrix and a correlation matrix are the cases where 6 by 4 leaves each panel too
   small to read. Each exception carries a comment saying why it is one.
3. **Type is 12 pt**, meaning a ggplot2 `base_size` of 12, in every figure but one kind: a
   **page of small panels**, `dc-eda`'s grids of two to a row, is **8 pt**. At 12 pt a
   long panel title and the year labels run past a 3.25 in panel. Those pages draw no legend
   and no category names: either took width the bars needed, and an EDA page is for seeing
   the data, so the house colors tell the categories apart and the report's frequency table
   names them (John, 2026-10-15; the names were drawn beside each panel from 2026-10-13).
   The year axis keeps about five labels (`.eda_page_panels()`). The test accepts 8 pt only
   on a line that also applies `.eda_page_panels()`. `theme_hv_manuscript()` already defaults to 12. ggplot2's own themes
   (`theme_minimal()`, `theme_bw()`, the default `theme_grey()`) default to 11, so a template
   using one of them must say `base_size = 12`.
4. **Every figure has a numbered caption**, meaning a chunk label starting `fig-` with a
   `fig-cap`. The caption says what is plotted, and names the point type and color of each
   mark, so a reader can decode the figure from its legend alone.
5. **No saved figure is larger than the printed page, 6.5 in wide by 9 in tall**, and no report
   figure larger than half as large again, 9.75 by 13.5 in, single panel or
   free-size alike. A figure whose panel count follows the study is paged instead: the RF and
   nb figures through `.figure_pages()`, `dc-eda`'s grid pages, `dc-stddiff`'s balance plot at
   30 rows a page. **The one exception is `dc-tables`' scatter-plot matrix**, saved at 10 by
   10 in: every cell pairs two variables, so it cannot be split across pages, and shrinking
   it to the page would shrink every cell with it. John decided this on 2026-10-15.
   `test-figure-standard.R` enforces the limit on chunk options and `save_figure()` sizes,
   and exempts that one `save_figure()` line and nothing else.

## Report size, decided 2026-10-23

At 6 by 4 in a report figure rendered at 576 by 384 screen pixels, under a third of the 2000 px
body every template's `page-layout: full` sets, and read as small (John, measured on #1356's
`nb-boostmtree` report). The report now draws every figure half as large again as its saved
copy, keeping `base_size = 12`, so the plot gains room and the type stays the same size on
screen. Options weighed: drawing 6 by 4 and displaying it larger (scales the type with it,
declined) and 9 by 6 everywhere (a saved figure wider than the 6.5 in page, its 12 pt printing
near 8.7 pt in a column, declined).

- Each template's `format:` block reads `fig-width: 9` and `fig-height: 6`.
- A free-size figure's chunk options are its old sizes times 1.5. A paged figure writes
  `.report_size()` (`R/figure-pages.R`) of its page into the chunk options and passes the page
  itself to `save_figure()`.
- `save_figure()` keeps its 6 by 4 default and the page cap. A figure the report shows from the
  saved PNG (`include_graphics()`, the `linked` path) is unchanged: knitr already displays a
  300 dpi 6 by 4 PNG at 900 px, about the inline figures' 864.
- So the report and the manuscript copy of a figure now differ in proportion of type to plot:
  the saved copy is the one to judge for print.

## Where the sizes come from

A template draws a figure in the report in one of two ways, and each has its own size.

| path | size set by | today |
|---|---|---|
| plot printed in the chunk | `fig-width`/`fig-height`, unset | Quarto's 7 by 5 default |
| saved PNG linked with `include_graphics()` | `save_figure(width, height)` | 6 by 4 by default, overridden in nine places |

So the report path gets `fig-width: 6` and `fig-height: 4` in each template's own `format:`
block. A template carries its own `format:` block, never a project `_quarto.yml`. The saved
path keeps `.save_figure()`'s 6 by 4 default and loses its overrides, except where a figure is
faceted.

## Inventory, 2026-10-13

Size overrides to resolve:

| template | figure | now | single panel? | becomes |
|---|---|---|---|---|
| `dc-trends` | trend by year | 8 x 6 | yes | 6 x 4 |
| `hp` | survival, hazard, phases | 9.3 x 6.7 | yes | 6 x 4 |
| `lp-mirror` | mirror histograms | 7 x 5 | yes | 6 x 4 |
| `bc`, `bh` | selection frequency | 6 x 7 | yes, one row per variable | free |
| `dc-stddiff` | balance | 7 x by rows | yes, one row per variable | free |
| `dc-eda`, `dc-gfup` | follow-up | 7 x 6 | check for facets | |
| `lg` | calibration | 9 x 6 | faceted (strips) | free |
| `dc-tables` | correlation matrix | 10 x 10 | matrix | free |

Type to resolve: `dc-eda`'s `base_size = 8`; `theme_minimal()` in `bc`, `bh`, `bl`, `br`;
`theme_bw()` in `.lg_plot()` (`R/logit-calibration.R`); and the rf and nb templates, which draw
with the plotting package's own default theme.

Captions: every figure already has a numbered caption. Figures drawn in a loop are captioned
through each template's `.child()` helper, which writes a `fig-` chunk at render time. No
caption names its point type or color, so all of them are rewritten.

## Decisions, 2026-10-13

- **A plot with one row per variable is a free-size exception**, like a faceted one. The
  selection-frequency dot plots in `bc`, `bh`, `bl` and `br`, the `dc-stddiff` balance plot and
  the forest importance plots hold about 15 rows at 4 in and 12 pt, and a candidate list is
  often longer.
- **The theme is hvtiPlotR's, with `base_size = 12` written out**:
  `theme_hv_manuscript(base_size = 12)` on every ggplot, including plots a package's `plot()`
  method returns. 12 is already its default, so writing it out is not redundant: it states
  the standard where a reader sees it, and survives a change of default. It is added per plot,
  not through `theme_set()`, so no job changes global state.
- **Caption style follows the ST1264 morphology manuscript's legends, shortened**: a title
  sentence saying what is plotted, then a key naming each mark by shape or line and color.
  The exemplar, `bc`'s selection-frequency figure: *Bootstrap selection frequency of each
  candidate variable. Black filled circles mark the percent of replicates selecting the
  variable, horizontal black bars ±1 Monte Carlo error, and the dashed vertical line the
  retention threshold.* Where colors follow a study's own groups, the caption says "one color
  per group, as in the legend" rather than naming hues the template cannot know.

`tests/testthat/test-figure-standard.R` enforces the size in the format block, the theme and
its `base_size`, and a `fig-cap` on every static `fig-` chunk. It cannot read whether a caption
names its marks; that stays with review.

## hv_panel_size(), adopted 2026-10-13

hvtiPlotR 2.8.8's `hv_panel_size()` sizes a faceted figure: 3 by 2 inch panels, shrunk together to
fit a 6.5 by 9 inch page, refusing panels under 1.6 inches and refusing a patchwork. The page and
floor were 6 and 1.75 inches until three facet columns at 12 pt turned out to need about 1.66 inches. A template uses
it only where the method fixes the panel count, because it stops rather than guesses, and a study's
variable count must never make a job fail. That is `lg` alone today, in its two rows of three.
Facet counts that follow the study's variables or response levels (`nb` effects and path,
`dc-tables`' scatter matrix), patchworks and one-row-per-variable plots stay free size.
