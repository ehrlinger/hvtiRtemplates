# Handoff — re-parse the corpus with per-folder naming rules

**Date:** 2026-09-02
**Repo:** hvtiRtemplates
**Status:** not started. Nothing changed in this repo.
**Origin:** biostats training, 2026-09-02. John, in the room: *"So this rule that we have for templates is not valid."* and *"I'm going to reparse these things and I'm going to come back with new numbers next week."*
**Priority:** do this first. It invalidates inputs the rest of the roadmap is ordered by.

⚠️ No study, variable or patient identifier appears here.

---

## 1. What is wrong

The corpus scans assume **one** filename rule across all folders: a two-letter prefix, then the outcome.

```
tp.<prefix>.<outcome>        e.g.  tp.hm.dead
```

That holds in `analyses`. It does **not** hold in `descriptives`, `distributions` or `graphs`, where the second component is a *refinement*, not an outcome:

```
tp.dp.trends          tp.dp.gfup          tp.dp.spaghetti.echo
tp.dp.histogram       tp.dp.distribution  tp.dc.<type>
```

So a single parser produced one bucket called `dp` (628 SAS / 1,780 R) that is really a family of distinct job types, and one called `dc` (1,010 SAS / 108 R) that is the same problem in `descriptives`.

**Two rules, one parser, forty years of files.**

## 2. Why it matters beyond the numbers

1. **The batch order is derived from SAS breadth.** `roadmap_render.py` and `2026-08-29-roadmap-seed.py` sort work by `sas_breadth`. If `dp` is five job types rather than one, its position is meaningless and everything below it may move.
2. **`dp` cannot be templated as it stands.** You cannot write one template for a bucket. Decomposition is a prerequisite to Batch 3 (the plots family), which is the largest unstarted batch.
3. **It changes package scope.** John, same meeting: the `DP.*` functionality moves into hvtiPlotR functions, hvtiPlotR goes to **3.0**, and hvtiRtables picks up the `DC.*` descriptive work and goes to about **2.0**. Those version plans are downstream of knowing what `dp` and `dc` actually contain.
4. ⭐ **This is the third assumption-at-scale failure in a fortnight**, after the two-studies gate and the `hzdead`/`hmdead` fusion. Same shape each time: a convention inferred from a small sample, applied to the whole corpus, with the sample size unrecorded. Worth naming in the design record.

## 3. What to build

**A parser that dispatches on folder, not on position.**

- `analyses` — `tp.<prefix>.<outcome>[.<qualifier>]`. Note the qualifier: `tp.br.summary` exists and was called out in the room as wrong — it should be `tp.br.<outcome>`, with `summary` as a further component. Record these as malformed rather than silently bucketing them.
- `descriptives`, `distributions`, `graphs` — `tp.<prefix>.<refinement>[.<sub>]`. `tp.dp.spaghetti.echo` is three levels; the parser must not stop at two.
- Emit the refinement as its own field. The output should let you ask "how many `dp.trends` are there" without re-parsing.

**Report the malformed set explicitly.** Anything matching neither shape goes to a named bucket with counts, not into the unknown pile. The unmatched bucket already holds 103,454 rows with only seven curated exclusions, and nobody has read past the top 40 — do not grow it silently.

**Re-run the allocation scan too.** `2026-08-14-macro-allocation-scan.py:100` still globs one level deep and still names the retired slugs `hvtiRdatasets` and `temporal_hazard` in its destination table. Re-running the current script as-is would reintroduce dead names.

## 4. What to check the result against

- `hz` and `hm` were hand-corrected by folding in `hzdead` (396) and `hmdead` (172). **A correct parser should find those itself.** If it does, drop the hand-applied `+n` and use the measured number. If it finds a different figure, that difference is the interesting result.
- ⚠️ `sas_breadth` counts **distinct studies**. Summing buckets double-counts any study that uses more than one naming form. Whatever the parser emits, state whether the figure is a sum or a distinct count.
- `deade` (170) and `deadl` (169) are still unidentified and were deliberately not folded in. See whether the new parse explains them.

## 5. Files

- `dev/specs/artifacts/2026-08-29-roadmap-seed.py` — seeds the roadmap from the census
- `dev/specs/artifacts/2026-08-29-job-census-summary.json` — the census output, unknown bucket truncated to 40
- `dev/specs/artifacts/2026-08-29-template-roadmap.json` — 45 prefixes, `status`/`batch`/`note`/`spec`/`ordinal` hand-maintained after seeding
- `dev/specs/artifacts/2026-08-22-prefix-placement-scan.py`, `2026-08-22-job-flow-scan.py`
- Raw census: `census-20260827-064249/` on the share, 961 MB, 2,240,570 files. Not in the repo, deliberately — every row is a study path.

## 6. Definition of done

- [ ] Design record at `dev/specs/2026-09-0X-per-folder-naming-parse-design.md`, listed in `dev/specs/README.md`
- [ ] Parser dispatches on folder; refinement is a first-class field
- [ ] Malformed set reported with counts, not absorbed
- [ ] New `job-census-summary.json` and regenerated `template-roadmap.json`, with the hand-maintained fields preserved
- [ ] `hz`/`hm` compared against the hand-applied +396/+172
- [ ] Batch order recomputed and the diff against the current order stated explicitly
- [ ] `deade`/`deadl` resolved or explicitly still unknown
- [ ] Allocation scan re-run with the fixed glob and current slugs
- [ ] Version bumped, `NEWS.md` updated
