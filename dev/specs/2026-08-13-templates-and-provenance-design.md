# Analysis Templates and Provenance — Design

> **Migrated 2026-08-18** from `/Volumes/qhsstudies/cardiac/valves/aortic/replacement/pericardial/lv_function/survival/analyses/R_hazard/docs/specs/2026-08-13-templates-and-provenance-design.md`.
> Cross-references to the other migrated documents have been repointed to their
> paths in this repository; the text is otherwise unchanged. Study folders on the
> share do not host git repositories, so the design record lives with the package
> that owns the migration programme. `dev/specs/artifacts/README.md` records what
> moved and from where.

**Date:** 2026-08-13
**Status:** approved in brainstorming, not yet planned
**Scope:** institutional — `hvtiRtemplates`, `hvtiRutilities`, and the per-study
job layout. Consumed by, but larger than, `analyses/R_hazard/`.
**Predecessor:** `dev/specs/2026-08-11-r-hazard-job-templates-design.md`

---

## 1. The problem

Study analyses are created by copying template files into a new study folder and
editing them. Two consequences follow, and only the second one hurts enough to
justify a design.

**Improvements strand.** A template improved in one study stays in that study.
The canonical library at `~/Documents/template` holds 25 SAS templates under
`distributions/templates/`; this study's copy of that same folder holds 7, all
dated September 2004. The study took a snapshot at creation and froze. Nothing
has flowed in for twenty years and nothing has flowed back.

**Provenance is unrecoverable, and this is the real problem.** A filed result
cannot answer the question "what produced this?" SAS jobs bind their analysis
logic with `filename kaplan "!MACROS/kaplan"; %inc kaplan;` — late binding to a
mutable central directory, resolved at run time. The `.lst` filed in 2006 was
produced by the 2006 `kaplan` macro. Nothing records which that was. Re-run the
job today and any difference in the numbers is unattributable: it could be a
fix, a regression, or an environment change, and there is no way to tell.

That second problem is what this design exists to make impossible in R.

### 1.1 What the current library actually looks like

Measured 2026-08-13 against `~/Documents/template` (the canonical library) and
`~/Documents/macro.library`.

| | Count |
|---|---|
| Canonical library, total size | 11 MB |
| Files inside `*/templates/` directories | 417 |
| — SAS templates (`tp.*.sas`) | 242 |
| — R-family (`.R`, `.qmd`, `.Rmd`, `.rmd`, `.Rnw`, `.S`) | 126 |
| — office/PDF/binary assets | 35 |
| — under an `archive/` subdirectory | 59 |
| Macro library files (excluding `.git`) | 579 |
| Documented analysis prefixes | ~30 |

The library is under **no version control**. Versioning is being done with
filenames:

```
tp.BoostmtreeLongitudinal_w_notes_032423.R  /  ..._032423-copy.R
tp.lp.mirror_histo_before_after_wt.R        /  ..._wt_Old.R
tp.dc.tables.ods.sas  /  tp.dc.tables.ods.2013.sas  /  tp.dc.tables0534.ods.sas
archive/tp.dp.gfup.R  /  .5.3.2023.R  /  .11.8.2023.R  /  _13oct21.rmd  /  _EAL.R
```

Six generations of `gfup` across two directories, plus `.BAK`, `_Old`, `-copy`
and `archive/`. Every one of those is a decision someone must make at copy time
with no information to make it on.

The library's own README has drifted from the library: it instructs the reader
to run `organize_templates.sh`, which is not present, and documents an R
template set (`01_data_engineering.qmd` through `04_results_figures.qmd`) that
does not exist.

`macro.library` carries CVS metadata (`CVS/Root` → `/u00/programs/CVS`) whose
repository is gone; that metadata describes a batch snapshot, not the
maintenance history of the deployed `!MACROS` directory.

But the directory **is itself a git repository**, and that history is real:

| | |
|---|---|
| First commit | `2014-09-19` "Initial Repository Commit" |
| Last commit | `2019-05-01` |
| Commits | 357, cron-driven ("Daily Commit") |
| Tracked files | 522 |
| Uncommitted working-tree changes | 255 — the 2019→2026 delta, currently captured nowhere else |

So macro provenance is recoverable for **2014–2019** and unrecoverable outside
it: nothing survives from the CVS era, and the cron stopped in 2019. `kaplan`
carries a single commit — the 2014 import — and has not changed since, which
bounds one common source of parity ambiguity.

Two consequences bind the implementation. This history **must be preserved, not
flattened** by a fresh `git init` — discarding recoverable provenance while
building a provenance system would be self-defeating. And the 255 uncommitted
changes must be captured before anything else touches the directory.

### 1.2 How much of a job is actually study-specific

Measured across the `ac` and `hz` families — 17 and 23 files respectively,
comprising the canonical `tp.*` templates plus every real job of that family in
this study. Lines whitespace-normalised; blank lines and decoration rules
dropped.

| Family | Lines shared with ≥half the corpus | Shared with ≥2 files | Unique to one file |
|---|---|---|---|
| `ac` study jobs | 40–63% | 67–93% | 7–33% |
| `hz` study jobs | 61–75% | 67–90% | 10–33% |

The aggregate understates the invariance, because "unique" counts lines that are
identical apart from a name. The direct diff of the canonical
`tp.hz.dead.sas` against this study's `distributions/hz.dead_JR.sas` is the
sharp measurement — ~100 lines, ~22 differ, in three buckets:

| Bucket | Lines | Content |
|---|---|---|
| **Identity** | 16 | job name ×4, study path ×2, study description ×2, titles ×2, input dataset, output dataset, `%macro skip`/`%mend` wrapper |
| **Analysis** | 5 | `noconserve` → `conserve`; three lines of `parms` starting values; time grid `1 to 15` → `1 to 10` |
| **Cruft** | 6 | a commented-out alternate model carried from the `metasize` study and never removed |

**The genuinely study-specific analytic content of an `hz` job is about five
lines in a hundred.** Everything else is invariant, identity, or someone else's
leftovers.

Identity repetition has already caused observable drift. In
`distributions/ac.dead_JR.sas` the study path appears twice with different
values: line 5 says `.../aortic/pericardial/lv_function/...` and line 16 says
`.../aortic/replacement/pericardial/...`. One copy of the same edit was updated
and the other was not.

---

## 2. The rule this design reduces to

**Bind late, to something versioned.**

SAS had both binding strategies and each failed differently:

| | Binding | Result |
|---|---|---|
| Macros (`%inc kaplan`) | late — resolved at run time | propagation works, provenance lost |
| Study identity (expanded into each job at creation) | early — frozen at copy time | drift, no propagation, no provenance |

Late binding is the correct choice in both cases. SAS could only make it safe
for one, because `!MACROS` had no version to pin. Copying was a workaround for a
missing version system, not a preference.

`renv` supplies the missing piece. Once versions can be pinned, late binding
costs nothing:

- **Working:** resolve to the latest, deliberately, via `renv::update()`.
- **Filing:** pin via `renv::snapshot()`; `renv.lock` records exactly what ran.
- **Revisiting:** `renv::restore()` to the filed lock, reproduce the filed
  numbers, *then* wind forward.

Every copy in the current workflow therefore becomes a late binding we can now
afford. The copies that remain are the ones that genuinely differ per job, which
section 1.2 measures at about five lines.

---

## 3. Architecture

Four layers. Each is versioned by something, and the version is recorded in
every filed result.

| Layer | Holds | Bound | Versioned by |
|---|---|---|---|
| method packages (`TemporalHazard`, `hvtiPlotR`, `survival`, …) | the statistics | late | package version in `renv.lock` |
| `hvtiRutilities` | study plumbing, governance: `study_config()`, `record_provenance()`, the data contract | late | package version in `renv.lock` |
| `hvtiRtemplates` | R job templates; SAS and macro reference corpus | late | package version in `renv.lock` |
| `_study.yml` | study identity, dataset, cohort | late, read at render | the study's own history |
| job `.qmd` | ~5 lines of call, plus narrative and interpretation | copied once, stamped | template name + `hvtiRtemplates` version |

Dependency direction is fixed: `hvtiRtemplates` → `hvtiRutilities` → method
packages. Never the reverse.

**Where analysis logic lives.** The statistics belong in the method packages,
not in `hvtiRutilities`. A template calls `TemporalHazard` directly for fitting.
`hvtiRutilities` holds what is institutional but not statistical: locating the
study, reading the built dataset, asserting the cohort, recording provenance.
The test is whether a function would mean anything outside this institution — if
yes it belongs in a method package, if no it belongs in `hvtiRutilities`.

### 3.1 Why two packages rather than one

`hvtiRtemplates` is separate from `hvtiRutilities` for four reasons, in order of
weight.

**Change cadence.** Utilities change on bug fixes. Templates change on methods
and standards decisions. Sharing a package means a utility patch forces a
template version bump and vice versa, which destroys the resolution this design
exists to buy. "We used templates 2.1 and utilities 1.4.7" must be a sentence
the provenance record can state.

**Dependency direction.** Templates call utilities, never the reverse. Templates
will pull `TemporalHazard`, `hvtiPlotR`, `gtsummary`, `flextable`, `survminer`.
Placing them in `hvtiRutilities` makes every one of those dependency weight on
the package everything else depends on.

**The SAS corpus needs version control now.** 242 SAS templates and 226 macros
are currently versioned by filename suffix. Shipping them as
`hvtiRtemplates/inst/sas/` and `inst/macros/` puts all of it under git in one
move, with no separate repository to maintain. They do not belong inside a
functional utility package. Combined size is 14 MB, which is acceptable for a
GitHub-installed package; the CRAN 5 MB tarball limit does not apply.

**Governance.** A template change is a methods decision the group should review.
A utility change is a code change. Different reviewers, different gates.

### 3.2 Package layout

```
hvtiRtemplates/
  DESCRIPTION              Imports: hvtiRutilities
  R/
    new_job.R              new_job(), job_path()
    manifest.R             template_manifest(), template_list()
  inst/
    templates/             ac.qmd hz.qmd hp.qmd bh.qmd hm.qmd ...
    sas/                   242 tp.* files — reference specification
    macros/                226 macro.library files — reference specification
  tests/testthat/
```

`inst/templates/` holds plain files. It deliberately does **not** use RStudio's
`inst/rmarkdown/templates/<name>/skeleton/skeleton.qmd` layout.

**Why the RStudio template gallery is excluded.** File → New File → R Markdown →
From Template is an RStudio feature reading an RStudio-defined directory
structure. Positron is VS Code-based with a different extension model, and this
design does not assume the gallery survives that transition. It is also the
*unstamped* path: the gallery copies a skeleton without recording where it came
from, which is the failure mode being removed. Excluding it leaves one
instantiation path — IDE-independent, always stamped, with no unstamped back
door to document.

`inst/sas/` and `inst/macros/` are **reference specifications, not runnable
assets.** They are what an R template is checked against. The package
documentation must say so, so that nobody mistakes them for a supported SAS
distribution. The institutional SAS licence expires 2026-09-29.

---

## 4. Components

### 4.1 `_study.yml` — the study manifest

One file at the study root. Replaces the 16 identity lines that section 1.2
measured, and the SAS-era job that expanded a study file's contents into every
individual job.

```yaml
study:       Survival after AVR — prosthesis or LV structure and function?
population:  CCF, 1991 to 2004, n=3316
built:       built103006
citation:    "Mihaljevic T, Nowicki ER, Rajeswaran J, Blackstone EH, Lagazzi L,
              Thomas J, Lytle BW, Cosgrove DM. J Thorac Cardiovasc Surg.
              2008;135(6):1270-9. doi:10.1016/j.jtcvs.2007.12.042"
cohort:
  n:          3049
  n_events:   1032
  n_censored: 2017
```

Read at render, never expanded into a job file. **No job `.qmd` contains a study
path, a study title, or a dataset name.** The study root is located by walking up
for `_study.yml`, which subsumes the `_quarto.yml` walk that `R_hazard` and
`R_parity` currently use.

`cohort:` feeds `assert_cohort()`. A build that changes the cohort fails every
job rather than silently producing different numbers.

### 4.2 `hvtiRutilities` additions

```r
study_config(start = getwd()) -> list
```
Walks up for `_study.yml`, parses it, validates required keys, returns it.
Errors if absent or if a required key is missing — a study without a manifest
must not render.

```r
record_provenance(path, extra = list()) -> invisible(list)
```
Writes the provenance sidecar described in section 5. Lives in
`hvtiRutilities` rather than `hvtiRtemplates` because provenance is a governance
check — the role the library README already assigns to that package — and
because a study that does not use a template still needs provenance.

The existing `R_hazard` data contract (`study_root()`, `sas_path()`,
`read_built()`, `built_manifest()`, `cohort_counts()`, `assert_cohort()`) moves
here, reading its study-specific values from `study_config()` instead of from
hard-coded constants.

### 4.3 `hvtiRtemplates` interface

```r
new_job(template, name, dir = NULL, open = FALSE) -> character(1)
```
Copies `inst/templates/<template>.qmd` into the study, placed by prefix
according to the taxonomy (`hz` → `distributions/`, `hm` → `analyses/`,
`hp` → `graphs/`, and so on), numbered by pipeline dependency order. Stamps the
YAML header. Returns the path written. Errors if the target exists — never
overwrites.

Encoding the prefix→folder taxonomy in a function rather than a README table
matters: the current table has already drifted from reality. Executable
documentation cannot silently go stale.

```r
template_manifest(root = study_root()) -> data.frame
```
Reads the stamp from every `.qmd` in the study and reports
`file, template, template_version, created, current_version, behind`.

This is the report that never existed for SAS. It also handles the case the
design cannot prevent: someone copying an existing job file rather than calling
`new_job()`. The copy carries a stamp that is now wrong for it, and
`template_manifest()` says so. **Detecting drift beats preventing it**, because
prevention requires changing what people do and detection does not.

```r
template_list() -> data.frame
```
`name, prefix, folder, title, description` for every shipped template.

### 4.4 The job `.qmd`

A call site plus narrative. The whole analytic surface of an `hz` job:

```r
fit <- hzr_multiphase(
  data     = read_built(),
  event    = "dead",
  phases   = c("early", "late"),
  conserve = TRUE,
  horizon  = 10,
  control  = list(n_starts = 5, maxit = 2000)
)
```

Compare to section 1.2: `conserve` was one line of the SAS diff, `control`
replaces three lines of `parms`, `horizon` replaces the time grid. Everything
else in the 100-line SAS job — the JCL wrapper, `libname`, `%inc vars`, the
`outhaz=` plumbing, the prediction grid — is invariant and belongs in the
function.

**Starting values carry a decided constraint**, inherited from the predecessor
plan and not weakened here. `R_parity` reads `theta0` from the SAS listing; a
template may not, and must not substitute literals — hard-coding one study's
converged parameters into a template meant for fourteen `hz` jobs defeats the
template, and the next person to instantiate it would have no way to know the
numbers were wrong for their data. The start is therefore computed from the data
with `n_starts > 1`.

The stage-2 likelihood **is multimodal**: during parity work a different start
reached -3678.83 against the SAS optimum. So the `hz` and `hm` templates must:

- pass `n_starts = 5`, never 1;
- print the objective at convergence and `fit$converged` in a table near the top
  of the report, not buried in a `str()` dump;
- state in prose that a multiphase hazard likelihood can have several optima, so
  a converged fit is not by itself evidence of the best one, and that comparing
  the objective across starts is how that gets checked.

A worse optimum is then visible in the rendered report. The requirement is not
that it cannot happen, but that it cannot happen quietly.

Study-specific values are **function arguments, not template lines**. An
argument that is omitted raises an error; a template line that is overwritten
does not.

YAML header stamp:

```yaml
title: "Hazard for death"
hvti:
  template: hz
  template_version: 1.0.0
  created: 2026-08-13
```

---

## 5. The provenance record

`renv.lock` alone does not close the provenance gap. It is **project-scoped and
time-varying**: a study runs 80 jobs over three years and is snapshotted
repeatedly. The lock at the end of the study does not say what produced
`01.ac.dead_JR.html` in month two. The lock is a restore *mechanism*, not a
*record* of any particular result.

The result is job-scoped and frozen when filed. So the record lives with the
result.

**Format: JSON sidecar**, written next to the rendered output as
`<job>.provenance.json`. JSON because the record must be readable in 2035 by
someone who may not have R, and because two runs must be diffable with `diff`.
RDS fails both tests.

```json
{
  "job":       "01.hz.dead_JR",
  "rendered":  "2026-08-13T14:22:07Z",
  "template":  { "name": "hz", "version": "1.0.0" },
  "study":     { "file": "_study.yml", "sha256": "..." },
  "r":         { "version": "4.5.1", "platform": "x86_64-pc-linux-gnu" },
  "packages":  [ { "package": "TemporalHazard", "version": "0.4.2", "source": "GitHub" },
                 { "package": "hvtiRutilities", "version": "1.4.7", "source": "GitHub" } ],
  "renv_lock": { "path": "renv.lock", "sha256": "..." },
  "data":      [ { "file": "built103006.sas7bdat", "bytes": 4194304,
                   "mtime": "2006-10-30T00:00:00Z", "sha256": "..." } ],
  "cohort":    { "n": 3049, "n_events": 1032, "n_censored": 2017 }
}
```

`packages` records every loaded package, not a curated list — the curated list
is what goes wrong when a dependency starts mattering and nobody notices.

**The loop this closes.** Revisiting a study to update the cohort becomes: read
the sidecar off the filed output → `renv::restore()` to that lock →
re-render → confirm the filed numbers reproduce → *only then* `renv::update()`
and wind forward. If the reproduction step fails, that is learned before
anything is built on top of it. Today that check is impossible.

The rendered document also prints a human-readable version of the same record,
so the HTML is self-describing without the sidecar. The sidecar is the machine
half; the table is the reading half. They are generated from one call.

---

## 6. Error handling

| Condition | Behaviour |
|---|---|
| `_study.yml` absent | `study_config()` errors, naming the directories walked |
| `_study.yml` missing a required key | error naming the key; no partial defaults |
| cohort in `_study.yml` disagrees with the built dataset | `assert_cohort()` errors — a rendered page is itself evidence the gate passed |
| `new_job()` target exists | error; never overwrite |
| unknown template name | error listing available templates |
| job `.qmd` has no `hvti:` stamp | `template_manifest()` reports it as `template: NA`, not an error — pre-existing jobs must remain readable |
| stamped version newer than installed | `template_manifest()` flags it; the study was rendered against a package this machine does not have |
| provenance sidecar cannot be written | error, not a warning — an unrecorded result is the failure this design exists to prevent |

The last row is the load-bearing one. Every other failure mode in this table is
recoverable; a silently unrecorded result is not.

---

## 7. Testing

**`hvtiRtemplates`**

- every file in `inst/templates/` appears in `template_list()` and vice versa
- every template's prefix maps to a folder in the taxonomy
- every template carries a well-formed `hvti:` stamp
- `new_job()` writes to the expected path, stamps correctly, refuses to overwrite
- `new_job()` on every shipped template produces a document that renders against
  a fixture study
- `template_manifest()` correctly reports behind / current / unstamped
- `inst/sas/` and `inst/macros/` file counts match a recorded expectation, so a
  silent partial copy is caught

**`hvtiRutilities`**

- `study_config()` walks up correctly, errors on absent and on missing keys
- `record_provenance()` output validates against a JSON schema
- two renders of the same job in the same environment produce sidecars differing
  only in `rendered`
- changing a fixture dataset changes its `sha256` and fails `assert_cohort()`

**Both**

- `R/` holds no top-level executable code — the `r_dir_impurities()` check
  already written for `R_hazard`, carried into both packages

---

## 8. What this changes in the in-flight `R_hazard` plan

`dev/specs/artifacts/2026-08-12-r-hazard-job-templates.md` is partly
executed on branch `feat/r-hazard-templates`. This design supersedes parts of it.

| Plan element | Change |
|---|---|
| `analyses/R_hazard/templates/*.template.qmd` | become the seed of `hvtiRtemplates/inst/templates/`; not study-local files |
| `# EDIT:` marker convention | replaced by `_study.yml` plus function arguments. A marker is a request to edit a line; an argument cannot be silently omitted |
| Task 12 Step 3 (instantiate by `cp` and edit `# EDIT:` lines) | replaced by `new_job()` |
| `study_root()`, `read_built()`, `assert_cohort()` in `R_hazard/R/` | move to `hvtiRutilities`, reading from `study_config()` |
| Deferred item "templates into `hvtiRutilities/inst/rmarkdown/templates/`" | resolved: a separate `hvtiRtemplates`, and not the RStudio gallery layout |
| Global constraint "no literal study path in any R or `.qmd` file" | retained and strengthened — no study *title* or *dataset name* either |
| Constraint "NO GIT in the study tree" | retained. The packages are developed in their own repositories, where normal branch-and-PR discipline applies |

Work already completed on the branch is not wasted. The five templates are the
content; this design changes where they live and how they are instantiated, not
what they compute. The parity split (`R_parity` → `R_hazard`) is unaffected.

---

## 9. Non-goals

- **Migrating the SAS corpus.** `inst/sas/` and `inst/macros/` are carried as
  reference specification. They are not converted, tested, or supported.
- **Recovering pre-R macro provenance.** Unrecoverable (section 1.1). Recorded
  as a known limit; `R_parity` documentation should state that a parity
  mismatch against a stored `.lst` has an irreducibly ambiguous cause, because
  the macro version that produced the `.lst` is unknown.
- **Preventing copy-and-edit.** People will copy existing jobs. The design
  detects the resulting drift rather than forbidding the practice.
- **Templates for all ~30 prefixes.** Five (`ac`, `hz`, `hp`, `bh`, `hm`) seed
  the package. Others are added as they are needed.
- **Replacing the canonical `~/Documents/template` project skeleton.** The
  folder structure, README taxonomy and setup instructions stay. This design
  changes what fills `templates/`, not the study layout.

## 10. Deferred, with triggers

| Deferred | Trigger |
|---|---|
| `hs` template | `hvtiRlifetables` exists (see its own spec) |
| Templates for prefixes beyond the five | first job of that prefix needed in R |
| A study-creation function (`new_study()`) replacing `organize_templates.sh` | second study is set up under this design |
| Backfilling `_study.yml` into existing studies | that study is revisited |
| Signing or checksumming filed outputs themselves | a filed result is ever disputed |

---

## 11. Success criteria

1. A filed result's sidecar names the exact `hvtiRtemplates` and
   `hvtiRutilities` versions, the R version, every loaded package version, and
   the input dataset checksum.
2. `renv::restore()` from a filed sidecar's lock reproduces that result's numbers.
3. `template_manifest()` on a study reports, for every job, which template and
   version it came from and whether a newer one exists.
4. No job `.qmd` contains a study path, study title, or dataset name.
5. A new job is `new_job()` plus editing the arguments of one function call.
6. The `hz` template's analytic surface is a single function call whose
   arguments correspond to the five lines measured in section 1.2.
7. `inst/sas/` and `inst/macros/` are under version control, and the filename
   generations (`-copy`, `_Old`, `.BAK`, date stamps) are resolved into git
   history rather than carried as files.

---

## 12. Implementation sequencing

This design is larger than one implementation plan. It spans two package
repositories and an in-flight branch in the study tree, and the pieces have a
dependency order. Each stage below gets its own plan, and each is independently
useful if the next one never happens.

**Stage 1 — provenance, in `hvtiRutilities`.** `study_config()`,
`record_provenance()`, the JSON schema, and the move of the `R_hazard` data
contract. Delivers success criteria 1, 2 and 4. This is first because it is the
problem that actually hurts, it does not depend on templates existing, and it
can be adopted by jobs written by hand.

**Stage 2 — `hvtiRtemplates` as a repository.** Create the package, import the
242 SAS templates and 226 macros into `inst/sas/` and `inst/macros/`, resolve
the filename generations into git history, and ship `template_list()`. Delivers
criterion 7. Independent of stage 1; can run in parallel. This is the stage that
puts twenty years of un-versioned institutional assets under version control,
and it should not wait on the R work.

**Stage 3 — `new_job()` and the five templates.** Move the `R_hazard` templates
into the package, add the stamp, `new_job()` and `template_manifest()`. Depends
on both prior stages. Delivers criteria 3, 5 and 6.

**Stage 4 — adopt in `R_hazard`.** Reconcile the in-flight branch per section 8.

The `feat/r-hazard-templates` branch continues under its existing plan until
stage 3. Nothing in stages 1 and 2 requires pausing it.
