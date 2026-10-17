title3 "General Descriptive Analyses";
* The shape of tp.dc.tables.ods.sas: each vartype twice, overall and by group;
%desc_tab(vartype=category, input=built,
  varlist=/* Demography */ female race_grp /* Procedure */ repair,
  by= ,
  byvalue=,
  countpersig=2,
  outrtf=&STUDY/documents/general_cate.rtf);
%desc_tab(vartype=category, input=built,
  varlist=/* Demography */ female race_grp /* Procedure */ repair,
  by= treatment,
  byvalue=0 1,
  countpersig=2,
  outrtf=&STUDY/documents/group_cate.rtf);
%desc_tab(vartype=continuous, input=built,
  varlist=/* Demography */ age bmi /* Follow-up */ iv_dead,
  by=,
  byvalue=,
  perctile=15 50 85,
  outrtf=&STUDY/documents/general_cont.rtf);
%desc_tab(vartype=continuous, input=built,
  varlist=/* Demography */ age bmi /* Follow-up */ iv_dead,
  by=treatment,
  byvalue=0 1,
  perctile=15 50 85,
  outrtf=&STUDY/documents/group_cont.rtf);
