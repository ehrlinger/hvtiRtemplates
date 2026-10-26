* The `ac` template's figures now mark each event with a point and join the points with straight
  lines, as the SAS `%KAPLAN` figures do. Set `STEPS <- TRUE` in a job for the Kaplan-Meier steps instead;
  the points stay either way. On the manuscript figure the line joins the events alone, so a censored
  time no longer puts a corner where survival did not change.
