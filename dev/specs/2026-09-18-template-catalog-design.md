# The template catalog: every job type is a template here

**Date:** 2026-09-18
**Status:** Draft for approval. The model in §2 and four of the five questions
in §9 were decided by John Ehrlinger on 2026-09-18; §9 question 4 stays open.
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
before 2026-09-04 (`dev/specs/artifacts/2026-08-29-template-roadmap.json`,
deleted in `5f224cc` when the catalog moved and recoverable from git history),
and that is what it still is.

## 4. The catalog after this change

**`inst/extdata/templates.json`** in `hvtiRtemplates`: **55 rows, 44
prefixes**, every row a template owed here. It is read by a new exported
accessor, **`template_catalog()`**, named to sit clearly apart from
`template_list()`, which lists the templates on disk rather than the catalog.

Its contract mirrors `hvtiR::jobs()`, so no caller has to relearn it:

- **Returns** a data frame, one row per template row. `uses`, `upstream`,
  `downstream` and `workflows` are list-columns, since each holds an array.
- **Errors** name the row and the field when a scalar field holds more than one
  value or a count field holds something other than an integer, as
  `jobs()` does today.
- **A missing or unreadable file is an error, not an empty result.** The
  catalog ships inside the package, so its absence is a packaging defect and
  must not read as "no templates".

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
join both `Suggests` and `Remotes`**: `Remotes` because CRAN's
`ggRandomForests` is 3.5.3 while `main` is 4.0.0, and `hvtiRpropensity` is not
on CRAN. `ggRandomForests` is also what the `rfs`/`rfc`/`rfr` templates call;
`hvtiRpropensity` is there for the two `uses` entries on existing rows, and
`dc-stddiff` is blocked on it. CI installs every `uses` package, and a skip
on this rule is a failure there, as the 2026-09-04 design required.

⚠️ **`uses` must list every direct call, not only the plotting layer.** Today
it lists the six packages above because it was inherited from
`replaced_by`, which only ever recorded replacements. A template that fits a
forest calls `randomForestSRC::rfsrc()` directly, so ML sub-project 2 adds
that entry to `uses` and `randomForestSRC` to `Suggests` when it writes the
`rfs`/`rfc`/`rfr` templates. Rule 3 then holds it to the same test as any
other call.

## 6. What `hvtiR` keeps

**Nothing of the job catalog.** It goes back to being the installer and
registry.
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
  both. Decided: the guard **derives** its exemption from a new column in
  `hvti_taxonomy()` (§8 step 0), rather than hard-coding two prefixes.
- **`hvti_taxonomy()` changes shape.** The new column changes an exported
  function's output. Measured: the only test anywhere that asserts its exact
  column set is `hvtiRutilities`' own shape test, so the change stays inside
  the repository that makes it. **Minor bump, `hvtiRutilities` 1.3.0** (John).
- **Removing an exported function.** `hvtiR::jobs()` is removed **in one
  step**, without a deprecation cycle (John: no one uses it yet). A search of
  every tracked file in the family's repositories on 2026-09-18 found no
  caller outside `hvtiR`; study code outside git was not searched. **Minor
  bump, `hvtiR` 1.2.0** (John).
- **Two catalogs exist briefly.** See §8.
- **The tarball grows** by the catalog, 41 KB of JSON today.

## 8. Migration order

0. **Prerequisites, in either order.**
   - **`hvtiR`: a freeze guard.** A test that fails if
     `inst/extdata/jobs.json` differs from its `v1.1.15` content by checksum.
     It turns the freeze in the ⚠️ note below from a convention into a check,
     and step 2 deletes it along with the file.
   - **`hvtiRutilities`: the `umbrella` column.** Add a logical column
     **`umbrella`** to `hvti_taxonomy()`, `TRUE` for `rf` and `rfsrc` and
     `FALSE` elsewhere (`NA` for the `estimates` artifact row, which has no
     prefix). Update the shape test and the roxygen, which today records the
     demotion only in the rows' wording. Release it as **1.3.0**: a minor
     bump, John's decision (2026-09-18), since an exported function's output
     changes.
1. **`hvtiRtemplates`, one pull request.** Add `inst/extdata/templates.json`,
   converted from `hvtiR` `v1.1.15`'s `jobs.json` by a script committed beside
   it: drop `rf` and `rfsrc`; drop `destination`; rename `replaced_by` to
   `uses`; set `status: queued` on the 8 former off-destination rows. Carry
   the rules in §5 over as tests here, adapted from `hvtiR`'s. Point
   `helper-ledger.R`, `roadmap_render.py` and the count scripts at the local
   file, **and migrate them to the new schema**, since a path change alone
   leaves them reading the old one: `check-roadmap-counts.py`'s required
   `FIELDS` drop `destination` and rename `replaced_by` to `uses`;
   `roadmap_render.py` drops its `destination` filter and routing labels; the
   generated roadmap's preamble and the tests' prose stop saying the catalog
   lives in `hvtiR`. Add `template_catalog()` and run `devtools::document()`,
   committing the generated `man/` and `NAMESPACE`, which the `docs-current`
   check requires. Drop both `hvtiR` checkouts and retire `check_pin_currency.py`.
   Exempt `hvti_taxonomy()$umbrella` rows from the direction-one guard and
   raise the `hvtiRutilities` floor to the release from step 0. Add `ggRandomForests` and `hvtiRpropensity` to
   `Suggests`, re-render the roadmap (47 in scope becomes 55), and update
   `AGENTS.md`. NEWS entry.
2. **`hvtiR`:** retire everything in §6, and mark
   `dev/specs/2026-09-04-job-catalog-design.md` superseded, pointing here.
   NEWS entry and a **minor** bump to **1.2.0** (John, 2026-09-18), since an
   export goes. Delete step 0's freeze guard with the file.
3. **`hvtiRutilities`:** its `hvti_taxonomy()` notes cite `hvtiR::jobs()` and
   the `retire` disposition. Both go stale in step 2; rewrite them to point at
   the template catalog.

⚠️ **Between steps 1 and 2 `hvtiR` still ships `jobs.json`,** a second copy
that nothing here reads any more. That is the drift the 2026-09-04 design
existed to prevent, so keep the window short. The freeze is **enforced, not
asked for**: step 0's guard fails any edit to `hvtiR`'s `jobs.json` until step
2 removes it.

## 9. Questions

**Decided by John, 2026-09-18:**

1. **Accessor:** `template_catalog()`, exported. Not `templates()`, which would
   sit beside `template_list()` with a different source.
2. **Umbrella marker:** a machine-readable `umbrella` column in
   `hvti_taxonomy()`, accepting the change to its output shape (§7, §8 step 0).
3. **`hvtiR::jobs()`:** removed in one step, no deprecation cycle.
5. **Older specs are annotated.** The ML roadmap
   (`2026-09-17-ml-family-roadmap-design.md` §2) said the `sid`/`vt` catalog
   rows "are repointed to `hvtiRforests`". Under this model there is no
   `destination` to repoint, and `blocked_on: hvtiRforests#1` is the whole
   story. That spec carries a dated note saying so, and so does
   `2026-09-16-standardized-difference-design.md`, which names `hvtiR`'s
   `jobs.json` and its `destination`/`replaced_by` as the source of truth for
   the `dc-stddiff` row. The 2026-09-04 design in
   `hvtiR` gets a superseded marker in §8 step 2.

**Open:**

4. **Is the separate strict CI step still needed** once the catalog ships in
   the tarball? It exists because the check legs could not see the catalog.
   Measure it on step 1's first CI run: if every check leg then reads
   `SKIP 0` for the catalog-reading tests, the step is redundant. Keep it
   until that run says so.

## 10. Out of scope

- `catalog.csv` in `hvtiR`.
- `hvti_taxonomy()` and its umbrella rows, beyond the marker in §9 question 2.
- The contents of any template.
