# One data contract for every template: data selection and shared settings

**Date:** 2026-09-29
**Status:** design. Every decision in sections 2 to 6 was made by John Ehrlinger
on 2026-09-29, in the order they appear. Section 4's home was corrected the same
day, before any code: see 4.4. Nothing is built yet.
**Reads with:** the template audit for the biostats review (a Claude Docs page,
"HVTI Template Audit for Biostats"), the rendered gallery (`dev/gallery/`), and
the data-path issues it raised, hvtiRtemplates #173 to #189.
**Packages:** `hvtiRtemplates` for the shared data step (section 4), the
templates and `migrate_job()`; `hvtiPlotR` for the narrowed identifier default
in `hv_eda_pages()` (section 6). `hvtiRutilities` is unchanged.

This note is self-contained. It assumes no memory of the session that produced
it.

⚠️ No study, variable or patient identifier appears here. `ccfid`, `MRN` and
`eMRN` are column names, not values.

## 1. What was asked

Make the templates consistent for the analysts who use them. Rendering all 30
templates on one registered synthetic study (the gallery, 2026-09-28) and the
onboarding session the same day showed that each template family takes its
data a different way:

| Family | How it chooses its data today |
|---|---|
| Descriptive (`dc-*`, `dp-eda`, `dp-gfup`, `dp-postage`) | `DATASET` and `ANALYSIS_SET`, defaulting to the analysis set `"eda"`, which a new study does not have |
| `dp-trends`, logistic (`lm-*`) | `DATASET` only; a cohort restriction means registering another dataset |
| Hazard chain (`ac`, `hz`, `hm`, `hp`, `hs`) | the registered `"study"` dataset, plus a hand-typed filter line and `EXPECTED` counts in every job |
| Random forest (`rf*`) | the registered `"study"` dataset, with no way to restrict it |
| Bootstrap (`bl`, `br`, `bc`, `bh`) | a saved bootstrap bag, not the data (section 7) |

The names for the same thing also differ: `TIME`/`STATUS` in `ac` and `hz`,
`EVENT` in `hm`, `hp` and `hs`, with defaults `iv_dead`/`dead` in the first two
and `iu_dead`/`idead` in the rest; `ID` in 7 templates, defaulting to `"id"`,
which no CORR built dataset carries.

This note covers **data selection and the shared settings**. Three sibling
pieces of the consistency work are out of scope and get their own notes: the
shared chunk skeleton and header, the template names (`dp-postage`,
`dc-tables`), and report output conventions.

## 2. Default: read the whole registered dataset

A template reads the study's registered built dataset, whole, by default. An
analysis set is a deliberate choice, not the default. This matches how the SAS
jobs work: they read the built dataset and narrow it in the job with `keep` and
`where` statements.

```r
DATASET      <- "study"   # a dataset registered in _study.yml
ANALYSIS_SET <- NULL      # an hvtiRdatabuild analysis set, or NULL for the whole dataset
```

Every template runs on a newly registered study with no data edits, and every
report states what it read (section 4.2).

## 3. Shared settings

Every template's `edit-study-choices` chunk carries these, with these defaults:

```r
DATASET      <- "study"
ANALYSIS_SET <- NULL
WHERE        <- NULL      # rows to keep, dplyr::filter() style
ID           <- "ccfid"   # the patient
KEY          <- ID        # what makes a row unique
```

### 3.1 `WHERE`: rows to keep, with `filter()` rules

`WHERE` is `NULL`, one quoted expression, or a list of them:

```r
WHERE <- quote(age >= 18 & hx_chf == 1)
WHERE <- rlang::exprs(age >= 18, hx_chf == 1)   # every condition must hold
```

It is evaluated with `rlang::eval_tidy()` against the data, so it has the same
data masking as `dplyr::filter()` (the `.data$` and `.env$` pronouns work), and
the same missing-value rule: **a row where a condition is `NA` is dropped**, and
counted separately. Base `d[cond, ]` would keep it as an all-missing row. The
templates do not need dplyr; `dplyr::filter(d, !!!WHERE)` gives the same rows.

`WHERE` is a value, not code, so it is recorded with the job's output and a
downstream job can reuse it (section 5).

### 3.2 `ID` and `KEY`: the patient and the row

`ID` is the patient: used to count patients and never printed or drawn. `KEY`
is what makes a row unique, and defaults to `ID`, one row per patient.

```r
KEY <- ID                            # one row per patient (the default)
KEY <- c("ccfid", "iv_echo")         # longitudinal: patient and time
KEY <- c("ccfid", "echo_date")       # longitudinal: patient and date
KEY <- c("ccfid", "_IMPUTATION_")    # stacked imputations; the template sets this itself
```

A date or time column in `KEY` is used for uniqueness only and, like `ID`, is
never printed.

### 3.3 Family vocabulary

Each family adds only the names it needs, from one vocabulary:

| Setting | Meaning | Default | Replaces |
|---|---|---|---|
| `TIME` | follow-up to event or censoring | `"iv_dead"` | `TIME` (unchanged), and `iu_dead` defaults |
| `EVENT` | event indicator, 1 = event | `"dead"` | `STATUS` in `ac`, `hz`; `idead` defaults |
| `OUTCOME` | a binary, ordinal, nominal or continuous outcome | none | unchanged |
| `TREATMENT` | the exposure | none | unchanged |
| `PREDICTORS` | covariates | none | unchanged (10 templates already) |

`EVENT` is the word the reports and the SAS jobs use, and
`survival::Surv(time, event)`'s own argument name.

## 4. The shared data step: `hvtiRtemplates::read_job_data()`

Every template's data chunk is named `data` and is one call:

```r
job_data <- read_job_data(.cfg, dataset = DATASET, analysis_set = ANALYSIS_SET,
                          where = WHERE, id = ID, key = KEY)
d <- job_data$data
```

It is exported from hvtiRtemplates, beside the provenance and hand-off code it
calls, and documented. A fix lands once instead of in 30 copies.

### 4.1 What it does, in order

It stops at the first failure with a message naming the setting to change.

1. **Read** the registered dataset, or the analysis set when one is named. An
   analysis set is derived from `"study"`, so naming one with any other
   `DATASET` is an error that says so.
2. **Resolve the ID.** Use `ID` if the column exists. When `ID` is the default
   `"ccfid"` and that column is absent, fall back to `MRN`, then `eMRN`, and
   record the fallback. When none exists (a study keyed on, say, `randid`), stop
   and point to `ID` in `edit-study-choices`.
3. **Drop identifiers.** Remove any column named `MRN` or `eMRN`, matched
   exactly and ignoring case, unless it is serving as the ID. No other name is
   treated as an identifier here; the group's naming is controlled, so a name
   such as `pt_mrn` does not occur and is not guessed at.
4. **Apply `WHERE`**, one condition at a time, counting the rows each removes and
   how many of those were `NA`.
5. **Check `KEY`.** Rows must be unique on `KEY`. A duplicate stops the job,
   reporting how many keys repeat (never which), and pointing to `KEY`. Patients
   are counted on `ID`.

### 4.2 What it returns and the report prints

`read_job_data()` returns `list(data, record, provenance, attrition)`: the rows, a
record of the steps, the read's provenance record, and an analysis set's
exclusion table (`NULL` for a plain dataset). The template prints the record as a
**Data** table:

| Step | Value |
|---|---|
| Source | dataset `study` (`built.rds`) |
| Rows read | 800 |
| ID | `ccfid` (or: fell back to `MRN`) |
| Identifiers dropped | `MRN` |
| `age >= 18` | removed 12 (3 had missing age) |
| Rows kept | 788 rows on 788 patients |

The record's settings (`attr(record, "selection")`: dataset, analysis set,
`WHERE` as text, ID, KEY, row and patient counts) travel in a `selection` slot of
the hand-off lineage a job attaches to its saved artifact
(`.attach_handoff_lineage()`), so the next job in a set can reuse them (section 5).
Existing hand-offs without the slot still validate.

**`WHERE` text and identifiers.** A condition that mentions the ID or KEY columns
(for example `ccfid != 12345`, a common way to exclude named patients) is shown
everywhere a report displays or prints it with its values replaced:
`ccfid != <value>`. The exact text is kept only in the saved hand-off inside the
study, where a downstream job needs it to rebuild the rows. Decided by John on
2026-09-29 after the branch review.

ID and KEY names are matched ignoring case, since `read_built()` lowercases
column names.
`EXPECTED` counts stay available as an optional check against the record.

### 4.3 No study set up

Today a job run outside a study stops in its `setup` chunk, where
`hvtiRutilities::study_root()` looks for `_study.yml`, with a message that
suggests `study-setup --recover`, a server command for recovering a lost
`_study.yml`. A new analyst needs `study_setup()` instead. The `setup` chunk
finds the root through an hvtiRtemplates helper that stops with:

> This job is not inside a set-up study (no `_study.yml` above it). Create one
> with `hvtiRutilities::study_setup("<study folder>", ...)`, register its data
> with `register_data()`, then scaffold jobs with `add_job()` or `open_job()`
> from inside it. If this study had a `_study.yml` and lost it, recover it with
> `study-setup --recover`.

### 4.4 Why hvtiRtemplates, not hvtiRutilities

The first draft put `read_job_data()` in hvtiRutilities, on the reasoning that
jobs did not need hvtiRtemplates when they render. They do: every template calls
`hvtiRtemplates:::.embed_provenance()`, and 27 call `.provenance_read()`, when the
job renders. hvtiRtemplates imports hvtiRutilities, so a function in hvtiRutilities
could not call the provenance code this design depends on without a circular
dependency. Corrected by John on 2026-09-29, before any code.

## 5. Downstream jobs read the record

Jobs that read an upstream job's output (`hm`, `hp`, `hs` from `hz`; each
forest `explain` from its `fit`; the bootstrap reports from their bag) take
`DATASET`, `ANALYSIS_SET`, `WHERE`, `ID`, `KEY`, `TIME` and `EVENT` from the
upstream selection instead of asking again, through one helper,
`.read_upstream_job_data()`. It checks the job's own settings against the
selection (a set value that disagrees stops, naming both), rebuilds `WHERE`,
reads the data where the job reads data, and stops if the rows or patients
differ from upstream's, so a downstream job cannot silently run on a different
cohort. An upstream artifact saved before this contract has no selection; the
helper stops and says to rerun the upstream job (decided by John on 2026-09-29).
This replaces the hazard chain's hand-typed filter in every job and closes #176
and #177.

## 6. The identifier rule, across three packages

Identifiers are now handled once, at read. The consequences elsewhere:

- **hvtiRtemplates `dp-eda` and `dp-postage`** drop their name rule for
  identifiers (the stem list `ccfid`, `patientid`, `studyid`, ... and "any name
  containing `mrn`", added 2026-09-28). They keep the date rule and the "text
  column where every value differs" rule, which find columns that should not be
  drawn, whatever their names.
- **hvtiPlotR `hv_eda_pages()`**, whose `vars = NULL` default leaves out the same
  stems and "any name holding `mrn`" (released in 2.8.0), narrows to `ccfid`,
  `MRN` and `eMRN`. Released as 2.8.1.

## 7. Scope by family

| Family | Change |
|---|---|
| Descriptive (6) | `ANALYSIS_SET` default `NULL`; add `WHERE`, `ID`, `KEY`; `dc-general`'s `KEY_COLS` becomes `ID` and `KEY` |
| `dp-trends` | its `edit-data` chunk becomes `data`; add the shared settings |
| Logistic (8) | `ID` default `"id"` becomes `"ccfid"`; add `ANALYSIS_SET`, `WHERE`, `KEY`; `lm-checkpred`'s validation cohort is a `WHERE` or a dataset, and must not share a `KEY` with the training cohort |
| Hazard chain (5) | `STATUS` becomes `EVENT`; `iu_dead`/`idead` defaults become `iv_dead`/`dead`; the `edit-cohort` filter becomes `WHERE`; downstream jobs read the record |
| Random forest (6) | `fit` gains the shared settings; `explain` reads them from the fit's record |
| Bootstrap (4) | the reports read a bag, not data. The contract applies to the runner that makes the bag, and the bag carries the data record as its lineage (#185). The report prints the record from the bag |

## 8. Rollout

1. **hvtiRtemplates, the function first:** `read_job_data()`, the Data table, the
   record in the hand-off lineage, the upstream check and the missing-study
   helper, with a contract test that lists the families not yet converted.
2. **hvtiRtemplates, one PR per family** after it, so each Wednesday review sees
   one family's change, each shrinking the contract test's list. `migrate_job()`
   writes the new names for the jobs it creates. There are few existing template
   jobs, so no translation of old template settings.
3. **hvtiPlotR 2.8.1**, independent of the other two.

The hvtiRtemplates 1.2.3 release goes first, without this contract, so it is not
held up.

## 9. Testing

- **hvtiRtemplates, `read_job_data()` on small synthetic data frames:** each
  `WHERE` form (`NULL`, one expression, a list), with per-condition counts and
  `NA` rows counted apart; the ID fallback `ccfid`, `MRN`, `eMRN`, then the stop;
  `MRN`/`eMRN` dropped unless serving as the ID, and `pt_mrn` left alone; `KEY`
  uniqueness, where a cross-sectional duplicate stops, longitudinal and
  imputation keys pass, and the message reports counts and never values; an
  analysis set with a non-`"study"` dataset refused; the missing-`_study.yml`
  message names `study_setup()`.
- **hvtiRtemplates, one contract test over every template:** `DATASET`,
  `ANALYSIS_SET`, `WHERE`, `ID` and `KEY` in `edit-study-choices` with these
  defaults; a chunk named `data` calling `read_job_data()`; the section 3.3 names
  for any time-to-event, outcome, treatment or predictor setting. Proved by
  mutation: break one template and the test goes red.
- **Downstream:** `hs` given a `WHERE` that disagrees with `hm`'s record stops.
- **The gallery is the end-to-end check.** All 30 templates render again on the
  synthetic study, and the data-path workarounds in `dev/gallery/family-*.R`
  (the hazard chain's zero-time filter slot, the forests' missing `WHERE`, the
  logistic family's extra registered datasets) are replaced by `WHERE`
  settings. Each workaround removed is evidence an issue closed.
- **Every release** passes the release gate: `R CMD check --as-cran` with the
  manual.

## 10. Open

- **Which templates expect repeated rows?** None of the 30 is longitudinal
  today; stacked imputations (`lm-*`, `IMPUTATION`) set `KEY` themselves. The
  first longitudinal template (`mm`, `gm`, `dp-spaghetti`) will set its own
  `KEY` default.
- **Same-day deaths** (#175) are outside this note: a time of zero is a value,
  not a selection. It needs its own named rule in the hazard chain.
