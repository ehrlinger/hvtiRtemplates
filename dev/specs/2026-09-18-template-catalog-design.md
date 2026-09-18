# The template catalog: every job type is a template here

**Date:** 2026-09-18
**Status:** Draft. The model in §2 was decided by John Ehrlinger on
2026-09-18; the open questions in §9 are not.
**Supersedes, once approved:** `hvtiR:dev/specs/2026-09-04-job-catalog-design.md`,
which moved this catalog to `hvtiR` as a routing table.

## 1. What this decides

- What the catalog is: a catalog of templates, not a routing table.
- Where it lives, what it is called, and which fields and rules survive.
- The order of the migration, and what it retires in `hvtiR`.

## 2. The model

**Every job type in the catalog is a template in `hvtiRtemplates`.** Other
packages appear only in two roles: as functions a template calls, and as the
place a missing function is being built. A hazard plot is a template here that
calls `hvtiPlotR`. A random forest job is a template here that fits with
randomForestSRC and plots with `ggRandomForests`. None of them lives in those
packages.

This is the principle already applied to `rfs`, `rfc` and `rfr` on 2026-09-18
(`hvtiR` #88: "the templates use ggRandomForests; they do not belong in it"),
taken to every row.

## 3. Why the current catalog does not fit it

The 2026-09-04 design framed the catalog as routing "each job type to the
package that owes it", with a `destination` field. Measured on `hvtiR` `main`
at `v1.1.15`, 57 rows:

- **47 rows** have `destination: hvtiRtemplates`, and **24 of them** already
  name other packages in `replaced_by`. For them the model in §2 is already
  true; `replaced_by` just carries it under a misleading name.
- **8 rows** have another `destination` but are `build` rows: `ce`, `cp`,
  `fp`, `gp` (blocked on `hvtiPlotR` #133 to #136), `nb` (`ggBoostedTrees#9`),
  `sid` and `vt` (`hvtiRforests#1`), and `dc-stddiff` (`hvtiRpropensity#34`).
  What is owed elsewhere is a *function*; the template is still owed here.
  `destination` was doing the job `blocked_on` already does.
- **2 rows**, `rf` and `rfsrc`, are the only rows that truly owe no template,
  and that is because they are not job types. `hvti_taxonomy()` demoted them to
  legacy umbrella labels on 2026-09-17.

So `destination` is redundant, `replaced_by` is misnamed, and `retire`
describes two labels rather than any job. The catalog was a template ledger
before 2026-09-04 (`dev/specs/artifacts/2026-08-29-template-roadmap.json`), and
that is what it still is.

## 4. The catalog after this change

**`inst/extdata/templates.json`** in `hvtiRtemplates`: **55 rows, 44
prefixes**, every row a template owed here.

| field | change |
|---|---|
| `destination` | **removed.** Every row's answer was, or becomes, `hvtiRtemplates`. |
| `replaced_by` | **renamed `uses`**: the `package::function` calls a template makes. |
| `blocked_on` | unchanged. For a `build` row it names the function issue, e.g. `hvtiPlotR#133`. |
| `disposition` | `scaffold` (31), `thin` (16) and `build` (8) survive. **`retire` is removed** with the two rows that carried it. |
| `status` | now required on every row. The 8 former off-destination rows take `queued`, since each names a real blocker and has no template on disk. |

`rf` and `rfsrc` are **dropped**. The taxonomy still carries them as legacy
umbrella rows, so a census still resolves the 131 `rfsrc` studies. The
catalog records templates, and no template is owed for either.

## 5. The rules after this change

The 2026-09-04 design's seven rules, restated for the model:

| rule | fate |
|---|---|
| 1. `destination` is a family member | **gone** with `destination`. This was the one rule that needed `hvtiR`'s `members()`. |
| 2. `retire` requires a replacement | **gone** with `retire`. |
| 3. every `replaced_by` entry is an exported function | **kept, as a rule on `uses`**, and it runs here. Every `uses` package must also be declared in this package's `DESCRIPTION`, which replaces `members()` as the authority: a template may call only what the package declares. |
| 4. `scaffold`/`thin` are destined here | **gone**. Every row is. |
| 5. `build` requires a blocker and no replacement | **kept, relaxed.** A `build` row still requires a real `Pkg#N` `blocked_on`. `uses` may now be non-empty, because a template can call existing functions while it waits for a new one. No row does this today. |
| 6. every row has a `disposition` | kept. |
| 7. `status`/`batch` null off-destination | **gone**. Every row has a `status`; `intake` keeps its meaning and its `blocked_on` requirement. |

Rule 3 needs every `uses` package installed. `uses` names six:
`ggRandomForests` (11 entries), `hvtiPlotR` (18), `TemporalHazard` (12),
`hvtiRutilities` (4), `hvtiRtables` (4) and `hvtiRpropensity` (2). This package
already imports or suggests four. **`ggRandomForests` and `hvtiRpropensity`
join `Suggests`**, which the `rfs`/`rfc`/`rfr` templates will need anyway. CI
installs all six, and a skip on this rule is a failure there, as the 2026-09-04
design required.

## 6. What `hvtiR` keeps

**Nothing catalog-related.** It goes back to being the installer and registry.
Retired: `inst/extdata/jobs.json`, `jobs()` and its Rd page, the
`job-catalog.qmd` vignette, `test-jobs.R` and `test-jobs-routing.R`,
`tools/check_jobs_pin.py` and its test, the `jobs-pin-drift` workflow, and the
`replaced_by` installs in `R-CMD-check.yaml`. `catalog.csv`, the
published-artifact catalog, is `hvtiR`'s own and stays.

What that retires in the family:

- the one backward version edge. No member depends on `hvtiR` again;
- the tag-and-pin sequence: a catalog change becomes one pull request here,
  landing with the templates it describes;
- `tools/check_pin_currency.py` here, and both `ehrlinger/hvtiR` checkouts;
- the `SKIP 4`/`SKIP 5` pattern. The catalog ships in the tarball, so the
  catalog-reading tests run inside `R CMD check` on every platform.

## 7. What it costs

- ⚠️ **Dropping `rf`/`rfsrc` trips a guard.** `test-roadmap.R`'s "every
  taxonomy prefix has a roadmap row" would fail, since the taxonomy keeps
  both. The guard needs an exemption for the demoted umbrellas; §9 question 2
  asks how to mark them.
- **Removing an exported function.** `hvtiR::jobs()` is exported. A search of
  every tracked file in the family's repositories on 2026-09-18 found no
  caller outside `hvtiR`; study code outside git was not searched. Removing an
  export is a breaking change, and the version digit is John's.
- **Two catalogs exist briefly.** See §8.
- **The tarball grows** by the catalog, 41 KB of JSON today.

## 8. Migration order

1. **`hvtiRtemplates`, one pull request.** Add `inst/extdata/templates.json`,
   converted from `hvtiR` `v1.1.15`'s `jobs.json` by a script committed beside
   it: drop `rf` and `rfsrc`; drop `destination`; rename `replaced_by` to
   `uses`; set `status: queued` on the 8 former off-destination rows. Carry
   the rules in §5 over as tests here, adapted from `hvtiR`'s. Point
   `helper-ledger.R`, `roadmap_render.py` and the count scripts at the local
   file. Drop both `hvtiR` checkouts and retire `check_pin_currency.py`. Add the
   umbrella exemption, add `ggRandomForests` and `hvtiRpropensity` to
   `Suggests`, re-render the roadmap (47 in scope becomes 55), and update
   `AGENTS.md`. NEWS entry.
2. **`hvtiR`:** retire everything in §6. NEWS entry and a version bump whose
   digit John chooses, since an export goes.
3. **`hvtiRutilities`:** its `hvti_taxonomy()` notes cite `hvtiR::jobs()` and
   the `retire` disposition. Both go stale in step 2; rewrite them to point at
   the template catalog.

⚠️ **Between steps 1 and 2 `hvtiR` still ships `jobs.json`,** a second copy
that nothing here reads any more. That is the drift the 2026-09-04 design
existed to prevent, so keep the window short and **freeze catalog edits in
`hvtiR`** from the moment step 1 merges.

## 9. Open questions

1. **Accessor name, and export or not.** `templates()` would sit beside the
   existing `template_list()`, which lists templates on disk. Two
   similar-sounding exports with different sources invite confusion.
   Alternatives: `template_catalog()`, or keep the reader internal, since
   today only tests and tooling read it.
2. **How are the umbrella prefixes marked for the direction-one guard?** An
   explicit `c("rf", "rfsrc")` in the test is simplest. A machine-readable
   marker in `hvti_taxonomy()` (a new column) would let the guard derive it,
   but it changes that function's output shape for every consumer.
3. **Deprecate `hvtiR::jobs()` first, or remove it in one step?** No caller
   was found, which argues for removal.
4. **Is the strict CI step still needed** once the catalog ships in the
   tarball? That should be measured on a real run, not assumed.
5. **Do older specs get annotated?** The ML roadmap
   (`2026-09-17-ml-family-roadmap-design.md` §2) says `sid`/`vt` catalog rows
   "are repointed to `hvtiRforests`". Under this model there is no
   `destination` to repoint; `blocked_on: hvtiRforests#1` is the whole story.

## 10. Out of scope

- `catalog.csv` in `hvtiR`.
- `hvti_taxonomy()` and its umbrella rows, beyond the marker in §9 question 2.
- The contents of any template.
