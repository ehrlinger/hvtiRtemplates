# hvtiRtemplates

Versioned analysis job templates for the HVTI CORR group at the
Cleveland Clinic.

## Install

``` r

renv::install("ehrlinger/hvtiRtemplates")
```

## What is here

| Directory | Status | Contents |
|----|----|----|
| `inst/templates/` | **supported** | R job templates. See `inst/templates/README.md` for coverage. |

Everything the package installs is supported: tested, maintained, and
intended to be run. There is no reference-only material.

## There is no SAS corpus here

During development this repository also carried the legacy SAS template
corpus (240 files) and the SAS macro library (495 files, with history
imported from 2014) as a reference specification. Both were removed
before release, and every path was purged from every commit with
`git filter-repo` — they are not recoverable from this repository’s
history by design.

Two consequences worth stating plainly. Parity work against the SAS
originals needs a source outside this repository; the institutional SAS
licence runs into 2027, so plan accordingly (`2027-09-29` is the working
date, not yet confirmed). And a result filed before the migration still
cannot say what produced it — that was already true, because `%inc`
bound late to a mutable directory with no version, and removing the
corpus neither creates nor worsens that gap.

## Why this package exists

Study analyses were created by copying template files into a new study
folder and editing them. Two things followed: improvements stayed in the
study where they were made, and — the problem that actually hurts — a
filed result could not say what produced it. SAS bound its analysis
logic with `%inc kaplan`, resolving at run time against a mutable
directory with no version, so the `.lst` filed in 2006 was produced by a
`kaplan` nobody can now identify.

The design rule is **bind late, to something versioned**. Late binding
is right; SAS could not make it safe because there was no version to
pin. `renv.lock` supplies that, so a study can use the latest while
working and pin it on filing.

In practice a study declares `hvtiRtemplates` in its `renv.lock`,
resolves a template through `template_path("ac")` instead of copying one
into the study folder, and pins the version when results are filed. The
lock file is then the answer to “what produced this?” — the question the
SAS arrangement could not answer, because `%inc` had nothing to pin.

## API

| Function | Returns |
|----|----|
| [`hvti_taxonomy()`](https://ehrlinger.github.io/hvtiRutilities/reference/hvti_taxonomy.html) | the analysis prefix table: prefix, name, folder, description |
| [`template_list()`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_list.md) | supported templates: name, prefix, qualifier, ordinal, folder, file |
| `template_path(prefix, qualifier = NULL)` | path to one supported template |
| [`hvti_non_prefixes()`](https://ehrlinger.github.io/hvtiRutilities/reference/hvti_non_prefixes.html) | leading name fields that are utilities, not analysis prefixes |
| `new_job(prefix, endpoint, type, dir = ".", qualifier = NULL)` | the scaffolded job’s path, invisibly |

`qualifier` names a job type within a prefix, for the prefixes that
carry several: `graphs/dp` is `trends`, `spaghetti` and `procs`, not one
job. It is `NULL` and the column is `NA` for a prefix with a single
template, which is every template shipped today. Naming no qualifier
where a prefix carries several is an error listing the choices, never a
silent pick of the first.
