# hvtiRtemplates

Versioned analysis job templates for the HVTI CORR group at the Cleveland
Clinic, plus the legacy SAS template corpus and macro library as a reference
specification.

## Install

```r
renv::install("ehrlinger/hvtiRtemplates")
```

## What is here

| Directory | Status | Contents |
|---|---|---|
| `inst/templates/` | **supported** | R job templates. Empty until stage 3. |
| `inst/corpus/` | reference only | 433 legacy SAS and R templates |
| `inst/macros/` | reference only | 496 SAS macro library files, history from 2014 |

The distinction is load-bearing. `inst/templates/` is tested and maintained;
`inst/corpus/` and `inst/macros/` are a citable record of what the R templates
reproduce, and nothing more.

## Why this package exists

Study analyses were created by copying template files into a new study folder
and editing them. Two things followed: improvements stayed in the study where
they were made, and — the problem that actually hurts — a filed result could
not say what produced it. SAS bound its analysis logic with
`%inc kaplan`, resolving at run time against a mutable directory with no
version, so the `.lst` filed in 2006 was produced by a `kaplan` nobody can now
identify.

The design rule is **bind late, to something versioned**. Late binding is right;
SAS could not make it safe because there was no version to pin. `renv.lock`
supplies that, so a study can use the latest while working and pin it on filing.

See `analyses/R_hazard/docs/specs/2026-08-13-templates-and-provenance-design.md`
in the AVR/LV-function survival study for the full design.

## API

| Function | Returns |
|---|---|
| `hvti_taxonomy()` | the analysis prefix table: prefix, name, folder, description |
| `template_list()` | supported templates: name, prefix, folder, file |
| `template_path(name)` | path to one supported template |
| `corpus_manifest()` | every reference-corpus file: file, prefix, folder, kind, bytes |
| `corpus_path(...)` | path to one reference-corpus file |
