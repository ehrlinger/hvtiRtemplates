# Study dataset build

# Study dataset build

Published

2026-11-06 08:07

This job cuts the study’s dataset from a master snapshot, records who
was excluded and why, and writes the study’s working dataset with its
build record beside it. When `REGISTER` is `TRUE` it registers that file
as a dated version of this study’s `"built"` dataset (also called
`"study"`), the one every analysis job reads.

Before it registers, the job checks what it built: what the rebuild
changed against the version registered now, cross-tabs, the follow-up
columns and the study’s own named checks. The report holds their counts;
the rows behind them go to the console, never into the report.

What does not belong here: corrections to a patient’s values (they
belong to the master’s corrections, in hvtiRdatabuild, so every study
sees them); imputation, propensity scores and variables for one model (a
`vars` job).

**final** · rendered by gallery on gallery · hvtiRtemplates 1.5.6

## Study choices

## Cohort

## Checks

These checks read the dataset this render has just written. They report
counts only: the rows behind a count, the patients on one side of the
rebuild only and the levels of each cross-tab are printed in the
console, so run the chunks in an interactive session to read them. A
finding changes nothing and blocks nothing. A check that cannot run,
because a column it names is missing or a condition does not evaluate,
stops the render, as a bad `EXCLUDE` rule does: a build whose checks did
not run is never registered. A finding becomes a correction to the
master, a rule in `EXCLUDE`, or a fix to the derive chunk; then render
again, and register once the checks read right. A draft’s report prints
the SHA-256 of the file it wrote, and a registering render registers
only a file whose bytes that report names, so register from a render,
never from chunks run by hand.

### What this rebuild changed

A comparison build: study_cohort.rds is not the study dataset. It is
compared against the study dataset built.rds, registered as
built_20261106.parquet, which this build leaves unchanged.

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
| dt_surg | identical | 0 | NA |
| female | identical | 0 | 0 |
| hx_chf | identical | 0 | 0 |
| hx_dm | identical | 0 | 0 |
| iv_dead | identical | 0 | 0 |
| lvef | identical | 0 | 0 |
| nyha_pr | identical | 0 | 0 |
| race_grp | identical | 0 | 0 |

Table 2: Each column of the rows in both, compared by value

### Cross-tabs

| dead | female | Frequency |  Percent | Small |
|:-----|:-------|----------:|---------:|:------|
| 0    | 0      |       204 | 29.86823 |       |
| 0    | 1      |       122 | 17.86237 |       |
| 1    | 0      |       234 | 34.26061 |       |
| 1    | 1      |       123 | 18.00878 |       |

Table 3: dead by female

| Pair           | Levels | Cells | Cells under 5 | Missing |
|:---------------|:-------|------:|--------------:|--------:|
| dead by female | 2 x 2  |     4 |             0 |       0 |

Table 4: Each cross-tab’s shape, with a missing value as a level of its
own

### Follow-up

| full | event | censored | missing_event |
|-----:|------:|---------:|--------------:|
|  683 |   357 |      326 |             0 |

Table 5: Patients by event status

| interval | missing | negative | zero | min |   q1 | median |    q3 |  mean |    sd |    max |
|:---------|--------:|---------:|-----:|----:|-----:|-------:|------:|------:|------:|-------:|
| iv_dead  |       0 |        0 |    0 |   0 | 2.72 |  6.971 | 13.52 | 8.945 | 7.448 | 29.711 |

Table 6: Each follow-up interval

0 row(s) look suspicious, listed in the console.

### Named checks

| Check                              | Rows matching | Undecided (missing) |
|:-----------------------------------|--------------:|--------------------:|
| Event with no follow-up interval   |             0 |                   0 |
| Follow-up interval of zero or less |             0 |                   0 |

Table 7: Rows matching each named check; the rows themselves are in the
console

## Register

## Report

| Item | Value |
|:---|:---|
| Mode | Working file only |
| Master snapshot | built.parquet |
| Master SHA-256 | fc5f56845a0e81f22412f7c6e44f244895c85b576fb76038154a4ad276154dda |
| Rehashed this render | no |
| Master parent release | NA |
| Rows in the dataset | 683 |
| Patients | 683 |
| Columns | 14 |
| Study dataset before | built_20261106.parquet |
| Study dataset after | built_20261106.parquet |
| Registration | Working file only: the study’s dataset is still built.rds, so this build was not declared or registered |
| Build reviewed (sha256) | 6596c1a4a83541cce8b973dd2a75fa6c5ceec316516dea1f1bbbe3ae4b21f7f8 |

Table 8: Run mode, master snapshot, row counts and dataset registration
for this render

### Who was excluded, and why

| Step | Reason | Rows before | Removed | Condition missing | Rows after | Patients after |
|:---|:---|---:|---:|---:|---:|---:|
| master | Rows read | 800 | 0 | 0 | 800 | 800 |
| exclude | No surgery date | 800 | 0 | 0 | 800 | 800 |
| exclude | Operated before 1995 | 800 | 104 | 0 | 696 | 696 |
| exclude | Creatinine over 2 mg/dL | 696 | 13 | 62 | 683 | 683 |

Table 9: Exclusions applied to the master, in order

### Columns

| Column     | Type      | Missing | Range               |
|:-----------|:----------|--------:|:--------------------|
| patient_id | character |       0 |                     |
| dt_surg    | Date      |       0 |                     |
| age        | numeric   |       0 | 32 to 100           |
| female     | numeric   |       0 | 0 to 1              |
| race_grp   | character |       0 |                     |
| bmi        | numeric   |       0 | 15.1 to 44.8        |
| hx_chf     | numeric   |       0 | 0 to 1              |
| hx_dm      | numeric   |       0 | 0 to 1              |
| nyha_pr    | numeric   |       0 | 1 to 4              |
| lvef       | numeric   |       0 | 20 to 75            |
| creat_pr   | numeric   |      62 | 0.48 to 1.91        |
| dead       | numeric   |       0 | 0 to 1              |
| iv_dead    | numeric   |       0 | 0.00025 to 29.71100 |
| op_year    | integer   |       0 | 1995 to 2024        |

Table 10: Type, missing count and range of each column

## About this run

| Group           | Item             | Value                   |
|:----------------|:-----------------|:------------------------|
| Run             | Started          | 2026-11-06 08:07:44 EST |
|                 | Ended            | 2026-11-06 08:07:45 EST |
|                 | Duration         | 1 s                     |
|                 | Status           | final                   |
|                 | Rendered by      | gallery                 |
|                 | Host             | gallery                 |
| Job             | File             | bd.study.build.qmd      |
|                 | Template         | bd                      |
|                 | Subject          | study                   |
|                 | Type             | build                   |
|                 | hvtiRtemplates   | 1.5.6                   |
| Reproducibility | renv             | not active              |
|                 | renv.lock sha256 | ed18165d16bf            |
