* In the HTML report, `dc-eda`'s percent and count pages carry hover labels.
  The pages name no categories, so a reader hovers a bar to see its category,
  year and count and percent. Each page is a ggiraph widget of about 120 KB,
  with no embedded fonts. The saved PNG and PDF figures are unchanged. The
  hover labels need ggiraph, now in Suggests, and a hvtiPlotR that has
  `hv_girafe()`. Without either, the pages are images as before.
