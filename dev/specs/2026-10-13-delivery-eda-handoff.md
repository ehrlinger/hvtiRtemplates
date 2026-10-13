# Handoff: an EDA report that ships with every data delivery

**Date:** 2026-10-13
**Repo:** hvtiRtemplates (report side); the data management repo in ADO (runner side)
**Status:** not started in this repo. Nothing under `R/` or `inst/templates/` changed.
**Origin:** design session with John, 2026-10-13.
**Priority:** next templates update, after the work already in flight.

⚠️ No study, variable or patient identifier appears here. The artifact uses
simulated data only.

---

## 1. What is asked

Every data request the team fills ships with a standard EDA report. The same
report does two jobs:

1. **Quality check before delivery.** Data managers and stat programmers read it
   for missingness, follow-up and outliers while the query can still be fixed.
2. **Orientation after delivery.** Researchers read it to understand what they
   received.

Deliveries into a study also carry the exact query that produced the data, so a
stat programmer starts from the executed query.

The data can be patient-level, longitudinal (repeated measures, expected long),
or both.

## 2. What exists here already

This handoff was designed before the session looked at this package, so the
artifact re-implements pieces that already ship. Read this section before the
artifact.

| need | already here |
|---|---|
| whole EDA report in one render | `10_descriptive/dc-eda.qmd` |
| goodness-of-follow-up figure | `hvtiPlotR::hv_followup_panels()`, through `dc-gfup` |
| missing, negative and zero interval checks | `hvtiRutilities::followup_check()`, through `dc-gfup` |
| continuous, percent and count postage stamps | `hvtiPlotR::hv_eda_pages()`, through `dc-eda` |
| trends over operation year | `10_descriptive/dc-trends.qmd` |

The artifact's `report/R/plots.R` and the overlapping parts of
`report/R/checks.R` (`check_followup()` interval checks) should be replaced by
these engines, not merged beside them. Two EDA reports that can disagree about
the same data is the outcome `dc-eda` was built to prevent.

## 3. What is new

These have no counterpart in the package today, and are the content of the
handoff:

1. **Flags as data.** Every check returns rows of one shape (table, variable,
   check ID, severity, count, finding, record IDs). The report renders them; a
   runner reads them as JSON.
2. **Two audiences from one template.** `internal` shows every flag and an
   appendix of record IDs; `delivery` shows each flag with the data manager's
   note and no IDs.
3. **The notes gate.** No warning or error flag ships without a note in
   `notes.yml`, keyed by table, variable and check. This is the warehouse rule of
   adjudicating at delivery, applied to the report.
4. **Checks the package lacks:** missingness by calendar year (MISS-ERA),
   explicit unknown codes counted apart from missing (MISS-UNK), clinical ranges
   before a robust fence (OUT-RANGE, OUT-FENCE), follow-up past the close date,
   follow-up after a terminal event, and the completeness index C (Clark,
   Altman and De Stavola, Lancet 2002).
5. **Longitudinal checks:** orphan measurements, cohort patients with no
   post-index measurement, pre-index and post-close measurements, conflicting
   duplicates, within-patient jumps, and yearly level shifts that signal a unit
   change.
6. **Input guards** that stop the render with a named reason: missing variable,
   duplicate patient rows, wide longitudinal tables, non-0/1 event indicators,
   unparseable dates.
7. **A single `config` parameter.** Quarto turns nested parameters (a list of
   events) into data frames, so the report takes one path to a YAML file and
   reads it with `yaml::read_yaml()`.

## 4. Proposed shape

- A `delivery` mode for `dc-eda`, or a sibling row, decided against
  `2026-09-03-template-identity-design.md`. The sections in 3.1 to 3.6 become
  exported functions whose output `dc-eda` can render.
- The runner (`runner/deliver.py`) does not belong in this package. It executes
  `.sql` files with bound parameters, writes parquet, renders both audiences,
  applies the gate and assembles the bundle with a manifest. It moves to the
  data management repo in ADO and calls the template through `quarto render`.

## 5. The artifact

`dev/specs/artifacts/2026-10-13-delivery-eda/` holds the spec (`SPEC.md`) and a
working skeleton built against it on a synthetic SQLite source with planted
problems. `README.md` there walks the example end to end.

Verified in the session that built it: the testthat file for the checks passes,
the pytest file for the runner passes including a full prepare and bundle run,
and every planted problem raised its expected flag. One gap: R `arrow` could not
be installed where it was built, so the parquet read went through a test-only
stand-in and `arrow::read_parquet()` itself has not run against this code.

## 6. Open decisions

1. Where the bundle lands in a study folder; study folders are created upstream.
2. Who may write notes, and whether a second person signs off before bundling.
3. Starting thresholds, to be tuned on the first real deliveries.
4. Mode of `dc-eda` versus a new row (section 4).
