# Next release: "EDA complete" Release Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** close out the 2026-09-24 template review with Lauren. A study author scaffolds one `dp-eda` job, renders it against a real study, and gets the whole EDA report: goodness of follow-up, continuous variables, categorical variables as percentages and as counts, each with its table, in the house palette, with labels a reader can tell apart.

**Architecture:** three packages, released in dependency order, the pattern that shipped 1.2.2 on 2026-09-25 (hvtiPlotR 2.7.17 and hvtiRutilities 1.4.1 first, then the templates). Logic goes into package functions; the templates stay thin and call them, so `dp-eda` and the standalone jobs cannot drift apart.

**Tech Stack:** R, Quarto templates, testthat 3e; hvtiPlotR, hvtiRutilities, hvtiRtemplates.

**Spec:** `dev/specs/2026-09-25-eda-composite-design.md` (the EDA composite) and `hvtiRutilities` `dev/specs/2026-09-02-label-length-and-fallback-design.md` §4.2 (smart truncation).

**Scope decided by John Ehrlinger, 2026-09-25:** finish EDA, including both cross-package pieces (the palette helper and smart truncation). Batch-3 plot templates wait for the release after.

## Where things stand (2026-09-25)

| piece | state |
|---|---|
| `hv_eda_pages()`, `hv_followup_panels()` | shipped, hvtiPlotR 2.7.17 |
| `followup_check()` | shipped, hvtiRutilities 1.4.1 |
| `dp-postage` in `SECTIONS`, `dc-gfup`/`dp-gfup` on the shared functions | shipped, hvtiRtemplates 1.2.2 |
| `dp-eda` | not started; design §4 and §6 decided, §4.1 (tables) proposed |
| palette | decided in the review, not built; `dp-gfup` hard-codes `COLOURS`, `dp-postage` uses ggplot defaults |
| smart truncation | spec §4.2 merged (hvtiRutilities #149), not built |
| `dc-general` edit block | Lauren's note, not done |

## Decisions needed before or during the work

1. **Version number.** The release adds a template and changes defaults in two others. The house rule makes minor and major John's call; the plan assumes the patch **1.2.3** unless John names 1.3.0.
2. **Confirm §4.1, a table beside each EDA section.** Proposed on 2026-09-25 and built into `dp-postage` (#148), but not marked decided in the spec. Phase 3 assumes yes.
3. **The acceptance study.** Which study, and which SAS EDA output, `dp-eda` is checked against (design §7.4). Needed for Phase 4 only.
4. **Whether a study's abbreviation list reaches `read_built()`** (hvtiRutilities spec §4.2.1). This plan takes the smaller path: the abbreviation list is a template `EDIT:` point passed to `label_map()`, and the analysis-set sidecar route is deferred (see Out of scope).

## Phase 1: hvtiPlotR palette helper (release 2.7.18)

The rule from the review: an event is red, censored is blue, missing is light grey; otherwise ColorBrewer Set1, falling back to Set3 when the levels outrun it; points at alpha 0.5; a single-level plot draws blue.

- [ ] **Design note first** (in hvtiPlotR `dev/`): name and shape of the helper. Working proposal: `hv_palette(levels, event = NULL, censored = NULL, missing = "(Missing)")` returning a named colour vector, plus `scale_colour_hv()` / `scale_fill_hv()` wrappers. Colours stay the caller's choice per CONTRIBUTING, so this is an opt-in scale, not a default inside constructors.
- [ ] Implement with tests: event and censored levels take red and blue whatever their position; missing takes light grey; Set1 order for the rest; Set3 beyond Set1's nine; a single level is blue.
- [ ] Worked example in `vignettes/plot-functions.qmd` and a row in the SAS migration guide (CONTRIBUTING steps 6 and 7).
- [ ] NEWS, `lintr` 0, full suite, local `/code-review`, PR.
- [ ] After merge: bump to **2.7.18** (separate PR), release gate, tag and release.

## Phase 2: hvtiRutilities smart truncation (release 1.4.2)

Implements hvtiRutilities spec §4.2 in `label_map()`: labels that differ in `label_full` differ in `label`.

- [ ] Step 1, abbreviate a shared heading: text before `: `, ` - ` or `; `, shared by two or more labels with one over the cap; initials skipping `of and the in for to at on with by or`; a one-word heading left alone; two headings with the same initials are not abbreviated.
- [ ] Step 2, the existing word-boundary cut. Step 3, keep both ends (`head ... tail`) where cut labels still collide. Step 4, show the label whole and set a new `over_cap` column.
- [ ] `abbreviations` argument: a named vector, phrase to abbreviation, used before the initials rule and applied whole-word to any over-cap label.
- [ ] The abbreviations used come back as an `abbreviations` attribute on the map (`abbreviation`, `expansion`).
- [ ] §4.1 still holds: a variable name standing in for a missing label is never abbreviated or cut.
- [ ] Property test of the invariant; tests for each step, the initials collision, the supplied list, and the name fallback. Prove the invariant test by mutation (disable step 3, watch it fail).
- [ ] NEWS, `lintr` 0 (install first; see that repo's AGENTS.md), full suite, local `/code-review`, PR.
- [ ] After merge: bump to **1.4.2**, release gate (with TeX on `PATH`), reverse dependencies hvtiRtemplates and hvtiRdatabuild, tag and release.

## Phase 3: hvtiRtemplates (release 1.2.3)

Phases 1 and 2 must be released before 3b and 3c can raise their floors; 3a and the skeleton of 3d need neither and can start at once.

### 3a. `dc-general`: explain the groupings where they are asked for
- [ ] Move the label and grouping explanation from the `spec` chunk into the `study-choices` edit block, where `CATEGORICAL` and `CONTINUOUS` are set. Prose only; no behaviour change. NEWS line.

### 3b. Palette in the EDA templates (needs hvtiPlotR 2.7.18)
- [ ] `dp-gfup`: replace the hard-coded `COLOURS` with the helper; keep a palette `EDIT:` point so a study can switch to Set3 or its own colours.
- [ ] `dp-postage`: apply the helper to categorical pages (`page & scale_fill_hv(...)`), missing in light grey.
- [ ] Floors: `hvtiPlotR (>= 2.7.18)` in `DESCRIPTION`, the templates' setup guards, and the Suggests-bounds test.

### 3c. Labels in the EDA templates (needs hvtiRutilities 1.4.2)
- [ ] `dp-postage`: `LABEL_MAX` (default 40) and `ABBREVIATIONS` (default `NULL`) edit points, passed to `label_map()`; print the abbreviation key under each section when one was used.
- [ ] Floors: `hvtiRutilities (>= 1.4.2)`; the helper allow-list test gains nothing new unless a new function is called.

### 3d. `dp-eda`, the composite template
- [ ] `inst/templates/10_descriptive/dp-eda.qmd`, following design §4 and §6: the usual setup, data and `study-choices` chunks; `PANELS`/`EVENTS`/`CLOSE_DATE`/`ORIGIN_YEAR` as `dp-gfup` has them; `VARIABLES`/`EXCLUDE`/`SECTIONS`/`ALPHA`/palette/`LABEL_MAX`/`ABBREVIATIONS` as `dp-postage` has them.
- [ ] Sections, in order: overview table (`proc_contents()`); follow-up (`followup_check()` tables and `hv_followup_panels()` figures); continuous, percent and count (`hv_eda_pages()` with `proc_means()` and one `proc_freq()` table). Chunk labels prefixed by section (`gfup-`, `cont-`, `pct-`, `cnt-`). Each page gets a heading and a caption naming its variables.
- [ ] Same-figure guarantee: a test that renders `dp-eda` and `dp-postage` on the same fixture and compares their page structure, so the composite cannot drift from the standalone job.
- [ ] Catalog row (`dp`, qualifier `eda`, folder `descriptive`) with a `description`; re-render the roadmap; `.lintr` file key; `inst/templates/README.md` row; `test-eda-configuration.R` and `test-template-provenance.R` inventories; render tests including an embed check and a subfolder job (the two ways `dp-postage` broke before #148 merged).
- [ ] NEWS entry.

### 3e. Before the version bump
- [ ] Mark design §4.1 decided (or change 3d if John says no) and record the Phase 1 and 2 function names in the design's status block.
- [ ] Full suite, `lintr` 0, spec-count checks, local `/code-review` on every substantive push.

## Phase 4: acceptance with Lauren

- [ ] Scaffold `dp-eda` on the acceptance study (decision 3) and render it.
- [ ] Walk it with Lauren against her current EDA report and the SAS EDA output: every variable present, sections split correctly, percent and count bars aligned, labels distinguishable, colours per the rule.
- [ ] Anything that fails becomes an issue; fixes land before the bump.

## Phase 5: release

- [ ] Bump PR: `# hvtiRtemplates (unreleased)` to the version from decision 1; `DESCRIPTION` `Version` and `Date`.
- [ ] Release gate on the bump PR's head: CRAN Cookbook spot-checks (`DESCRIPTION`, `\value`, `\dontrun`), `R CMD check --as-cran` with the PDF manual from a clean `git archive` (TeX on `PATH`), `urlchecker`, reverse dependencies (none today).
- [ ] After merge: confirm the merge tree equals the gated tree, tag, publish the release from the NEWS section.
- [ ] Then the hvtiR catalog refresh and its bump (deferred from 1.2.2 on 2026-09-25).

## Order and parallelism

```
Phase 1 (hvtiPlotR) ──► 2.7.18 ──┐
Phase 2 (hvtiRutilities) ► 1.4.2 ─┼─► 3b, 3c ─► 3e ─► Phase 4 ─► Phase 5
3a, 3d skeleton (no new deps) ────┘
```

Phases 1, 2, 3a and a `dp-eda` skeleton on today's defaults can run in parallel. `dp-eda` is written against 2.7.17 and 1.4.1 first, and gains the palette and label edit points once those releases exist. The house rule allows one version bump per package per day, so plan the two upstream releases for different days from any other bump in their packages.

## Risks

- **Check time.** The 1.2.2 check took 11.9 minutes, most of it Quarto render subprocesses. hvtiRtemplates is not a CRAN target, so the 10-minute budget does not bind, but `dp-eda` adds renders: keep its render tests to one fixture each and reuse fixtures across assertions.
- **Copilot reviews a PR once, as opened.** Each phase's fix commits need the local `/code-review`; say so in the PR body.
- **A shared checkout.** On 2026-09-25 two sessions worked in the same hvtiRtemplates directory. Use a worktree per branch.

## Out of scope, and where it goes

| item | goes to |
|---|---|
| batch-3 templates (`lp`, `np`, `dp-variable`, `rp`, `mp`, `dp-spaghetti`, `dp-procs`) | the release after this one |
| `dp-spaghetti` as a fifth EDA section (design §7.1) | decide when `dp-spaghetti` ships |
| a study abbreviation list recorded in the analysis-set sidecar (hvtiRutilities §4.2.1, needs hvtiRdatabuild) | a later release; this one uses a template `EDIT:` point |
| a Kaplan-Meier connector argument (review, 2026-09-24) | hvtiPlotR, when Lauren's `%KAPLAN` research answers what `ac` plots |
| updating an existing job to a newer template | its own design note |
| year and month of operation built in the data build | the SAS programmers (design §7.2) |
| hvtiPlotR dead bibliography URLs and 17 MB tarball | in progress in a separate session |
