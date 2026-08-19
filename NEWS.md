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

Version: 1.0.0

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
