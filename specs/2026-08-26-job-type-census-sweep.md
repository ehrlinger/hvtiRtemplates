# Census sweep: extending coverage beyond `hz`

**Date:** 2026-08-26
**Status:** scoped, not started — **pick up in a separate session**
**Prompted by:** the `hz` census (2026-08-26) answering its own question well
and exposing how narrow it is.

This note is self-contained. It assumes no memory of the session that produced
it.

---

## 1. What exists today

`shape-census.R` lives in the **study tree**, not in a repo:

```
/studies/vascular/thoracic-aorta/dissection/ascending/acute/preserve_root/analyses/R_hazard/R/shape-census.R
```

Run server-side (never over SMB), R 4.6.0, TemporalHazard ≥ 1.2.6:

```
cd /studies/vascular/thoracic-aorta/dissection/ascending/acute/preserve_root/analyses/R_hazard/R
env -u R_HOME /opt/R/4.6.0/bin/Rscript shape-census.R /studies
```

Latest output: `shape-census-20260826-092229.csv` — **3,269 listings,
4,843 fit blocks, 527 studies.** Columns: `study, file, fit, shape, has_early,
has_con, has_late, n_free_late, free_late, free_early, m_free, n_obs, n_events,
nomogram, path, note`.

**Its scope is deliberately narrow and should be understood before extending
it:** it matches `^hz[.].*[.]lst$` and keeps only files whose immediate parent
is `distributions/`. It was built to answer one question — which phase shapes
and late-shape grades exist, so a `hzr_decompos_g3()` benchmark could be found.
It answered it. It is not a general corpus inventory and does not pretend to be.

Two properties worth knowing before reusing it:

- The `^hz[.]` anchor **excludes `tp.hz.*`** templates, which is correct —
  a `tp.` prefix marks a template that is not meant to be run. An unanchored
  pattern would pull templates into the counts.
- It reports what it discards (fixed 2026-08-26). Corpus answer: **zero**
  misfiled `hz` jobs — every one sits under `distributions/`.

## 2. Level 1 — job-type inventory. Cheap, and the one to do first

**The question it answers:** for each untemplated job prefix, which studies have
run it, and how many jobs each?

That is the question the template roadmap keeps needing. `hvtiRtemplates` gates
each template on *a second study having run that job type*, so for every pending
prefix someone has to know whether a second study exists. On 2026-08-26 that was
answered by hand, one `ls` at a time, to produce this:

| prefix | maze/atricure/gender | preserve_root |
|---|---|---|
| `ac` | 30 | 40 |
| `hz` | 24 | 35 |
| `hp` | 28 | 67 |
| `hm` | **0** | 1 |
| `hs` | **0** | 3 |
| `bh` | **0** | 6 |

That table decided a real design question — `hm`/`hs`/`bh` exist in only one
study, so they cannot be templated yet and must not be stubbed. It should have
been one lookup.

**Shape of the work.** Filename-only. No parsing, no `.lst` reading, no
TemporalHazard dependency. Group by `(prefix, study)`, emit a CSV. The rough
server-side shape:

```
find /studies -name '*.lst' -path '*/distributions/*' -o -name '*.lst' -path '*/analyses/*' \
  -o -name '*.lst' -path '*/graphs/*' -o -name '*.lst' -path '*/descriptive/*'
```

then derive the prefix from each basename and the study from the path above the
taxonomy folder.

**Extracting the prefix is not "split on the first `.`".** A `tp.` marker
precedes the real prefix, so `tp.hz.dead.lst` would classify as prefix `tp` —
which both loses the fact that it is an `hz` template and collides with the
exclusion rule below. Strip a leading `tp.` **first**, record the file as a
template, and take the prefix from what remains.

**Requirements, learned the hard way elsewhere:**

- **Exclude `tp.` from the job counts** — templates, not jobs — but count
  them separately rather than dropping them silently, per the paragraph above.
  Anchor at `^<prefix>[.]` once the marker is stripped.
- **Validate the prefix against `hvti_taxonomy()`** and report unknown ones
  separately rather than dropping them. An unknown prefix is a finding.
- **Report what is discarded**, by reason and count. A sweep that reports only
  what it kept makes a missing job indistinguishable from a job that does not
  exist. This bit the `hz` census.
- **Do not assume the taxonomy folder.** `hz` turned out to be clean, but that
  was verified, not assumed.
- Server-side only. `/studies` over SMB is metadata-latency-bound.

**Success:** a CSV of `(study, prefix, folder, n_jobs)` covering `/studies`,
plus a printed summary of prefixes by number-of-distinct-studies — which is
the column that says whether a template is unblocked.

## 3. Level 2 — flag repeated-events fits in the `hz` census. Small, do it next

**The problem.** Repeated-events hazard jobs are in the census already, because
they carry the `hz.` prefix — e.g.
`cardiac/rhythm/maze/atricure/gender/distributions/hz.ce_cardioversion_repeated.lst`.
Nothing marks them as recurrent. **A recurrent-event fit and a single-event fit
are different estimands and are currently pooled** in every count and every
parity table the census feeds.

This matters concretely: those `ce_cardioversion_repeated` fits are grade 4
(all of `TAU/GAMMA/ALPHA/ETA` free) and are the largest remaining
`hzr_decompos_g3` widening available. Anyone reaching for them needs to know
what they are.

**The obvious detector does not work.** Observations-exceeding-subjects was
tried and **does not fire**: that listing reports

```
There are   876 observations available for analysis with:
                            876 Total Subjects
```

876 = 876. So the tell is elsewhere — likely in the `.sas` (the job's data step
producing one row per event), or in a `.lst` line not yet found. **Budget about
an hour and stop.** If no reliable tell exists in the `.lst`, record that as the
finding and fall back to reading the `.sas`, or to a name heuristic that is
explicitly labelled a heuristic.

**Do not ship a detector that silently guesses.** A wrong flag here is worse
than no flag, because it would license pooling.

## 4. Level 3 — content census for other job families. Defer

`shape-census.R` works because `.hzr_parse_sas_lst()` understands hazard
listings. There is no equivalent for mixed-model, generalized-model or
bootstrap output, so a content census for those means **one parser per job
family**. That is real work.

Defer it until a specific question pulls it, exactly as the g3 question pulled
the `hz` census. Building parsers speculatively produces parsers nobody has
validated against a real question.

The families, when their turn comes:

| prefix | job | folder |
|---|---|---|
| `mm` | Mixed model — continuous repeated-measures longitudinal | `analyses` |
| `gm` | Generalized model — repeated-measures ordinal / count | `analyses` |
| `mp` | Mixed model plot | `graphs` |
| `gp` | Generalized model plot | `graphs` |
| `bh` | Bootstrap hazard | `analyses` |

Longitudinal is currently **completely invisible** to any census — not a bug,
out of scope by construction, but worth stating plainly since longitudinal work
is expected.

Note `maze/atricure/gender` carries 12 `gm.` and 20 `gp.` jobs, so it is a
candidate second exemplar well beyond the hazard chain.

## 5. Where this work should live

`shape-census.R` is an untracked file on a network share, in a tree that is
**not a git workspace** (`preserve_root` carries a stray 2023 `.git` with no
remote and hundreds of uncommitted paths — do not branch or commit there).

That is fine for a one-question script and bad for tooling that the template
roadmap depends on. Worth deciding early in the pickup session: does the
inventory sweep belong in `hvtiRutilities` (which already owns `study_config()`,
`study_init()`, the manifest layer), or stay a study-tree script? The Level 1
sweep has no study-specific content and no TemporalHazard dependency, which
argues for the package.

## 6. What NOT to do

- Do not widen `^hz[.]` to catch more files without re-checking `tp.`
  exclusion.
- Do not report a sweep's coverage without reporting its discards.
- Do not pool repeated-events and single-event fits in any parity number until
  §3 lands.
- Do not write per-family parsers before a question needs them.
