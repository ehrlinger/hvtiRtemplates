# Data delivery EDA report: design spec

Version 0.1, 2026-10-13. Status: draft for the ADO hand-off. A working skeleton
that implements this spec on synthetic data accompanies it (see README.md).

## Purpose

Every data request the team fills ships with a standard exploratory report. The
same report serves two jobs:

1. **Quality check before delivery.** Data managers and stat programmers use it
   to find missingness, follow-up and outlier problems while they can still fix
   the query or explain what they see.
2. **Orientation after delivery.** Researchers use it to understand what they
   received before they model anything.

For deliveries into a study, the bundle also carries the exact query that
produced the data, so stat programmers start from the executed query rather
than reconstructing it.

The report checks three things: missingness, follow-up, and outliers. It handles
patient-level tables and longitudinal (repeated-measures) tables.

## Principles

- **One template, two audiences.** The internal and delivery reports render from
  the same `.qmd` with an `audience` parameter. They compute identical checks.
- **Nothing ships unexplained.** Every warning or error flag carries a note from
  the data manager before the delivery report can render. "Known, left as
  delivered" is a valid note. This is the warehouse rule of adjudicating at
  delivery, applied to the report.
- **The delivered query is the executed query.** The runner executes `.sql`
  files and copies those same files into the bundle. Nobody retypes or tidies a
  query after it runs.
- **Fail loudly on bad input.** A missing variable, a wide table, or an event
  indicator that is not 0/1 stops the render with a message naming the problem.
  The report never drops a panel silently.
- **Skip loudly on absent input.** No `date_var` or no events means the
  dependent sections are skipped with a sentence saying why.
- **No row-level data leaves in the report.** Record IDs appear only in the
  internal report's appendix, which is never bundled. As a final check, `bundle`
  searches the delivery report for every flagged ID and removes the bundle if
  any appears.

## Components and ownership

| Component | Language | Home | Owner |
|---|---|---|---|
| Report template (`eda.qmd`) and check functions | R | `hvtiRtemplates` | Analysis team |
| Delivery runner (`deliver.py`) | Python | Data management repo | Data managers |
| Request file (`request.yml`) | YAML | Per request | Data manager filling the request |
| Notes file (`notes.yml`) | YAML | Per request | Data manager filling the request |

This follows the existing language split: Python at the data layer, R at the
analysis and reporting layer. The runner calls the report through
`quarto render`, so neither side imports the other's code.

## Workflow

```
request.yml + queries/*.sql
        |
        v
deliver.py prepare      executes queries, writes parquet, renders INTERNAL report,
        |               writes flags.json, prints the flag summary
        v
data manager            reads internal report; fixes the query and re-runs prepare,
        |               or writes a note for each flag in notes.yml
        v
deliver.py bundle       verifies data unchanged since prepare, applies the notes gate,
        |               renders DELIVERY report, writes manifest, assembles bundle
        v
bundle/<request_id>/    to the researcher, or into the study folder
```

## Bundle

```
<request_id>/
  data/<table>.parquet       one file per table
  query/<table>.sql          the executed query files, byte-identical
  report/eda.html            delivery report, self-contained
  params.yml                 exactly what the report was told
  notes.yml                  the data manager's notes
  manifest.json              provenance and flag summary
```

Researchers receive the whole bundle. A study delivery places it in the study
folder (location to be decided, see Open decisions). The internal report and
`flags.json` stay in the runner's working directory.

### Manifest

```json
{
  "request_id": "DR-2026-0412",
  "created": "2026-10-13T14:30:00-04:00",
  "source": {"kind": "mssql", "url_env": "SOURCE_DB_URL"},
  "bind_params": {"start": "2000-01-01", "end": "2024-12-31"},
  "close_date": "2025-06-30",
  "tables": [
    {"name": "patients", "role": "patient", "query": "query/patients.sql",
     "query_sha256": "...", "data": "data/patients.parquet",
     "data_sha256": "...", "rows": 1480, "columns": 14}
  ],
  "flags": [
    {"table": "patients", "variable": "bmi", "check": "OUT-RANGE",
     "severity": "warning", "n": 3, "note": "Unit error in source..."}
  ],
  "software": {"runner": "0.1.0", "R": "4.4.1", "quarto": "1.6.x",
               "report_template_sha256": "..."}
}
```

The flag summary carries counts only. Written to a central table on every
bundle, it becomes the cross-request record of variable health that feeds the
adjudication work (out of scope for v1, but the manifest is shaped for it).

## Request file

```yaml
request_id: "DR-2026-0412"
source:
  kind: mssql                  # mssql | snowflake | sqlite (tests)
  url_env: SOURCE_DB_URL         # SQLAlchemy URL read from this environment variable
bind_params:                   # bound into every query by name (:start, :end)
  start: "2000-01-01"
  end: "2024-12-31"
close_date: "2025-06-30"       # end of follow-up; omit to use the latest observed date
unknown_codes: ["unknown", "unk", "not documented"]
ranges: ranges.yml             # optional clinical ranges, see Outliers
tables:
  - name: patients
    role: patient
    query: queries/patients.sql
    id: pt_id
    date_var: surgery_date
    events:
      - {label: "Death", event: dead, interval: iv_dead, unit: years, terminal: true}
      - {label: "Reoperation", event: reop, interval: iv_reop, unit: years}
  - name: echo
    role: longitudinal
    query: queries/echo.sql
    id: pt_id
    time: echo_date            # a date, or a numeric interval from the patient date_var
    values: [lvef, peak_gradient]
    baseline_window_days: 365  # measurements earlier than this before index are flagged
```

Connection credentials never appear in the request file; `url_env` names an
environment variable. Queries use named binds (`:start`), which SQLAlchemy
translates for SQL Server, Snowflake and SQLite alike.

## Report parameters

The runner derives `params.yml` from the request file, adds absolute paths to
the parquet files, the audience, and the notes path, and passes the file's path
as the report's single parameter: `quarto render eda.qmd -P config:params.yml`.
The report reads the file with `yaml::read_yaml()`. Passing the structure as
Quarto parameters does not work: a list of events cannot go on the command line,
and Quarto's parameter handling turns lists of records into data frames.

## Report structure

1. **Delivery summary** (researcher-facing): cohort size, date range, event
   counts, median potential follow-up, tables and their row counts.
2. **Flag summary**: one row per flag with table, variable, check, severity,
   count, and the note (delivery) or "unexplained" (internal).
3. **Per patient-level table**: follow-up, missingness, outliers, variable
   overview.
4. **Per longitudinal table**: linkage, measurement density and timing, values.
5. **Appendix (internal only)**: record IDs per flag, capped at 50 per flag.

## Checks

Severity: **error** means the data is wrong as delivered; **warning** means it
may be wrong and needs a note; **info** is context and needs no note.

### Input guards (stop the render)

| ID | Condition |
|---|---|
| IN-VAR | A variable named in the parameters is not in the table |
| IN-DUPID | A patient-level table has more than one row per ID |
| IN-WIDE | A longitudinal table has one row per ID and numbered sibling columns (`lvef_1`, `lvef_2`, ...): reshape to long in the runner |
| IN-EVENT | An event indicator has values other than 0, 1 and missing |
| IN-TYPE | An interval or value variable is not numeric, or a date variable cannot be parsed as a date |

### Follow-up (patient-level, per event)

| ID | Severity | Condition |
|---|---|---|
| FU-MISSING | warning | Event or interval missing |
| FU-NEG | error | Interval below zero |
| FU-PAST-CLOSE | error | Index date plus interval falls after `close_date` |
| FU-ZERO-EVENT | warning | Event recorded at interval zero |
| FU-AFTER-TERMINAL | error | A non-terminal event's interval exceeds the terminal event's interval for a patient who had the terminal event |
| FU-COMPLETENESS | info | Completeness index C = observed / potential person-time (Clark, Altman and De Stavola, Lancet 2002) |

Potential follow-up runs from the index date to `close_date`, ending at the
event for patients who had it and, for non-terminal events, at the terminal
event. The goodness-of-follow-up plot shows each patient at (index date,
observed interval) against the potential-follow-up diagonal, one panel per
event.

### Missingness (all variables)

| ID | Severity | Condition |
|---|---|---|
| MISS-RATE | warning | More than 20% missing |
| MISS-ERA | warning | Missing share differs by 50 points or more between calendar years of `date_var` (years with at least 20 rows): the field was not collected in some period |
| MISS-UNK | info | Values matching `unknown_codes` (counted separately from missing) |
| MISS-ALL | error | Variable entirely missing |

Missing is a database null or an empty string. An explicit unknown code is
counted apart from missing, because whether a null means "no" or "not
recorded" is a property of the source the report cannot decide; the
missingness-by-year view is how a reader sees it.

### Outliers (numeric and date variables)

| ID | Severity | Condition |
|---|---|---|
| OUT-RANGE | warning | Outside the clinical range in `ranges.yml` |
| OUT-FENCE | warning | No clinical range given, and beyond median ± 5 × scaled MAD |
| OUT-DATE | error | A date before 1900 or after `close_date` |
| OUT-CONST | info | Variable takes a single value |

Clinical ranges come first because purely statistical fences fire on every
skewed lab, and a flag list that is mostly noise stops being read. The fence is
deliberately wide. `ranges.yml` should eventually be generated from the data
dictionary and module definitions:

```yaml
bmi: [12, 80]
creatinine: [0.2, 20]
lvef: [5, 85]
```

### Longitudinal tables

| ID | Severity | Condition |
|---|---|---|
| LONG-ORPHAN | error | Measurement IDs absent from the patient table |
| LONG-NOMEAS | info | Cohort patients with no measurement after index |
| LONG-PREINDEX | warning | Measurement earlier than `baseline_window_days` before index |
| LONG-POSTCLOSE | error | Measurement after `close_date` |
| LONG-DUP | warning | Same ID and time with different values |
| LONG-JUMP | warning | Consecutive within-patient change beyond 6 × scaled MAD of all consecutive changes |
| LONG-SHIFT | warning | A calendar year's median differs from the overall median by a factor of 1.8 or more (years with at least 30 measurements): possible unit change |

Value variables also get the missingness and outlier checks above.

### Thresholds

All thresholds live in one list in the check functions with the defaults above,
and can be overridden per request. Tuning them on the first month of real
deliveries is part of v1; the target is few enough false positives that every
flag gets read.

## Notes and the gate

`notes.yml` is keyed by table, variable and check. Table-level checks use the
variable name `_table`.

```yaml
patients:
  bmi:
    OUT-RANGE: "3 values above 80; unit error in source (lb recorded as kg). Left as delivered; raised for HVTR."
echo:
  _table:
    LONG-ORPHAN: "Echo query filtered by date, not cohort. Fixed in query; re-run."
```

`deliver.py bundle` refuses to proceed while any warning or error flag lacks a
note, and lists the missing ones with a skeleton to paste into `notes.yml`.
When one cause raises several flags (a unit change raises LONG-SHIFT, LONG-JUMP
and OUT-RANGE), the note is written once with a YAML anchor and repeated by
alias; the delivery report groups flags that share a note on the same variable
into one row. It also refuses if the data or query hashes
differ from those recorded at `prepare`, so notes always describe the data
that ships. Notes that recur across requests ("unit error in source") are
candidates for fixing in HVTR rather than explaining again.

## Visuals

The report uses the team's postage-stamp design: continuous variables over
`date_var`, categorical percentages by calendar year, and the
goodness-of-follow-up plot. The v1 skeleton draws these with plain ggplot2 so
the template runs anywhere; they are placeholders for the `hvtiPlotR` versions.

## Not in v1

- Writing the manifest flag summary to a central variable-health table.
- Generating `ranges.yml` from the data dictionary.
- Python engine for the report (the skeleton of sections is shared; the body is R).
- Automatic pre-fill of `events` from naming conventions.

## Open decisions

1. Where the bundle lands in a study folder. Study folders are created upstream,
   so this follows the existing convention rather than inventing one.
2. Who may write notes, and whether a second person signs off before `bundle`.
3. Initial thresholds, to be tuned on real deliveries.
4. How the runner obtains connections on the delivery machine (service account,
   per-user credentials).
