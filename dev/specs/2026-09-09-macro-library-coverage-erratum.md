# Erratum — every published macro-library count is over 63% of the library

**Date:** 2026-09-09
**Repo:** hvtiRtemplates (the scans), affecting notes in hvtiRutilities too
**Status:** 🔴 **counts held, not corrected.** The correct numbers do not exist
yet — they need the picker fixed and both scans re-run. This note records what
is wrong, how wrong, and which notes inherit it.
**Origin:** John, 2026-09-09: *"One directory listing settles what those files
are; until then the corpus run should not start."*
**Blocks:** the corpus run in `2026-09-09-macro-corpus-run-handoff.md` §1.

⚠️ No study, variable or patient identifier appears here.

---

## The defect

`2026-08-14-macro-allocation-scan.py` and `2026-09-09-macro-component-scan.py`
both select their input with `~/Documents/macro.library/*.sas`. The library's
top level holds 281 files, of which 176 carry that extension.

| | files | share |
|---|---:|---:|
| `*.sas` — what both scans read | 176 | **62.6%** |
| extensionless — never opened | 105 | 37.4% |
| **top level, total** | **281** | |

**Scope of this erratum: the top level only.** The library also has nine
subdirectories holding a further 79 `.sas` files. Those are **deliberately out
of scope** — `archive/`, `tests/`, `macros_to_test/` and `repeat_test/` are not
the library corpus, and pulling them in would change what "library-only" means
rather than correct it. The denominator is 281, not 360.

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

## What closes this

1. Replace the `*.sas` glob in both scans with a **denylist** picker — the rule
   `hvtiRutilities::sas_triage()` already ships, added 2026-08-14 for this exact
   failure. Keep the `%macro` reader verbatim; only the picker changes.
2. Re-run both scans over 281 files. Diff against the 176-file output and paste
   the difference rather than summarising it.
3. Resolve the 180-vs-176 discrepancy above.
4. Re-run the `%inc` seeding measurement, which is uninterpretable on the
   partial corpus — an `%inc` naming an extensionless file cannot resolve under
   a `*.sas` picker, so it registers as nothing rather than as unresolved.
5. Update the three notes above from the new artifacts. Do not hand-edit a
   count; re-sync from the JSON, per the rule already in
   `2026-08-14-macro-allocation-design.md`.
6. Only then start the corpus run.

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
