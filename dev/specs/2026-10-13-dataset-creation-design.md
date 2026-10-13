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
| 1 | Where does the master live? | **In the warehouse, as layered views over its own tables** (decision 8). No SAS-made copy persists: a dated SAS build is snapshotted only as a temporary parity baseline for the port (section 6, C) |
| 2 | How does a study get its data from the master? | **It cuts the corrected base, pinned with `as_of`, applies its own corrections, recomputes the master's derivations, and keeps a file** (section 5). Jobs keep reading a checksummed file under the existing manifest contract; no render needs a warehouse connection |
| 3 | What is a study's working data? | **One undated file, `built`,** whatever produced it: a legacy SAS build, a `bd` cut of the view, or a rebuild. It is overwritten in place |
| 4 | What is versioned? | **Only a registered dataset, and every registered dataset the same way:** a dated version (`<stem>_YYYYMMDD[_rN].parquet`), whatever produced it. How it was produced is provenance recorded on the version, not a second scheme |
| 5 | How does a legacy study enter (#225)? | **It registers its existing `built`.** That is decision 4 applied to a file SAS made. Its next version may come from a `bd` cut, which `compare_built()` checks against the legacy one |
| 6 | What does a study do with a value it believes is wrong? | **It records a correction in the study's overlay, applies it locally, and proposes it upstream.** See section 5 |
| 8 | How is the master built? (sub-project C) | **Port the SAS program; do not lift its snapshot.** The port runs **query, rename, correct, derive**, as three layers: base views over the warehouse (the pull, with names aligned to the standard), adjudicated corrections applied to base columns and pinned with `as_of`, and derived views that read corrected base columns only. Decided 2026-10-13; see section 7, item 0, for the measurement it rests on |
| 7 | Order of work | **A (one version scheme) before B (#225),** so the adoption job is built on the scheme that stays |

## 4. The model

```
warehouse tables --query, rename--> BASE views
                                       |
     corrections tables (propose / decide; read at as_of) --> CORRECTED BASE   (layer 2)
                                       |                           |
                                       |                           +--derive--> DERIVED views (layer 3)
                                       v  bd cuts corrected base, pinned as_of
                       study overlay (section 5) applied to base columns
                                       |
                                       v  the SAME derivations, run on the cut
legacy SAS study built --+
                         +--> datasets/built   (working: undated, overwritten)
                   bd ---+         |   each overlay row is also proposed upstream, pending
                                   v   register_data()
                     built_YYYYMMDD[_rN].parquet + manifest entry   (registered: dated, with provenance)
                                   |
                                   v   jobs: verify_manifest(); the freeze = every job CURRENT

parity baseline only: a dated SAS built.master --snapshot_master()--> parquet, compared with the
port's output by compare_built(); never lifted, never read by a study
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
2. **Apply, to base columns.** `bd` cuts the *corrected base* (layer 2), not the derived
   view, and applies each overlay row to it, after checking that the cut holds
   `expected_prior`. A row whose prior no longer matches stops the build, naming the variable
   and the count, never the key or the value. An overlay row may only name a base column; a
   derived column is corrected by correcting its inputs.
3. **Derive.** `bd` then computes every derived column from the corrected cut, using the
   master's own derivation definitions (layer 3), so a local correction to `age` reaches
   `crcl_pr` exactly as an upstream one would. This requires C to write the derivations once,
   in a form that both defines the warehouse's derived views and runs on a study's cut (for
   example SQL that duckdb runs over the cut); two copies would drift. Registration refuses a
   cut whose derivations were not recomputed after its overlay was applied.
4. **Propose.** Each new overlay row is proposed upstream with `propose_correction()`. It is
   pending there until `decide_correction()` decides it.
5. **Reconcile, on every later cut, at that cut's own watermark.** Decisions are read as of
   the same `as_of` the cut is pinned to, never "latest", because an acceptance made after the
   watermark is not in the cut, and an accepted correction can still be stale and unapplied.
   So the test for retiring a row is the **effective value**: if the cut, before the overlay,
   already holds the row's `new_value` for that cell, the row is a no-op and is retired. If the
   latest decision at the watermark is `reject`, the build stops until the study drops the row
   or argues it again. In every other case (no decision, accepted after the watermark, accepted
   but not applied) the row stays applied and pending.
6. **Report.** The build lists, by variable and count, how many corrections were applied,
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
| **C** | Port the master program (decision 8): base views with the renames, corrections applied to base columns, and derivations written once so they define the derived views and run on a study's cut (section 5, step 3). Proved against a dated SAS build snapshotted as a parity baseline with `snapshot_master()` and compared with `compare_built()`, differing by design where corrections now precede derivations. `lift_master()` is not used. Needs warehouse write access and the registries team's agreement | hvtiRdatabuild | none |
| **D** | `bd` cuts the corrected base, pinned with `as_of`, derives, writes `built` and registers it | hvtiRtemplates | A, C |
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

0. **Settled by decision 8: port the program.** The measurement behind it: `lift_master()` loads a
   frozen SAS snapshot into a base table, a copy SAS made. Porting the program would make its
   pull and derivations views over the warehouse's own tables, leaving no SAS-made copy. The
   cardiac build was measured on 2026-10-13 by a structure-only scan (statement kinds, tables,
   counts; no key or value read out):
   - **It is two programs.** `masterDWpull.sas` makes nine ODBC pass-through queries to the
     warehouse (base, status, echo, follow-up, follow-up medications, ad hoc, base id, EKG and a
     cohort table) and saves each as a dated SAS dataset. `bd.data.master.sas` reads
     `bdbase_&PULLDT`, the date typed by hand to match the pull.
   - **The pull does not align names.** The base query selects the warehouse views' columns as
     they stand (`c.*, v.*, w.*` over `vw_CardSurg_Base`, `_Valve` and `_Cabg`), renaming only the
     MRN to `ccfid`; the build adds a handful of `rename` statements.
   - **Corrections are not last, and one runs too late.** 18 key-matched fix statements correct
     6 columns (counting `then do;` blocks, which agrees with the 2026-09-23 count). Three
     corrected columns feed later derivations: `dt_disc` (`hdeath`, `iv_dead`, `iv_fup`),
     `dt_fcst` (`iv_fup`) and `ht` (`bsa`, `wtht`). `dt_birth` and `dt_admt` are read by nothing
     after their fix. **`age` is read before it is corrected:** `crcl_pr` is derived from it
     about 270 lines before the five `age` fixes, so the master holds a creatinine clearance
     computed from the uncorrected age for those patients. Correcting last would repeat that
     defect for every corrected input; correcting before deriving fixes it.
   - **What the scan cannot see.** It is static: macro-generated code, arrays and columns read
     inside `proc sql` are not followed, and only the corrected columns' readers were traced.
     The port's parity check against a dated build is the proof, and it will differ, by design,
     for exactly the patients whose corrections feed a derivation; those differences are listed
     and accepted as the fix.
   - **The master reads more than the warehouse:** pre-op echo, labs, ECG, the SSDI death index,
     one imported CSV, and four study `built` datasets joined in by `proc sql`. Data already
     flows from studies into the master as files. Each needs a source decision before a port.
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
