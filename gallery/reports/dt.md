# Study dataset check

# Study dataset check

Published

2026-10-29 12:34

This job checks the working dataset a `bd` job writes, before it is
registered: what the rebuild changed against the version registered now,
cross-tabs of derived columns against their sources, the follow-up
columns, and the study’s own named checks. It is the loop a programmer
runs after a build: build, check, fix, rebuild.

A check never writes. It writes no dataset, registers nothing and
corrects nothing. A finding becomes a correction to the master, a rule
in `bd`’s `EXCLUDE`, or a fix to a derivation in `bd`, never an edit
made here.

The report holds counts only. The rows behind a count, and the patients
present on one side of the rebuild only, are printed in the console: run
the chunks in an interactive session to read them. A render leaves them
out.

**final** · data: see About this run · rendered by gallery on gallery ·
hvtiRtemplates 1.5.4

## Study choices

## What this rebuild changed

A comparison build: study_cohort.rds is not the study dataset. It is
compared against the study dataset built.rds, registered as
built_20261029.parquet, which this build leaves unchanged.

| Item                           | Value |
|:-------------------------------|------:|
| Rows in the registered version |   800 |
| Rows in this build             |   683 |
| Rows in both                   |   683 |
| In the registered version only |   117 |
| In this build only             |     0 |

Table 1: Rows in the registered version and in this build, joined on the
dataset’s key

| Column | Verdict | Rows differing | Largest difference |
|:---|:---|---:|---:|
| approach | in the registered version only | NA | NA |
| complication | in the registered version only | NA | NA |
| cpb_time | in the registered version only | NA | NA |
| discharge | in the registered version only | NA | NA |
| e_e | in the registered version only | NA | NA |
| icu_hours | in the registered version only | NA | NA |
| iv_opyrs | in the registered version only | NA | NA |
| iv_reint | in the registered version only | NA | NA |
| iv_reop | in the registered version only | NA | NA |
| la_diam | in the registered version only | NA | NA |
| log_los | in the registered version only | NA | NA |
| los | in the registered version only | NA | NA |
| lvedd | in the registered version only | NA | NA |
| lvesd | in the registered version only | NA | NA |
| male | in the registered version only | NA | NA |
| match_pair | in the registered version only | NA | NA |
| mr_grade | in the registered version only | NA | NA |
| mv_procedure | in the registered version only | NA | NA |
| nonwhite | in the registered version only | NA | NA |
| plvmassi | in the registered version only | NA | NA |
| prior_ops | in the registered version only | NA | NA |
| reint | in the registered version only | NA | NA |
| reop | in the registered version only | NA | NA |
| rvsp | in the registered version only | NA | NA |
| stroke | in the registered version only | NA | NA |
| valve_size | in the registered version only | NA | NA |
| valve_type | in the registered version only | NA | NA |
| vent | in the registered version only | NA | NA |
| op_year | in this build only | NA | NA |
| age | identical | 0 | 0 |
| bmi | identical | 0 | 0 |
| creat_pr | identical | 0 | 0 |
| dead | identical | 0 | 0 |
| dt_surg | identical | 0 | 0 |
| female | identical | 0 | 0 |
| hx_chf | identical | 0 | 0 |
| hx_dm | identical | 0 | 0 |
| iv_dead | identical | 0 | 0 |
| lvef | identical | 0 | 0 |
| nyha_pr | identical | 0 | 0 |
| race_grp | identical | 0 | 0 |

Table 2: Each column of the rows in both, compared by value

## Cross-tabs

### dead by female

| dead | female | Frequency |  Percent | Small |
|:-----|:-------|----------:|---------:|:------|
| 0    | 0      |       204 | 29.86823 |       |
| 0    | 1      |       122 | 17.86237 |       |
| 1    | 0      |       234 | 34.26061 |       |
| 1    | 1      |       123 | 18.00878 |       |

Table 3: dead by female, with a missing value as a level of its own

## Follow-up

| full | event | censored | missing_event |
|-----:|------:|---------:|--------------:|
|  683 |   357 |      326 |             0 |

Table 4: Patients by event status

| interval | missing | negative | zero | min |   q1 | median |    q3 |  mean |    sd |    max |
|:---------|--------:|---------:|-----:|----:|-----:|-------:|------:|------:|------:|-------:|
| iv_dead  |       0 |        0 |    0 |   0 | 2.72 |  6.971 | 13.52 | 8.945 | 7.448 | 29.711 |

Table 5: Each follow-up interval

0 row(s) look suspicious, listed in the console.

## Named checks

| Check                              | Rows matching | Undecided (missing) |
|:-----------------------------------|--------------:|--------------------:|
| Event with no follow-up interval   |             0 |                   0 |
| Follow-up interval of zero or less |             0 |                   0 |

Table 6: Rows matching each named check; the rows themselves are in the
console

## About this run

| Group           | Item             | Value                   |
|:----------------|:-----------------|:------------------------|
| Run             | Started          | 2026-10-29 12:34:31 EDT |
|                 | Ended            | 2026-10-29 12:34:31 EDT |
|                 | Duration         | 0 s                     |
|                 | Status           | final                   |
|                 | Rendered by      | gallery                 |
|                 | Host             | gallery                 |
| Job             | File             | dt.study.check.qmd      |
|                 | Template         | dt                      |
|                 | Subject          | study                   |
|                 | Type             | check                   |
|                 | hvtiRtemplates   | 1.5.4                   |
| Reproducibility | renv             | not active              |
|                 | renv.lock sha256 | d09f96b6cd21            |
