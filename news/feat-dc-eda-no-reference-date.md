- `dc-eda` takes `X_VAR <- NULL` for a build with no reference date. Each
  continuous variable is drawn as the spread of its values over the whole
  cohort and each categorical one as a single bar, under the label "Cohort"
  unless `X_LABEL` names another, and the captions say so. The follow-up
  section, which draws follow-up against the operation date, is left out with
  a note in place of an error. The study-choice comment adds that an age or an
  interval works as `X_VAR`, and that `JOIN` can bring one in. A job that names
  its `X_VAR` draws as before (#615).
