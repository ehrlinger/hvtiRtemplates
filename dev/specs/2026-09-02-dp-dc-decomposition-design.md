# Decomposing `dp` and `dc`

**Status.** Evidence complete, **decision open**. Nothing in the ledger has been
changed. Sections 2 to 7 are measurement; section 8 states the choice that has
to be made and section 9 recommends, but the count of templates and the
identity scheme are the maintainer's call.

**Why now.** `2026-09-02-per-folder-naming-parse-design.md` established that
`dp` and `dc` are not single job types. This note asks what they actually
decompose into, and hits a constraint the ledger has never had to face.

⚠️ **No STUDY path, study name or patient identifier** appears here. The one
path named is `~/Documents/template`, the template corpus on the maintainer's
machine, which holds no study data. The distinction is the point: a catalogue
row is a study path and must not land in a public repository, while a template
directory may.

⚠️ **Clinical variable names DO appear** (`afib`, `echo`, `rv_index`, `tvrg`,
`POAF`), because template filenames carry them and the filenames are the
evidence here. They are shared clinical vocabulary, not study-specific.

## 1. Two facts that make this cheap to decide now

**Neither `dp` nor `dc` has an ordinal.** Both are `null` in
`artifacts/2026-08-29-template-roadmap.json`. An ordinal is assigned once and a
retired one is never reissued, so deciding the shape before either ships costs
nothing. Deciding after `dp` ships as one template costs a retirement, which is
what `04.06-bh` already cost once.

**The ledger allows one row per prefix.** `check-roadmap-counts.py` fails a
duplicate, and each row carries exactly one `folder` and one `ordinal`. That
constraint is what the evidence below collides with.

## 2. What the corpus counts say

Job studies per folder, from `artifacts/2026-09-02-job-census-summary.json`.
These are distinct-study counts and **do not partition**: a study runs several
qualifiers, so they do not sum to the folder total.

| `descriptive/dc` (1,002 studies) | | `graphs/dp` (320) | | `distributions/dp` (237) | |
|---|---|---|---|---|---|
| `general` | 759 (75.7%) | `trends` | 80 (25.0%) | `echo` | 52 (21.9%) |
| `tables` | 551 (55.0%) | `gfup` | 48 (15.0%) | `afib` | 18 (7.6%) |
| `gfup` | 389 (38.8%) | `spaghetti` | 40 (12.5%) | `lvmassi` | 14 (5.9%) |
| `dead` | 171 (17.1%) | `procs` | 35 (10.9%) | `avmngrad` | 11 (4.6%) |
| `std_dif` | 72 (7.2%) | *cliff* | | `mv_regn` | 9 (3.8%) |
| `stddiff` | 59 (5.9%) | `boxplot` | 9 (2.8%) | `pain_score` | 9 (3.8%) |

Three different shapes. `dc` has a head so large it is nearly universal.
`graphs/dp` has a head of four then a cliff to 3%. `distributions/dp` has no
head at all: 620 distinct values over 237 studies, and they are variables.

## 3. The template corpus already answers most of it

`~/Documents/template` carries live templates for these prefixes:

| folder | prefix | live | `tp_ggplot/` | `archive/` |
|---|---|---|---|---|
| `descriptive` | `dc` | 21 | 0 | 2 |
| `descriptive` | `dp` | 6 | 0 | 7 |
| `distributions` | `dp` | 3 | 0 | 0 |
| `graphs` | `dp` | 15 | 7 | 10 |

**The split is not a proposal. It is current practice.** `graphs/dp` alone ships
`trends`, `spaghetti`, `histogram`, `boxplot`, `bubbleplot`, `procs`,
`relative-distribution`, `matrix_plot`, `scatter_matrix` and three sankeys as
separate files. Deciding to decompose `dp` ratifies what the corpus does; the
open question is only how the RESULT is named and recorded here.

## 4. `dc.general` and `dc.tables` are different work

This was the question the counts could not answer. The macro dependency answers
it.

| template | what it does | dependency |
|---|---|---|
| `tp.dc.general.sas` | `proc contents`, `proc means`, `proc freq`. Raw and unformatted | **base procs only**, no package |
| `tp.dc.tables.ods.sas` | `%desc_tab(vartype=category, input=built, varlist=...)`, rendered through ODS | `desc_tab.sas`, allocated to **`hvtiRtables`** |

They read the same `built` dataset, apply the same `%vars` transformation and
even carry the same `title3`. One is "look at the data" and the other is
"produce the table for the manuscript", and they resolve to **different
destination packages**. Two templates, not one with a format switch.

## 5. `std_dif` and `stddiff` are two generations, not two spellings

⚠️ **This corrects a reading given earlier the same day**, that they are one
thing spelled two ways and the template should simply pick a spelling. They are
different macros with different capability and different owners:

| macro | size and provenance | owner |
|---|---|---|
| `std_dif.sas` | 108 lines, Rajeswaran, 2009. Emits a dataset of standardized differences | `hvtiRtables` |
| `stddiff.sas` | 649 lines, Artis 2019, from Dongsheng Yang's 2012 macro. Handles continuous, ordinal AND categorical, and integrates `%summarytable` | `hvtiRutilities` |

The corpus split, `std_dif` 72 studies against `stddiff` 59, is what a 2009
macro versus its 2019 successor should look like. A template states what a NEW
study should do, so this is not a spelling choice: it is whether to ship the
successor. Shipping `stddiff` also moves the template's dependency from
`hvtiRtables` to `hvtiRutilities`, which the port has to know.

## 6. `graphs/dp` carries three generations

| generation | count | what it is |
|---|---|---|
| `archive/old_rplots/` | 4 `.S`, 6 `.R` | S-Plus and early R |
| live | 11 `.R`, 4 `.sas` | current mixed estate |
| `tp_ggplot/` | 7 `.R` | ggplot2 rewrite |

`AFib_long_profile_binary.R` exists live and again in `tp_ggplot/` as
`afib_long_profile_binary.R`, differing only in case. **A template extracted
without choosing a generation will encode whichever copy was opened first.**
That is the same failure as section 5, one directory up.

## 7. Two things the ledger currently mis-states

**`dp` spans three folders, not one.** The row records `folder: graphs`.
`distributions/dp` is 237 job studies and `descriptive/` carries six live `dp`
templates (`DescriptiveSummary`, `EDA_barplots_scatterplots`,
`descriptive.figures`, `gfup` and two variants).

**The qualifier's second field differs by folder too**, which the naming-parse
note did not reach:

| folder | shape | example |
|---|---|---|
| `graphs` | `dp.<plot type>.<variable>` | `tp.dp.spaghetti.echo.R` |
| `distributions` | `dp.<variable>.<measurement scale>` | `tp.dp.pain_score.ordinal.sas` |
| `descriptive` | `dc.<what>.<output format>` | `tp.dc.tables.html_and_rtf.sas` |

So `distributions/dp` is **not** one template parameterised by variable, as
first suggested. The scale is what changes the code; the variable is an `EDIT:`
field. That points at one template per scale, binary / ordinal / continuous,
which is two or three rather than one.

## 8. The decision: what is a template's identity?

Decomposition forces this, and it is the only genuinely open question.
A template file is `<NN.MM>-<prefix>.qmd` and a ledger row is keyed by prefix.
Four `graphs/dp` templates cannot both be `dp`.

| option | what it costs | what it buys |
|---|---|---|
| **A. Carry the qualifier in the filename**, `06.03-dp-trends.qmd` | changes `.template_fields()` and `new_job()`, both of which parse `<NN.MM>-<prefix>`; ledger key becomes `(prefix, qualifier)` | the name says what the template is. A study author asking for the trends plot can find it |
| **B. Several ordinals, one prefix**, `06.03-dp.qmd` and `06.04-dp.qmd` | ledger uniqueness check must go; no code change to the parser | filenames already permit it, but they are opaque: nothing distinguishes the two but an ordinal |
| **C. Do not split.** One `dp` template branching on an `EDIT:` field | nothing | re-buries the distinction this whole exercise surfaced, and cannot express that `general` and `tables` have different package dependencies |

**Recommendation: A.** It is the only option under which the filename states the
job type, and the job type is what a study author is looking for. It is also the
only one that survives section 4: `general` and `tables` resolve to different
packages, so a single template that switches between them would depend on both.

## 9. Recommended shape, if A is taken

| folder | prefix | templates | note |
|---|---|---|---|
| `descriptive` | `dc` | `general`, `tables`, `gfup`, `dead` | plus `stddiff` if section 5 is resolved in favour of the 2019 macro |
| `graphs` | `dp` | `trends`, `gfup`, `spaghetti`, `procs` | from `tp_ggplot/` where a ggplot version exists |
| `distributions` | `dp` | one per measurement scale | binary / ordinal / continuous, variable as `EDIT:` |

Roughly ten to eleven templates where the ledger currently carries two rows.

## 10. What this does not settle

- **Whether `dc.general` deserves a template at all.** It is 759 studies and
  base procs only, so it is either the most valuable template here or too
  trivial to be worth one. The counts cannot say; reading two study exemplars
  can, and the share was unmounted when this was written.
- **Which generation each `graphs/dp` template extracts from.** Section 6 says
  choose deliberately, not which to choose.
- **The `tp_ggplot/` set has no `trends` or `spaghetti`.** The two largest
  `graphs/dp` job types have no ggplot version, so recommending "from
  `tp_ggplot/` where it exists" leaves the two biggest cases unanswered.
- **Cumulative row coverage**, which would say how much of each folder the
  recommended set actually covers. It needs the raw catalogue and the share was
  unmounted. The study percentages in section 2 are exact but do not sum.
