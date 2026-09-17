title3 "General Descriptive Analyses";
%desc_tab(vartype=category, input=built,
  varlist=/* Demography */ female race_grp /* Procedure */ repair,
  by=treatment, byvalue=0 1, countpersig=2,
  outrtf=&STUDY/documents/general_cate.rtf);
%desc_tab(vartype=continuous, input=built,
  varlist=/* Demography */ age bmi /* Follow-up */ iv_dead,
  by=treatment, byvalue=0 1, countpersig=2,
  outrtf=&STUDY/documents/general_cont.rtf);
