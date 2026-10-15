* A selected figure is saved as a TIFF too, beside its PNG and PDF: 300 dpi and
  LZW-compressed, through `ragg::agg_tiff()`, since `grDevices::tiff()` cannot
  compress on a Mac without XQuartz. Journals ask for a PDF or a TIFF, and the
  TIFF is the raster format the family delivers by default, as hvtiPlotR's
  `save_manuscript()` does. The PNG stays the image a report embeds. ragg is
  suggested: without it the TIFF is skipped, with a message once a session.
