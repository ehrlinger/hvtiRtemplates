/* Synthetic follow-up example; no study data. */
data followup;
  set built;
  %inc vars;
  current=mdy(1,1,2026);
  maxfup=(current-dt_surg)/365.2425;
run;
proc sort data=followup; by dead dt_surg; run;
proc means data=followup; var iv_dead; by dead; run;
proc means data=followup; var iv_fup; by dead; run;
proc print data=followup; id study_id; var iv_dead iv_fup;
  if dead=0;
run;
/* proc means; by stroke; var stroke_time; run; */
