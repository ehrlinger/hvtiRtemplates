* `dc-tables`: the comment above `DROP_CONSTANT` no longer says a row with nothing recorded is kept. The table
  stops and names such a row, and `GROUPS <- NULL` leaves those columns out before it gets there.
