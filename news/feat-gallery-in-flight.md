* `vt-fit`'s Gower eligibility declares each 0/1 predictor symmetric binary
  before `cluster::daisy()`, which otherwise printed "binary variable(s) ...
  treated as interval scaled" in every report whose predictors mix a factor
  with a 0/1 flag. The distances are unchanged: on a 0/1 column the two
  readings agree.
