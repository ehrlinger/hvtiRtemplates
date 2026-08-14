# Macro allocation - assigning the SAS macro library to hvtiR* packages

Date: 2026-08-14
Status: approved, pending implementation plan
Evidence: `specs/artifacts/2026-08-14-macro-callsite-scan.md` (+ `.json`, `.py`)

## Problem

The estate-wide map in
`hvtiRutilities:specs/2026-07-10-sas-macro-canonicalization-design.md` (on the
unmerged `spec/sas-macro-canonicalization` branch) decomposes the corpus "along
the `tp.<prefix>` naming convention". That is a **template** convention. Of the
180 files in `~/Documents/macro.library`, **3 carry a prefix**. So templates are
mapped and macros are not, and allocation has been happening one macro at a
time outside any map - `hvtiRlifetables` was scaffolded from `%usmatchd` on
2026-08-13, and `hvtiRtables` ported `%summarytable` on 2026-08-14, neither
under a governing rule.

This spec supplies the missing half: a rule that turns call-site evidence into
macro allocations, one prefix-owner decision, and a generated map.

## Scope

**Decides:** an owner for the `dc` prefix; the allocation rule; the shape and
regeneration of the map.

**Does not decide:** owners for the other unmapped prefixes; the fate of macros
those prefixes block; any code movement. Porting a macro to R remains separate
work with its own spec - this says where a port belongs, not how to do it.

## Evidence basis

The scan resolves three edge types transitively: named `%macro` invocation,
`%inc` of a library file via `filename ref "!MACROS/<file>.sas"`, and
macro-to-macro calls of both kinds. Two properties of the corpus shaped the
rule below:

1. **`%inc` of a file is the dominant edge** - 200 of 229 templates use it and
   never name the macro. A name-only scan reports 223 of 270 macro names dead;
   the real figure is 133.
2. **Transitive reach inflates sharing** - blocks of macros carry identical
   package fingerprints because they are helpers of one widely-called parent
   (`%plot` accounts for 17). They are components, not shared utilities.

The scan is committed with its output so the map regenerates rather than being
trusted.

## Decision 1 - `dc` belongs to `hvtiRtables`

Three independent supports:

- **37 macros reach `dc` and no other prefix**, the largest single-owner block
  in the library.
- **The family is coherent**, not a grab bag: `summarytable`, `stddiffci`,
  `std_dif`, `std_cof`, `var_sdif`, `stdz`, `contab`, `congytab`, `freq_tab`,
  `desc_tab`, `edt1`-`edt4`, `reorder`-`reorder4`, `lrtrend`, `mw_var`.
- **The precedent already exists.** `hvtiRtables` ported `%summarytable` and
  owns the `gtsummary`-consuming rendering half, so the receiving package is
  established rather than invented.

Other unmapped prefixes are deliberately left unowned - see Deferred.

## Decision 2 - the allocation rule

Applied to macro **names** (270 of them across 180 files; a file may define
several).

| Tier | Condition | Destination |
|---|---|---|
| 1 | Direct edge from templates of exactly one owned prefix | that prefix's package |
| 2 | Direct edge from templates of two or more owned prefixes | `hvtiRutilities` |
| 3 | No direct edge; reachable only through another macro | moves with its parent |
| 4 | Not reachable from any template | corpus-only in `hvtiRtemplates` |

**Tier 2 is what "some of the macros belong in hvtiRutilities" means
operationally** - shared is a computed property of the call graph, not a
judgement call.

**Tier 3 exists because tier 2 would otherwise be wrong.** A macro reachable
only through one parent is part of that parent's component and moves with it;
it is not independently shared. Resolution: if every parent allocates to the
same package, the child goes there; if parents split across packages, the child
escalates to tier 2. Worked example: `stddiff`, `stddiffci` and `mw_var` have
no direct template edge and are called by `summarytable`, so they follow it to
`hvtiRtables`. Without tier 3, `%plot`'s 17 internal helpers would each be
classified shared and scattered into `hvtiRutilities`.

**Ties and precedence.** A macro satisfying tier 1 for one prefix and blocked on
another unowned prefix is *blocked*, not allocated - an unowned prefix is
unknown evidence, not absent evidence. This is why 34 macros are held rather
than assigned to the one owner currently visible.

## What this allocates

| Destination | Macros |
|---|---|
| `hvtiRtables` | 35 |
| `hvtiRutilities` (tier 2, shared) | 26 |
| `temporal_hazard` | 8 |
| `hvtiRdatasets` | 4 |
| `hvtiPlotR` | 1 |
| **Allocated now** | **74** |
| Moves with parent (tier 3) | 29 |
| Blocked on a deferred prefix | 34 |
| Corpus-only (tier 4) | 133 |

### `hvtiRtables` (35)

`callfreq`, `cdfs1`, `combo`, `congytab`, `congytab82`, `contab`, `contab82`, `desc_tab`, `edt`, `edt1`, `edt2`, `edt3`, `edt3a`, `edt4`, `freq`, `freq1`, `freq_tab`, `freq_tab82`, `frgy_tab`, `frgy_tab82`, `lrtrend`, `newlist`, `reorder`, `reorder2`, `reorder3`, `reorder4`, `sans`, `std_cof`, `std_dif`, `stdz`, `summarytable`, `trunc`, `tx`, `var_sdif`, `vexist`

### `hvtiRutilities` - shared (26)

`_by`, `_id`, `_label`, `_plot`, `_scan_`, `_uscan_`, `adj_symb`, `axis`, `bld_anno`, `bldano_c`, `bounds`, `bounds1`, `connect`, `decompos`, `dist`, `dummy`, `goption`, `inv`, `kaplan`, `labl_pos`, `nelsonl`, `numobs`, `plot`, `repeat`, `set_size`, `token`

### `temporal_hazard` (8)

`botregwt`, `cifcp`, `cind_haz`, `greenwod`, `hazplot`, `nelsont`, `sample`, `usmatchd`

### `hvtiRdatasets` (4)

`gmatch`, `greedy`, `max1`, `repeatxt`

### `hvtiPlotR` (1)

`lgt_nom`

### Tier 3 - moves with parent (29)

`axisspec`, `bootsens`, `dcom`, `dij`, `doit`, `errm1`, `greedmtch`, `initcc`, `lbls`, `lgrpargs`, `lmakespl`, `lstep8`, `match`, `mknowinout`, `mw_var`, `numargs`, `psplerr`, `pstep8`, `sens`, `sortcc`, `stddiff`, `stddiffci`, `trends`, `varindat`, `vbles`, `vls1`, `vls1i`, `vls1p`, `vmatch`

## Deferred - prefixes without an owner

34 macros are blocked. They concentrate in three prefixes:

| Prefix | Macros blocked | Status |
|---|---|---|
| `bl` | 20 | modeling group, owner undetermined in the canonicalization spec |
| `bn` | 16 | absent from the map entirely |
| `bh` | 12 | modeling group, owner undetermined in the canonicalization spec |
| `br` | 4 | absent from the map entirely |
| `ls` | 4 | absent from the map entirely |
| `bq` | 2 | absent from the map entirely |
| `hm` | 2 | absent from the map entirely |
| `rp` | 1 | absent from the map entirely |
| `vars_base_only` | 1 | absent from the map entirely |
| `mp` | 1 | absent from the map entirely |

What unblocks them is an **owner decision, not more evidence** - the call-site
data for these macros is already complete. `bn` is the notable case: 10
templates carry that prefix and it appears in no version of the map.

Blocked macros: `bnmnr`, `bnmnr_gr`, `bnprev`, `bootqr`, `bootreg`, `break`, `cluster`, `dcom1`, `dcom2`, `expdobsdplot`, `f`, `g`, `getref`, `haz_to_mi`, `hazboot`, `hazbtcp`, `linregm`, `ln`, `logistc`, `logitlasso`, `mi_to_haz`, `mrg`, `mrg0`, `mrg1`, `mrg2`, `mrg3`, `mxpredc`, `ord_ci`, `probest`, `skip`, `skkip`, `stsratiopval`, `ststable`, `sumboot`

## Unreachable macros (133)

Corpus-only. They stay in `hvtiRtemplates` as reference and are allocated
nowhere.

**This is absence of evidence, not evidence of absence.** The scan sees
templates, not the study programs copied from them, and a macro used only by
real studies is indistinguishable here from one used by nobody. The single
thing that would overturn this classification is a scan of actual study
directories; until that is run, no macro should be deleted on the strength of
this list.

## Deliverable

A generated `specs/artifacts/macro_allocation.yaml`, keyed by macro name, each
entry carrying its destination, tier, defining file(s), and the prefixes it was
reached from. Regenerated by extending the committed scan, not hand-edited -
when a prefix gains an owner, the map is re-derived and the diff shows exactly
which macros moved.

Hand-editing the map is the failure mode to avoid: it would make the map and
the evidence disagree silently, which is the same defect class that produced
eight documentation bugs in `hvtiRtables` the week this was written.

## Relationship to the canonicalization spec

This **amends** `2026-07-10-sas-macro-canonicalization-design.md` rather than
replacing it. That spec stays authoritative for templates and for the
`tp.<prefix>` to package map. This one covers macros, the half it never
addressed, and adds one prefix owner (`dc`) to its table.

## Open decisions for the maintainer

1. Owners for `bl`, `bn`, `bh`, `br`, `bq`, `ls`, `rp`, `hm`, and the rest of
   the modeling group. Each is a one-line addition that re-derives the map.
2. Whether to scan study directories to convert the 133 unreachable macros from
   "no evidence" to a real classification. Requires access to study trees and
   raises PHI-adjacent path questions, so it is deliberately out of scope here.
3. Whether `hvtiRtemplates` should re-vendor the corpus. Its README describes
   `inst/corpus` and `inst/macros` as the citable record, but neither is present
   in any branch, so this spec's evidence reads live paths outside version
   control.
