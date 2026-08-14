# Changelog

## hvtiRtemplates 1.0.0

- Initial release.

- [`hvti_taxonomy()`](https://ehrlinger.github.io/hvtiRtemplates/reference/hvti_taxonomy.md)
  encodes the group’s analysis-prefix system as data rather than as a
  README, so the test suite checks it against the templates actually
  present instead of letting it drift.

- [`template_list()`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_list.md)
  and
  [`template_path()`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_path.md)
  resolve a template name to an installed file, so a study binds to a
  versioned template rather than to a copy. Both return empty until
  stage 3 of the templates-and-provenance design adds the templates.

- [`hvti_non_prefixes()`](https://ehrlinger.github.io/hvtiRtemplates/reference/hvti_non_prefixes.md)
  records the leading name fields that are utilities rather than
  analysis prefixes, which is what lets the test suite tell “not a
  prefix” apart from “a prefix nobody documented”.

### Provenance

During development this repository also carried the legacy SAS template
corpus (240 files) and the SAS macro library (495 files, with history
imported from 2014) as a reference specification. Both were removed
before release, and every path was purged from every commit with
`git filter-repo`. They are not recoverable from this repository’s
history.

Parity checks against the SAS originals therefore need a source outside
this repository. The institutional SAS licence expires 2026-09-29.

A result filed before the migration still cannot say which macro version
produced it. That was already true — `%inc` bound late to a mutable
directory with no version — and removing the corpus neither creates nor
worsens it.
