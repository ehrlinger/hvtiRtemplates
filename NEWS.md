# hvtiRtemplates 1.0.3

## Breaking changes

- `new_job()` now takes `endpoint` and `type` in place of `basename`, and `dir`
  defaults to the study root rather than `"qmd"`. It writes
  `<folder>/<endpoint>-<type>-<NN.MM>-<prefix>.qmd` — into the taxonomy folder
  the template belongs to, not a flat `qmd/`. The `type` is required because a
  set is keyed on `(endpoint, analysis type)`: one endpoint is analysed by
  several methods and those chains share their upstream, so keyed on the
  endpoint alone two sets would write to one filename.
- `template_path()`'s argument is renamed `name` to `prefix`, which is what it
  always matched on.
- `template_list()` gains an `ordinal` column, and reports `folder` from the
  directory a template sits in rather than by looking its prefix up in
  `hvti_taxonomy()`.

## Improvements

- Templates are named `<NN.MM>-<prefix>.qmd` and live in the taxonomy folder
  they scaffold into. The name is parsed by pattern rather than by splitting on
  dots, which the old `.prefix_of()` heuristic could not do once the ordinal
  contained one.
- The `ac` template declares its set with `ENDPOINT` and `TYPE` markers and
  resolves artifact paths from them, so a scaffolded job needs no output path
  edited by hand. `new_job()` now substitutes the caller's `endpoint`/`type`
  into those declarations after copying the template, so a scaffolded job's
  body agrees with its own filename instead of still naming the template's
  placeholder set. The template itself checks this at render time — comparing
  its `ENDPOINT`/`TYPE` declarations against `knitr::current_input()` — and
  errors if they disagree, because a mismatch resolves `set_path()` into
  another set's artifact directory silently. The check is a no-op outside a
  knitr render, so editing the file interactively in RStudio is unaffected.
- `new_job()` validates `endpoint` and `type`: each must be a single non-`NA`
  string matching `^[A-Za-z0-9_]+$`, since `-` is the filename's field
  separator and `.` is reserved to the ordinal. This also rejects a leading
  `../` that would otherwise escape the taxonomy folder.
- New tests cross-check every template's ordinal against `hvti_taxonomy()` —
  the major against the folder it sits in, and the minors against row order
  within that folder — and assert that no two templates share a prefix, since
  `template_path()` and `new_job()` both resolve with `match()`, which takes
  the first hit silently.

# hvtiRtemplates 1.0.2

## Bug fixes

- `.Rbuildignore` now excludes `.claude` and `.remember`, which hold session
  tooling; `.claude` can also contain a git worktree. Their contents were
  raising two NOTEs — hidden files, and non-portable paths over the tarball
  length limit — neither of which is about the package. `.remember` was
  invisible until `.claude` was excluded, because `R CMD check` reports every
  hidden path in one NOTE.

# hvtiRtemplates 1.0.1

## New features

- `new_job()` scaffolds an analysis job from a supported template, naming the
  file `<prefix>.<basename>.qmd` and refusing to overwrite an existing job.
- `inst/templates/ac.qmd` — the first supported job template, for actuarial
  life tables. It carries its own `format:` block so that a copied job renders
  standalone, resolves the project root itself so no path needs editing, and
  marks every study-specific line `EDIT:`.

  The cohort section offers two shapes, because the choice is not cosmetic:
  a job analysing the whole study uses `assert_cohort()`, while a job
  analysing a filtered subset must supply its own gate — `_study.yml` records
  the study cohort, so `assert_cohort()` would pass while the job ran on a
  cohort nobody checked.

  `hz` and `hp` are deliberately absent: each exists in only one study, and a
  template extracted from a single example encodes that study's choices as
  though they were general.

# hvtiRtemplates 1.0.0

* Initial release.

* `hvti_taxonomy()` encodes the group's analysis-prefix system as data rather
  than as a README, so the test suite checks it against the templates actually
  present instead of letting it drift.

* `template_list()` and `template_path()` resolve a template name to an
  installed file, so a study binds to a versioned template rather than to a
  copy. Both return empty until stage 3 of the templates-and-provenance design
  adds the templates.

* `hvti_non_prefixes()` records the leading name fields that are utilities
  rather than analysis prefixes, which is what lets the test suite tell "not a
  prefix" apart from "a prefix nobody documented".

## Provenance

During development this repository also carried the legacy SAS template corpus
(240 files) and the SAS macro library (495 files, with history imported from
2014) as a reference specification. Both were removed before release, and
every path was purged from every commit with `git filter-repo`. They are not
recoverable from this repository's history.

Parity checks against the SAS originals therefore need a source outside this
repository. The institutional SAS licence expires 2026-09-29.

A result filed before the migration still cannot say which macro version
produced it. That was already true — `%inc` bound late to a mutable directory
with no version — and removing the corpus neither creates nor worsens it.
