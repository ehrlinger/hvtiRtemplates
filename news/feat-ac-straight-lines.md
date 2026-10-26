* The `ac` template's figures now mark each event with a point and join the points with straight
  lines, as the SAS `%KAPLAN` figures do. Set `STEPS <- TRUE` in a job for the Kaplan-Meier steps instead;
  the points stay either way. On the manuscript figure the line joins the events alone, so a censored
  time no longer puts a corner where survival did not change.
* Under the straight lines, a `CI_TIMES` bar stands at the last event at or before its time, where the line
  passes through the estimate the bar's limits bracket. The limits are still the horizon table's, but with
  sparse events a bar can stand well left of the time asked for. With `STEPS <- TRUE` a bar stands at its time.
