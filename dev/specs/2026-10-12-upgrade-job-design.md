# upgrade_job(): rewrite a job from the current version of its template

Issue: [#307](https://github.com/ehrlinger/hvtiRtemplates/issues/307), from the 2026-10-12
analyst check-in. Status: **design, approved 2026-10-12** (both open questions settled as recommended).

## Problem

`add_job()` copies a template once. When the template improves, the job keeps the old shape.
#303 made that concrete: every template's four setup chunks (`setup`, `guard-edits`,
`guard-partial`, `set`) became one, and every job scaffolded before it still carries four.
Today the only path forward is a fresh `add_job()` and re-entering every choice by hand.

`migrate_job()` does not cover this. It converts a legacy *source* job (SAS, old QMD) through a
per-template converter. This is a job that already came from a template, moving to that
template's current version.

## The constraint that shapes the design

**A job does not record which version of its template it was copied from.** `add_job()` writes
`SUBJECT` and `TYPE` into the copy and nothing else. The package version in the run record
(`R/run-info.R`) is the version installed at *render* time, which says nothing about scaffold
time.

So a true three-way merge (base = the template as copied, ours = the job, theirs = the current
template) is not available: the base is unknown, and recovering it would mean searching the
template's git history, which an installed package does not have.

What *is* available is the interface `AGENTS.md` already defines: a study's choices are the
`EDIT:`-marked top-level assignments in the job, `DATASET <- "built"`, `PREDICTORS <- c(...)`
and so on. Those carry by name, independent of the base.

## Decisions

1. **The template is read from the filename**, through `.job_name_fields()` and
   `.select_template()`, so both spellings (`rfs.dead.rfs.qmd` and the pre-2026-10
   `dead-rfs-rfs.qmd`) and renamed templates (`dp-trends` to `dc-trends`, with its deprecation
   warning) resolve as they do everywhere else. A job whose name names no template is an
   error, not a guess.

2. **A choice is a top-level `NAME <- value` assignment** found by `parse()` in the job's
   `edit-*` chunks (every template has one `edit-study-choices` chunk; `hm`, `hz` and
   `hs-concordance` have more), with `NAME` matching `^[A-Z][A-Z0-9_]*$`. Found by the parser, not by regex, so a
   multi-line `CATEGORICAL <- list(...)` is one choice. Excluded: `SUBJECT` and `TYPE`, which
   the filename owns and `add_job()` writes; dot-prefixed and lowercase names (`.in`, `.root`,
   `set_path`, `d`), which are the template's machinery, not the analyst's choices.

3. **A carried choice replaces the same-named assignment in the current template verbatim**,
   source text and all, multi-line included. Where the job had resolved that choice's
   `EDIT:` marker (deleted the comment), the upgrade deletes the current template's marker above
   it too; where the job still carried the marker, the upgrade keeps it. Otherwise every
   upgraded job would come back a draft for choices the analyst had already made.

4. **Nothing is dropped silently.** The report lists:
   - **carried**: each choice, with the line it landed on;
   - **not placed**: a choice the job sets that the current template no longer has, with its
     line in the old job. The upgrade adds an `EDIT:` marker at the end of the study-choices
     chunk naming each one, so the job cannot render final until someone decides;
   - **new**: a choice the current template has that the job did not, left at the template
     default with its marker;
   - **review**: a chunk label in the old job that the current template does not have (an
     analyst-added chunk, such as study-specific checks), and a shared chunk whose code, outside
     the carried assignments, differs from the current template. Both are listed by label and
     line range; their code is not moved, because without the base the upgrade cannot tell an
     analyst's edit from the old template's text.

   **Prose is not carried.** The upgraded job has the current template's prose, its
   `EDIT:` markers included, and the report lists every marker left. The old job's prose is
   in `<file>.pre-upgrade`.

   The report quotes **names and line numbers, never values**: a `WHERE` can name a patient,
   and the report is a file that travels.

5. **The old job is kept, under a name nothing renders.** It is renamed to
   `<file>.pre-upgrade`, with no `.qmd` extension, so a project render does not pick it up and
   fail its name check. The upgraded job is written at the current spelling. A job in the
   pre-2026-10 spelling therefore moves to the dot spelling, which is the name `add_job()` would
   give it today. The upgrade refuses if either the `.pre-upgrade` file or the target already
   exists, as `add_job()` and `migrate_job()` refuse to overwrite.

6. **The report is `<stem>-upgrade.md` beside the job**, with the same shape as
   `migrate_job()`'s `-migration.md`: the template name, the package version, the old job's
   path and SHA-256, and the four lists above.

7. **From now on, `add_job()` stamps the job.** It writes one HTML comment after the front
   matter, `<!-- hvtiRtemplates: <template> <version> -->`. A later `upgrade_job()` reads it
   to report the version a job came from. The stamp is also what makes a real three-way
   merge possible later, once there are stamped jobs and an archive of shipped templates to
   read the base from. That is out of scope here.

## Out of scope

- Three-way merge of arbitrary code edits (decision 7 makes it possible later).
- Upgrading runners (`inst/runners/`). They are R scripts with their own shape; a follow-up.
- Batch upgrade of a whole study. `upgrade_job()` takes one path; a loop is the caller's.

## Done when (from #307)

- An `rfs-fit` job scaffolded from the **v1.3.0** template (four setup chunks) upgrades to the
  current template with every choice intact. The test fixture is that file from the tag, with
  its choices edited away from the defaults.
- A choice the current template does not have is listed in the report and marked in the job.
- `devtools::check()` 0/0/0; new tests proven by mutation (revert the carry and they go red).

## Settled 2026-10-12

- **Decision 5**: the old job stays beside the new one as `<file>.pre-upgrade`.
  <sub>Superseded 2026-10-23: the old job and the report now go to `_archive/` in the job's folder, as
  `<stem>.<stamp>.pre-upgrade` and `<stem>.<stamp>-upgrade.md`, so a second upgrade no longer stops on the first's
  files (requested at the 2026-10-23 umbrella review).</sub>
- **Decision 3**: a marker the analyst already resolved is dropped from the upgraded job.
