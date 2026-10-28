# Study dataset build

# Study dataset build

Published

2026-10-28 09:14

This job cuts the study’s dataset from a master snapshot, records who
was excluded and why, and writes the study’s working dataset with its
build record beside it. When `REGISTER` is `TRUE` it registers that file
as a dated version of this study’s `"built"` dataset (also called
`"study"`), the one every analysis job reads.

What does not belong here: corrections to a patient’s values (they
belong to the master’s corrections, in hvtiRdatabuild, so every study
sees them); imputation, propensity scores and variables for one model (a
`vars` job); printing patient rows to check them (do that in the
console, never in a report).

**final** · rendered by gallery on gallery · hvtiRtemplates 1.5.3

## Study choices

## Cohort

## Register

## Report

| Item | Value |
|:---|:---|
| Mode | Working file only |
| Master snapshot | built.parquet |
| Master SHA-256 | 387e49a8b89b038fe5a8b4afc8532fa46b5cb7f950f2dbcbd197e8f58e8f1553 |
| Rehashed this render | no |
| Master parent release | NA |
| Rows in the dataset | 683 |
| Patients | 683 |
| Columns | 14 |
| Study dataset before | built_20261028.parquet |
| Study dataset after | built_20261028.parquet |
| Registration | Working file only: the study’s dataset is still built.rds, so this build was not declared or registered |

Table 1: Run mode, master snapshot, row counts and dataset registration
for this render

### Who was excluded, and why

| Step | Reason | Rows before | Removed | Condition missing | Rows after | Patients after |
|:---|:---|---:|---:|---:|---:|---:|
| master | Rows read | 800 | 0 | 0 | 800 | 800 |
| exclude | No surgery date | 800 | 0 | 0 | 800 | 800 |
| exclude | Operated before 1995 | 800 | 104 | 0 | 696 | 696 |
| exclude | Creatinine over 2 mg/dL | 696 | 13 | 62 | 683 | 683 |

Table 2: Exclusions applied to the master, in order

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

Table 3: Type, missing count and range of each column

## About this run

| Group           | Item             | Value                   |
|:----------------|:-----------------|:------------------------|
| Run             | Started          | 2026-10-28 09:14:45 EDT |
|                 | Ended            | 2026-10-28 09:14:46 EDT |
|                 | Duration         | 0 s                     |
|                 | Status           | final                   |
|                 | Rendered by      | gallery                 |
|                 | Host             | gallery                 |
| Job             | File             | bd.study.build.qmd      |
|                 | Template         | bd                      |
|                 | Subject          | study                   |
|                 | Type             | build                   |
|                 | hvtiRtemplates   | 1.5.3                   |
| Reproducibility | renv             | not active              |
|                 | renv.lock sha256 | d09f96b6cd21            |
