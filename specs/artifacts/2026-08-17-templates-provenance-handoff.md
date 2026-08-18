# Handoff — templates & provenance work

> **Migrated 2026-08-18** from `/Volumes/qhsstudies/cardiac/valves/aortic/replacement/pericardial/lv_function/survival/analyses/R_hazard/docs/HANDOFF.md`.
> Cross-references to the other migrated documents have been repointed to their
> paths in this repository; the text is otherwise unchanged. Study folders on the
> share do not host git repositories, so the design record lives with the package
> that owns the migration programme. `specs/artifacts/README.md` records what
> moved and from where.

**Last updated:** 2026-08-13
**Read this first if you are a new session picking up this work.**

---

## The problem, in one paragraph

Study analyses were created by copying SAS template files into a new study
folder and editing them. Improvements stranded in whichever study made them —
annoying but survivable. The real problem is that **a filed result cannot say
what produced it.** SAS bound analysis logic with
`filename kaplan "!MACROS/kaplan"; %inc kaplan;` — late binding to a mutable
central directory with no version. The `.lst` filed in 2006 was produced by the
2006 `kaplan`, and nothing records which that was. Re-run it today and any
difference is unattributable: fix, regression, or environment, you cannot tell.

## The design, in one rule

**Bind late, to something versioned.**

SAS used both binding strategies and each failed differently:

| | Binding | Result |
|---|---|---|
| Macros (`%inc kaplan`) | late — resolved at run time | propagation works, provenance lost |
| Study identity (expanded into each job at creation) | early — frozen at copy time | drift, no propagation, no provenance |

Late binding is correct in both cases. SAS could only make it safe for one,
because `!MACROS` had no version to pin. Copying was a workaround for a missing
version system, not a preference. `renv` supplies the missing piece: work
against the latest, `renv::snapshot()` on filing, `renv::restore()` to revisit.

## The measurement that made it decidable

Across the `ac` (17 files) and `hz` (23 files) families, comparing the canonical
`tp.hz.dead.sas` against this study's `hz.dead_JR.sas`: ~100 lines, ~22 differ —
**16 identity, 5 analysis, 6 cruft.** The genuinely study-specific *analytic*
content of an `hz` job is about **five lines in a hundred**.

That is why the `.qmd` is a call site plus narrative rather than a thick
template. At 50 lines in 100 the thin-template design would have been wrong.

## Architecture — four layers

| Layer | Holds | Versioned by |
|---|---|---|
| method packages (`TemporalHazard`, `hvtiPlotR`, `survival`) | the statistics | `renv.lock` |
| `hvtiRutilities` | study plumbing + governance: `study_config()`, `record_provenance()`, the data contract | `renv.lock` |
| `hvtiRtemplates` | R job templates; SAS + macro reference corpus | `renv.lock` |
| `_study.yml` | study identity, dataset, cohort — read at render, never expanded into jobs | the study's own history |
| job `.qmd` | ~5 lines of call + narrative | stamped with template + package version |

Dependency direction is fixed: templates → utilities → method packages. Never
the reverse. Test for where a function belongs: if it would mean anything
outside this institution it goes in a method package; if not, `hvtiRutilities`.

**Spec:** `specs/2026-08-13-templates-and-provenance-design.md`

---

## Status

| Stage | State |
|---|---|
| **1 — provenance in `hvtiRutilities`** | not started; unblocked |
| **2 — `hvtiRtemplates` repository** | **COMPLETE** |
| **3 — `new_job()` + the five R templates** | not started; needs 1 and 2 |
| **4 — adopt in `R_hazard`** | not started |

### Stage 2, as delivered

`https://github.com/ehrlinger/hvtiRtemplates` — **private**, `main` at `66d52a2`.

- 240 SAS templates (`inst/corpus/sas/`), 495 macros (`inst/macros/`)
- 381 commits, earliest **2014-09-19** — the macro library's real history,
  imported via `git subtree` and preserved through two rewrites
- API: `hvti_taxonomy()`, `hvti_non_prefixes()`, `corpus_manifest()`,
  `corpus_path()`, `template_list()`, `template_path()`
- 33/33 tests, 0 skips; `R CMD check` Status: OK; 13.3 MB installed
- `inst/templates/` is empty by design — stage 3 fills it

**Plan:** `specs/artifacts/2026-08-13-hvtirtemplates-repository.md` (amended in
flight; the amendments are the interesting part)

### Stage 1 — what to build

`study_config()`, `record_provenance()`, and the move of `R_hazard`'s data
contract (`study_root()`, `sas_path()`, `read_built()`, `built_manifest()`,
`cohort_counts()`, `assert_cohort()`) into `hvtiRutilities`, reading from
`_study.yml`.

Provenance is a **JSON sidecar per job**, not RDS and not `renv.lock` alone.
`renv.lock` is project-scoped and time-varying; it cannot say what produced
`01.ac.dead_JR.html` in month two of a three-year study. JSON because the record
must be readable in 2035 by someone without R, and two runs must be diffable
with `diff`. Schema in spec section 5.

**Coupling to check before landing stage 1.** The plan
(`specs/artifacts/2026-08-17-hvtirutilities-provenance.md`) has the packaged
`built_manifest()` emit `sha256` where the per-study one emits `md5`, so that
one hash algorithm serves both the manifest and the sidecar. `R_hazard`'s
`R/bagging-pool.R` reads the chunk checksum to decide whether chunks may be
pooled. It was hardened on 2026-08-17 to read whichever of `sha256`/`md5` is
recorded and to refuse a mix, so the change no longer breaks it — but the
reason it mattered is worth keeping: before that, a field no chunk recorded
passed the gate *unanimously*, because `format(NULL)` is `"NULL"` and every
chunk produced the same string. The `max_steps` gate had been vacuous in the
test fixture on exactly those grounds and the suite was green. **Any new
`agree()`-style check must test absence before agreement.**

**Also queued for stage 1:** a content-based PHI check for the release gate.
Use the **">=3 consecutive record-shaped lines"** form, not the keyword form.
Keywords alone flagged ~200 corpus files that were only *variable names*
(`ccfid`, `mrn`, `dob` in code that reads patient data), and would have **missed**
the one real hit had its column been named anything other than `ccfid`.

---

## State of the bh / hm jobs (2026-08-17)

- **`bh` is running.** 25 chunks × 20 replicates = 500, launched ~08:48,
  measured 37-42 replicates/hour, ETA ~midnight. Do not touch `_output/` or
  `_output/run-snapshot.R` while it runs. `bh-progress.sh` only reports
  `alive` correctly ON THE SERVER; from the Mac it always reads `alive 0`.
  Short windows between calls give meaningless rates — chunks tick in 5% jumps.
- **`hm` already ran (2026-08-12/13) and its model is budget-limited.**
  `selection_hm.rds`: 10 of 10 steps used, `hit_cap = TRUE`, and at least 2 of
  the 10 slots went to redundant forms of one concept (`late.age`,
  `late.age2`, `late.ln_age`). `agee` is deliberately NOT grouped with `age`
  — there is an explicit test asserting that — so 2 is a floor, not an
  estimate. **John's call, 2026-08-17: report it, do not re-run yet**; decide
  the modelling question once `bh`'s reliability numbers are in.
- **`bh` and `hm` do not screen the same pool.** `bh` prunes competing
  transformations to one form per concept; `hm` does not, because the SAS
  `%macro model` it reproduces had no notion of a concept. Their variable
  lists are therefore not directly comparable, and neither substitutes for the
  other. Both reports now say so.
- **`selection_bh.csv` is a deliverable, not a handoff.** Nothing reads it.
  `hm` runs its own selection from its own SAS candidate block. The `bh`
  report used to claim otherwise; corrected 2026-08-17.
- **Dataset provenance is clean**: `hm` ran against md5 `37ff2395…` /
  mtime 2026-08-04 20:29, which is still the dataset on disk and the one `bh`
  is running against now.

## Constraints that will bite you

- **NO GIT in the study tree** (`/Volumes/qhsstudies/...`). Not a preference —
  the SMB mount makes it unsafe (`core.fileMode` churns 301 files, the share
  has unmounted mid-commit). Log to `.superpowers/sdd/progress.md` instead of
  committing. **There is no undo here.** Copy a working file aside before
  rewriting it.
- **Quarto renders on the SERVER, not the Mac.** The mount cannot delete a file
  it just wrote, so Quarto's cleanup leaves undeletable `.smbdelete*`
  tombstones. Acceptance on the Mac is
  `Rscript -e 'knitr::knit("<file>.qmd", output = tempfile(fileext = ".md"))'`.
  **Do not retry a failed render** — each attempt leaves another tombstone.
- **`hvtiRtemplates` is private and must stay so until deliberately published.**
  It is *intended* to go public eventually; it has been screened for that and is
  currently clean.
- **`R/` holds side-effect-free helpers only.** Every consumer sources it
  wholesale; a side effect there runs on every render. Enforced by
  `r_dir_impurities()`.
- Versioning: three digits, never `.9000`. Do not roll MINOR or MAJOR — that is
  John's call.

## Lessons that cost real work

1. **A filename is never evidence about its contents.** Four times a rule keyed
   on filename shape got a file wrong: four `*~` files with no original (one was
   an Extended Kaplan-Meier estimator for time-varying covariates, authored,
   dated); a `_old` file that was a different *study*, not an older draft; four
   `Copy of` duplicates missed entirely; and a `.lst` treated as code by an
   extension allowlist that turned out to hold patient data. Check the file,
   not the name.
2. **Import everything, then remove in separate commits.** A `git rm` against a
   parent that still holds the file is reviewable and recoverable. A file
   filtered out at import is gone with no record it existed. This rule is what
   made all four recoveries above possible.
3. **`git log -- <subtree-prefix>` does not show grafted history.** `git subtree
   add` keeps the imported commits' original root paths, so a pathspec on the
   new prefix matches only the merge. Verify with `git rev-list --count`, the
   earliest commit date, and the merge's two parents.
4. **Investigating an exposure can propagate it.** Fetching `refs/pull/1/head`
   to check whether GitHub still held a blob pulled that blob into the local
   clone. Clean up after such a check (`git reflog expire --expire=now --all &&
   git gc --prune=now`) and verify by SHA.
5. **`refs/pull/N/head` is permanent.** Force-pushing cannot remove it. If
   something must be purged from a GitHub repo that has ever had a PR, the repo
   has to be deleted and recreated. Pushing straight to `main` on a fresh repo
   avoids creating the ref at all.

## Key locations

| What | Where |
|---|---|
| Spec | `specs/2026-08-13-templates-and-provenance-design.md` |
| Stage 2 plan | `specs/artifacts/2026-08-13-hvtirtemplates-repository.md` |
| Execution ledger + every decision | `.superpowers/sdd/progress.md` - a gitignored working-directory artifact, not carried into this repository |
| Earlier R_hazard plan (partly superseded) | `specs/artifacts/2026-08-12-r-hazard-job-templates.md` |
| Package repo | `~/Documents/GitHub/hvtiRtemplates` |
| Macro library (import source) | `~/Documents/macro.library` |
| Canonical template library (read-only source) | `~/Documents/template` |

## Open housekeeping (John's)

- ~~`~/Documents/repo-backups-2026-08-13/` — pre-rewrite mirrors holding the
  PHI.~~ **Deleted by John 2026-08-17.** Do not go looking for it.
- `~/Documents/macro.library-mailbox-removed-2026-08-13/Mailbox` — a 2.5 MB
  email archive that was never committed anywhere. Keep or delete.
- Local branch `feat/import-corpus` in the package repo, same commit as `main`.
- The ~8 binary `.doc`/`.pdf` files that `macro.library`'s `.gitignore`
  excludes were scanned and are clean, but were dropped from the corpus anyway
  when it was reduced to SAS-only.
