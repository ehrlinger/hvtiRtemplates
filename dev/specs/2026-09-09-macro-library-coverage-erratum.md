# Erratum — every published macro-library count is over 57% of the library

**Date:** 2026-09-09
**Repo:** hvtiRtemplates (the scans), affecting notes in hvtiRutilities too
**Status:** ✅ **picker fixed and the allocation re-run, same day.** Written
while the counts were still held; kept as the record of the defect, with the
measured result folded in below rather than replacing it. Two things remain
open: the call-site artifact cannot be re-run (no script survives), and the
studies-corpus run has not happened.
**Origin:** John, 2026-09-09: *"One directory listing settles what those files
are; until then the corpus run should not start."*
**Blocked:** the corpus run in `2026-09-09-macro-corpus-run-handoff.md` §1 —
now unblocked, and staged to `/studies/general/hvtiRtemplates-scan/`.

⚠️ No study, variable or patient identifier appears here.

---

## The defect

`2026-08-14-macro-allocation-scan.py` and `2026-09-09-macro-component-scan.py`
both select their input with `~/Documents/macro.library/*.sas`. The library's
top level holds 346 files, of which 310 are SAS source and 176 carry that
extension.

| | files | share |
|---|---:|---:|
| `*.sas` — what both scans read | 176 | **56.8%** |
| extensionless — never opened | 105 | 33.9% |
| dot-named, no `.sas` — never opened | 29 | 9.4% |
| **top-level SAS source, total** | **310** | |
| non-source (logs, listings, `.doc`, data sets) | 36 | — |

🔴 **The first version of this note said 281 and 63%, and was wrong the same
way the scans are.** It reached that denominator as "`.sas` plus extensionless",
which still assumes the trailing token after a dot is an extension. It is not:
this library uses dots as word separators, so `kaplan.int` (206 lines),
`lm.cprobs` (218), `plot.compile` (1291), `hazplot.production` (316) and
`gee.uab` (519) are macro source with names, not stems. 18 of those 29 define
macros outright. Correcting an extension assumption while still holding one is
the failure mode this note exists to describe, and it survived one round of it.

**Scope of this erratum: the top level only.** The library also has nine
subdirectories, holding a further 163 source files under the same denylist
rule. Those are **deliberately out of scope** — `archive/`, `tests/`,
`macros_to_test/` and `repeat_test/` are not the library corpus, and pulling
them in would change what "library-only" means rather than correct it. The
denominator is 310, not 473. Both scans now emit the per-directory counts
alongside their totals, so the exclusion is visible in the artifact rather than
implied by its absence.

## What the 105 files are

Directory listing, 2026-09-09. This answers the open question in
`2026-09-09-macro-corpus-run-handoff.md` §1 — *"autocall members, editor
leftovers, or a second generation?"* — as **none of the three**. They are the
card-image generation of the same library, 80-column fixed records from the
CMS/MVS era, sitting beside the filesystem-era `.sas` files rather than beneath
them.

| kind | count | evidence |
|---|---:|---|
| `%MACRO` definitions | 58 | `kaplan`, `cumhaz`, `logit`, `deciles`, `vartest1`–`8`, `clprop*`, `condtga*` |
| `PROC MATRIX` programs | 8 | `sasproc`, `mlephase`, `mlephas1`, `mle86apr`, `mleqtest`, `mletoler`, `nlphases`, `goodfit2` |
| job decks and driver examples | 38 | CMS `SUBMIT * HAZARDEX * *` headers; MVS `//CONSERVE JOB (CVSR,...)` cards |
| empty | 1 | `Ne00` |

The 29 dot-named files are a different population and mostly not card images —
they are variant and platform copies (`gee.uab`, `gee.pc.version`,
`hazplot.pc` vs `hazplot.production`, `rem.original` vs `rem.uab`,
`deciles.new` vs `deciles.joan`). 18 define macros. These are exactly the
divergent-copy pattern the union rule addresses; they are not duplicates to
pick a winner from.

⚠️ **The 8 `PROC MATRIX` files read as binary to `file(1)`** — they are plain
text with no trailing newline, which `file` reports as `RAGE Package Format`. A
picker that screens on `file` type, rather than on extension, would drop these
eight for a second and unrelated reason. Screen on content, not on either.

## They are not stale copies

Only 8 of the 105 have a `.sas` twin at all, and 5 of those 8 differ:

| bare | lines | `.sas` lines | |
|---|---:|---:|---|
| `linregm` | 38 | 99 | differ |
| `logistc` | 38 | 86 | differ |
| `nelsonl` | 118 | 174 | differ |
| `nelsont` | 210 | 210 | differ |
| `plot` | 1400 | 1438 | differ |
| `nelson2`, `nelsonb`, `nelsong` | | | identical |

**97 have no `.sas` counterpart whatsoever.** `kaplan` is the consequential one:
a complete `%MACRO KAPLAN(...)` carrying a 2003-10-17 date stamp, and there is
no `kaplan.sas`. The 2026-08-14 call-site scan validated its own method against
`kaplan` — *"4 packages, shared"* — while unable to open the file it named.

## What this invalidates, and in which direction

The error is **not** one-sided, which is why the counts are held rather than
adjusted.

- **Definitions never seen.** A macro defined only in an extensionless file is
  absent from the definition table, so it cannot be allocated, cannot be
  reported unowned, and does not appear in any total. Silent omission.
- **Callers never seen.** The 38 job decks are *call sites*. A macro whose only
  caller sits in one of them is reported **unreachable** — a false positive, in
  the direction that invites retiring a live macro.

So `unreachable = 133` is inflated by an unknown amount, and `corpus-only = 73`
is wrong in both directions at once. Neither can be repaired by arithmetic.

🔴 **Measured 2026-09-09, after the fix: only ONE of those two directions was
real, and the prediction above is wrong about the other.** The caller-direction
error does not reach the allocation scan, because that scan seeds ownership from
`~/Documents/template` templates only. The 38 missed call sites are *inside* the
library, and an unseeded library file confers no ownership on what it calls. So
no previously-unreachable file became reachable — `corpus-only` grew rather than
shrank. The caller-direction concern still stands for any scan that seeds from
the library itself; it did not apply here, and this note asserted it without
checking.

⚠️ **A second, older discrepancy surfaces alongside this.**
`artifacts/2026-08-14-macro-callsite-scan.md` states its source as
`~/Documents/macro.library` **(180 files)**, while
`2026-08-14-macro-allocation-design.md` totals **176**. Both claim the same
directory and the same day. That gap is unexplained and predates this finding;
resolve it in the same pass rather than carrying two partial-corpus figures
forward.

## The notes that inherit this

Three, all of which publish counts derived from the 176:

| note | inherited counts |
|---|---|
| `hvtiRtemplates/dev/specs/artifacts/2026-08-14-macro-callsite-scan.md` | reachable 137, unreachable 133, macro names 270, "180 files" |
| `hvtiRtemplates/dev/specs/2026-08-14-macro-allocation-design.md` | allocated 94, corpus-only 73, total 176, and every per-package file list |
| `hvtiRutilities/dev/specs/2026-09-08-macro-port-coverage-handoff.md` | 32 of 176 ported, 104 to go, 35 unowned |

Downstream of those, `[[Projects/SAS Macro Port Status]]` in the vault carries
the same 176 denominator, and the biostats deck reports it externally. Neither
is a design note; both need the corrected figures when they exist.

## Measured — the allocation scan re-run, 2026-09-09

Picker replaced with `artifacts/macro_library_files.py` (a port of the shipped
`hvtiRutilities:::.sas_source_files()`; both return 310 on this directory, which
is how the port was checked). `2026-08-14-macro-allocation.json` regenerated.

| | before | after | |
|---|---:|---:|---|
| macro files read | 176 | **310** | +134 |
| macro names defined | 272 | **317** | +45 |
| allocated | 94 | **119** | +25 |
| corpus-only | 73 | **178** | +105 |
| blocked on an unowned prefix | 4 | **8** | +4 |
| travels with a dependent | 5 | 5 | — |

⭐ **Zero pre-existing files changed tier or destination.** All 176 keep the
allocation they had; the 134 new files account for the entire delta
(105 + 25 + 4 = 134). The three ground truths still hold — `summarytable.sas` →
`hvtiRtables`, `usmatchd.sas` → `hvtiRlifetables` by override, `plot.sas`
shared. **The old allocation was not wrong, it was short.** That is the best
available evidence that the `%macro` reader was never the problem and only the
picker was, which is what keeping the reader verbatim was for.

⚠️ **But the headline moves the wrong way, and it should be stated that way to
anyone reading the old figure.** Corpus-only more than doubles: 178 of 310
library files are named by no template, against 73 of 176. As a share that is
57% against 41%. The extensionless generation is almost entirely unreferenced by
the template corpus — which is consistent with it being the older generation,
and is a finding about the templates as much as about the macros. It is **not**
a licence to retire those files: the template corpus is a curated sample, and
the studies corpus is the population. That is what the component emitter reads.

### 🔴 The fix surfaces a package-level dependency cycle

`check-spec-counts.py` fails on the new map, as designed — the design note's
tables are hand-synced copies and are now stale. Most of what it reports is
count drift to be re-synced. **One item is not.**

```
spec calls the dependency graph acyclic; the map reports a cycle at the packages level
```

The file graph stays acyclic. The package graph does not, and the edge that
closes it is new:

| dependent | dependency | edges | |
|---|---|---:|---|
| `TemporalHazard` | `hvtiRutilities` | 44 | was 12 |
| **`hvtiRutilities`** | **`TemporalHazard`** | **8** | **new** |

All eight are the same two calls from four files:

```
deciles.hazard, deciles.hazard.test, deciles.joan, deciles.new   (hvtiRutilities)
        -> chisqgf, chisqgf.exact                                (TemporalHazard)
```

Every one of the six files is in the newly-admitted set, which is why this could
not appear before. The calibration family (`deciles.*`) votes to
`hvtiRutilities` and the goodness-of-fit macros (`chisqgf*`) vote to
`TemporalHazard` on the `hz`/`hs` prefixes, and calibration calls
goodness-of-fit.

⚠️ **`hvtiRutilities` is the package the family depends on; it cannot depend on
`TemporalHazard`.** So one of the two votes has to lose, and which one is a
design decision, not a scan output — either `chisqgf*` is a shared primitive
that belongs in `hvtiRutilities`, or the `deciles.*` calibration family belongs
in `TemporalHazard` beside the fit it calibrates. **Not decided here.** It is
raised because the acyclicity check exists precisely to catch this, it fired,
and a re-sync of the spec's tables would otherwise bury it among sixty lines of
count drift.

## What closes this

1. ✅ **Replace the `*.sas` glob in both scans with a denylist picker.** Done —
   `artifacts/macro_library_files.py`, ported from the shipped
   `hvtiRutilities:::.sas_source_files()`. Both implementations return 310 on
   this directory, which is how the port was checked. The `%macro` reader is
   verbatim; only the picker changed.
2. ✅ **Re-run the allocation scan over 310 files.** Done; the deltas are in
   *Measured* above, per file rather than summarised.
3. 🔴 **Resolve the 180-vs-176 discrepancy.** Not done. The call-site artifact
   that reports 180 has no surviving script, so its figures can only be
   replaced, not re-derived. Its banner now says so.
4. 🔴 **Re-run the `%inc` seeding measurement.** Not done — an `%inc` naming an
   extensionless file could not resolve under a `*.sas` picker, so it
   registered as nothing rather than as unresolved. The picker is fixed, so
   the measurement is now possible; it has not been taken.
5. ✅ **Update the three notes from the new artifacts.** Done, and mechanically:
   `artifacts/render-spec-counts.py` re-renders the design note's tables and
   lists from the JSON, so no count was hand-edited. It deliberately refuses to
   rewrite a *claim* — which is how the acyclicity paragraph came to be
   rewritten by hand instead of silently patched.
6. 🔴 **Then start the corpus run.** Not done, and no longer blocked. Staged to
   `/studies/general/hvtiRtemplates-scan/`: the workstation run was killed at
   24 minutes and 18,000 job files having used 9.9 seconds of CPU, so it is a
   server job.

## The general rule this is the second instance of

Scoping a scan by filename convention measures the convention, not the corpus.
This library uses dots as word separators (`bl_ord.perc.ci.sas`,
`bootstrap.hazard_CP_2evnt.sas`) and its older generation uses no extension at
all, so an extension filter encodes an assumption about file naming that the
corpus never held. The same failure is recorded in
`[[Projects/SAS to R Migration]]` for four separate scans, with the procedure
that prevents it: **before a scan runs, write down its scoping basis and what
that basis would miss — and report the basis beside every number it produces.**
A count with no stated reference set is not a finding.
