# Working data, registered data and the freeze: how a study's jobs become final

**Date:** 2026-10-05
**Status:** superseded on 2026-10-23, never built. hvtiRutilities
`dev/specs/2026-10-13-one-version-scheme-design.md` replaced it: that design retired releases and
`PUBLISH`, and chose dated versions with provenance plus `working=` / `HVTI_DATA=working` reads,
limited to dataset and descriptive jobs and the console. Kept as the record of the reasoning, and
for the review findings in section 12, which still bear on any future freeze. Decision 1
(section 3) was made by John Ehrlinger on 2026-10-05.
**Reads with:** `2026-09-29-template-data-contract-design.md` (the selection record this
extends), `2026-10-02-bd-build-job-design.md` (the draft and release files this names) and
`2026-08-13-templates-and-provenance-design.md` (the sidecars the audit reads).
**Packages:** `hvtiRtemplates` (the read mode, the hand-off guard, the templates) and
`hvtiRutilities` (the currency audit and the freeze checkpoint).

This note is self-contained. It assumes no memory of the session that produced it.

⚠️ No study, variable value or patient identifier appears here. `older`, `age` and `ccfid` are
column names in a synthetic four-row probe.

## 1. The problem

The data contract assumes a job reads **registered** data and nothing else.
`read_job_data()` reads a registered dataset or analysis set, applies `WHERE`, and records the
selection (dataset, conditions, rows, patients, `key_hash`) that a downstream job uses to
rebuild the same rows. A study does not work that way. Early on, an author explores data that
is not registered yet and derives variables inside a job, as the SAS data step did. Later the
data must be frozen and every job shown to be current against it. The package supports the
second half and has no account of the first.

Measured on a synthetic study, 2026-10-05:

1. **`WHERE` on a derived column stops**: `WHERE condition 'older == 1': object 'older' not
   found`. `WHERE` runs inside the read, before any job code, so a SAS `data; set; older = ...;
   if older;` cannot be expressed in it. This is loud and safe.
2. **Deriving and then filtering in the job records the wrong cohort, silently.** The job
   analysed 2 rows; its selection recorded `where = (none)`, `rows = 4`, `patients = 4`. The
   report's data table states the wrong cohort, and a downstream job rebuilds 4 rows, compares
   them with a record that also says 4, and passes every check. It then describes a different
   cohort from the one the upstream model was fitted on.
3. **Registering the derived file fixes it.** The same derivation written to a file registered
   with `register_data(role = "named", dataset = "older")`, read with `DATASET <- "older"` and
   `WHERE <- quote(older == 1)`, recorded `rows = 2` and a matching condition.

The fix in (3) is the right end state and the wrong starting point: it asks an author to
register data before knowing whether the data are worth keeping.

## 2. What exists

| need | built, and where |
|---|---|
| a frozen copy of the data | `bd.qmd` under `PUBLISH = TRUE` publishes `<dataset_id>_<YYYYMMDD>[-rN]` and pins its `release_id` in `_study.yml` |
| knowing new data arrived | `check_data_updates()`, `review_data_update()`, `adopt_data_update()` (hvtiRutilities) |
| what each render read | the `.provenance.json` sidecar: data SHA-256 per read, source SHA-256 per managed file |
| a frozen moment | `study_checkpoint(kind, attributes =)`, a tagged snapshot in `.checkpoint/` |
| a draft render | `HVTI_TEMPLATE_STRICT`: unset renders a job with unworked `EDIT:` markers as a draft; set, it stops |

Missing: a sanctioned way to read unregistered data, and a check that each job's sidecar
still matches the pinned data and its own source. `study_status()` checks that a sidecar
exists for every source, not that it is current.

## 3. Decisions

| # | question | answer |
|---|---|---|
| 1 | Is a freeze per study or per manuscript? | **Both, because they are the same thing: one study per manuscript, one-to-one and onto.** A freeze therefore covers every job in the study and never has to name its jobs. An abstract that precedes the paper is a checkpoint inside the same study, not a separate freeze |
| 2 | How is unregistered data read? | Proposed: `DATASET <- "draft:<dataset_id>"` (section 5) |
| 3 | What does such a render produce? | Proposed: a draft, in the same sense as an unworked `EDIT:` marker (section 5.2) |
| 4 | May a registered job derive columns? | Proposed: yes; it may not drop rows after the read (section 6) |
| 5 | What is "current"? | Proposed: the six statuses of section 7 |
| 6 | What is the freeze? | Proposed: a `data_frozen` checkpoint, taken only when every job is `CURRENT` (section 8) |

## 4. Three states

1. **Working.** Data is unregistered: a `bd` draft, or columns a job derives itself. Any job
   may read it. Every render is a draft.
2. **Registered.** The study pins a release. Jobs render normally against it. Job-side
   derivations may add columns; rows are chosen only by the dataset, an analysis set or `WHERE`.
3. **Frozen.** Every job is current against the pinned release, and a checkpoint records it.

A study moves forward through these and may move back: new data reopens the study, which
returns it to registered, and its jobs go `STALE-DATA` until rerendered.

## 5. Reading working data

### 5.1 The read

`DATASET <- "draft:<dataset_id>"` reads `00_datasets/draft-<dataset_id>.rds`, the file `bd`
already writes in draft mode. `read_job_data()` applies `WHERE`, `ID` and `KEY` exactly as for
a registered dataset, and records `dataset = "draft:<dataset_id>"` in the selection. The
sidecar records the read with role `draft:<dataset_id>`, mirroring the existing
`analysis_set:<name>` role, and the data file's SHA-256 as for any read.

Only files under `00_datasets/` named `draft-*.rds` are readable this way. An arbitrary path is
not: a draft is still a file the study's own build job wrote, so the provenance chain from
master snapshot to job stays unbroken.

### 5.2 The render is a draft

A job that read any `draft:` dataset renders with a draft banner, and its sidecar carries
`status: draft`. `HVTI_TEMPLATE_STRICT=1` stops it, with a message naming the dataset and
`bd`'s `PUBLISH` as the way out. This reuses the `EDIT:` guard's meaning of "draft" rather than
adding a second one: a render early and fast, never mistaken for final.

## 6. The hand-off guard

Closes problem (2) in section 1 for registered data. When a job saves its hand-off, it checks
the rows it is handing off against its own recorded selection: row count, patient count and
`key_hash`. A mismatch stops the render and names the fix: move the filter into `WHERE`, or,
when it needs a derived column, derive it in `bd` or a registered named dataset.

Adding columns is not refused. A derived predictor is the job's business, and a downstream
job that needs it stops loudly on the missing column today.

## 7. The currency audit

A read-only function in hvtiRutilities, beside `study_status()` and feeding a row into it. For
every managed job source it reports one status:

| status | meaning |
|---|---|
| `CURRENT` | sidecar present; every data hash equals the pinned file's; source hash equals the `.qmd`'s; every upstream hand-off it read is itself `CURRENT` |
| `STALE-DATA` | a data hash in the sidecar differs from the pinned file's |
| `STALE-SOURCE` | the `.qmd` changed after the render |
| `STALE-UPSTREAM` | it read a hand-off whose job is not `CURRENT` |
| `DRAFT` | the sidecar carries `status: draft` |
| `NO-SIDECAR` | never rendered, or the sidecar is missing |

Every input is already on disk, so the audit compares and writes nothing. It also gives the
rerender order: the numbered folders already run in hand-off order, `00` then `10` and `20`,
then `30`, `40`, `50`.

## 8. The freeze

`study_checkpoint(kind = "data_frozen", attributes = list(release_id = ...))`, refused unless
the audit reports every job `CURRENT`. Because a study is one manuscript (decision 1), "every
job" needs no further scoping.

## 9. Naming conventions

| thing | convention | status |
|---|---|---|
| logical dataset name | `study` is reserved; any other is `[a-z0-9_]+`, no `-` | matches the `subject` and `type` rule in `add_job()` |
| working file | `00_datasets/draft-<dataset_id>.rds` | written by `bd` today |
| reading it | `DATASET <- "draft:<dataset_id>"` | new |
| published release | `<dataset_id>_<YYYYMMDD>[-rN]` | owned by `publish_dataset()`; not redefined here |
| freeze | checkpoint kind `data_frozen`, `release_id` in its attributes | new kind |

## 10. Open

1. Is `data_frozen` in the StudyTracker checkpoint vocabulary, or does it need adding there?
2. A frozen study holding exploratory jobs left as drafts cannot freeze under section 8. Delete
   them, or exclude a marked set (for example an `explore/` folder) from the audit?
3. Can a job read a `draft:` dataset and a registered one together, and if so which one does
   the selection record?
4. Does the hand-off guard belong in `read_job_data()`'s caller in each template, or in the
   shared hand-off writer? Read the writer before deciding.

## 11. Out of scope

Changing `publish_dataset()`'s release naming, the `bd` template's cohort steps, and the
hvtiRutilities update functions of section 2.

## 12. Review findings carried forward

Codex reviewed this note on 2026-10-23 ([#413](https://github.com/ehrlinger/hvtiRtemplates/pull/413)),
after it had been superseded. Three findings still hold for whatever design next decides when a
study's results are final, so they are recorded here as open questions rather than fixed in a
design nobody will build.

1. **Currency must compare content, not status.** The audit of section 7 asks whether each
   producer is current. A consumer is stale when a hand-off it read has changed since, so compare
   the SHA-256 each consumer recorded for each hand-off (the `.read_handoff()` lineage) against
   the hand-off on disk.
2. **The source hash has to persist.** Post-render publication removes `.hvti_source_sha256`
   (`R/provenance.R`), so nothing durable records which job text produced a result. The record
   must also cover the study `R/*.R` helpers that `.job_setup()` sources, since a change there
   changes results without touching the job.
3. **Rerender order is a graph, not a folder number.** Ordering by the numbered taxonomy folder
   breaks when a later folder feeds an earlier one or two jobs share a folder, as `rfc-fit` and
   `rfc-explain` do. Derive the order topologically from the hand-offs each job consumed.
