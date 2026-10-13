# How a study's dataset is created in R: one master, one working file, dated registered versions

**Date:** 2026-10-13
**Status:** architecture approved by John Ehrlinger on 2026-10-13 (sections 3 and 4).
Sub-project A (section 6) is the next to be specified in detail; nothing here is built yet.
**Supersedes, where they disagree:** `2026-10-02-bd-build-job-design.md` decision 4 (`MASTER`
names a parquet snapshot) and its release publication; `2026-10-05-data-freeze-design.md`
(unpushed, branch `spec/data-freeze`) section 9's working file and release naming.
**Reads with:** hvtiRdatabuild `2026-09-23-cardiac-master-view-design.md` (the view and its
corrections); hvtiR `dev/specs/2026-10-07-dated-parquet-manifest-design.md` (dated versions);
`2026-09-29-template-data-contract-design.md` (the selection record jobs keep).
**Packages:** hvtiRutilities (registration), hvtiRdatabuild (master, corrections),
hvtiRtemplates (`bd`, the adoption job, the read path).

This note is self-contained. It assumes no memory of the session that produced it.

⚠️ No study, variable value or patient identifier appears here.

## 1. The problem

The tools for getting data into a study were designed in pieces, and the pieces disagree:

1. **Corrections never reach a study.** The cardiac master design says a study reads the
   corrected master *view*. `bd.qmd` reads the master's *parquet snapshot*, which carries no
   corrections.
2. **A study can be on one of two version schemes and cannot move between them.** A legacy
   registration (`register_data()` without a release) keeps dated parquet versions in the
   manifest. A `bd` build publishes catalog *releases* (`dataset-catalog.yml`,
   `<id>-YYYYMMDD-rN`) and registers one. `register_data()` refuses to move a study from the
   first to the second, and `bd` stops on a legacy-registered study.
3. **A study's corrections have no way back.** In SAS a study fixes a value it disagrees with
   inline in its build program. Those fixes stay in the study, so every other study cutting the
   same master inherits the uncorrected value, and the next cut of the same study loses them
   unless the program is carried forward.
4. **The R warehouse pull is a dead end.** `dw_pull()`, `build_dataset()` and `derive_vars()`
   exist in hvtiRdatabuild, but none writes a file and nothing passes their output to
   `publish_dataset()` or `register_data()`.

Smaller mismatches found while mapping this, recorded so they are not lost: `bd.qmd` accepts a
`DATASET_ID` beginning with a digit that `publish_dataset()` rejects; hvtiRdatabuild's
`read_study_config()` (reads `study.yaml`) and hvtiRutilities' `study_config()` (reads
`_study.yml`) share a class name; and "catalog" names four different things across the
designs (the release catalog, the job catalog `templates.json`, the mitral design's catalogue
of step shapes, and the `studies_data_catalog` repository).

## 2. What users expect, and what that rules out

Stat programmers know one working file per study: `built`, rebuilt in place whenever the
build runs. **They do not want dated `built` files.** A date belongs to a *registered*
version, the copy a result can be traced to, and only there. Any scheme that dates the working
file, or that asks an author to choose a version name before the data are worth keeping, is
ruled out.

## 3. Decisions

| # | question | answer |
|---|---|---|
| 1 | Where does the master live? | **In the warehouse, as one corrected view.** SAS and parquet are a one-time route in (`snapshot_master()` then `lift_master()`), not a copy that persists alongside it |
| 2 | How does a study get its data from the master? | **It cuts the view, pinned with `as_of`, and keeps a file.** Jobs keep reading a checksummed file under the existing manifest contract; no render needs a warehouse connection |
| 3 | What is a study's working data? | **One undated file, `built`,** whatever produced it: a legacy SAS build, a `bd` cut of the view, or a rebuild. It is overwritten in place |
| 4 | What is versioned? | **Only a registered dataset, and every registered dataset the same way:** a dated version (`<stem>_YYYYMMDD[_rN].parquet`), whatever produced it. How it was produced is provenance recorded on the version, not a second scheme |
| 5 | How does a legacy study enter (#225)? | **It registers its existing `built`.** That is decision 4 applied to a file SAS made. Its next version may come from a `bd` cut, which `compare_built()` checks against the legacy one |
| 6 | What does a study do with a value it believes is wrong? | **It records a correction in the study's overlay, applies it locally, and proposes it upstream.** See section 5 |
| 7 | Order of work | **A (one version scheme) before B (#225),** so the adoption job is built on the scheme that stays |

## 4. The model

```
SAS built.master --snapshot_master()--> parquet --lift_master()--> warehouse table
                                                                      |
                 corrections tables (propose / decide, as_of) --------+
                                                                      v
                                                        corrected master VIEW
                                                                      |  bd cuts, pinned as_of
                                                                      v
legacy SAS study built --+                        study overlay: corrections (section 5)
                         +--> datasets/built   (working: undated, overwritten)
                   bd ---+         |   each overlay row is also proposed upstream, pending
                                   v   register_data()
                     built_YYYYMMDD[_rN].parquet + manifest entry   (registered: dated, with provenance)
                                   |
                                   v   jobs: verify_manifest(); the freeze = every job CURRENT
```

Three states, matching the data-freeze design's: **working** (`built`, unregistered; a render
against it is a draft), **registered** (a dated version is pinned; jobs render normally) and
**frozen** (every job current against the pinned version, recorded by a checkpoint).

## 5. Study corrections

A study correction is **one cell**, written in `propose_correction()`'s shape: the master's
key, the `variable`, the `expected_prior` value, the `new_value`, `evidence_type`,
`evidence_ref` and `asserted_by`. It is never an inline `if <key> = ... then ...` in a build.

1. **The overlay.** A study keeps its corrections in one file under `00_datasets/`, one row
   per cell. The file holds keys and values, so it is study data: it lives on the share with
   the dataset and never in a repository.
2. **Apply.** `bd` applies each overlay row to its cut, after checking that the cut holds
   `expected_prior`. A row whose prior no longer matches stops the build, naming the variable
   and the count, never the key or the value.
3. **Propose.** Each new overlay row is proposed upstream with `propose_correction()`. It is
   pending there until `decide_correction()` decides it.
4. **Reconcile, on every later cut.** For each overlay row, the latest upstream decision says
   what happens: `accept`, the view now carries the value, so the row is a no-op and is
   retired; `reject`, the build stops until the study drops the row or argues it again; no
   decision yet, the row stays applied and pending.
5. **Report.** The build lists, by variable and count, how many corrections were applied,
   pending, accepted and retired, or rejected. The registered version's provenance records
   the overlay's SHA-256.

Work therefore continues while adjudication is pending, nothing the study analyses silently
differs from the view without being recorded, and other studies receive an accepted
correction on their next cut.

## 6. Sub-projects, in order

Each gets its own design, plan and pull request.

| | sub-project | package | depends on |
|---|---|---|---|
| **A** | One version scheme for study datasets: dated versions only, with provenance | hvtiRutilities | none |
| **B** | #225: register a legacy study's `built` (a `00_datasets` job named from `tp.bd.SAStoR`) | hvtiRtemplates | A |
| **C** | The master in the warehouse: run `snapshot_master()`, `lift_master()`, `backfill_corrections()` for the cardiac master. A runbook, needing warehouse write access and the registries team's agreement | hvtiRdatabuild | none |
| **D** | `bd` cuts the view, pinned with `as_of`, writes `built` and registers it | hvtiRtemplates | A, C |
| **E** | The study corrections overlay, and its reconciliation | hvtiRdatabuild, hvtiRtemplates | C, D |
| **F** | Fold the data-freeze design into this model (`draft:` reads become reads of an unregistered `built`) | hvtiRtemplates, hvtiRutilities | A |

### 6.1 What A has to settle

hvtiRutilities 1.5.2 already implements decision 4 for legacy studies: `registered_versions.R`
converts each accepted state of a study dataset once to `<stem>_YYYYMMDD[_rN].parquet`, keeps a
`history`, and leaves the source free to be rebuilt. A makes that the only scheme for study
datasets:

1. **Provenance on a version.** A version records its parquet, hashes, extract date, counts,
   schema hash, reader and `recovered_from`, but not how the data were produced. Add an
   `origin` (legacy build, or `bd`) and, for a build, a pointer to its build record: the job
   file, the master view and `as_of`, the cohort rules and the overlay's SHA-256.
2. **Retire the release path for study datasets.** `register_data(catalog_dataset =,
   release_id =)`, `check_data_updates()`, `review_data_update()` and `adopt_data_update()`
   work on the per-study release catalog. Decide what replaces them for dated versions, and
   whether `publish_dataset()` keeps any role for study datasets.
3. **Migration.** Count the studies registered by release before choosing between converting
   them and refusing them with a message. `bd` shipped in 1.2.4 as in-flight, so the count may
   be zero; measure it rather than assume it.

## 7. Open

0. **C's first question: lift the snapshot, or port the program?** `lift_master()` loads a
   frozen SAS snapshot into a base table, a copy SAS made. The cardiac build
   (`bd.data.master.sas`, measured by statement pattern on 2026-09-23) queries the warehouse
   (16 `proc sql` blocks), derives (48 data steps) and corrects inline (18 `if ccfid = ...`
   statements, 2 rule-style fixes) before saving `built.sas7bdat`. Porting the program would
   make the query and its renames a view over the warehouse's own tables, the derivations
   view columns, and the inline fixes rows in the corrections tables, leaving no SAS-made copy
   at all. It is the larger job. Not measured: whether the query or the data steps align column
   names to the standard, and whether the fixes run last or among the derivations.
1. Who runs the warehouse DDL and load for C, and who holds write rights there. The registries
   team declined upstream corrections as of 2026-10-01; section 5's proposals depend on that
   changing, or on the corrections tables being writable by the group.
2. The overlay's file format and name (section 5.1), and whether `propose_correction()` is
   called by `bd` itself or by a separate step a stat programmer runs.
3. Whether a correction proposed by one study and accepted upstream should notify other
   studies whose pinned versions hold the old value, or wait for their next cut.
4. Whether `dw_pull()`, `build_dataset()` and `derive_vars()` have a role once `bd` cuts the
   view (section 1, item 4), or are retired.

## 8. Out of scope

The view's own definition and the corrections tables' schema (hvtiRdatabuild's cardiac master
design owns them), analysis sets, and the analysis templates' read path beyond `bd`.
