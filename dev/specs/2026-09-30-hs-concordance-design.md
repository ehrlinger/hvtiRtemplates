# The `hs-concordance` template: every patient through every group's model

**Date:** 2026-09-30
**Status:** design, not implemented. No plan yet.
**Decided by the maintainer on 2026-09-30:** the name is `hs-concordance`; the
existing `hs` template becomes `hs-setup`; a model from another study is
allowed but not expected.
**Left open by the maintainer on 2026-09-30:** whether the models should share
one variable set (section 8).

This note is self-contained. It assumes no memory of the session that
produced it.

---

## 1. What this decides

The shape, inputs, guards and saved artifact of a new template,
`inst/templates/40_graphs/hs-concordance.qmd`, and the rename of the existing
`hs` template that the qualifier rule forces (section 4).

It does not decide a display of the predictions against a covariate
(section 10), a one-model "who benefits" template (section 11), or anything
about forest-based twins.

---

## 2. Evidence, measured on 2026-09-30

**The request.** The director described the most important `hs` job for a
current two-cohort valve study as: predict one cohort's patients, at 10
years, from the model fitted on the other cohort, and set that against the
first cohort's own experience, displayed against age. He called it "typical
twins fashion".

**The census.** A source-text census of every `hs` job under the studies
tree, run on the production server (script and output in
`general/_development/hs-two-model-census-20260930/` on the studies share):

| class | files | studies |
|---|---|---|
| reads two or more models | 33 | 15 |
| one model, repeated predictions | 129 | 42 |
| one model, one prediction | 33 | 15 |
| no prediction | 193 | 56 |

388 source files in 73 studies, all read. No `hs` file contains the word
"twin". The corpus name for the shape is **concordance and discordance**.

⚠️ 73 is not the 144 studies `inst/templates/README.md` reports for `hs`.
This census counts studies holding an `hs` SOURCE file at three directory
depths; the README counts files of any extension. Do not reconcile them by
eye.

**Three exemplars, all read in full.** That opens the two-studies gate.

| | A | B | C |
|---|---|---|---|
| study | `cardiac/ischemic/comparison/cabg_pci` | `cardiac/failure/ischemic/comparison` | `cardiac/ischemic/cabg/reoperation/mag` |
| job | `hs.dead.concor_discor10.sas` | `hs.dead.concor_discor.sas` | `hs.dead.check.mtc_concor_discor10.sas` |
| models | 3 | 4 | 2, plus a third slot that re-reads the second |
| horizon | 10 years | 5 years | 10 years |

C is a copy of A with the names changed. All three run the same steps:

1. take the cohort;
2. keep the union of every model's covariates;
3. set ONE horizon;
4. read one fitted model per treatment group;
5. predict every patient through every model, keeping each survival under
   the group's name;
6. call the highest survival "optimal" and cross it with the treatment the
   patient received;
7. save the patient-level predictions for the plotting jobs.

**What each adds.** B applies clinical eligibility rules, so a prediction for
an operation the patient could not have had cannot win. C keeps the
confidence limits and flags patients whose intervals do not overlap, and it
restricts the cohort to matched cases with models fitted on the matched set.

**What fails quietly in them.** These are readings of the source; no output
was opened, so none is claimed to have changed a published number.

| job | in the source | consequence |
|---|---|---|
| A | the header says one model is "NOT USED FOR 10 YEARS"; it is predicted at 10 years and competes for optimal | extrapolation past a group's follow-up |
| all | optimal is an `if / else if` chain over `max()` | a tie goes to the group listed first, unrecorded |
| A, B | optimal is chosen on point estimates | a fourth-decimal difference decides |
| B | the overall optimal is computed before eligibility is applied, the per-group tables after | two definitions of optimal in one job |
| B | ineligible predictions are overwritten with `-1` and then saved | a reader takes `-1` for a survival |
| C | the third model slot reads the second model | a placeholder that produces numbers |

**Two-model jobs that are NOT this shape.** Five further studies were opened
and none is a concordance job: two nested models of the same patients
overlaid with no choice (`hs.dead.current_era.surv`), one model under several
scenarios (`hs.dead_srg.life_saved`, `hs.dead.mr.setup`), two versions of one
model in a setup job, and two stratum models saved apart. Brier jobs read a
death model and a censoring model. A two-model read is a candidate, not a
classification.

**No exemplar reads a model from another study.**

---

## 3. The shape

`hs-concordance` has a **core** and an **optional decision section**.

The core is steps 1 to 5 and 7: a named set of models, one horizon, every
patient through every model, one saved artifact. The director's request and
all three exemplars share it.

The decision section is step 6. The exemplars have it; the director's
request does not, and it is where most of the quiet failures in section 2
sit. It is a section the author keeps or deletes, marked `EDIT:`.

The number of models is 2, 3 and 4 in the exemplars, so the template takes a
list, never a pair.

---

## 4. Name, and what the qualifier rule forces

The file is `40_graphs/hs-concordance.qmd`: prefix `hs`, qualifier
`concordance`.

⚠️ **A prefix must be wholly qualified or wholly unqualified**, and
`check-roadmap-counts.py` enforces it. `hs` ships today as one unqualified
template, so adding `hs-concordance` requires the existing template to take a
qualifier in the same change.

**Decided: `hs-setup`.** It is the corpus's own word (`hs.dead.setup`), and
the existing template's narration already explains the `setup` and
`uses_setup` pairing.

Consequences of the rename, to be carried by the plan:

- `add_job("hs", ...)` with no qualifier becomes an error listing the
  choices. That is the documented behavior for an ambiguous prefix.
- Jobs already scaffolded as `<subject>-<type>-hs.qmd` keep their names. No
  study file is renamed.
- The ledger gains a row and changes one; `inst/templates/README.md` and the
  catalog follow. `.lintr` needs a file key for each of the two files.

---

## 5. Interface

```r
add_job("hs", subject = "dead", type = "cabg_pci", qualifier = "concordance")
```

The job's own `(SUBJECT, TYPE)` names the **comparison set**, where its
artifact is written. The models are read from OTHER sets. That is a
deliberate departure from `hs-setup`, which reads `hm.rds` from its own set
precisely so that a prediction cannot be filed against another set. Here the
crossing is the point, so it is declared instead of prevented:

```r
# EDIT: one entry per group. The NAME is the group's label in this report
#       and must be a value of GROUP below. The VALUE is the set whose hm job
#       fitted that group's model.
MODELS <- c(cabg = "dead-cabg", pci = "dead-pci")

# EDIT: the column recording which group each patient was actually in.
GROUP <- "group"

# EDIT: the single horizon, in TIME's own units.
HORIZON <- 10
```

Each model is read through `.read_handoff()` from
`<estimates>/<set>/hm.rds`, as `hs-setup` reads its one. The lineage of every
model read is attached to the saved artifact.

Study choices carried over unchanged from `hs-setup`: `TIME`, `EVENT`, the
cohort filter, `CLEVEL` (0.68268948) and logit-scale limits.

---

## 6. The core

In chunk order:

1. **`guard-edits`, `set`**: as in `hs-setup`.
2. **`edit-cohort`**: read the built data, apply the job filter. The overlap
   choice is made here (section 7).
3. **`models`**: read each entry of `MODELS`. Stop if two entries resolve to
   the same file, which is exemplar C's placeholder.
4. **`covariates`**: take each model's covariates from its artifact. Stop if
   the cohort lacks a column any model needs. Apply
   `covariates_to_numeric()` as `hs-setup` does.
5. **`horizon`**: for EACH model, stop if `HORIZON` exceeds the last observed
   time in that model's fitted data. One check per model, because exemplar A
   fails on one model out of three.
6. **`support`**: for each model, count the patients whose numeric
   covariates fall outside the range that model was fitted on, and print the
   counts by covariate. This reports and does not stop: predicting a patient
   under another group's model is the purpose, and how far outside is
   acceptable is a clinical judgment.
7. **`predict`**: one `predict()` call per model on the same patient frame,
   `type = "survival"`, with limits. The result is LONG: one row per patient
   per model, with columns for patient id, actual group, model name,
   survival, lower and upper.
8. **`summary`**: for each model, the distribution of predicted survival
   within each actual group, as a table.
9. **`save`**: `hs-concordance.rds` in the comparison set, holding the long
   predictions, `HORIZON`, `CLEVEL`, the per-model covariate lists, the
   support counts and the overlap choice.

Long form is chosen over the exemplars' one column per model because it
holds any number of models without new column names, and because the display
the director asked for is a plot of survival against a covariate by model,
which is one grouped aesthetic on a long frame.

---

## 7. Overlap is the author's choice, and the report states it

The three exemplars and the one R precedent made four different choices:
none (A, B), matched cases (C), propensity common support (the R twins
book). The template cannot default one of them without deciding a study's
estimand.

So `edit-cohort` carries an `EDIT:` with the three options written out, and
a required declaration:

```r
# EDIT: "none", "matched" or "common_support". Say which, and why, in the
#       prose above. It is saved with the estimates and printed in the report.
OVERLAP <- NULL
```

A `NULL` stops the render. The value is saved so that a reader of the
artifact does not have to recover it from prose.

---

## 8. Variable sets: not enforced either way

Every exemplar gives each group's model its own variable list. The
director's request floats the opposite for a small cohort: fit it with the
larger cohort's variables, with a stated worry that few events make that
model overdetermined.

**This is undecided, and it is not this template's decision to make.** Which
variables a model carries is settled in each group's `hm` job. The template
works with either and does two things so the choice is visible:

- prints the per-model covariate lists side by side, marking which are
  shared;
- saves them in the artifact.

If a shared set becomes practice, the place for it is a note in the `hm`
template, not a rule here.

---

## 9. The optional decision section

Kept or deleted by the author. When kept, it fixes the failures in
section 2:

- **Eligibility is a mask, never a sentinel.** An optional logical column
  per model. An ineligible prediction is `NA` in the decision step and is
  left untouched in the saved predictions.
- **One definition of optimal**, computed after eligibility.
- **Ties are reported.** The count of patients whose best two predictions
  are equal is printed, and those patients get no optimal group.
- **Differences are reported with their limits.** Alongside the point
  choice, the count of patients whose optimal model's lower limit is above
  the runner-up's upper limit, which is exemplar C's check. The coverage is
  named wherever it is printed, because 0.68268948 is not the coverage a
  reader assumes.
- **The concordance table**: actual group by optimal group.

Its results are saved in the same artifact under `decision`, absent when the
section is deleted.

---

## 10. Out of scope: the display against a covariate

The director's request ends in a figure of the paired predictions against
age. The artifact in section 6 is built to feed it, but the figure is a
plotting job and a separate template.

⚠️ **That template is not yet allowed.** No corpus job shows two group
models against a covariate without choosing between them, so the request is
its only exemplar and the two-studies gate is closed. The first study writes
the figure as a study job reading `hs-concordance.rds`; a template follows a
second.

---

## 11. Out of scope: other shapes found on the way

- **One model, treatment flipped** ("who benefits"). 15 files in 6 studies,
  and the SAS template `tp.hs.dead.compare_benefit.setup`. It needs the
  treatment IN the model, where concordance models the groups apart. The
  gate is open for it and it is a separate qualifier, not a mode of this
  template.
- **Forest twins.** Two R studies do this with random survival forests.
  They are not `hs` jobs and belong with the forest templates.
- **Validation** (Brier, C-index). Still out of `hs`, for the reason the
  `hs` design gave.

---

## 12. A model from another study: allowed, not expected

No exemplar does this. It is allowed because the request in section 2 is
exactly this case.

An entry of `MODELS` may be a path to another study's `hm.rds` instead of a
set name. When any entry is a path:

- the render stops unless `CROSS_STUDY <- TRUE` is set, so a cross-study
  read is never an accident of a mistyped set name;
- the other study's lineage is attached like any other handoff;
- the `support` counts in section 6 matter most here, and the narration
  says so.

The template still carries no study identifier: the path is the author's
`EDIT:`.

---

## 13. Open questions

1. **Shared variable sets** (section 8). Open by the maintainer's own
   account; the template does not wait on it.
2. **Whether `support` should be able to stop the render** above some
   fraction of patients outside a model's range. Proposed: no, report only.

---

## 14. Definition of done

- `add_job("hs", "dead", "x", qualifier = "concordance")` scaffolds a job
  with exactly one `SUBJECT` line and one `TYPE` line.
- The template renders against two fitted models in a test fixture, and the
  saved artifact has one row per patient per model.
- Tests, each proved by mutation: two `MODELS` entries resolving to one file
  stop the render; a horizon beyond ONE model's follow-up stops it; a path
  entry without `CROSS_STUDY` stops it; `OVERLAP <- NULL` stops it; a tie
  yields no optimal group; an ineligible prediction is unchanged in the
  saved predictions.
- `hs-setup` renders as `hs` did, and `add_job("hs", ...)` without a
  qualifier errors with both choices listed.
- Each of the two files has its own `.lintr` key.
- `devtools::test()` passes and `devtools::check()` is 0/0/0.

---

## 15. Rejected

- **An engine-neutral job taking any two fitted models.** The two engines
  have different prediction interfaces and different homes in the taxonomy.
  Three hazard-model exemplars justify a hazard-model template; the forest
  case can follow its own.
- **A pair of models.** The exemplars use 2, 3 and 4.
- **Calling it `hs-twins`.** It is the director's word and the R book's,
  but no `hs` job in the corpus uses it, and a study author searching the
  corpus finds `concor_discor`.
- **Defaulting the overlap choice.** Four precedents, four choices.
- **Making the decision section the template's purpose.** The request that
  started this does not want it.
