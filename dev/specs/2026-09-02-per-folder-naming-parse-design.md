# Per-folder naming parse

**Status.** Parser fixed upstream and the corpus re-parsed. The batch order
is recomputed and the diff is stated in section 6. What remains is a decision
about `dp` and `dc`, which section 5 sets out but does not take.

**Provenance.** Raised in biostats training, 2026-09-02: "this rule that we
have for templates is not valid". Handoff at
`2026-09-02-per-folder-naming-parse-handoff.md`.

⚠️ No study, variable or patient identifier appears in this note or in any
artifact it produces. The re-parse reads study paths and emits counts.

## 1. The defect

`hvtiRutilities:::.job_name_fields()` matched a legacy name with

```
legacy = "^([A-Za-z0-9_]+)[.].+$"
```

which captures the first dot-field and discards the rest. So `dp.trends`,
`dp.gfup` and `dp.spaghetti.echo` all reduced to a single bucket called `dp`,
and `2026-08-29-roadmap-seed.py` ordered the conversion work by the size of
buckets like that one. A bucket cannot be templated, which is why Batch 3 was
stuck.

The fix is upstream, where the parser lives: `qualifier1`, `qualifiers` and
`n_qualifiers` now carry those fields through, and `job_files()` promises 16
columns rather than 13. Fixing it here instead would have left `job_census()`
regenerating the same defect on its next run.

## 2. What the second field actually contains

The handoff proposed one rule for `analyses` (`<prefix>.<outcome>`) and a
second for the rest (`<prefix>.<refinement>`). Measured over all 2,240,554
catalogue rows, the second rule does not hold, because the second field means
a different thing in each folder:

| folder / prefix | distinct `qualifier1` | what it holds | evidence |
|---|---|---|---|
| `analyses` / `hm` | 587 | an **outcome** | `dead` 262 studies, `st_dead` 32, `reop` 23 |
| `descriptive` / `dc` | 2,330 | a **table type** | `general` 759, `tables` 551, `gfup` 389, `dead` 171 |
| `graphs` / `dp` | 600 | a **plot type** | `trends` 80, `gfup` 48, `spaghetti` 40, `procs` 35 |
| `distributions` / `dp` | 620 | a **clinical variable** | `echo` 52, `afib` 18, `lvmassi` 14, `avmngrad` 11 |

Three different readings, and the fourth is not a refinement of the third.
Calling all of them "refinement" would encode `descriptive`'s reading as
though it were general, which is the same move that produced the `dp` bucket
one level up.

**So the parser does not name the field.** It emits `qualifier1` by position
and stops. Naming is a separate, curated step that dispatches on `folder`,
recorded in this note and reviewable as prose rather than buried in a regex.
That division is the decision of 2026-09-02.

## 3. Corrections to the handoff

The handoff was right that one parser cannot serve every folder. Four of its
supporting claims did not survive measurement, and are corrected here so they
are not carried forward:

1. **The corpus folder is `descriptive`, singular**, and there are seven
   folders, not four: `analyses`, `datasets`, `descriptive`, `distributions`,
   `documents`, `estimates`, `graphs`.
2. **`tp.br.summary` is not the malformed case.** The real ones are
   `br.linear_regression_summary` and `br.linear_regression_bagging`, and
   they are 2 studies each. The whole malformed set is 3 rows (section 4).
   The shape is right and the scale is not: this is a curiosity, not a
   blocker.
3. **`estimates` is the only output folder. `datasets` is not.** `datasets`
   holds 27,231 `.sas` programs that build datasets, and excluding it would
   have repeated this bug with the opposite sign.
4. **Do not fold a fused prefix by string-prefix match.** 21,351 unknown
   first-fields begin with a known prefix, 60,271 rows, and the top hits are
   `hsearch`, `dplyr`, `broom`, `arrow`, `rpart` and `cpp11`. A rule that
   recovers `hzdead` also swallows half of CRAN.

## 4. What counts as a job

The 2026-08-29 census counted every extension and said so in its own caveat.
That means a `.lst`, a `.log`, a `.pdf` and a `.sas7bdat` each counted as
evidence that a study runs a job of that type. The re-parse keeps that figure
as `sas_breadth_all_ext`, reproduces it **exactly for all 42 prefixes**, and
adds `sas_breadth_jobs`, which requires:

- a program extension (`sas`, `R`, `r`, `S`, `qmd`, `Rmd`, `rmd`, `Rnw`,
  `sql`, `py`, `do`);
- a folder other than `estimates`;
- `is_template == FALSE`;
- a placed file, so `study != "NA"`.

The exact reproduction is the point. It says the new numbers differ from the
old only by the change named above, not by a parsing accident. Two filters
were found by that check rather than by reasoning: templates are copied into
nearly every study, so counting them returned a near-uniform ~1,100 studies
for every prefix alike, and unplaced files carry the literal study `"NA"`,
which added exactly one phantom study to 35 of the 42 prefixes.

**`sas_breadth` is a distinct-study count and the buckets must not be summed.**
A study using both `dp.trends` and `dp.gfup` is one study in `dp`, and adding
the two family rows double-counts it. Every figure in the new artifact is a
distinct count within its own scope; `job_studies_in_folder` and
`job_studies_all_folders` are given separately for that reason.

### The malformed set

Reported, never absorbed:

| prefix | qualifier1 | studies |
|---|---|---|
| `br` | `linear_regression_summary` | 2 |
| `br` | `linear_regression_bagging` | 2 |
| `bl` | `bagging` | 1 |

## 5. `dp` and `dc`, which was the point

**`graphs/dp` decomposes and should become several templates.** `trends` (80
studies), `gfup` (48), `spaghetti` (40), `procs` (35), then `histogram` and
`boxplot` at 8 and 9. These are distinct job types sharing a prefix.

**`distributions/dp` does not decompose.** 620 distinct `qualifier1` over 515
studies, roughly 1.2 distinct values per study, and the values are clinical
variables. This is ONE job type parameterised by variable, and it wants one
template with the variable as an `EDIT:` field, not 620 templates.

That distinction is the finding. The same prefix is a family in one folder
and a single parameterised job in another, and only a per-folder reading can
tell them apart.

**`descriptive/dc`** has a templatable core of four, `general` (759 studies),
`tables` (551), `gfup` (389) and `dead` (171), then a long tail. Note
`std_dif` (72) and `stddiff` (59) are the same thing spelled two ways; any
curated vocabulary has to decide which spelling it recognises.

This note does not choose how many templates `dp` and `dc` become. That is a
maintainer decision and it is now answerable from evidence, which it was not
before.

## 6. Batch order

Reordering by `sas_breadth_jobs` moves ten prefixes by three ranks or more:

| prefix | old breadth | new job breadth | rank | status |
|---|---|---|---|---|
| `lp` | 636 | 310 | 6 → 15 | queued |
| `ar` | 706 | 394 | 5 → 10 | queued |
| `bn` | 214 | 108 | 18 → 23 | queued |
| `mp` | 82 | 41 | 26 → 31 | queued |
| `hz` | 581 | 574 | 9 → 5 | shipped |
| `hp` | 557 | 541 | 10 → 6 | revisit |
| `rfs` | 25 | 9 | 35 → 39 | queued |
| `dt` | 512 | 503 | 11 → 8 | queued |
| `bc` | 16 | 16 | 39 → 36 | shipped |
| `nm` | 122 | 121 | 24 → 22 | queued |

The top four are unmoved: `bd`, `dc`, `vars`, `ac`. `lp` is the one that
matters, dropping nine places because more than half its 636 studies were
counted from output rather than from programs. `hz` and `hp` rise because
their jobs are unusually program-dense, not because they grew.

## 7. `hz`, `hm`, and the hand-applied `+396` / `+172`

**Withdraw both.** The handoff asked whether a correct parser finds `hzdead`
(396) and `hmdead` (172) itself. It does, and finding them shows the
correction was wrong:

| stem head | studies | folder | extensions |
|---|---|---|---|
| `hzdead` | 395 | `estimates` | `sas7bdat` 357, `ssd01` 68 |
| `hmdead` | 172 | `estimates` | `sas7bdat` 153, `ssd01` 34 |

These are **result datasets**, not jobs. Adding 396 to `hz` added 396
studies' worth of model output to a count of programs. The measured job
breadth is `hz` 574 and `hm` 373, and those are the figures to use.

## 8. `deade` and `deadl` are resolved

They sit in `estimates`, extension `.sas7bdat` / `.ssd01`, at 169 and 168
studies, and `deadc` sits beside them at 60. Early, late and constant: the
three-phase hazard decomposition, one saved estimate dataset per phase.
`deade ∩ deadl` is 150 studies of 169 and 168, so they are near-always
written as a set.

They were never jobs, and the reason they looked unidentifiable is that a
`.sas7bdat` in `estimates` was being counted as evidence of an analysis.

## 9. The pattern worth naming

This is the third assumption-at-scale failure in a fortnight, after the
two-studies gate and the `hzdead` / `hmdead` fusion. The shape is constant: a
convention inferred from a small sample, applied to the whole corpus, with
the sample size unrecorded.

The handoff named that pattern and then repeated it, proposing "the second
field is a refinement" from the folders someone had looked at. So did this
work, twice, until the numbers were checked: a near-uniform ~1,100 and a
uniform `+1` were both caught by reading the output, not by reading the code.

The countermeasure that actually worked was **reproducing the old number
exactly before trusting the new one**. A re-parse that cannot reproduce what
it replaces is not a correction, it is a second opinion.

## 10. The allocation scan

`artifacts/2026-08-14-macro-allocation-scan.py` was re-run, with two fixes the
handoff called for.

**The glob was one level deep** and missed 13 of the 244 template `.sas`
files: ten under `datasets/templates/transplant_mcs/`, two under
`descriptive/templates/archive/` and one under
`graphs/templates/archive/old_rplots/`. A scan that silently reads 95% of its
input still reports a confident allocation. It is now `**` with
`recursive=True`. The three `archive/` files are included rather than
filtered, because excluding a directory on the strength of its name is the
same move as the glob that hid it; they are visible in the output if anyone
wants them dropped.

**Three destination slugs had been retired.** Verified against
`~/Documents/GitHub` on 2026-09-02:

| was | is |
|---|---|
| `hvtiRdatasets` | `hvtiRdatabuild` |
| `temporal_hazard` | `TemporalHazard` |
| `hvtiPropensityScores` | `hvtiRpropensity` |

Every delta in the regenerated map is accounted for, which is the only reason
to trust it:

- `macro_files` 180 → 176. Four `Copy of *.sas` Finder duplicates were
  deleted from `~/Documents/macro.library` after 2026-08-14. Not this change.
- `templates` 229 → 244. Two were added upstream by `macro.library`
  `6264707`, thirteen by the glob fix.
- `allocated` 93 → 94 and `corpus_only` 78 → 73. One template newly in scope
  allocates one more macro file, to `hvtiRutilities`; the other four leaving
  `corpus_only` are the deleted duplicates.

**Three files changed destination**, and one of them matters:

| file | was | is | why |
|---|---|---|---|
| `xls2sas.sas` | corpus-only | `hvtiRdatabuild` | reached from a `transplant_mcs` template the glob could not see |
| `xls2sas_MA.sas` | corpus-only | `hvtiRdatabuild` | same |
| `stddiff.sas` | `hvtiRdatabuild` | `hvtiRutilities` (shared) | the two `dc` templates under `descriptive/templates/archive/` call it, so it has more than one owning prefix |

`stddiff.sas` is the one to read twice. It was allocated to a single package
only because the glob hid the templates that made it shared. The fix does not
merely widen the map, it corrects it.

## 11. Artifacts

| file | what it is |
|---|---|
| `artifacts/2026-09-02-per-folder-parse.py` | the re-parse, so the numbers regenerate rather than being trusted. Takes the catalogue path as an argument; `--selftest` pins the parse |
| `artifacts/2026-09-02-job-census-summary.json` | counts only. Supersedes `2026-08-29-job-census-summary.json` |

The raw catalogue stays off this repository. Every row is a study path and
`tests/testthat/test-new-job.R` forbids one here.
