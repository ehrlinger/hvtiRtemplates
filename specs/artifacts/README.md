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

It reads `~/Documents/macro.library` and `~/Documents/template/*/templates`
directly. Those paths are the live sources  -  this package's own `inst/corpus`
and `inst/macros`, described in the README as the citable record, are not
present in any branch as of this date.

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
