# dp-trends: trends over operation year

**Date:** 2026-09-10
**Status:** implemented on `feat/dp-trends-template`. Ships once hvtiRtemplates
pins hvtiR `v1.1.8`, whose catalog marks the row `shipped` (hvtiR#60).
**Parent:** `2026-09-09-eda-templates-design.md`, wave 1.

## 1. Evidence

A sweep of the studies share on 2026-09-10 found **24 studies** with a
`graphs/dp.trends*` source job, **50 files** in all. **None calls
`hvtiPlotR::hv_trends()`.** 26 hand-roll `smooth.spline()` and 21 `loess`; the
one 2026 file that loads a plotting package loads the dead 2017 `hviPlotR`.

The shape was extracted from two independent studies:

| study | jobs | era | what they draw |
|---|---|---|---|
| `cardiac/valves/mitral/degeneration/complex` | 3 | 2017 to 2018 | 0/1 characteristics x 100 (heart failure, repair), NYHA I to IV as four wide 0/1 columns, continuous LV indices; each figure repeated for all, complex and simple |
| `cardiac/general/trends/2026` | 1 | 2026 | three 0/1 procedure indicators x 100 as series; a stacked count histogram per year |

A third, `cardiac/valves/mitral/mac/2021`, is **not** independent: its header is
the first study's, path included. It is a copy, the same copy-as-template
pattern `dc.general` showed, and it is counted as evidence of reuse, not as a
second exemplar.

Common to both: calendar year as years-since-origin plus an origin that differs
by study (1985 in one, 2000 in the other); per-year means computed by hand with
`group_by()`/`summarise()`; a smooth through the patient-level data; fixed axis
breaks; 11.5 by 8 PDFs.

## 2. Decisions

- **Thin over `hv_trends()`.** It takes patient-level data and computes the
  per-year points itself, so the template never aggregates.
- **One job renders a list of figures** (`TRENDS`), because every exemplar
  draws several, and **optional subgroups** (`SUBGROUPS`), each figure drawn
  once per subgroup on shared axes, because the first study's jobs all do.
- **Set key `(cohort, eda)`.** `new_job()` requires an endpoint and a type, but
  a trends plot describes a cohort rather than analysing an endpoint.
  `ENDPOINT` names the subject, `TYPE` is always `eda`, so every EDA figure for
  one subject lands under `graphs/<subject>-eda/`. Chosen over running inside an
  analysis set, and over a package change exempting descriptive jobs from the
  endpoint layer.
- **Out of scope:** per-year volume counts (`dp-procs`, `hv_stacked()`), and a
  single variable's distribution (`dp-variable`).
- **hvtiPlotR floor 2.7.7, not 2.7.6.** The job reports each figure's dropped
  rows from `meta$n_missing`, which arrived part-way through 2.7.6 without a
  version bump: a package reporting 2.7.6 may or may not have it.
- **LOESS, not `smooth.spline(df = 6)`.** `hv_trends()`'s smoother. The two
  differ at the ends of the year range, which the template says in prose.

## 3. Guards

Each fails loudly where the exemplars failed quietly:

- a calendar year outside 1900 to next year stops the render, which is what a
  wrong origin produces;
- a `percent` column holding anything but 0/1 or logical stops, because a 1/2
  code times 100 draws a plausible wrong figure;
- a subgroup that selects nobody stops;
- rows missing the year or the value are counted and printed with every figure,
  where the exemplars dropped them with `na.omit()` and said nothing.

## 4. Render gate

Against a synthetic project built with `study_init()` and 600 simulated
patients, scaffolded with `new_job("dp", "cohort", "eda", qualifier = "trends")`.
No study data, path or identifier is involved.

| check | result |
|---|---|
| unedited, no draft mode | stops: "5 unresolved ... marker(s) remain" |
| `HVTI_TEMPLATE_DRAFT=1` | renders; 2 PNGs written and embedded |
| edited: four-series NYHA percent trend, median points, a `complex` subgroup | renders 6 figures; subgroup headings `all (n = 600)`, `complex (n = 244)`; dropped-row counts match the 40 injected missing values |
| a `percent` column coded 1/2 | stops: "is kind "percent" but holds 2" |

## 5. Catalog sequencing

`check-roadmap-counts.py` treats a template on disk as claimed only when its row
is `shipped`, `revisit` or `in-flight`, and fails any such row whose file is
absent. So each template ships with its own catalog flip and tag: the row goes
straight to `shipped` in hvtiR, a tag is cut, and this repository's pin moves in
the same pull request that adds the file. Flipping `dp-gfup` in the same tag
was rejected because the `dp-trends` pull request would then fail on `dp-gfup`'s
missing file. hvtiR names a version at most once a day, so `v1.1.8` follows
1.1.7 no earlier than 2026-09-11.
