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
2026-08-18` banner naming its source path.

**Cross-references between these documents were repointed** to their paths in
this repository, so the set resolves against itself from inside the repo rather
than against a directory layout that is no longer where the documents live.
Nothing else in the text was changed. This table records where each came from.

**Why these are here rather than on the share.** Study folders on the network
share do not host git repositories. That is a constraint on where the *record*
lives, not on reproducibility - the templates-and-provenance design locates
reproducibility in the per-job sidecar and the `renv` lock, neither of which
requires the study directory to be under version control. These documents govern
packages rather than one study, so they live with the package that owns the
migration programme.

| Was at, in the study tree | Now at |
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

**Three references were deliberately left pointing outward.** The directory
diagrams in the two designs draw the *study tree on the share*, where
`docs/specs/` still exists - repointing those would have drawn a layout that has
never existed anywhere, so only the "this document" comment was corrected. The
`(commit 86e5b81)` pin in the `R_hazard` templates plan names a commit in the
study tree's own git, which is not reachable from here and is kept as the
historical record it is.

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

## 2026-08-22  -  job flow diagrams

Three diagrams tracing how a study actually moves through the taxonomy, drawn
from the SAS study template rather than from documentation, plus the two scans
that produced their numbers. They exist to be **argued with**: they are the
briefing biostats reviews before the layout in
`specs/2026-08-21-template-set-layout-design.md` is built out past `ac`.

| File | What it is |
|---|---|
| `2026-08-22-job-set-flow.html` | one endpoint end to end: which job writes what, which reads it back |
| `2026-08-22-two-sets-one-endpoint.html` | why a set is keyed on `(endpoint, type)` and not the endpoint alone |
| `2026-08-22-prefix-map.html` | all 43 taxonomy rows against all three sources that describe them |
| `2026-08-22-job-flow-scan.py` | the estimates read/write scan, so its counts regenerate |
| `2026-08-22-job-flow.json` | the generated graph |
| `2026-08-22-prefix-placement-scan.py` | the prefix-placement scan |
| `2026-08-22-prefix-placement.json` | the generated comparison |
| `check-flow-counts.py` | CI guard: fails when a diagram's numbers disagree with the maps |

**Reproduce:**

```
python3 specs/artifacts/2026-08-22-job-flow-scan.py         > specs/artifacts/2026-08-22-job-flow.json
python3 specs/artifacts/2026-08-22-prefix-placement-scan.py > specs/artifacts/2026-08-22-prefix-placement.json
```

Both read `~/Documents/template` directly, for the same reason the macro scan
above does: this package holds no copy of the SAS corpus.

**The finding is not a count.** Across the 231 SAS job templates, `estimates`
members are written 79 times and read 110 times, and only 13 carry a handoff
between two different jobs. Those numbers describe a corpus of examples drawn
from many studies, so an unmatched read usually means the writer lives in a
study the scan cannot see - it is **not** a defect list, and the diagrams say so
on their face. What the scan establishes is the shape of the coupling: a
writer and a reader are joined by a SAS member name, typed twice, checked
nowhere. `estimates/<endpoint>-<type>/` replaces that with a name neither end
has to type.

**One edge in the flow diagram is in no file.** `hz` fits the hazard shape and
`hm` re-fits with covariates holding that shape fixed - but `hm` does not read
`est.hzdead`. The shaping parameters are transcribed by hand from the `hz`
listing into `hm`'s `fixthalf fixnu fixm` arguments. Re-run `hz` without
re-transcribing and `hm` still converges, still reports covariates, and is
wrong. It is drawn in a different colour because no filesystem scan can find
it, and it is the reason these diagrams are worth a reviewer's hour.

**Four rows are open, and are the point of showing this to biostats.**
`hs` is filed in three different places by the three sources; `rfs` is filed
under `analyses` but its only file is a report in `documents`; `dp` spans three
folders and `ce`, `cd` and `ar` each span two; and the current R study template
writes a *generated* folder into `distributions/`, which the layout rule says
holds authored files only. `new_job()` must pick exactly one folder per prefix,
and picking silently is how the README table drifted in the first place.

**The counts inside the `.html` are a convenience copy of the `.json`, and
CI holds them to it.** That is the same arrangement that drifted three times in
one day above, so it gets the same treatment: every checkable number in a
diagram carries an anchor naming the map key it came from,

```html
<span  data-check="n_jobs">231</span>          in prose
<tspan data-check="n_jobs">231</tspan>         inside an SVG label
```

and `check-flow-counts.py` fails the PR when the two disagree. It also checks
the prefix-map table row by row, since a renamed or dropped row is drift no
count would catch. Adding an anchor needs no change to the checker - every
folder total, prefix total and prefix-in-folder total is already in its
registry, so `data-check="files_ac"` resolves on its own.

**Some numbers are deliberately unanchored.** The masthead of
`two-sets-one-endpoint.html` counts naming conventions and missing checks; those
are readings of the corpus, not scan output, and anchoring them would imply a
derivation that does not exist. `check-flow-counts.py` reports which map keys
are quoted nowhere, so the gap between what is derived and what is asserted
stays visible rather than being assumed.

**The `dead_pa-rfs` chain is proposed, not observed.** Its ordinals
(`04.19-rfs`, `06.14-np`) are the design's. The random-forest templates exist in
`analyses/templates/`, but that chain has never been run as a numbered set.
