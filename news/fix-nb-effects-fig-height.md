* `nb-boostmtree`'s partial-effects pages are drawn at their own height.
  Since 1.4.1 every page was emitted as tall as it was wide, because one
  `sprintf()` call built both chunk options and handed each the page width,
  so a one-panel page came out 3.25 by 3.25 in rather than 3.25 by 3. The
  saved files were already the right size; only the figure in the report was
  wrong, and the call raised a warning on every page.
