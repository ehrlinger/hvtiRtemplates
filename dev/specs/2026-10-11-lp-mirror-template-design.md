# `lp-mirror` template: design, 2026-10-11

**Status** Design, approved section by section on 2026-10-10 and 2026-10-11. Not
implemented.
**Replaces** the R and SAS `lp` jobs that draw a mirrored propensity-score
histogram, and the legacy `tp.lp.propen.mirror_histo_*` templates.
**Depends on** `lm-propensity_binary` (its saved bundle), and #287's `MODEL_FILE`
and `MODEL_SET` settings, which `lp-mirror` reuses.

## 1. What `lp` is

A read-only survey on 2026-10-10 read 23 R `lp` jobs drawn from 19 studies, against
the 2026-08-27 job census. The census holds 612 R-side `lp` job files across 186
studies.

- **In R, `lp` is propensity diagnostics.** By filename, about 578 of the 612 (94%)
  are propensity plots: about 284 mirrored histograms, about 238 covariate-balance
  plots and about 56 others. Every legacy `tp.lp.*` template is one of these.
- **None refits.** No R `lp` file calls `glm(` or `predict(`. Each reads scores
  computed upstream, usually a one-row-per-patient export carrying the score, the
  group and a match flag or weight.
- **The balance plot already ships.** `dc-stddiff` draws it with `ps_stddiff()` and
  `hvtiPlotR::hv_balance()`.
- **The mirrored histogram is the gap.** `hvtiPlotR::hv_mirror_hist()` draws it,
  and no shipped template calls it.
- **No R exemplar plots predicted probability against a covariate.** If that shape
  exists under `lp`, it is in the SAS jobs, which were not surveyed. It is not part
  of this design.

The two-study gate is met many times over.

**`lp` becomes a qualified prefix.** Its ledger row becomes `lp-mirror`, because a
prefix is wholly qualified or wholly unqualified. A later `lp` shape, such as
calibration, arrives as its own qualifier.

## 2. Where it sits and what it reads

- **Placement.** `inst/templates/40_graphs/lp-mirror.qmd`, scaffolded with
  `add_job("lp.mirror", subject, type)`. It shares the set of the
  `lm-propensity_binary` job it plots, as `hp` shares its set with `hz`. `SUBJECT`
  and `TYPE` match that job, so the template finds its bundle without a path.
- **The bundle.** It reads `estimates/lm-propensity_binary.rds` from that set.
  `MODEL_FILE` and `MODEL_SET` let a mirror job live in a set of its own, with the
  same checks lm-checkpred makes: a bare `.rds` name and a valid set name, so
  nothing outside the study's estimates can be reached.
- **Lineage.** It checks the bundle's lineage as `hp` checks its upstreams. A bundle
  with no source lineage, or one whose rebuilt read has different rows,
  patients or patient hash, stops with the command to rebuild it.
- **It never refits.**
- **What the bundle supplies.** Its `$data` holds, for each patient:
  - the score (`prob_t`) and its logit;
  - the treatment;
  - the matching weight (`mt_wt`);
  - the patient ID, as a study-keyed digest.

  It also records which column is which, and the declared treatment levels, which
  hvtiRpropensity 0.1.10 records (hvtiRpropensity#47). A study author types no
  column names.
- **The optional match flag.** This is the only input the bundle cannot supply.
  - The default is `MATCH <- NULL`.
  - A study whose dataset already carries a pair-match flag, for example from a SAS
    match, sets `MATCH` to that column, with `DATASET` and `ID` as in any job.
  - The template reads that dataset with `read_job_data()` and joins the flag onto
    the bundle's patients **by ID digest**, with the same study key lm-checkpred
    uses. No identifier is stored or printed.
  - Two counts are reported, never listed: bundle patients with no flag, and
    flagged patients absent from the bundle.
  - When too few patients join, it stops and says why: the dataset is not the
    cohort the scores came from, or the identifiers do not match.
- **When `cm` or `rm` ship,** they save a bundle that carries the flag, and
  `MATCH` comes from there without a dataset read.

## 3. Figures and settings

All figures come from `hvtiPlotR::hv_mirror_hist()`, with treated patients above
the axis and controls below.

| figure | when | from |
|---|---|---|
| `fig-mirror-unmatched` | always | score and treatment |
| `fig-mirror-weighted` | always | the same, weighted by `mt_wt` (`weight_col`) |
| `fig-mirror-matched` | only when `MATCH` is set | unmatched against matched shading, from the joined flag (`match_col`) |

- Each figure is saved as PNG and PDF through `.save_figure()`, as in every
  template since 1.3.0.
- **The y-axis is derived** from the counts, symmetric about zero. Every exemplar
  types its axis by hand, and that is where they go wrong.
- A table under each figure gives the patients in each group, and for the matched
  figure, the matched count in each group. It holds counts only.

| setting | default | `EDIT:` |
|---|---|---|
| `SUBJECT`, `TYPE` | the propensity job's set | yes |
| `MODEL_FILE`, `MODEL_SET` | `"lm-propensity_binary.rds"`, `NULL` | no |
| `GROUP_LABELS` | `NULL`: the bundle's declared treatment levels | no |
| `BINWIDTH` | `5` on the 0 to 100 scale; exemplars use 5 or 10, and 1 for a rare exposure | yes |
| `MATCH`, `DATASET`, `ID` | `NULL`, `"built"`, `"ccfid"` | no |
| `SAVE_FIGURES`, `FIGURES` | as in every template | no |

**Out of scope:**
- the dark "presentation" copies;
- pptx export;
- axis breaks;
- `setwd()` and absolute paths;
- the balance plot, which belongs to `dc-stddiff`;
- any refit.

## 4. Catalog, versions and lint

- **Catalog and roadmap.** The `lp` ledger row becomes `lp-mirror`, folder
  `graphs`. The roadmap is regenerated with its renderer, and the three spec-count
  scripts must pass.
- **`.lintr`** gains a key for the file itself, never for the directory.
- **hvtiPlotR.** The floor stays at `>= 2.8.0`. `hv_mirror_hist()` has taken
  `weight_col` and `match_col` since at least v2.7.2, as checked against the tags
  on 2026-10-11.
- **hvtiRpropensity.** The floor stays at `>= 0.1.10`, set by #287, for the
  declared treatment levels. The template's version check is tied to DESCRIPTION
  by the same test #287 added.

## 5. Provenance

The job records:
- the bundle it read: its set, file and lineage;
- when `MATCH` is set, the dataset's version and the join counts.

It records no identifiers. A stale bundle, or one without lineage, stops with the
rebuild command, as `hp` does.

## 6. Gallery

A new job in `dev/gallery/family-lm.R`, after `lm-propensity_binary`, in the same
set.
- The main run leaves `MATCH` unset and shows two figures.
- The synthetic study gains a simulated match column, so a second gallery job can
  exercise the matched figure.

## 7. Tests

All fixtures synthetic, no PHI. Each test fails with its code reverted.

1. **Reading.** The bundle is read from the template's own set, and from another
   set through `MODEL_SET`. A bad `MODEL_FILE` or `MODEL_SET` stops.
2. **Labels.** Group labels come from the bundle's declared levels, and
   `GROUP_LABELS` overrides them.
3. **Axis.** The y-limits are symmetric and derived from the largest bin count.
4. **Weights.** The weighted bar heights equal the sum of `mt_wt` per group and bin.
5. **Match join.** The flag joins by ID digest. The counts of unflagged bundle
   patients and of flags with no bundle patient are right. A dataset from another
   cohort, where too few join, stops.
6. **Lineage.** A missing or stale bundle stops with the rebuild command.
7. **No identifiers.** No patient identifier appears in the rendered report.
8. **Render.** The template renders: two figures without `MATCH`, and three with
   it.
