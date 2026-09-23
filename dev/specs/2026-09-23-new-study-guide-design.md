# New-study guide: start a study from a delivered dataset

**Date:** 2026-09-23
**Status:** Design approved by John Ehrlinger on 2026-09-23; spec awaiting review
**Depends on:** [#142](https://github.com/ehrlinger/hvtiRtemplates/pull/142)
(`subject`, provenance hooks, `hvtiRutilities (>= 1.4.0)`). Branches from it and
merges after it.

## 1. Objective

`vignettes/study-setup.qmd` covers one path: adopting an **existing** study for
descriptive and EDA work. No guide covers the other common start, a study that
does not exist yet and whose analysis dataset has just been delivered. This
guide covers that path, from an empty directory through a first analysis chain,
so a study author sees how the templates connect rather than meeting them one
at a time.

### In scope

- `hvtiRutilities::study_setup()` on an empty directory.
- Registering one delivered, analysis-ready dataset with `register_data()`.
- Scaffolding a first EDA job and the hooks `add_job()` installs.
- What rendering produces, including the `.provenance.json` sidecar.
- One worked chain, `ac` then `hz` then `hp`, on a `death` subject.

### Out of scope

- Building the analysis dataset from a raw extract (`hvtiRdatabuild`). Linked,
  not taught. **Planned follow-up (John Ehrlinger, 2026-09-23):** amend this
  guide to start *without* a study dataset, with building it as the first
  step. That waits on the template package learning to build datasets (a
  `00_datasets` build template); the guide follows the package, not the other
  way round.
- RStudio project, R version and `renv` pinning. Already covered by
  `study-setup.qmd`, and linked rather than copied, so the two cannot drift.
- Rendering any job during the vignette build (section 4).
- Chains other than `ac`/`hz`/`hp`. Listed in the closing section only.

## 2. Placement

- New file `vignettes/new-study.qmd`, titled "Start a new study from a delivered
  dataset", with `VignetteIndexEntry` "Start a new study".
- Added to `_pkgdown.yml` `articles:` beside `study-setup`.
- Each vignette's introduction names the other and says when to use it: a study
  directory that already holds jobs and data goes to `study-setup`; an empty one
  comes here.
- `study-setup.qmd` gains that one cross-link paragraph and nothing else.

## 3. Outline

1. **Before you start.** What "delivered dataset" means here: one
   analysis-ready file, CSV or SAS transport, one row per patient or per
   observation as the analysis needs. No PHI enters the repository. A link to
   `study-setup.qmd` for the RStudio project, R version and `renv` steps.
2. **Create the study.** Create the Study Tracker record first, then run the
   `qhsprograms` `study-setup` command (`--dry-run`, then for real) with its
   Tracker ID; it calls `study_setup()` underneath, which the executable
   example calls directly because the vignette cannot reach Study Tracker. The numbered layout (`00_datasets`, `10_descriptive`,
   `20_distributions`, `30_analyses`, `40_graphs`, `50_documents`,
   `90_estimates`), what each folder holds, and why `90_estimates` holds saved
   output rather than jobs. `_study.yml` and what it identifies.
3. **Register the dataset.** Copy the file into `00_datasets`, then
   `register_data(root, built = "<file>", role = "study", population = "...")`.
   What the registration records (bytes, hash, population) and why every job
   reads through it rather than through a path: the render records which bytes
   it read, and a job that reads a path cannot.
4. **Scaffold the first EDA job.**
   `add_job("dc", subject = "cohort", type = "eda", qualifier = "general")`.
   How the filename `<subject>-<type>-<prefix>[-<qualifier>].qmd` is built and
   why `cohort` is a valid subject for an endpoint-free job. The `EDIT:` markers
   as the job's interface. What `add_job()` also installs: `_quarto.yml`
   pre-render and post-render hooks and `.hvtiR/hooks/`, with existing project
   settings preserved.
5. **Render and read the provenance.** `render_job()` and the Render button run
   the same hooks. A fixed, labelled excerpt of a `.provenance.json` sidecar,
   annotated: job, subject and type, the dataset record, and the output hash.
   What happens to a sidecar when a render fails.
6. **A first analysis chain: death.** Scaffold `ac`, `hz` and `hp`, each with
   `subject = "death", type = "hz"`. Why the chain shares one `(subject, type)`
   set: `hp` reads `ac.rds` and `hz.rds` from that set's `90_estimates`
   directory. Render order `ac`, `hz`, `hp`. Each handoff `.rds` carries
   `hvti_provenance` lineage, and `hp` stops on a handoff without it or on two
   handoffs built from different data. An inline SVG figure shows the three
   jobs, the two handoffs and the sidecars.
7. **Where to go next.** `template_list()` to browse, and pointers to the other
   chains: random forests (`rf*`), logistic models (`lm*`), bootstrap (`bh`).

## 4. How the vignette executes

- A hidden `synthetic-setup` chunk, following `study-setup.qmd`, builds a
  temporary workspace and a 40-row synthetic death dataset: an id, a follow-up
  time, a 0/1 event indicator and two covariates. It is generated in the chunk,
  so the vignette ships no data file and no PHI.
- Every chunk the reader copies runs for real: `study_setup()`,
  `register_data()` and each `add_job()`. A renamed argument then fails the
  vignette build instead of leaving the guide silently wrong.
- **Nothing renders.** Section 5's sidecar is a static excerpt marked as an
  example. The vignette build therefore needs neither Quarto execution of a job
  nor TemporalHazard or hvtiRpropensity, and adds no measurable check time.
- The chain figure is inline SVG with colours drawn from CSS variables, so it
  reads in the pkgdown site's light and dark themes.

## 5. Tests

New `tests/testthat/test-vignette-new-study.R`, reading the vignette source in
the manner of `test-vignette-migration.R`:

- Every `add_job()` call names `subject =` and none names `endpoint =`.
- The vignette scaffolds `dc` with qualifier `general`, and `ac`, `hz` and
  `hp`, and the three chain jobs share one subject and one type.
- The two vignettes link to each other.

`new-study.qmd` is also added to the existing "tutorials use the RStudio project
as the study root" test, so it inherits the no-`setwd()` and `.Rproj` checks.

**These tests run in CI.** Like `skip_without_vignette()` in
`test-vignette-migration.R`, the new helper falls back from the source tree to
`system.file("doc", "new-study.qmd")`, which `R CMD check` installs. Only tests
that read `test_path()` alone skip on CI (the SAS-guide and tutorials tests,
the two skips on every leg). Adding `new-study.qmd` to the tutorials test
therefore adds no new skip, and the expected summaries stay SKIP 2 on macOS and
Ubuntu and SKIP 3 on Windows.

The vignette build is the second gate: `R CMD check` re-builds vignette outputs
on every leg, and every reader-facing chunk executes.

## 6. Definition of done

- `devtools::test()` passes.
- `devtools::check()` is 0 errors, 0 warnings, 0 notes, and the vignette
  rebuild step's time is read from the log.
- The pkgdown article builds and the chain figure renders in both themes.
- The prose has had an `ehrlinger-writing` pass.
- `NEWS.md` gains an entry under `# hvtiRtemplates (unreleased)`, since the
  vignette ships.
