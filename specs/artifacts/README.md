# specs/artifacts/

Evidence produced to inform a spec, kept beside the corpus it describes.
Excluded from the build via `.Rbuildignore`, so nothing here affects
`R CMD check`.

## 2026-08-14 — macro call-site scan

Which macro-library files are reachable from which `tp.<prefix>` templates, and
therefore which destination package each macro belongs to.

| File | What it is |
|---|---|
| `2026-08-14-macro-callsite-scan.md` | the report: method, counts, validation, per-macro tables |
| `2026-08-14-macro-callsite-evidence.json` | raw `macro -> {packages, files, edge types}` |
| `2026-08-14-macro-callsite-scan.py` | the scan, so the evidence regenerates rather than being trusted |

**Why this exists.** The estate-wide allocation map in
`hvtiRutilities:specs/2026-07-10-sas-macro-canonicalization-design.md` (on the
unmerged `spec/sas-macro-canonicalization` branch) decomposes along the
`tp.<prefix>` naming convention — a *template* convention. Only 3 of the 180
macro-library files carry a prefix, so **templates are mapped and macros are
not**. This scan is the evidence for closing that gap, and nothing in it
decides an allocation.

**Reproduce:**

```
python3 specs/artifacts/2026-08-14-macro-callsite-scan.py
```

It reads `~/Documents/macro.library` and `~/Documents/template/*/templates`
directly. Those paths are the live sources — this package's own `inst/corpus`
and `inst/macros`, described in the README as the citable record, are not
present in any branch as of this date.

**Two things to carry into the spec:**

1. `%inc` of a *file* is the dominant edge (200 of 229 templates), not named
   `%macro` invocation. A name-only scan reports most of the library dead.
2. Transitive reach inflates sharing — blocks of macros carry identical package
   fingerprints because they are helpers of one widely-called parent. Allocate
   on direct edges and move a component as a unit.
