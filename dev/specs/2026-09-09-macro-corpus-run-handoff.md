# Handoff — run the macro component emitter against the studies corpus

**Date:** 2026-09-09
**Repo:** hvtiRtemplates
**Status:** emitter merged on [#93](https://github.com/ehrlinger/hvtiRtemplates/pull/93); the library picker it reads through is fixed on [#94](https://github.com/ehrlinger/hvtiRtemplates/pull/94). **No allocation has been produced.** The only run so far is a dry run against `~/Documents/template`, and it labels itself `PROVISIONAL`.
**Origin:** John, 2026-09-09: *"Do I need a similar studies crawl to determine what macros belong in each of the hvtiR packages?"* then *"direct-edge majority, component moves as a unit"*, *"dominator-based"*, and *"I want to know where macros and templates will land … the final catalog is something we're tracking as backlog work as well."*
**Priority:** item 1 below comes **before** the corpus run. It invalidates the input the run reads.

⚠️ No study, variable or patient identifier appears here.

---

## 1. ✅ Done first: the library glob read 176 of 310 files

**Fixed 2026-09-09 on [#94](https://github.com/ehrlinger/hvtiRtemplates/pull/94);
kept here as the finding that led the run.** Both scans now use a shared
denylist picker and read all 310.

`2026-09-09-macro-component-scan.py` and `2026-08-14-macro-allocation-scan.py`
both read `~/Documents/macro.library/*.sas`. That is **176 files** of the top
level's **310 SAS source files** (346 files in all). The directory also holds
**105 extensionless files** and **29 dot-named ones** — `kaplan.int`,
`lm.cprobs`, `plot.compile` — which neither scan had ever opened. Measured
2026-09-09:

| File | Finding |
|---|---|
| `kaplan` | **extensionless only — there is no `kaplan.sas`.** The house survival primitive that 2026-08-14 validated as "4 packages, shared" is reached by both scans only through `kaplan_jr.sas` and `kaplan.int.sas`. |
| `nelsonl` vs `nelsonl.sas` | **differ**, 118 against 174 lines. Not a duplicate. |
| `nelsont` vs `nelsont.sas` | differ, both 210 lines. |

So the extensionless files are not stale copies of their `.sas` siblings, and at
least one macro exists **only** in that form. Every "unreachable" and
"library-only" count either scan has published is a count over a partial
library, and nothing in either output says so.

This is the shape of defect this family keeps shipping: a full, plausible
allocation table over an input that was silently 57% of itself.

**What to do:** decide what the extensionless files are — SAS autocall members,
editor leftovers, or a second generation — then either widen the glob or record
in the script *why* they are excluded. Do not widen it silently: if they are
included, every count in `2026-08-14-macro-allocation.json` moves, and that file
is cited in three design notes.

## 2. Then: the corpus run

The share was **not mounted** on 2026-09-09, which is the only reason this is a
handoff rather than a result.

```sh
mount | grep -i qhs      # the mount name changes across remounts; resolve it
cd dev/specs/artifacts
./2026-09-09-macro-component-scan.py        # resolves the mount itself
```

The script refuses to produce a confident answer over a thin corpus: it aborts
when every component resolves to one destination, and stamps
`allocation_provisional` when the median vote denominator is under three
studies. Read `allocation_trust` in the JSON before quoting anything.

Expect the run to be slow — it opens every `.sas` job in the corpus, and the
census sweep that walks the same tree read 2,240,554 rows. `--limit N` gives a
bounded smoke test first. **A limited run is still provisional** and says so.

## 3. What the dry run established, and what it did not

**Machinery, verified.** Ground truths hold: `summarytable` → hvtiRtables
(confirming the open `dc` gap), `usmatchd` → TemporalHazard, `plot.sas` shared
at a 0.40 majority share.

**Allocation, not established.** Denominator of one study. The
`by_destination` block in a template-corpus run is not an allocation.

Two findings that change what to expect:

1. **`%inc` adds no ROOT edge that a named call does not already add.**
   Measured at the source: 96 call-seeded files, 34 `%inc`-seeded, **inc-only =
   0**. The `--seed` flag is kept because the studies corpus may differ, and
   defaults to `call` on principle — `%inc` is a load, not a use — but it
   changed nothing on the templates.
2. **The library is flat**: 106 macro→macro direct edges over 176 files, and 96
   of ~97 reachable files are called directly. Components come out
   near-singleton (2 multi-member of 95), so *component moves as a unit* is a
   safety net for the few indirectly-reached helpers, **not** a restructuring.
   Anyone reading "dominator-based" as heavy lifting will be disappointed, and
   should be told so before they read the output.

## 4. The catalog is the deliverable, and it answers two questions

`res["catalog"]`, one row per prefix. The two landing questions have **different
authorities** and conflating them is the trap this scan started from:

| Question | Authority |
|---|---|
| where the **template / job** lands | hvtiR `jobs.json` `destination` — who owes the R job |
| where the **macro** lands | this scan — who owns the domain primitive |

`jobs.json` is **not** usable for the second. It reads `hvtiRtemplates` on 42 of
its 55 rows, so voting macro ownership through it sends four fifths of the
library to one package and returns a complete, believable allocation over a vote
that never varied.

Each row carries `n_jobs`, `n_studies`, the macro components the prefix reaches
with each one's destination and tier, `needs_dependency_on`,
`cran_boundary_blocked_on`, `blocked_on_unallocated`, and `backlog_ready`. A row
is workable when the job destination is known and every macro it touches has a
home.

## 5. The finding that will need a decision, not a measurement

Even on the dry run, **five prefixes are CRAN-boundary blocked**: `ac`, `ce`,
`hs`, `hz`, `nd` — all TemporalHazard-owned, all reaching macros that allocate
to `hvtiRutilities`, which a CRAN package **cannot declare as a dependency**
(CRAN requires every dependency to resolve on CRAN/Bioconductor and does not
accept `Remotes:`). The specific macros in the `hz` row are `nelsonl.sas` and
`repeat.sas`.

This is the one place duplication is genuinely forced, and the expected
resolution is to **move the primitive up into TemporalHazard**, not to vendor a
copy into it — a vendored copy carries no version edge and drifts silently. But
that is John's call per macro, and the numbers behind it are provisional until
§1 and §2 are done.

## 6. Carried over deliberately, and not carried over

- **Dropped:** the `FILE_OVERRIDE` block from 2026-08-14 — the five `usmatchd*`
  files routed to hvtiRlifetables as *"replaced, not ported"*. That is a human
  decision the call graph cannot see, so under the new rule they allocate to
  TemporalHazard. Re-add it as an explicit override if the decision should
  survive; it was left out rather than smuggled into a derived result.
- **Kept verbatim:** the SAS reader — `bodies()`, `calls()`, the `INC` regex,
  the per-`%macro` body split. So a difference between the two outputs is a
  difference in the *rule*, never in how a macro body was read.
- **Unresolved and emitted, not decided:** `owner_map_vs_catalog` reports `dc`
  disagreeing — the `OWNER` map says hvtiRtables, the catalog's `replaced_by`
  says hvtiRutilities. That is the still-open `dc` routing gap showing up on a
  second instrument.
