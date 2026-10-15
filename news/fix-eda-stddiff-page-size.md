* `dc-eda` draws its pages on the printed page, 6.5 by 9 in portrait, rather
  than 11 by 8.5 in landscape, and its grid defaults to two panels across
  (`GRID_NCOL <- 2L`), so each 8 pt panel keeps room for its categories
  named beside it. A section takes more pages than before. A job that sets
  `GRID_NCOL` keeps its choice; more than two columns crowd the names.
  Migrating a legacy EDA job that sets no grid now gives two columns.

* `dc-stddiff` draws its balance figure 6.5 in wide, not 7, and puts at most
  30 variables on a page of at most 9 in; more variables go on further pages,
  each a numbered figure (`fig-balance-1`, ...) whose caption names its first
  and last variable. The saved file is `dc-stddiff-balance-page-01.png` and
  so on, not `dc-stddiff-balance.png`.
