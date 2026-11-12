* New in-flight template `ar`, an analysis report for one research question.
  Each item shows a figure, table or value a finished job saved, checked
  against the bytes that job recorded, with Methods, Results and Interpretation
  for the researchers to choose from. `ar_item()`, `ar_value()`,
  `ar_paste_methods()` and `ar_review()` are new exports.
* `hz` and `ac` now record their exhibits and a Methods paragraph for `ar`
  reports. Jobs rendered before this record none; render them again to cite
  them.
