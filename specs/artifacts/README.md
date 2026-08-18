# specs/artifacts/

Evidence produced to inform a spec, kept beside the corpus it describes.
Excluded from the build via `.Rbuildignore`, so nothing here affects
`R CMD check`.

## 2026-08-14  -  macro call-site scan

Which macro-library files are reachable from which `tp.<prefix>` templates, and
by which edge type. This is input to the allocation rule; it describes the call
graph and decides nothing.

| File | What it is |
|---|---|
| `2026-08-14-macro-callsite-scan.md` | the original call-graph report: method, counts, edge types |
| `2026-08-14-macro-allocation.json` | the generated map, keyed by file |
| `2026-08-14-macro-allocation-scan.py` | the scan, so the map regenerates rather than being trusted |
| `check-spec-counts.py` | CI guard: fails when the spec's prose disagrees with the map |

**Why this exists.** The estate-wide allocation map in
`hvtiRutilities:specs/2026-07-10-sas-macro-canonicalization-design.md` (on the
unmerged `spec/sas-macro-canonicalization` branch) decomposes along the
`tp.<prefix>` naming convention  -  a *template* convention. Only 3 of the 180
macro-library files carry a prefix, so **templates are mapped and macros are
not**. This scan is the evidence for closing that gap, and nothing in it
decides an allocation.

**Reproduce:**

```
python3 specs/artifacts/2026-08-14-macro-allocation-scan.py
```

It reads `~/Documents/macro.library/*.sas` and
`~/Documents/template/*/templates/*.sas` directly, and must: this package deliberately removed and purged the SAS corpus
before release (see "There is no SAS corpus here" in the top-level README), so
there is no in-repo copy to scan. Those live paths are outside version control,
and the institutional SAS licence expires 2026-09-29.

**Why the scan is file-keyed and body-parsed.** Three corpus properties, each
of which broke an earlier draft:

1. `%inc` of a *file* is the dominant edge (200 of 229 templates), not named
   `%macro` invocation - so a name-only scan reports most of the library dead,
   and an include-driven ownership rule mis-assigns `usmatchd.sas`.
2. 64 of 180 files define more than one macro (`xmacro.sas` defines 63).
   Attributing a file's calls to every macro it defines invents edges and
   inflates sharing.
3. 117 macro names are defined in more than one file, so the name is not a
   stable key.

**The map is authoritative; the spec's tables are a convenience copy.** That copy
drifted three times on 2026-08-14 - a count hand-synced in one place and not
another, caught each time by a reviewer rather than by CI. `check-spec-counts.py`
now makes the agreement mechanical and runs on every PR touching `specs/`
(`.github/workflows/spec-counts.yaml`). It checks the summary table's
per-destination counts, the tier totals and their reconciliation, and every
per-package section's heading count *and* the files it actually lists.

It deliberately does **not** re-run the scan: that needs `~/Documents/macro.library`
and `~/Documents/template`, which are outside version control and absent on a
runner. Regenerating the map stays a local step.

## 2026-08-18  -  lv_function study design record

The design and planning documents for the `lv_function/survival` study, copied
out of the study tree on the network share. Each file carries a `Migrated
2026-08-18` banner naming its source path; **bodies are verbatim**, so their
cross-references still describe the pre-migration layout. This table is what
resolves them.

**Why these are here rather than on the share.** Study folders on the network
share do not host git repositories. That is a constraint on where the *record*
lives, not on reproducibility - the templates-and-provenance design locates
reproducibility in the per-job sidecar and the `renv` lock, neither of which
requires the study directory to be under version control. These documents govern
packages rather than one study, so they live with the package that owns the
migration programme.

| Referenced in a body as | Now at |
|---|---|
| `analyses/R_parity/docs/specs/2026-08-10-avr-lvf-temporalhazard-parity-design.md` | `specs/2026-08-10-avr-lvf-temporalhazard-parity-design.md` |
| `analyses/R_hazard/docs/specs/2026-08-11-r-hazard-job-templates-design.md` | `specs/2026-08-11-r-hazard-job-templates-design.md` |
| `analyses/R_hazard/docs/specs/2026-08-13-templates-and-provenance-design.md` | `specs/2026-08-13-templates-and-provenance-design.md` |
| `analyses/R_parity/docs/plans/2026-08-10-avr-lvf-parity-stages-1-3.md` | `specs/artifacts/2026-08-10-avr-lvf-parity-stages-1-3.md` |
| `analyses/R_hazard/docs/plans/2026-08-12-r-hazard-job-templates.md` | `specs/artifacts/2026-08-12-r-hazard-job-templates.md` |
| `analyses/R_hazard/docs/plans/2026-08-13-hvtirtemplates-repository.md` | `specs/artifacts/2026-08-13-hvtirtemplates-repository.md` |
| `analyses/R_hazard/docs/plans/2026-08-17-hvtirutilities-provenance.md` | `specs/artifacts/2026-08-17-hvtirutilities-provenance.md` |
| `analyses/R_hazard/docs/HANDOFF.md` | `specs/artifacts/2026-08-17-templates-provenance-handoff.md` |
| `analyses/R_hazard/docs/specs/2026-08-13-hvtirlifetables-design.md` | **not migrated** - see below |

**Designs sit at the top level, plans and the handoff sit here.** The three
designs are the standing record of what was decided. The four plans are the
execution record of carrying those decisions out - three of them against *other*
repositories (`hvtiRtemplates` itself, `hvtiRutilities`, and the `R_parity`
tree) - and the handoff is a session note. They support the designs rather than
standing beside them, which is what this directory is for.

`2026-08-13-hvtirtemplates-repository.md` is the plan **this repository was
built from**. It reads as history rather than as work to do.

### `hvtirlifetables-design.md` is deliberately not here

The study tree's copy is a superseded snapshot and says so in its own banner. The
maintained copy is committed at
[`ehrlinger/hvtiRlifetables`](https://github.com/ehrlinger/hvtiRlifetables), under
`docs/specs/2026-08-13-hvtirlifetables-design.md`, and the two have diverged: the
study copy still reads "Design, awaiting review. Not yet built", while the
maintained one records the package as implemented on 2026-08-14, resolves both of
the snapshot's open questions, and adds a correction plus a future-work section.

Copying the snapshot here would have put a third, knowingly-stale copy of a
version-controlled document into a public repository. That design belongs with
`hvtiRlifetables` and ships with it; the pointer is the part that belongs here.

**`hvtiRlifetables` is not an installed package.** The repository exists; the
package is not on the library path. Specs here that assume it - notably the
`hs.*` life-table jobs - are describing a dependency that is not yet satisfiable.
