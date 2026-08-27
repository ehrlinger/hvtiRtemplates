# Making the `EDIT:` convention enforced — design, 2026-08-27

Closes [#27](https://github.com/ehrlinger/hvtiRtemplates/issues/27).

## The problem

`inst/templates/README.md` states that the `EDIT:` markers are "placed so that a
job which still contains one has not been finished." Nothing enforces that.
`R/templates.R` never reads a marker and no test renders a template, so the
property is a convention that the tooling neither checks nor can check.

The `03.01-ac` template makes the gap concrete. Its `derive` chunk indexes a
placeholder column:

```r
d$cat_a[!is.na(d$src_a) & d$src_a < 0.00] <- 3L
```

In a study without `src_a`, `d$src_a` is `NULL`, `!is.na(NULL)` is `logical(0)`,
and **assignment through a zero-length index is a silent no-op in R** — not an
error. Every patient keeps `cat_a = 4L`, the downstream chunks all run against a
single dummy stratum, and the render completes green with 12 unresolved markers
still in the file.

`derived_rows()` one chunk down has the same hole from the other side:
`d[["src_a"]]` on an absent column is `NULL`, so its summary table comes back
with zero rows and renders quietly beside a `derive` table showing every patient
in one category.

This is the shape the study work keeps meeting: **a gate that passes while
wrong**. The irony is that `derive-check`'s own comment anticipates quiet failure
from *mis-ordered* conditions and guards it, but not the case where the source
column is absent and no condition fires at all.

## Two failure modes, two guards

They look identical at runtime — both yield `NULL` — but no single guard catches
both:

| | what happened | marker left? | caught by |
|---|---|---|---|
| **Unedited** | `src_a` never replaced | yes | marker guard |
| **Mis-edited** | replaced with a typo'd or renamed real column | **no** | column assertion |

A marker scan cannot see the second: the author did the edit, so the marker is
gone; the name is just wrong. A column assertion catches the second cleanly but
only fires chunk by chunk, and says nothing about the other ten markers.

Both are therefore in scope.

## 1. The marker guard

A new `edit-guard` chunk between `setup` and `set`. It follows the shape the
`set` chunk's endpoint/type guard already established in this template, rather
than inventing a second idiom.

```r
.cur <- knitr::current_input()
if (!is.null(.cur)) { ...scan and stop... }
```

`current_input()` is `NULL` outside a render — a study author stepping through
chunks in RStudio — and there is no file to scan then, so that case is a no-op
exactly as it is in the `set` chunk.

### ⚠️ The guard must not match its own source

**Measured, not assumed.** `current_input()` returns Quarto's `.rmarkdown`
intermediate, and a probe render confirms both marker forms survive into it: an
HTML-comment marker and an in-chunk `#` comment marker are both found. So the
scan reaches all 12.

But the intermediate includes **the guard's own chunk**. A guard written the
obvious way —

```r
hits <- grep("EDIT:", src, fixed = TRUE)     # WRONG: matches this very line
```

— matches itself and fires on every render, finished or not. The probe found
**3 markers in a file containing 2**. The token is therefore constructed rather
than written literally:

```r
.tok <- paste0("ED", "IT", ":")
```

with a comment saying why, because the trap is invisible and the obvious edit
re-introduces it. Note the failure direction: a self-matching guard makes a
*finished* template unrenderable, which is loud. That is better than the silent
pass it replaces, but it is still broken, and a template that cries wolf on
every render is a template whose guard gets deleted.

### What it reports

Marker **text**, not just line numbers. The numbers come from the intermediate,
not the `.qmd`, so a reported line may not match what the author sees in their
editor. The text is unambiguous; the number is a hint.

## 2. The drafting escape

`HVTI_TEMPLATE_DRAFT=1` downgrades the stop to a warning **and emits a visible
banner into the rendered document**.

An escape is needed: an author wants to render after the cohort chunk to check
it works, before the derive chunk exists. Without one they cannot, and the guard
becomes something to route around.

Two properties matter:

- **Environment variable, not a YAML param.** A param lives in the file, so it
  gets committed and forgotten — re-opening the exact hole being closed. The
  variable is per-invocation and leaves no trace in the job.
- **The banner is not optional.** A draft render that looks like a finished one
  is #27 again with an extra step. The warning alone is insufficient: warnings
  scroll past, and the rendered `.html` is the artifact that gets sent on.

## 3. Column assertions

`derive_cats()` asserts its source columns exist before deriving, naming the
missing ones and saying the chunk needs editing.

`derived_rows()` asserts every value of `DERIVED` is a column of `d`, and every
name of `DERIVED` is a column after derivation. The second half catches a
`DERIVED` entry that was never derived — a `derive_cats()` edited without
`DERIVED` being updated to match.

## 4. Tests

testthat cannot render a template. It can check the shipped source, which is
what actually needs protecting:

1. **Every template carries an `edit-guard` chunk.** A future template cannot
   ship without one. This recovers most of what extracting the guard into
   `hvtiRutilities` would have bought, without making every scaffolded job
   depend on a package it does not currently load. (Jobs load `TemporalHazard`
   and `hvtiRutilities`; `hvtiRtemplates` is scaffolding, not a runtime
   dependency.)
2. **The guard's token is split.** A regression test for the self-match trap.
   This is the test most likely to look pointless later and most likely to be
   load-bearing.

## 5. Verification

Tests on the source are not evidence the guard fires. #27 was found by an
unedited render *succeeding*, so the fix is proven by rendering:

1. Scaffold a minimal study — `_quarto.yml`, an `R/` directory, enough for the
   `setup` chunk to resolve — and render the unedited template. **Must fail**,
   naming the markers.
2. Render again with the markers stripped. **Must get past the guard** — the
   run may then fail later for want of real data, which is fine and expected;
   what matters is that it is no longer the guard stopping it.

Step 2 is the half that would be easy to skip and is the one that catches the
self-match trap.

## 6. README

State the property as enforced rather than conventional, and document
`HVTI_TEMPLATE_DRAFT`.

## Out of scope

The issue's closing suggestion of sweeping all 474 lines for every
`!is.na(d$<placeholder>)` pattern. The two sites named above are the ones that
index a placeholder column; the remaining markers are prose, output paths and
cutpoint values, which fail visibly or not at all. If a third site appears, the
sweep can be revisited with two exemplars in hand rather than one.
