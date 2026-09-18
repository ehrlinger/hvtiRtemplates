# Relocating the job catalog from `hvtiR` to `hvtiRtemplates`

**Date:** 2026-09-18
**Status:** Draft, for review. Not approved; not implemented.
**Revisits:** `hvtiR:dev/specs/2026-09-04-job-catalog-design.md` §3 ("Why
`hvtiR`") and §7 ("The consumer coupling"). That design is not wrong in its
reasoning; this note argues that one alternative it never weighed is better
now that two weeks of use have measured the cost.

## 1. What this decides

- Which repository owns `jobs.json`, the job catalog.
- Where each of its validation rules runs.
- The order of the migration, and what it retires.

It changes no row, field or rule of the catalog itself.

## 2. The problem

`hvtiRtemplates` reads the catalog from `hvtiR`, and it does so at a **pinned
tag**: both `R-CMD-check.yaml` and `spec-counts.yaml` check out
`ehrlinger/hvtiR` at `ref: v1.1.13`. That pin is the one edge in the family
where a member depends on `hvtiR` rather than the reverse. Everywhere else,
`hvtiR` records its members' versions (`catalog.csv`, `members()`), and no
member imports `hvtiR`.

The edge makes the dependency graph cyclic, and the cycle has a price paid on
every catalog change. Changing rows that `hvtiRtemplates` owes takes:

1. a catalog pull request in `hvtiR`;
2. an `hvtiR` version bump;
3. an `hvtiR` tag;
4. an `hvtiRtemplates` pull request that moves both pins **and** re-renders the
   roadmap document in the same commit, because either alone turns its CI red.

Measured on the ML rows, 2026-09-17/18: steps 1 to 3 were `hvtiR` #87, #88,
#89 and tag `v1.1.15`, with step 4 still to come. The `pm` removal on
2026-09-13 took the same four steps. Because the pin drifts silently between
steps, two guards exist only to watch it: `hvtiR`'s `jobs-pin-drift` workflow
with `tools/check_jobs_pin.py`, and this repository's
`tools/check_pin_currency.py`.

A second cost is structural. The tarball `R CMD check` builds carries no
catalog, so every catalog-reading test in this repository skips on every check
leg (`SKIP 4`/`SKIP 5`), and a separate strict step exists to run them from the
source tree. `AGENTS.md` records how easily that arrangement hides an untested
gate: the filter decides which paths CI exercises at all.

## 3. What the catalog is, measured

**57 rows** on `hvtiR` `main` at `v1.1.15`.

| destination | rows |
|---|---|
| `hvtiRtemplates` | **47** (82%) |
| `hvtiPlotR` | 4 |
| `ggRandomForests` | 4 |
| `ggBoostedTrees` | 1 |
| `hvtiRpropensity` | 1 |

Readers, from a search of every tracked file in the family (`NEWS.md` and the
built site excluded):

- **In `hvtiR`:** `R/jobs.R` (`jobs()`, exported), the `job-catalog.qmd`
  vignette, `tests/testthat/test-jobs.R` (29 tests) and `test-jobs-routing.R`
  (4 tests), `tools/check_jobs_pin.py` and its test, the `jobs-pin-drift`
  workflow, and the dependency installs in `R-CMD-check.yaml`.
  **`status()` does not read it.**
- **In `hvtiRtemplates`:** `helper-ledger.R`, `test-roadmap.R`,
  `test-taxonomy.R`, `roadmap_render.py`, `check-roadmap-counts.py`,
  `check_pin_currency.py`, two workflows, and two scan scripts.
- **Anywhere else:** no reader. The 2026-09-04 design lists `hvtiPlotR`,
  `hvtiRtables`, `ggRandomForests` and `ggBoostedTrees` as consumers; none of
  them references the catalog. `hvtiRutilities` mentions it only in
  documentation.

The catalog was seeded from a ledger that lived here
(`dev/specs/artifacts/2026-08-29-template-roadmap.json`) and moved to `hvtiR`
on 2026-09-04 (`hvtiR` `e7de800`).

## 4. Why `hvtiR` was chosen, and what it did not weigh

The 2026-09-04 design chose `hvtiR` on **validation**, not storage:

> A routing table that **validates** a destination must load that package to
> read its exports.

Rule 3 checks every `replaced_by` entry against
`getNamespaceExports()` of its package, so the host must install those
packages. The design ruled out `hvtiRutilities` because `hvtiRtemplates` and
`hvtiRdatabuild` import it, so a validator there would have to suggest its own
dependents. That argument is correct, and it stands.

It never assessed `hvtiRtemplates`. Nothing in the family imports
`hvtiRtemplates`, so it can suggest the `replaced_by` packages without
creating a cycle. `replaced_by` names six packages: `ggRandomForests` (20
entries), `hvtiPlotR` (18), `TemporalHazard` (12), `hvtiRutilities` (4),
`hvtiRtables` (4) and `hvtiRpropensity` (2). This repository already imports
`hvtiRutilities` and suggests `hvtiPlotR`, `hvtiRtables` and `TemporalHazard`,
so four of the six are present; only `ggRandomForests` and `hvtiRpropensity`
are missing.

## 5. The proposal

Split the catalog's rules along the line the 2026-09-04 design already drew:
what needs the family roster, and what does not.

| piece | home after the move | why |
|---|---|---|
| `jobs.json` | `hvtiRtemplates`, `inst/extdata/jobs.json` | 82% of rows and every non-`hvtiR` reader are here |
| structural rules (2, 4, 5, 6, 7) and their tests | `hvtiRtemplates` | they read only the catalog, and fail on the pull request that breaks them |
| roster and export rules (1, 3), `test-jobs-routing.R` | **stay in `hvtiR`** | they need `members()`, which is `hvtiR`'s, and `hvtiR` already installs every `replaced_by` package |
| `jobs()` and the `job-catalog` vignette | stay in `hvtiR`, reading `system.file("extdata", "jobs.json", package = "hvtiRtemplates")` | the accessor stays with the family registry; only the data moves |

`hvtiR` gains `hvtiRtemplates` in `Suggests` and `Remotes`. That is the
direction the rest of the family already runs: `hvtiR` depends on a member,
never the reverse.

What this retires:

- both `ehrlinger/hvtiR` checkouts and pins in this repository's workflows;
- `tools/check_pin_currency.py` here, and `jobs-pin-drift` with
  `tools/check_jobs_pin.py` and its test in `hvtiR`;
- the tag-and-pin dance in §2. A catalog change that `hvtiRtemplates` owes
  becomes one pull request here, landing with the templates it describes;
- the `SKIP 4`/`SKIP 5` pattern. With the catalog in `inst/extdata`, it ships
  in the tarball, and the catalog-reading tests run inside `R CMD check` on
  every platform. Whether the separate strict step is then still needed is
  §8 question 3.

## 6. What it costs

- ⚠️ **The coupling reverses rather than disappears.** Today a catalog edit in
  `hvtiR` cannot fail a pull request here, which was the 2026-09-04 design's
  explicit aim. After the move, an edit here that breaks rule 1 or 3 fails
  `hvtiR`'s CI, not this repository's, because those rules run there against
  `hvtiRtemplates` `main`. The structural rules still fail here, on the
  offending pull request. `hvtiR` is the aggregator and sees few pull
  requests, so a red run there is visible and cheap to trace. But a routing
  error would no longer be caught by the pull request that made it. §8
  question 1 asks whether to close that gap.
- **Ten rows owed elsewhere would live here.** They describe corpus job types
  this repository decided not to template. That is defensible, since the
  catalog is the template roadmap's source, but it is a category stretch, and
  `jobs()`'s documentation must say so.
- **The tarball grows** by the size of `jobs.json`, 41 KB of JSON today.
- **A migration across two repositories**, sequenced in §7.

## 7. Migration order

Each step leaves both repositories green.

1. **`hvtiRtemplates`:** add `inst/extdata/jobs.json`, byte-identical to
   `hvtiR` `v1.1.15`. Point `helper-ledger.R` and `roadmap_render.py` at the
   local file first, keeping `HVTI_JOBS` as an override. Move the structural
   tests over from `hvtiR`'s `test-jobs.R`. The pins stay in place, reading a
   now-identical copy.
2. **`hvtiR`:** `jobs()` and the vignette read from `hvtiRtemplates`. Add it to
   `Suggests` and `Remotes`. Delete `hvtiR`'s `jobs.json` and the moved
   structural tests. Keep `test-jobs-routing.R`, now run against the
   `hvtiRtemplates` copy. Retire `jobs-pin-drift` and `check_jobs_pin.py`.
   NEWS entry and a patch bump.
3. **`hvtiRtemplates`:** drop both `hvtiR` checkouts and pins, retire
   `check_pin_currency.py`, and update `AGENTS.md`'s gate table and pin
   guidance. NEWS entry and a patch bump.

⚠️ **Between steps 1 and 2 there are two copies.** That is the failure the
2026-09-04 move existed to escape, so the window must be short and the
`hvtiR` copy frozen. No catalog edits merge in either repository until step 2
lands. Step 1's pull request should assert the two copies are identical,
and that assertion is deleted in step 2.

## 8. Open questions

1. **Should `hvtiRtemplates` also run rule 3 on its own pull requests?** It
   would need to suggest `ggRandomForests` and `hvtiRpropensity`, the two
   `replaced_by` packages it lacks. `ggRandomForests` it will likely need
   anyway, since the `rfs`/`rfc`/`rfr` templates of ML sub-project 2 call it.
   It still could not check rule 1 without `members()`. Running it in both places is duplication. Not
   running it here is the gap in §6.
2. **Does `jobs()` stay exported from `hvtiR`,** or does `hvtiRtemplates`
   export its own accessor, with `hvtiR` re-exporting it? The former changes
   less.
3. **Is the separate strict CI step still needed** once the catalog ships in
   the tarball? It exists because the check legs could not see the catalog.
   If they can, it may be redundant, but that should be measured on a real
   run, not assumed.
4. **Does the 2026-09-04 design get a superseded marker** in `hvtiR`, pointing
   here, once this is approved?

## 9. Out of scope

- The catalog's contents, fields and rules.
- `catalog.csv`, the published-artifact catalog. It is `hvtiR`'s own, records
  its members' versions, and stays where it is.
- `hvti_taxonomy()`, which stays in `hvtiRutilities`.
- Moving the pending pin to `v1.1.15`. That is needed under the current
  layout and should not wait on this decision.
