# Production job workflow: one root, three entry points

Date: 2026-09-16
Status: design, awaiting review

## 1. Problem

A biostatistician porting one SAS job to R on the analysis server currently
works from a three-page manual cue sheet (bio-aggrecan, 2026-09-16). Almost
none of it is statistical judgement. It exists because the tools do not meet:

- Templates find the study root by looking for `_quarto.yml` in `.` or `..`.
  `hvtiRutilities::study_root()` looks for `_study.yml`. A study therefore has
  two root markers, and adopting a legacy study writes only one, so the author
  creates `_quarto.yml` by hand.
- Nothing derives the root, so the author defines `root` before calling
  `add_job()`. An undefined `root` is the first error a new user hits.
- Rendering is a remembered sequence: search for `EDIT:`, set or clear an
  environment variable, call `quarto_render()` with `execute_dir`.
- `migrate_job()` exists only on the unmerged
  [#120](https://github.com/ehrlinger/hvtiRtemplates/pull/120), and asks the
  user to name the template although the SAS filename already does.

The decisions that need a biostatistician are the `EDIT:` markers. Everything
else should be done by the package.

## 2. Goal

From inside a study that `study_setup()` has adopted, a biostatistician:

1. opens the study's R project,
2. calls `migrate_job()` for a SAS job, or `open_job()` for a new one, and lands
   in the job file,
3. works the `EDIT:` markers, rendering drafts as they go,
4. calls `render_job(path, final = TRUE)` for the accepted result.

No step creates a support file by hand, defines a path variable, or sets an
environment variable.

## 3. Decisions

| Question | Decision |
|---|---|
| Root marker | `_study.yml` only, found by `hvtiRutilities::study_root()` |
| `here::here()` | Not used by templates. `study_setup()` writes `<study>.Rproj`, so the opened project and `study_root()` agree |
| `endpoint`, `type` | Required arguments everywhere. They name the set and control artifact paths; a person chooses them |
| SAS job with no converter | Still migrates: scaffold, every marker kept, evidence report says no converter |
| Existing job in `open_job()` | Opened, not refused |
| Draft rendering | Draft by default, as #119 made the templates; `final = TRUE` makes an unfinished job stop |
| Existing production jobs | None exist. No compatibility path; test jobs are removed by hand |

`here::here()` was considered and not adopted for templates. It fixes its root
once per R session from the working directory, so a session started outside
`/studies` stays wrong without saying so, and it stops at the nearest of
`.here`, `.Rproj`, `DESCRIPTION` or `.git`, which a stray study `.git` can
satisfy. `study_root()` walks the same way but for the one file that defines a
study.

## 4. Design

### 4.1 Template root lookup (all templates)

Each template's `.root` block, which searches `.` and `..` for `_quarto.yml`,
becomes a call to `hvtiRutilities::study_root()` started from the directory of
the file being rendered, not the working directory, so the RStudio Render
button, `quarto render` and `render_job()` resolve the same root:

```r
.root <- hvtiRutilities::study_root(dirname(knitr::current_input(dir = TRUE)))
```

The line above is unverified under a server-side `quarto render`; the first
implementation task tests it and replaces it if it fails. Sourcing `R/*.R`
stays as it is, now under `.root`.

No dependency changes: `hvtiRutilities (>= 1.1.12)` already provides
`study_root()`.

### 4.2 `open_job(prefix, endpoint, type, qualifier = NULL, dir = ".")`

- Resolves the root with `study_root(dir)`.
- If the job file is absent, creates it through `add_job()`, keeping every rule
  `add_job()` enforces: refuse an ambiguous prefix, validate names, never
  overwrite.
- If the job file exists, opens it and says so.
- Opens the file in the editor in an interactive session; always returns the
  path invisibly.

### 4.3 `render_job(path, final = FALSE)`

- `final = FALSE` renders a draft: open markers appear in the template's DRAFT
  banner, as with the Render button.
- `final = TRUE` sets `HVTI_TEMPLATE_STRICT=1` for this render only and restores
  the previous value, so an unfinished job stops.
- Does not scan for `EDIT:` itself. The template's edit guard is the one
  authority, so `render_job()` and a bare `quarto render` cannot disagree.
- Renders with the job's own directory as the execution directory.

### 4.4 `migrate_job()` (on #120, after it merges `main`)

```r
migrate_job(source, endpoint, type, prefix = NULL, qualifier = NULL,
            lst = NULL, log = NULL, reference = NULL, dir = NULL)
```

- **Template from the filename.** A corpus job is `<prefix>.<variable>[...].sas`.
  `dc.tables.ods.sas` gives prefix `dc`, qualifier `tables`; later fields are
  ignored. Where the prefix is qualified and the second field names none of its
  qualifiers, stop and list them. `prefix` and `qualifier` override.
- **Root** from `study_root()` started at the source file's directory; `dir`
  overrides.
- **Listing and log** default to the same-stem `.lst` and `.log` beside the
  source; the report records whether each was found. `lst` and `log` override,
  for studies that name them differently.
- **`reference`** stays explicit: output references are not named after the job.
- **With a converter** (`dc-tables`, `dc-gfup`, `dp-trends`, `dp-postage`):
  behaviour as on #120. Only deterministic extraction removes an `EDIT:` marker.
- **Without a converter:** scaffold through `add_job()`, keep every marker, and
  write the evidence report headed "no converter: every choice is manual".
- Ends as `open_job()` does. Never overwrites, never modifies source files, and
  keeps #120's withholding of patient-level content from reports.

The cue sheet's port step becomes:

```r
migrate_job("descriptive/dc.tables.ods.sas", "cohort", "eda",
            reference = list.files("documents", "^general_.*[.]rtf$", full.names = TRUE))
```

### 4.5 `study_setup()` writes an R project (hvtiRutilities)

When no `.Rproj` exists at the root, `study_setup()` writes `<study>.Rproj`.
An existing one is left alone.

## 5. Errors

Each names what failed, what was checked, and the next step.

| Condition | Response |
|---|---|
| No `_study.yml` above the job | `study_root()`'s error: directories walked, run `study_setup()` |
| Ambiguous prefix | Stop, list qualifiers (as `add_job()`) |
| SAS filename not `<prefix>.<variable>` | Stop, say to pass `prefix` and `qualifier` |
| `lst` or `log` override path missing | Stop |
| Default `.lst` or `.log` absent | Continue, recorded in the report |
| `render_job(final = TRUE)` on an unfinished job | The template's own stop, unchanged |

## 6. Tests

All in temporary studies, never `/studies`.

- Root: a template renders to the same root from outside the study, from the job
  directory, and from a deeper directory. First task; it decides §4.1's line.
- No template contains `_quarto.yml`.
- `open_job()`: creates when absent; opens an existing job and leaves its bytes
  unchanged; stops on an ambiguous prefix.
- `render_job()`: marked job drafts by default, stops under `final = TRUE`, and
  `HVTI_TEMPLATE_STRICT` is restored afterwards, including after an error.
- `migrate_job()`: filename inference, including the ambiguous case; a
  no-converter prefix gets the scaffold, all markers and the report heading;
  default and override `lst`/`log`.
- `study_setup()`: writes `.Rproj` when absent, leaves an existing one.
- Each change is proven by mutation: revert it and confirm its tests fail.
- If a new test reads the job catalog, widen the `R-CMD-check.yaml` filter.

## 7. Delivery

| Order | Repository | Change |
|---|---|---|
| 1 | hvtiRutilities | §4.5 |
| 2 | hvtiRtemplates | §4.1 to §4.3, NEWS under unreleased |
| 3 | hvtiRtemplates, #120 | Merge `main`, then §4.4 |
| 4 | hvtiRtemplates | Vignette and production walkthrough rewritten around the three entry points; may join 3 |

Manual, by the maintainer: remove the test jobs already scaffolded into
production studies before PR 2 is used there.

## 8. Out of scope

- Converters for templates that lack one. The intended end state is that every
  template ships as a pair, template and converter; that is separate work with
  its own design.
- Changing whether templates source `R/*.R`.
- Package installation and version checks on the server (`hvtiR::doctor()`
  already covers them).
