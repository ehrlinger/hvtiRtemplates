* Requires `hvtiRutilities` 1.5.10 or later, the first release whose taxonomy names the `vp` prefix of the `vp-fit`
  and `vp-explain` templates. With 1.5.8 or 1.5.9 the templates still listed and scaffolded, since the template
  catalog places them, but `hvti_taxonomy()`, which this package re-exports, did not know `vp`, so the package's
  taxonomy disagreed with its own templates.
