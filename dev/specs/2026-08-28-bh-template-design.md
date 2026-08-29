# `04.06-bh` template — design, 2026-08-28

Fourth template from [#8](https://github.com/ehrlinger/hvtiRtemplates/issues/8).
Replaces the SAS `%hazboot` / `%sumboot` / `%cluster` chain: a bootstrap
variable-selection screen whose deliverable is a **selection frequency** — the
percentage of replicates in which a variable was retained, published as a
*Reliability (%)* column.

Depends on **hvtiRbootstrap >= 0.1.1** and **hvtiRutilities >= 1.1.5**. Both
releases exist as of 2026-08-28; before them the helpers this template calls
lived in one study's local `R/`, and templating against them would have produced
a job that stops on arrival anywhere else. That is the `hm` lesson applied
ahead of time rather than after.

## Scope: the report, not the runner

**This template is the report.** It reads what a companion runner wrote, pools
it, and reports over it. It does not run the screen.

That is not a simplification — it is the shape of the job. `hzr_bootstrap()`
writes nothing until its final replicate, and a full screen is days of compute,
so a run that dies near the end leaves nothing at all. The runner exists to
convert one all-or-nothing multi-day call into N independently restartable
ones. **The file boundary is a durability boundary**, not tidiness.

The exemplar is therefore three files, and only the middle one is templated
here:

| file | lines | role | templated |
|---|---|---|---|
| `scripts/bh.example-run.R` | 749 | chunked runner | no |
| `example-jobs/bh.example.qmd` | 581 | the report | **yes** |
| `scripts/bh-progress.sh` | 112 | progress watcher | no |

This follows `04.01-hm.qmd`, which already says selection "is run from a
companion script rather than inline" and reads the saved `.rds`. `hm` set the
precedent; `bh` follows it rather than inventing a second convention.

⚠️ **The cost is stated plainly, because it is real.** The runner encodes every
rule in `dev/TemporalHazard_runbook.md` — seed derived from the chunk number,
refuse-to-overwrite checked both before the work and at save, the pilot cost
paid knowingly — and none of that is templated by this PR. Each study rewrites
it. Templating the runner means teaching `new_job()` multi-file templates,
which is a package change and not this one. **Recorded here so the gap is a
decision on the record rather than an oversight**, and so that whoever picks it
up knows `hm` has the same gap.

## Exemplars — one R, one SAS, and again that is the point

| exemplar | kind | what it contributes |
|---|---|---|
| `lv_function/survival/.../bh.example.qmd` | R, 581 lines | the whole R report: pooling, provenance, completeness, frequencies |
| `preserve_root/analyses/bh.dead_summary.sas` | SAS, 228 lines | `%cluster` — correlation clustering the R exemplar has no equivalent for |

The corpus census counts `bh` in **2** studies as an R job and **322** as SAS.
The gate is met on the R count alone; the SAS exemplar was read anyway, on the
`hm` precedent, and earned its place immediately.

### What the second exemplar added

`bh.dead_summary.sas` calls `%cluster` **sixteen times** — eight named concept
clusters (`Age`, `Size`, `BMI`, `race`, `GFR`, `iv_opyrs`, `Renal`,
`blrbn_pr`), each run twice, once per phase against `bhearly` and `bhconst`.

**The R exemplar has no equivalent.** It groups candidates by *name*, via
`concept_map()`. `%cluster` groups them by *correlation* and attaches a
human-supplied label.

That gap is the same distinction the 2026-08-18 reversal turned on:

> The naming convention tells you two variables are RELATED. Only the data
> tells you whether they are REDUNDANT.
> — `dev/specs/2026-08-19-report-design-learnings.md`

So the R exemplar alone would have shipped the name-based half — the half that
same measurement found insufficient. `hvtiRbootstrap` exports `boot_clusters()`,
the port of `%cluster`, so the data-driven half maps directly.

### The exemplars disagree, and the disagreement is the template

| | `resampl` | `sle` | `sls` |
|---|---|---|---|
| `lv_function` | 500 | 0.07 | 0.05 |
| `preserve_root` | 1000 | 0.12 | 0.1 |

Neither is a default. Extracted from either alone the template would have
shipped one study's criteria as though they were the convention — which is the
`hz` argument, restated: what the exemplars disagree about is exactly what must
carry an `EDIT:` marker.

## ⚠️ Four silent traps this template must carry

Each is here because it produces a **plausible, publishable-looking artifact**
rather than an error. That is the marking rule from `inst/templates/README.md`:
mark what is silent when wrong, not merely what must change.

### 1. Do NOT prune competing transformations before the screen

Screen every form; group only when reading. `hvtiRutilities` exports
`prune_to_one_form()`, so the wrong move is one function call away and looks
like tidying.

Measured, on this study: of the 57 forms pruning removed, **16 correlated
at |r| < 0.9** with the form kept and five below 0.5. `in_zexp` **is**
`1/zexp` (r = 0.9997 against the reciprocal) yet correlates with `zexp` at
only **-0.195**, because `zexp` spans 0.038 to 151.9 — over a 4000-fold
range a value and its reciprocal are different information. The study's
published model uses `zexp` and `in_zexp` **in the same phase, both
significant** (z = 4.00 and 2.76): a two-parameter flexible form that
pruning forbids.

### 2. A screen that selected nothing is a failure, not a finding

It is the signature of the formula-rewrite defect: `hzr_bootstrap()` and
`hzr_stepwise()` rewrite the stored formula per replicate, and a symbol
standing where the formula should be does not survive that rewrite. The refit
errors, the error is caught, the step reports nothing accepted, and the screen
halts having selected nothing — with **no warning and `n_failed = 0`**. The
resulting summary reads as a table of perfectly reliable variables.

**Write the model formula literally at the call site.** Not in a variable, not
via `as.formula()` or `reformulate()`.

### 3. `EXPECT_CHUNKS` and `EXPECT_BOOT` are what you LAUNCHED

Nothing in a chunk knows how many siblings it was launched alongside, so these
two numbers are the only thing that can tell a partial pool from a complete
one. Without them a render at hour eight of a twelve-hour run produces a report
that is **wrong in no visible way**: every health check passes, every frequency
is honestly computed, and only the denominator is not the intended one.

`boot_shortfall()` turns that into a provisional callout, rendered as a callout
rather than a table cell so it survives someone receiving the `.html` without
the context of when it was made.

### 4. `cpu_hours` is summed across chunks, not wall clock

`boot_pool_chunks()` SUMS elapsed across chunks. On a chunked run that figure
is total compute; chunks run in parallel finish in a fraction of it. Reported
in hours because the minutes figure reads as wall clock and is off by the chunk
count.

## `bh` and `hm` are parallel analyses, not a pipeline

The template must state this and must **write no handoff file**.

`%hazboot` and `%model` were parallel analyses in SAS, not a pipeline, and the
R jobs faithfully reproduce that. The study's `bh` report stated that its
retained set is what `hm` fits, and wrote `selection_bh.csv` to make the
handoff explicit. **Nothing reads that file.** A reader who believed the claim
would assume the `hm` model had been screened for reliability first. It has
not.

Recorded in `dev/specs/2026-08-17-job-template-findings.md` as the kind of
claim that survives copying for twenty years, which is the failure mode this
whole design exists to remove.

## Structure

| section | content |
|---|---|
| front matter | own `format:` block, `embed-resources: true` |
| `EDIT:` SAS provenance | the `%hazboot` call pasted verbatim — the call is the specification |
| what a selection frequency is | Monte-Carlo error `sqrt(p(1-p)/n_boot)`; ~2.2pp at p = 0.5 over 500 replicates |
| `setup` | root resolution; load chunks or single `.rds`; hard stop naming the runner |
| `EXPECT_*` | `EDIT:` — what was launched, not what is on disk |
| `completeness` | `boot_shortfall()` to a provisional callout |
| `provenance` | seeds per chunk, criteria, candidate counts listed/usable, cpu-hours, dataset manifest |
| dropped candidates | counts by phase and reason first, detail second |
| frequencies | per-phase reliability table, with per-variable Monte-Carlo error |
| concept grouping | `concept_map()` / `concept_of()`, **at read time only** |
| correlation clusters | `boot_clusters()` — from the SAS exemplar |

**Why counts before detail:** the dropped-candidate table runs to dozens of
rows on a real pool, and a reader who has to scroll it to discover that a whole
*class* of variable was never screened will not discover it.

**Why per-variable Monte-Carlo error:** a variable within a few points of the
retention threshold can fall on either side of it on resampling noise alone.
Agreement on the retention *decision* matters more than agreement on the
frequency, and a near-threshold variable is not a weak risk factor — it is a
variable whose selection is unstable, which is a different claim.

## The ordinal: `04.06`

`analyses` is stage `04`; `bh` sits **sixth** in that folder's taxonomy order
(`hm`, `hs`, `mm`, `gm`, `lm`, `bh`). So `04.06`, not the next-free `04.02`.

This is the positional rule the `hm` design corrected §5 of the layout spec to,
and `bh` is the template that would have broken under the alternative: next-free
gives `bh` = 04.02, and `order(ordinal)` then disagrees with
`order(taxonomy row)` because `hs` precedes `bh` — a red test in
`test-taxonomy.R` whose only fix is renumbering a shipped template, which §5
promises never happens.

## Dependencies

| package | version | used for |
|---|---|---|
| `TemporalHazard` | 1.2.6 | the objects the runner saved |
| `hvtiRbootstrap` | >= 0.1.1 | `boot_pool_chunks()`, `boot_chunk_files()`, `boot_shortfall()`, `boot_summary()`, `boot_clusters()` |
| `hvtiRutilities` | >= 1.1.5 | `concept_map()`, `concept_of()`, `selection_crowding()`, `pool_collinear_pairs()` |

⚠️ **`hvtiRbootstrap` is 0.1.1 — pre-1.0, and its API may still move.** The
template pins a floor, not a ceiling, and this is the first template to depend
on a pre-1.0 package. If it proves unstable the fallback is to inline the
pooling, which is the thing the 2026-08-17 findings explicitly argued against;
prefer bumping the floor.

## Out of scope

- **Running the screen.** Above; the runner is not templated.
- **The progress watcher.** `bh-progress.sh` is operational tooling, not part
  of the report.
- **Parity**, as with `hz`, `hp` and `hm`.
- `hs` follows, and note that the taxonomy's `hs` ("Hazard setup", patient-level
  predictions from the `hm` model) is **not** the `hs` named in #8 ("age, race
  and sex-matched US Life Table survival", needing `%usmatchd`). Two different
  jobs share the prefix. That must be resolved before `hs` is templated, and it
  is not resolved here.

## Verification

As `hz`, `hp` and `hm`: `lintr::lint_package()` clean with the template's own
**file** key in `.lintr` (never a directory key), `devtools::test()`, and a
scaffolded render both unedited — which must halt at `edit-guard` — and with
markers stripped, which must pass it. `devtools::check()` 0/0/0.

Plus, because the template is the first caller of either: `boot_clusters()` and
`boot_shortfall()` exercised against a synthetic pooled object, so the render is
not the only thing standing behind them.
