/* Synthetic migration fixture. */
* %desc_tab(vartype=bad, varlist=ignore_me);
data mock;
  ratio = top / bottom;
run;
%desc_tab(
  vartype=category,
  varlist=/* Intake */ mock_flag /* Event */ mock_event,
  by=mock_arm
);
