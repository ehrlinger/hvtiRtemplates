# run_job: one command that runs a job safely

**Date:** 2026-10-22
**Status:** designed, not built. Approved in conversation 2026-10-22.
**Reads with:** `2026-10-20-background-jobs-design.md` (`submit_job()`, `job_status()`),
`2026-10-21-job-progress-design.md` (`.run.progress`), `2026-10-01-nb-boostmtree-design.md`
(the CORES table).
**Packages:** hvtiRtemplates (the command, the checks, the diagnosis). hvtiRutilities and hvtiR
(the snapshot guard, section 7, in separate pull requests).

## 1. Why

On 2026-10-22 two boostmtree jobs that had rendered the day before failed on lri Posit Workbench,
after the move from RStudio to Positron: COMMENCE (R 4.5.3 study) and Penny's prolapse outcomes job
(R 4.6.1). It took most of a day, run by the package's author, to get both running. The causes were
eight separate failures, none of them in the analysis itself. Each one either surfaced hours into a
fit or never surfaced as a reason at all.

If we cannot run a job correctly together, no study author will. The goal is that an author who
knows nothing about renv, Quarto, cgroups or Workbench profiles can render a long job correctly, and
that every failure on 2026-10-22 is refused up front with a plain reason and the exact fix, or, where
it cannot be foreseen, is explained in plain words afterwards.

## 2. What the author types

```sh
hvti run analyses/nb.boostmtree.lvef.boost.qmd          # any terminal on lri
hvti run analyses/nb.boostmtree.lvef.boost.qmd --final
hvti status analyses/nb.boostmtree.lvef.boost.qmd
hvti cancel analyses/nb.boostmtree.lvef.boost.qmd
```

or, from an R session already running the study's R:

```r
hvtiRtemplates::run_job("analyses/nb.boostmtree.lvef.boost.qmd")
```

`run_job(path, final = FALSE, wait = 300)` runs the preflight checks (section 4), calls
`submit_job()`, then waits until the render has passed its own in-render checks or failed (section
5). It prints one line per check and returns the job's status invisibly, as `job_status()` does.
`submit_job()`, `job_status()` and `cancel_job()` stay as they are, for anyone who wants the parts.

## 3. The `hvti` command

A POSIX `sh` script, `inst/bin/hvti`. It exists because only something outside R can choose which R
to start. Once a session is running R 4.6.1 in a 4.5.3 study, renv has already pointed it at a
different library, which is failure 1. It is also the way round failure 8: Positron's console hung,
and the only route that worked was a terminal `Rscript` with a full path.

1. Walks up from the job's directory to the study root, the first directory holding `renv.lock`.
   It refuses if there is none.
2. Reads the R version from `renv.lock` with `sed`, using the pattern hvtiR's `lockfile_r_version()`
   uses (`"R": { ... "Version": "x.y.z"`).
3. Finds that R's `Rscript`, first `$HVTI_R_ROOT/<ver>/bin/Rscript` and then
   `/opt/R/<ver>/bin/Rscript` (Posit's layout on lri). If neither exists it refuses, naming the
   version the lock wants and listing the versions under `/opt/R`.
4. `cd` to the root and `exec "$RSCRIPT" -e '<fixed expression>' <cmd> <path> <final>`. The job path
   reaches R as an argument read with `commandArgs()`, never pasted into R source, so a directory
   name holding a quote or backslash cannot change what R runs. `status` and `cancel` go through the
   same expression to `job_status()` and `cancel_job()`.
5. `hvti run` exits 1 when a check refuses, or the render fails or vanishes during the wait, so
   `hvti run <job> && <next>` stops there. The R API still returns the status.

`hvtiRtemplates::install_hvti(dir = "~/bin")` installs it once per user. It **copies** the script and
does not symlink it: a symlink into the library breaks when the library path changes with the R
version, which is exactly the change the command exists to survive. It prints the `PATH` line to add
when `dir` is not on `PATH`. The script carries its version in a comment, and `run_job()` warns
once when the installed copy is older than the package's.

## 4. Preflight checks, before submit

Each check has a name, which is printed with its result and appears in the refusal, so a report or a
message to the team can name it. A refusal is one sentence saying what is wrong and one line giving
the exact command that fixes it. All the checks run, and every failure is reported together, so one
round of fixes clears them.

### 4.1 `r_version` (failure 1)

The session's R major.minor must equal the lock's. renv keeps one library per major.minor
(`renv/library/<platform>/R-4.5/`), so 4.5.1 and 4.5.3 share a library and a patch difference is a
note, not a refusal. On 2026-10-22, Positron started R 4.6.1 in a 4.5.3 study. renv then read the
empty R-4.6 library, and a `renv::snapshot()` rewrote the lock to 4.6.1, dropping boostmtree and
ggBoostedTrees.

> `r_version`: this study's renv.lock records R 4.5.3, but this session is R 4.6.1, so it would use
> a different package library. Run it from a terminal with `hvti run analyses/<job>.qmd`, or start
> R 4.5.3 (`/opt/R/4.5.3/bin/R`).

`hvti` makes this check pass by construction. It stays in `run_job()` for the R-console route.

### 4.2 `packages` (failure 3)

This covers the packages the job needs: what its `setup` chunk attaches, requires or version-checks
(the same scan as `.template_packages()`, run on the job rather than the template), plus `quarto`,
`knitr`, `rmarkdown`, `hvtiRtemplates` and `hvtiRutilities`. Each must be

- installed in the study library,
- recorded in `renv.lock`, and
- at the same version in both.

Each kind of gap has its own fix line. Missing from the library but locked: `renv::restore(packages
= "<pkg>")`. Installed but not locked: `hvtiR::update()`, which records it (and is itself guarded,
section 7). Versions differ: the same two commands, depending on which side is newer. Drift in a
package the job does not load is reported as one line and does not refuse: a ten-hour fit should not
wait on a package nobody attaches.

The lock is read with `jsonlite`, already in this package's Imports. Missing `quarto` on 2026-10-22 is the case this catches, and hvtiR 1.3.2 now
declares it.

### 4.3 `run_state` (failure 6)

This check reads `job_status()`.

- `running` on this host: refuse, pointing at `hvti status` and `hvti cancel`.
- `running` on another host: refuse, naming the host and the age of its last progress write. When
  that progress is `stale` (no write for three intervals and at least 30 minutes), the message says
  the job is probably dead and gives the `cancel_job()` call that abandons it from here (section 6).
- `submitted` less than 120 s ago: refuse as a submit in progress.
- A `.run.lock` directory older than 10 minutes: refuse, naming it and saying that a crashed submit
  left it. It is not removed automatically.
- `none`, `finished`, `failed`, `vanished`, `cancelled`: pass.

### 4.4 `quarto`

The Quarto CLI is found (`quarto::quarto_path()`), and `QUARTO_R`, if set in the environment the
render will inherit, names this R's `bin` directory. #386 leaves an existing non-empty `QUARTO_R`
alone, so a `.Renviron` that pins another R would otherwise win silently. This is the pre-submit half
of failure 2. The authoritative half runs in the render (5.1).

## 5. Checks inside the render, and the wait

Some facts exist only once the render is running: which R knitr really runs, and how many patients
and visits are left after the job's filters. These checks run in the render and stop it within a
minute or two of the start, not hours in. `run_job()` waits for them so the author sees the refusal
at the terminal, not later in a log.

### 5.1 `render_r` (failure 2)

`submit_job()` exports `HVTI_RUN_R=<R.home()>` to the runner. `.job_setup()` compares knitr's
`R.home()` with it when it is set, and stops on a difference:

> `render_r`: Quarto ran this render on R 4.4.1 (/usr/lib/R), not the R that submitted it, R 4.5.3.
> A QUARTO_R setting is overriding it: remove QUARTO_R from ~/.Renviron or the study's .Renviron.

An unset `HVTI_RUN_R`, as in a render from the editor's Render button, skips the check.

### 5.2 `memory` (failures 4 and 5)

`guard_memory(need_gib, why)` is a new exported function, called in a template's fit chunk just
before its expensive `cache_fit()`. It is also skipped when the cache exists, as `guard_long_fit()`
is.

- **Limit.** The function finds the session's memory cgroup from `/proc/self/cgroup` and reads
  `memory.limit_in_bytes` under the memory controller (cgroup v1, as on lri) or `memory.max`
  (v2). An unlimited leaf can sit beneath a capped ancestor, so the binding cap is the smallest
  finite limit from the leaf up, and usage and peak are read at that same cgroup. A detached job counts against its submitting session's cgroup, so this is the cap the fit
  will hit. If no limit can be read (macOS, or "max"), it uses physical memory and says so.
- **Need.** The template computes it from the data it actually loaded. For nb-boostmtree,
  `.boostmtree_need_gib(patients, visits, family, cores, M)` is fitted to the measured CORES table
  (2026-10-19, 2.0.4, ordinal) and the 2026-10-21 2.0.8 continuous run, with the per-step growth term
  the table's comment gives (about 0.35 MB per step per 1,000 visits, ordinal). The table and the
  estimator move into one place, `R/fit-memory.R`, and the template's comment points at it, so the
  numbers cannot drift between them.
- **Refusal** when need exceeds 90% of the limit. It names the profile to use, from a table of
  Workbench profiles and their enforced caps: Default 19.2, Small 38.4, Medium 76.8 and Large
  153.6 GiB, each 1.2 times the profile. It also names the `CORES` that would fit the current
  session.

> `memory`: this fit needs about <N> GiB (1,391 patients, 4,771 visits, continuous, 8 cores) and this
> session is capped at 19.2 GiB (Workbench "Default"). Start a "Medium" session (76.8 GiB) or
> larger, or set CORES <- <k> to fit in this one.

`<N>` and `<k>` come from the estimator. They are left symbolic here because fitting it is plan work,
not a number to guess in a spec.

The two 2026-10-22 cases are the fixtures. COMMENCE at 8 cores ran in a Default session (19.2 GiB)
and its workers were killed at the first CV step. Penny's ordinal fit, about 5,500 patients, 13,900
echoes and 8 cores, ran in a Medium session (76.8 GiB) and hit the cap at iteration 2. The estimator
must refuse both, and pass COMMENCE in Medium and Penny's fit in Large, which is how they then ran.

A cached rerender only loads the fit, so the template calls `guard_memory()` unconditionally with a
need of 0 in that case. That still records the `memory` check, so `run_job()`'s wait completes.
`guard_memory()` also records its estimate as `mem_need_gib` in `.run.progress` for the diagnosis.

`guard_memory()` is general. Other long templates (`rf*-fit`, `vp-fit`, the bootstraps) adopt it
when they have measured numbers. This spec wires only nb-boostmtree.

### 5.3 The wait

Each in-render check that passes writes `checks: [<name>, ...]` to `.run.progress`. `run_job()`
scans the job file for `guard_memory(` to know which checks to expect: always `render_r`, and
`memory` when the guard is present. It then polls `job_status()` every 5 s until

- every expected check is recorded, and it prints "checks passed; running (pid, host); `hvti status`
  to follow", or
- the state is `finished`, `failed`, `vanished` or `cancelled`, and it prints that status at once,
  with the diagnosis for a failure (section 6). A render can finish between two polls, or
- `wait` seconds pass, and it prints "still starting; `hvti status <job>` to follow".

A failure is then still diagnosed by `job_status()` later. `wait = 0` returns at once, as
`submit_job()` does.

**Legacy jobs.** A job scaffolded before the setup consolidation keeps its four old setup chunks
(AGENTS.md preserves them) and never calls `.job_setup()`, so it can never record `render_r`.
Installing a new package cannot add a check to a copied job, so `run_job()` does not expect one.
It runs the job with the pre-submit checks only, printing a note that the in-render checks do not
run and that `upgrade_job("<job>")` adds them. It does not refuse. The pre-submit `quarto` check
already refuses the known cause of a wrong render R (a conflicting `QUARTO_R`), and `render_job()`
sets `QUARTO_R` itself (#386). Refusing every legacy job would block studies whose jobs are
correct, and the upgrade is a choice the author makes, not a fix to impose before a run.

## 6. Diagnosis after a failure (failure 7)

When `job_status()` reports `failed` or `vanished`, it now ends with a plain reason and a fix,
matched from `<job>.run.log` and `.run.yml` in this order:

| signature | reason | fix |
|---|---|---|
| a check's own refusal (`r_version:`, `memory:` ...) | the refusal itself, verbatim | as it says |
| `worker result(s) were not delivered`, `Killed`, or exit status 137, **and** recorded peak ≥ 95% of the limit | the session ran out of memory: peak X of a Y GiB cap | the profile for the `mem_need_gib` `guard_memory()` recorded; with none recorded, "a session larger than this one (Y GiB)"; fewer `CORES` |
| the same without a recorded peak | probably memory; this run recorded no peak | as above, hedged |
| `there is no package called '<pkg>'` | the render ran on an R or library that lacks `<pkg>` | `hvti run <job>`; then the `packages` fix |
| `Quitting from <file>:<lines> [<label>]` | the job stopped in chunk `<label>`, lines `<lines>` | the error line that follows, quoted |
| anything else | no known cause | the last 20 lines of the log |

**Fixtures are real renderer output.** Quarto prints `Error:` (or `Error in <call>:`), then the
condition with a `! ` bullet, then `Quitting from <file>:<lines> [<label>]`, so the error comes
before the quitting marker. The matcher strips condition bullets before matching a check's refusal,
and takes the error from above the marker. The fixtures are rendered, not hand-written.

**Peak tracking (failure 5).** `.progress_write()` adds `mem_gib`, the cgroup's current usage, to
each write. At the end the runner records `mem_peak_gib` (v1 `memory.max_usage_in_bytes`, v2
`memory.peak`) and `mem_limit_gib` in `.run.yml`. Telemetry is advisory. A memory reading that fails or is NA drops its field and never prevents the
runner's terminal status write. `job_status()` shows `memory: 70.2 of 76.8 GiB
(peak)` while the job runs and after it ends. The v1 peak is the session's, not the job's alone. For
a session that submits one long job that is the number that matters, and the documentation says
which it is.

**Stale state (failure 6), with cancel_job().** `cancel_job()` is being built in its own session
(branch `feat/cancel-job`). This design does not duplicate it. It asks for one addition, sent to that
session on 2026-10-22: an explicit option to abandon a run recorded on another host, e.g.
`cancel_job(path, other_host = "abandon")`. It signals nothing, because no process on another host
can be reached. It records `cancelled` with a reason naming both hosts, and removes
`.run.progress`. `run_state` (4.3) names it when the other host's progress is stale. Until it
lands, `run_state` refuses and says to delete the two files by hand, as was done on 2026-10-22.

Built on `feat/cancel-job` as `cancel_job(path, other_host = c("refuse", "abandon"))`. ⚠️ **Stale
progress is not proof the job is dead.** processx starts Quarto's knitr in a session of its own, so a
host whose Workbench session has ended may still be running the fit. Abandoning it then lets a
second render start on the same outputs. `cancel_job()` therefore records an environment marker,
`HVTI_JOB_MARKER`, as `marker` in `.run.yml`. The `run_state` refusal never calls the job dead. It
says "probably", gives the command that confirms nothing is left on that host, `ps eww -u $USER |
grep <marker>` run there (or `hvti status` from a session on that host), and offers the abandon
call only after that.

## 7. Snapshot guard, in hvtiRutilities and hvtiR (failure 1, second half)

A `renv::snapshot()` from an R whose major.minor differs from the lock's records the wrong R and
drops every package the new library lacks. On 2026-10-22 that removed boostmtree and ggBoostedTrees
from COMMENCE's lock. The guard goes where snapshots are taken:

- `hvtiRutilities/R/study_need.R` (`.need_snapshot()`),
- `hvtiRutilities/R/study_setup.R:300`,
- `hvtiR/R/setup.R:663` (the snapshot `hvtiR::setup()` and `update()` run in the study).

Each refuses when `getRversion()` major.minor ≠ the lock's, naming both versions and the R to
start. `r_upgrade = TRUE` opts in to moving the study to the new R deliberately. Even then it refuses
while any package in the lock is missing from the new library, listing them and the
`renv::restore()` that installs them first, so a deliberate upgrade cannot drop a package either. A
study with no lock, or a lock with no R, passes.

Release order: hvtiRutilities first, with a patch bump, then hvtiR, raising its hvtiRutilities floor
in its own bump. Each is its own pull request in its own repository. This spec is the design record
for both.

## 8. Failure map

| failure on 2026-10-22 | check or diagnosis | test that reproduces it |
|---|---|---|
| 1. Session R 4.6.1 in a 4.5.3 study | `r_version` (4.1); `hvti` picks the lock's R (3) | temp study whose lock records 4.5.3, `getRversion()` mocked to 4.6.1: refuses, names 4.5.3. `hvti` against a fake `/opt/R` tree: execs 4.5.3's Rscript |
| 1b. snapshot rewrote the lock to 4.6.1 | snapshot guard (7) | in each repo: lock at 4.5.3, R mocked to 4.6.1, `renv::snapshot` mocked, so it is never called; with `r_upgrade = TRUE` and a locked package missing, still refuses |
| 2. Quarto rendered on the server's default R | `quarto` (4.4); `render_r` (5.1) | `QUARTO_R` set to another dir: preflight refuses. `.job_setup()` with `HVTI_RUN_R` ≠ `R.home()`: stops with the `render_r` message |
| 3. `quarto` package missing | `packages` (4.2) | lock without `quarto`, library with it; lock with it, library without; versions differ. Each refuses with its own fix line |
| 4. COMMENCE killed in a Default session | `memory` (5.2); diagnosis (6) | fake cgroup v1 tree at 19.2 GiB with COMMENCE's counts: refuses and names Medium. A log ending in "worker result(s) were not delivered" with peak 19.1/19.2: diagnosed as memory |
| 5. Penny's fit hit Medium's cap at iteration 2 | `memory` (5.2); peak tracking (6) | 5,500 / 13,900 / ordinal / 8 cores at 76.8 GiB: refuses, names Large; at 153.6: passes. The runner records `mem_peak_gib`, and `job_status()` prints it |
| 6. Stale `.run.yml` / `.run.progress` after a kill | `run_state` (4.3), with `cancel_job()` | `.run.yml` running on `lri-r06` with stale progress: refuses, names the host and the abandon call. Stale lock dir: refuses, naming it |
| 7. No plain reason on failure | diagnosis table (6) | one fixture log per signature, cut from the 2026-10-22 logs with no data in them, each mapped to its sentence; an unknown log gives the last 20 lines |
| 8. Positron console hung | `hvti` from a terminal (3) | `hvti run` in a fake study with a stub Rscript that records its arguments: called from the root with the right path and `final` |

Every test runs in a temp directory, with cgroup files, `/opt/R` trees and lockfiles built as
fixtures. None touches a study share, and none needs Workbench.

## 9. Not in scope

- `upgrade_job()`'s merge, designed in #384 and #388. For context only, what it did wrong on
  2026-10-22:
  - It wrote blank entries into the report and the description, because `paste0()` over empty
    vectors recycled to `""` (fixed with `recycle0 = TRUE`, #383).
  - It carried the description badly (two P2 regressions found in review, #383).
  - It refused on a `dc-tables` job because a `.pre-upgrade` copy from an earlier attempt already
    existed, with no way through but deleting it by hand.
  - It replaced Penny's job with the template's new text, losing her edits, which were restored by
    hand from the `.pre-upgrade` copy. That is the case the three-way merge exists for.
  - It left the job needing a `REFIT` decision before `submit_job()`, with nothing saying so.
- Memory estimators for templates other than nb-boostmtree.
- Windows. `submit_job()` already refuses there, and `hvti` is POSIX `sh`.
- Choosing or starting a Workbench session. The command can say which profile to start, but only
  the author can start it.
