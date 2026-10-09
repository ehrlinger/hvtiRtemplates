* `dp-postage` is removed, as its deprecation promised for the release after
  1.2.3. Use `dp-eda`: `add_job("dp.eda", subject, type)` with
  `SECTIONS <- c("continuous", "percent", "count")` draws the pages it drew.
  Asking for `dp.postage` now stops with the usual unknown-template error, which
  lists `dp.eda` among the `dp` templates.
