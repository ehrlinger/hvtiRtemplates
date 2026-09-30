# `hs-concordance` Implementation Plan

> **For agentic workers:** work task by task, in order. Steps use checkbox
> (`- [ ]`) syntax. Stop and report at each checkpoint; do not start the next
> task from a state you cannot describe.

**Goal:** Rename the shipped `hs` template to `hs-setup`, then ship
`hs-concordance`, with catalog rows, lint keys, tests and docs.

**Spec:** `dev/specs/2026-09-30-hs-concordance-design.md`. Read its sections
5 to 9 and 12 before Task 5.

**Architecture:** `hs-concordance` reads one `hm.rds` per treatment group,
each from the set whose `hm` job fitted it, predicts every patient through
every model at one horizon, and saves one long artifact,
`hs-concordance.rds`, in its own comparison set. A decision section
(optimal group, concordance table) is optional.

**Two pull requests, in this order.** The rename changes no behavior and
touches many tests; the new template adds behavior and touches few. Keeping
them apart keeps each reviewable.

| PR | branch | contents |
|---|---|---|
| A | `feat/hs-setup-rename` | Tasks 1 to 4 |
| B | `feat/hs-concordance` | Tasks 5 to 10, opened after A merges |

---

## Global constraints

- Branch from `origin/main`, never local `main`. Open each PR against
  `main`. Never push to `main`.
- No `Version:` change. `NEWS.md` entries go under
  `# hvtiRtemplates (unreleased)`, added if absent.
- Templates carry no study identifiers. Every study-specific line is marked
  `EDIT:`. Exactly one `^SUBJECT\s+<- ` line and one `^TYPE\s+<- ` line per
  template.
- Each template carries its own `format:` block and its own FILE key in
  `.lintr`.
- Lines at most 135 characters. Roxygen is Rd markup, not markdown.
- Prose follows the house voice, with no em-dashes. R comments use `--`.
- Look up any `TemporalHazard` or `hvtiRutilities` call in the installed
  documentation before using it.
- Definition of done for each PR: `devtools::test()` passes with `WARN 0`
  outside the known `test-rf-templates.R` warnings, `devtools::check()` is
  0/0/0, `lintr::lint_package()` is clean, `devtools::document()` leaves no
  diff, and the three `dev/specs/artifacts/check-*.py` guards pass.
- Run `/code-review` locally before opening each PR and say so in its body.

---

## Measured before planning, 2026-09-30, on `origin/main` at `7164e2d`

- The catalog is `inst/extdata/templates.json`, 66 rows, 44 prefixes.
  `tests/testthat/test-template-catalog.R` asserts both numbers.
- The `hs` row has `qualifier: null`, `status: shipped`, `folder: graphs`,
  `spec: dev/specs/2026-08-29-hs-template-design.md`.
- ⚠️ **The `hs` row's note records a 2026-09-10 triage decision** that the
  setup and uses-setup split, the conditional setups and the compare-benefit
  setups "fold into this row rather than becoming qualifiers". This plan
  qualifies the prefix anyway, on the maintainer's 2026-09-30 decision.
  Task 1 rewrites the note so the row does not contradict itself. The
  folding still holds for everything that note lists: they all stay under
  `hs-setup`.
- `R/` has no literal `"hs"`. Placement and selection are driven by the
  catalog.
- `hs.qmd` saves `hs.rds`. Nothing else in `inst/templates/` or `R/` reads
  that filename.
- Files that name the template, outside `dev/specs/` and `NEWS.md`:
  `.lintr`, `inst/templates/README.md`, `dev/gallery/index.html`, and under
  `tests/testthat/`: `helper-hazard.R`, `test-data-contract.R`,
  `test-eda-configuration.R`, `test-hazard-chain.R`,
  `test-template-lineage.R`, `test-template-provenance.R`,
  `test-templates.R`, `test-taxonomy.R`.
- `hazard_run(prefix, labels, env, choices)` in `helper-hazard.R` resolves
  the file with `template_path(prefix)`. `rf_run()` in `helper-rf.R` already
  takes `(prefix, qualifier, ...)` and is the pattern to follow.
- `migrate_job()` reads a qualifier from a SAS filename's SECOND field, and
  only when that field names a qualifier of the prefix. A corpus job is
  `hs.dead.setup.sas` or `hs.dead.concor_discor10.sas`: the second field is
  the endpoint. So after the rename, migrating an `hs` job needs
  `qualifier =` passed by the caller.

---

## File structure

| file | PR | change |
|---|---|---|
| `inst/templates/40_graphs/hs.qmd` | A | renamed to `hs-setup.qmd`, contents unchanged except self-references |
| `inst/extdata/templates.json` | A | `hs` row takes `qualifier: "setup"`; a `queued` `hs-concordance` row is added |
| `.lintr` | A | the `hs.qmd` key becomes `hs-setup.qmd` |
| `tests/testthat/helper-hazard.R` | A | `hazard_run()` gains `qualifier = NULL` |
| the eight test files listed above | A | resolve `hs-setup` |
| `tests/testthat/test-template-catalog.R` | A | 66 rows becomes 67 |
| `inst/templates/README.md` | A, B | table row, prose, migration note; then the new row |
| `dev/gallery/index.html` | A | only if it names the template by file |
| `NEWS.md` | A, B | one unreleased entry each |
| `inst/templates/40_graphs/hs-concordance.qmd` | B | new |
| `tests/testthat/helper-concordance.R` | B | new: a two-group study with two fitted `hm` sets |
| `tests/testthat/test-hs-concordance.R` | B | new |

---

# PR A: rename `hs` to `hs-setup`

## Task 1: catalog

- [ ] In `inst/extdata/templates.json`, set the `hs` row's `qualifier` to
  `"setup"`. Keep `name`, counts, `upstream`, `downstream` and `spec`.
- [ ] Rewrite that row's `note`: keep the 2026-09-10 triage sentence, and add
  that on 2026-09-30 the prefix was qualified because `hs-concordance` was
  admitted, and that the setups the triage folded in remain under
  `hs-setup`.
- [ ] Add a row: `prefix: "hs"`, `qualifier: "concordance"`,
  `name: "Hazard concordance"`, `folder: "graphs"`,
  `family: "hazard-chain"`, `kind: "job"`, `status: "queued"`,
  `upstream: ["hm"]`, `downstream: []`, `workflows: ["hazard-chain"]`,
  `spec: "dev/specs/2026-09-30-hs-concordance-design.md"`,
  `disposition: "scaffold"`, `uses: ["TemporalHazard::hazard"]`,
  `sas_breadth_jobs: 3`, `sas_breadth: null`, `r_exemplars: 0`,
  `r_jobs: 0`. In `note`, say the 3 was measured on 2026-09-30 by reading
  the jobs, and is the count of studies with a `concor_discor` job.
- [ ] Copy the field set and order from a neighbouring qualified row; do not
  invent fields.
- [ ] Run `python3 dev/specs/artifacts/check-roadmap-counts.py`. It will
  fail until Task 2 renames the file. Read the failure and confirm it names
  only the missing `hs-setup.qmd`.

## Task 2: the file and its lint key

- [ ] `git mv inst/templates/40_graphs/hs.qmd inst/templates/40_graphs/hs-setup.qmd`.
- [ ] In the file, update any reference to its own name or to "the `hs`
  template". Leave `hs.rds` as the artifact name: downstream jobs and
  existing studies read it.
- [ ] In `.lintr`, rename the key to
  `"inst/templates/40_graphs/hs-setup.qmd"`. The key must be the FILE.
- [ ] `check-roadmap-counts.py` now passes.

## Task 3: tests

- [ ] `helper-hazard.R`: give `hazard_run()` a `qualifier = NULL` argument
  passed to `template_path()`, as `rf_run()` does. Update the two `"hs"`
  calls in `hazard_chain_run()`.
- [ ] Work through each test file in the measured list. Where a vector of
  template names maps to files, make `hs` resolve to `hs-setup`. Do not
  change what any test asserts.
- [ ] `test-template-catalog.R`: 66 becomes 67. The prefix count stays 44.
- [ ] Add one test: `template_path("hs")` and `add_job("hs", "dead", "x")`
  each error, and the message lists both `setup` and `concordance`.
- [ ] Add one test: `migrate_job()` on a file named `hs.dead.setup.sas`
  with no `qualifier` errors with the choices listed, and succeeds with
  `qualifier = "setup"`.
- [ ] `devtools::test()`. Read the summary line. Review any `_snaps` diff
  line by line; a snapshot that lists templates is expected to change by
  exactly the rename and the new queued row.
- [ ] Sweep for what the list missed:
  `git grep -n -E "hs\.qmd|template_path\(\"hs\"\)|add_job\(\"hs\""`.
  Every remaining hit is either history in `NEWS.md` or `dev/specs/`, or a
  defect.

## Task 4: docs, NEWS, PR

- [ ] `inst/templates/README.md`: the table row becomes
  `40_graphs/hs-setup.qmd`. Add one short paragraph where qualified
  templates are explained: `hs` now needs a qualifier, scaffolded jobs keep
  their names, and migrating a SAS `hs` job needs `qualifier =`.
- [ ] `dev/gallery/index.html`: update only if it names the file.
- [ ] `NEWS.md`, unreleased: the rename, the new error from
  `add_job("hs", ...)` without a qualifier, and that existing jobs are
  unaffected.
- [ ] Full gates, then `/code-review`, then open PR A.

**Checkpoint A.** Report: the test summary line, the check result, and the
list of files changed against the file-structure table.

---

# PR B: the `hs-concordance` template

## Task 5: read before writing

- [ ] Read `hs-setup.qmd` whole. `hs-concordance` reuses its `setup`,
  `guard-edits`, `set`, `read-upstream`, `data` and `cohort` chunks and its
  prediction call. Copy, do not paraphrase.
- [ ] Read `hvtiRtemplates:::.read_handoff` and `.attach_handoff_lineage`.
  Establish what `.read_handoff()` does with the `study_config` it is given
  when the path is in ANOTHER set, and when it is in another study. Write
  the answer into the PR description. If it cannot read outside the job's
  own set, stop and report; the spec's section 5 depends on it.
- [ ] Read the installed help for `predict` on a `hazard` object and
  confirm the arguments `hs-setup` passes.

## Task 6: test fixture first

- [ ] `helper-concordance.R`: a study with a two-level `group` column, and
  an `hm.rds` fitted for each group in its own set. Build it by running the
  `ac`, `hz` and `hm` chunks once per group, as `hazard_chain_run()` does
  for one set.
- [ ] Time it with `system.time()`. Two hazard chains is the likely cost of
  this PR's tests. If it exceeds 30 seconds, fit once per test file, not
  per test.

## Task 7: the template core

Write `inst/templates/40_graphs/hs-concordance.qmd`. Write each test in
`test-hs-concordance.R` before the chunk it covers, and see it fail.

- [ ] Front matter and `format:` block from `hs-setup.qmd`. Opening
  narration: what the job is, that it crosses sets on purpose, and that it
  is the corpus's concordance and discordance job.
- [ ] `edit-study-choices`: `MODELS`, `GROUP`, `HORIZON`, `CARRY`, `OVERLAP`,
  `CROSS_STUDY <- FALSE`, `CROSS_STUDY_TIME_CHECKED <- FALSE`, each with an `EDIT:` marker and a comment saying
  why the choice matters. Spec sections 5, 7 and 12.
- [ ] `models`: read each entry. Guards, each with a test:
  - names of `MODELS` are non-empty and unique;
  - every `GROUP` value observed in the cohort has a model; a model no
    patient carries is reported, not refused;
  - every model's recorded time variable equals `TIME`;
  - two entries resolving to the same file stop the render;
  - an entry that is a path stops the render unless `CROSS_STUDY` and
    `CROSS_STUDY_TIME_CHECKED` are both `TRUE`.
- [ ] `carry`: `CARRY` columns exist and do not name `ID`. Saved one row per
  patient with the actual group, keyed by row number.
- [ ] `overlap`: `OVERLAP` must be one of `"none"`, `"matched"`,
  `"common_support"`. `NULL` stops the render.
- [ ] `covariates`: per-model covariates from each artifact; stop on a
  column the cohort lacks; print the lists side by side with shared ones
  marked.
- [ ] `horizon`: one check per model against that model's last observed
  time. Test: a horizon beyond ONE model's follow-up stops the render and
  the message names that model.
- [ ] `support`: per model, counts of patients outside the fitted range of
  each numeric covariate. Prints, does not stop.
- [ ] `predict`: one call per model on the same frame. Long result: id,
  actual group, model, survival, lower, upper. Same `CLEVEL` and
  `conf.type` as `hs-setup`. Range and `NA` checks as `hs-setup`.
- [ ] `summary`: predicted survival by model within actual group.
- [ ] `save`: `hs-concordance.rds` with the predictions, `HORIZON`,
  `CLEVEL`, per-model covariates, support counts, `OVERLAP`, and the
  lineage of every model read.
- [ ] Test: the saved artifact has one row per patient per model.
- [ ] Test: no patient identifier is saved that `hs-setup` would not save.
  Reuse the check in `test-hazard-chain.R`.

**Checkpoint B1.** The core renders in the fixture. Report the test summary
before writing the decision section.

## Task 8: the optional decision section

- [ ] One chunk, `edit-decision`, with narration saying it can be deleted
  and what it claims when kept. Spec section 9.
- [ ] Eligibility as optional logical columns, applied as `NA` in the
  decision only. Test: an ineligible prediction is unchanged in the saved
  predictions.
- [ ] Best-predicted group after eligibility, classed separated or not by
  the limits. Only a separated choice is optimal. Tests: an exact tie and a
  near-tie inside the limits each yield no optimal group; a separated
  choice yields one.
- [ ] The coverage named in every printed label.
- [ ] Concordance table twice: best-predicted for all patients, optimal for
  the separated ones, with the excluded count stated.
- [ ] Saved under `decision`. Test: deleting the chunk leaves a render that
  passes and an artifact without `decision`.

## Task 9: prove the tests by mutation

- [ ] For each guard test in Tasks 7 and 8, remove the guard from the
  template, run the test, and confirm it goes red. Restore. List the
  guards and the result in the PR description. A guard whose test stays
  green is not covered.

## Task 10: catalog, lint, docs, NEWS, PR

- [ ] `templates.json`: the `hs-concordance` row becomes `shipped`.
- [ ] `.lintr`: a FILE key for `hs-concordance.qmd`, with the same
  per-linter exclusions as `hs-setup.qmd` and no others.
- [ ] Add the template to the name lists in `test-data-contract.R`,
  `test-template-provenance.R` and `test-eda-configuration.R` where
  `hs-setup` appears and the contract applies. Where it does not apply,
  say why in the PR description.
- [ ] `inst/templates/README.md`: the table row, and a short section on
  when to use `hs-setup` and when `hs-concordance`.
- [ ] `NEWS.md`, unreleased.
- [ ] Render the template once end to end in the fixture study with
  `render_job()`, not only chunk by chunk.
- [ ] Full gates, then `/code-review`, then open PR B. After CI runs, read
  the `testthat` summary on every leg:
  `gh run view <run-id> --log | grep -E "SKIP [0-9]+ \| PASS"`.

**Checkpoint B2.** Report: test summary per platform, check result, the
mutation table, and the measured test time added.

---

## Risks

- **`.read_handoff()` may assume the job's own set or study.** Task 5
  settles it before any template code is written.
- **Test time.** Two fitted hazard chains per fixture. Task 6 measures it.
- **The rename reaches tests this plan did not list.** Task 3's sweep is
  the backstop.
- **`migrate_job()` on corpus `hs` jobs** now needs a qualifier. That is
  correct behavior for an ambiguous prefix, and Task 3 pins it with a test
  so it is a documented change, not a surprise.

## Not in this plan

- The display of paired predictions against a covariate (spec section 10).
- A one-model "who benefits" template (spec section 11).
- A version bump. That is the maintainer's, in a separate commit.
