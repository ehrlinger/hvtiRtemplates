# `ar` census: results, 2026-11-12

The results of running `2026-11-12-ar-census.py` three times against the 2026-08-27 corpus
catalogue (`census-ALL.csv`, 2,240,554 rows), and of labelling the two samples from each
run. Each run tightened the name exclusions:

| run | script | counts in |
|---|---|---|
| 1 | as merged in #530 | `2026-11-12-ar-census-summary.json` |
| 2 | adds a `boilerplate` bucket, matched by bare prefix (#537, first version) | `2026-11-12-ar-census-summary-boilerplate.json` |
| 3 | boilerplate matched by whole name, plus a `manuscript_folder` bucket (#537) | `2026-11-12-ar-census-summary-folder.json` |

Run 2's JSON carries the `exclusion_match` wording the script wrote after a later wording
fix that changed no count. Run 3's JSON is the script's own output. Run 3 predates one
addition to the boilerplate tail (the `StudyXXX` placeholder), so a few unfilled
project-plan forms are still in its frame.

All three runs use seed 20261112. Their frames differ, so they draw different studies and
files, and the labels are independent. The labelled worksheets carry study paths, so they
stay on the server in scratch folders under `_development` and are not committed.

⚠️ **All six samples were labelled from file names only, and no file was opened.** That was
enough to decide most rows. It cannot tell a finished report from an abandoned draft, and
it leaves a few names undecided. Treat the estimates below as a first reading that a person
opening files could tighten.

## The figures

| measure | run 1 | run 2 | run 3 | pooled |
|---|---|---|---|---|
| candidate frame, studies | 1,484 | 1,344 | 1,366 | not pooled |
| candidate frame, files | 42,277 | 36,076 | 32,746 | not pooled |
| **breadth, best estimate** | about 670 (455 to 895) | about 705 (505 to 900) | about 545 (360 to 755) | **about 640 (515 to 760)** |
| breadth, lenient | about 815 | about 940 | about 820 | not pooled |
| **volume, report files** | about 4,200 (2,450 to 7,050) | about 2,100 (1,040 to 4,170) | about 3,300 (1,900 to 5,450) | **about 2,900 (1,900 to 3,950)** |

Plus one figure that needs no sample: **570 catalogue studies**, the filename-based
candidates. That is the number of distinct catalogue `study` values holding at least one
`ar`-named Word or RTF file, with templates and system files excluded. It comes from one
command over the catalogue (below), with no judgement calls. It is not validated: no file
was opened, nested fragments are not consolidated, and an RTF table named for aortic
regurgitation (`ar_cont.rtf` turned up in run 2's file sample) may parse as prefix `ar` and
inflate it. It is neither a confirmed count nor a strict lower bound on independent
studies.

**How to read the table.**

- **Breadth** is studies holding at least one report, scaled from 40 studies drawn
  uniformly from the frame. Strict `yes` means an `ar.*` file, or a file named as a report,
  an analysis or results. Lenient also counts studies whose only evidence is SAS table
  output or request write-ups.
- **Volume** is report files, scaled from 120 kept files drawn uniformly from the frame.
  Every audit row in every run was a correct exclusion, and run 3's frame keeps `ar`-named
  files even inside a manuscript folder, so the three runs estimate the same quantity.
- **The intervals** are Wilson 95% intervals on each run's sampled proportion. The pooled
  figures are inverse-variance averages of the three runs on a normal approximation, which
  is rough: the frames differ, and a few studies were drawn in more than one run. All of
  them measure **sampling uncertainty inside the candidate frame and nothing else**. They do
  not cover errors in the filename-only labels, or the populations the frame leaves out
  (see the last section).
- **The frame is not an upper bound.** A study whose only report was excluded by name, is
  unplaced or exists only as PDF is outside it.
- **Run 3's frame is larger than run 2's** (1,366 against 1,344), although run 3 excludes
  more. Run 2's bare-prefix boilerplate rule had removed 22 studies outright, which is the
  bias Codex raised on #537 and the whole-name rule removed.

**Draft-collapsed volume is not estimated.** Each run reports a collapse ratio (0.76, 0.74
and 0.75), but it is measured over ALL kept documents, not reports, and `report_key()` drops
every numeric token, not only draft numbers. Applying it to the pooled 2,900 gives about
2,200 distinct reports, which holds only if reports duplicate at the same rate as everything
else. That is a conditional heuristic, not an estimate.

**The catalogue's own `ar` figures measure something else.** `templates.json` carries
`sas_breadth` 706, from the 2026-08-29 job census, and `sas_breadth_jobs` 394, from the
2026-09-02 per-folder parse. Both count studies with a file whose name parses to `ar`. 706
counts files of any extension. 394 counts program extensions only, which an analysis report
never has. This note does not change either value. Whether `sas_breadth` should become 570
or about 640 is the maintainer's call.

The 570 command:

```sh
python3 -c "import csv,sys;csv.field_size_limit(10**7);print(len({r['study'] for r in csv.DictReader(open(sys.argv[1])) if r['prefix']=='ar' and r['ext'].lower() in ('doc','docx','rtf','odt') and r['study'] not in ('','NA') and r['is_template'].strip().upper()!='TRUE' and not r['stem'].startswith(('~\$','._','.~lock'))}))" <census-ALL.csv>
```

⚠️ **Leave out the `is_template` test and the count reads 1,000.** A copy of the `ar`
template sits in most studies, and the script's own comment records the same effect on an
earlier parse (about 1,100 studies for every prefix alike). Run 1's study sample is what
gave this away: 15 of its 40 studies hold an `ar`-named file, which predicts about 557, and
570 agrees with that.

## How the studies were labelled

| | run 1 | run 2 | run 3 |
|---|---|---|---|
| `yes` (strict) | 18 | 21 | 16 |
| `no` under strict, `yes` under lenient | 4 | 7 | 8 |
| `no` under both | 16 | 12 | 14 |
| `nested`, not an independent study | 2 | 0 | 2 |

- `ar.*` decided 15 of run 1's 18 strict yeses, 17 of run 2's 21, and 15 of run 3's 16.
- The `nested` rows are catalogue study keys that sit inside another study: a taxonomy
  folder found in another study's `documents/` (run 1) or `documents/Manuscript` (run 3),
  and data folders under another study's `datasets/` (one in each of runs 1 and 3). Some
  catalogue study keys are fragments of other studies.
- In run 1, seven of the twenty `no` studies held nothing but files copied into every
  study. Runs 2 and 3 exclude those files, and their `no` studies hold proposals,
  abstracts, manuscripts, forms and data notes instead.

## How the files were labelled

| class | run 1 (of 42,277) | run 2 (of 36,076) | run 3 (of 32,746) |
|---|---|---|---|
| report | 12 (10%) | 7 (6%) | 12 (10%) |
| SAS table output (`general_cont.rtf` and the like) | 44 (37%) | 59 (49%) | 67 (56%) |
| manuscript that the rules missed | 24 (20%) | 24 (20%) | 10 (8%) |
| other | 40 (33%) | 30 (25%) | 31 (26%) |

All 120 audit rows were correct exclusions under the strict reading, 40 from each run,
drawn from 8,086, 14,287 and 17,617 named exclusions. Each run bounds the wrong-exclusion
rate below about 9% at 95%. Run 3's 11 `manuscript_folder` audit rows were all manuscripts,
revisions or supplements. Run 1's one borderline row was SAS table output written for a
manuscript. System files never enter the audit by design, so their absence there tells you
nothing.

## What would tighten stage 2

The boilerplate bucket cut "other" from a third to a quarter of kept files, and the
manuscript-folder bucket cut missed manuscripts from a fifth to a twelfth. What leaks
through now, in order of size:

1. **Abstracts named with the house `ab.` prefix** (`ab.Name_RD24_[0]`): 8 of run 3's 31
   "other" files, and two more abstracts named otherwise. A rule on the `ab.` prefix would catch most of them, and abstracts
   whose name runs the word into another (`…ACHDabstractgp2`) too.
2. **Manuscripts outside a manuscript folder** with names the token rule cannot read:
   journal-named drafts (`Ms to ATS`), compressed spellings (`mnscrpt`), supplement tables.
3. **Boilerplate the whole-name rule cannot see**: a leading qualifier
   (`QMR_ProjectPlan…`), or a proposal that runs a person's name into the word. Keeping
   these is the safe way to fail.

None of these changes the report estimates, which already treat these files as non-reports.
They would make the frame tighter and the samples more efficient.

## What the catalogue cannot see

The census counts placed files only. 2,178 Word and RTF files, and 2,857 PDFs, sit with no
taxonomy folder above them and belong to no study. That is about 4% of the Word and RTF
files, but the share of documents says nothing about how many reports or studies are
missing: unplaced files may hold reports at a different rate, and may belong to studies
the catalogue never names.

So every estimate here has a narrower scope than "the corpus". The sample proportions,
and all three candidate frames, apply only to **kept, placed Word and RTF documents**.
Outside that frame, with nothing estimated for it, are unplaced files, reports kept only
as PDF, and any report that a name exclusion removed (the audits bound that last group at
about 9% of exclusions; they do not measure it).
