* **Every template figure is saved as a PNG and a PDF.** Figures go to the
  job's `graphs/<subject>-<type>/` folder as a 300 dpi PNG, for a Word draft,
  and a PDF of the same name with fonts embedded, for the publisher. Eight
  templates saved a PNG before, at 150 dpi; eleven (bc, bh, bl, br,
  nb-boostmtree and the six random-forest templates) only printed their
  figures. Each job's study choices gain `SAVE_FIGURES` and `FIGURES` to turn
  saving off or keep only some figures by name; `inst/templates/README.md`
  lists the names. A PNG the report shows keeps its name and is always written.
  The PDF falls back to the default `pdf()` device where `cairo_pdf()` cannot
  open, as on a Mac without XQuartz, whose R reports cairo as available anyway.
