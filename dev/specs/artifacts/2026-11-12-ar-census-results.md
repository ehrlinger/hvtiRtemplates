# `ar` census: results, 2026-11-12

The results of running `2026-11-12-ar-census.py` against the 2026-08-27 corpus catalogue
(`census-ALL.csv`, 2,240,554 rows), and of labelling its two samples. The counts are in
`2026-11-12-ar-census-summary.json`, next to this file. The labelled worksheets carry study
paths, so they stay on the server in a scratch folder under `_development` and are not
committed.

⚠️ **Both samples were labelled from file names only, and no file was opened.** That was
enough to decide most rows. It cannot tell a finished report from an abandoned draft, and
it leaves a few names undecided. Treat the estimates below as a first reading that a
person opening files could tighten.

## The figures

| measure | value | basis |
|---|---|---|
| **breadth, firm lower bound** | **570 studies** | studies holding at least one `ar`-named Word or RTF file. Templates and system files excluded. One command over the catalogue, with no judgement calls |
| breadth, best estimate | about 670 (about 455 to 895) | 18 of 40 sampled studies hold a report, scaled to 1,484 |
| breadth, lenient | about 815 | also counts studies whose only evidence is SAS table output |
| breadth, upper bound | 1,484 | studies with any Word or RTF file left after the name exclusions |
| **volume, reports** | **about 4,200 files** (about 2,450 to 7,050) | 12 of 120 sampled kept files are reports, scaled to 42,277 |
| volume, drafts collapsed | about 3,200 | the census's ratio of collapsed to raw files, 0.76, applied to the line above |

The intervals are Wilson 95% intervals on the sampled proportion. They are wide enough to
rank the figures against each other, but not to quote to two significant figures.

**The catalogue's own `ar` figures measure something else.** `templates.json` carries
`sas_breadth` 706, from the 2026-08-29 job census, and `sas_breadth_jobs` 394, from the
2026-09-02 per-folder parse. Both count studies with a file whose name parses to `ar`. 706
counts files of any extension. 394 counts program extensions only, which an analysis report
never has. This note does not change either value; whether
`sas_breadth` should become 570 or about 670 is the maintainer's call.

The 570 command:

```sh
python3 -c "import csv,sys;csv.field_size_limit(10**7);print(len({r['study'] for r in csv.DictReader(open(sys.argv[1])) if r['prefix']=='ar' and r['ext'].lower() in ('doc','docx','rtf','odt') and r['study'] not in ('','NA') and r['is_template'].strip().upper()!='TRUE' and not r['stem'].startswith(('~\$','._','.~lock'))}))" <census-ALL.csv>
```

⚠️ **Leave out the `is_template` test and the count reads 1,000.** A copy of the `ar`
template sits in most studies, and the script's own comment records the same effect on an
earlier parse (about 1,100 studies for every prefix alike). The study sample is what gave
this away: 15 of its 40 studies hold an `ar`-named file, which predicts about 557, and 570
agrees with that.

## How the studies were labelled

Of the 40 studies drawn uniformly from the 1,484, 18 were labelled `yes`, 20 `no` and 2
`nested`.

- `yes` (strict): an `ar.*` file, or a file named as a report or an analysis summary.
  `ar.*` decided 15 of the 18.
- `nested`: not an independent study. One was a taxonomy folder found inside another
  study's `documents/`. The other was an archived data pull under a `datasets/` folder.
  Both count against breadth, and they show that some of the 1,484 are fragments of other
  studies.
- `no`: seven of the twenty hold nothing but files copied into every study (see below).

## How the files were labelled

Of the 120 kept files, drawn uniformly from the 42,277:

| class | files | share |
|---|---|---|
| report | 12 | 10% |
| SAS table output (`general_cont.rtf` and the like) | 44 | 37% |
| manuscript that the name rule missed | 24 | 20% |
| other: boilerplate, proposals, project plans, data requests | 40 | 33% |

All 40 audit rows, drawn from the 8,086 named exclusions, were correct exclusions. The
upper 95% bound on wrong exclusions is about 9%. The one borderline row was SAS table
output written for a manuscript. System files never enter the audit by design, so their
absence there tells you nothing.

## What would tighten stage 2

Two changes would turn 42,277 into a much closer upper bound. Neither is made here.

1. **An exact-name boilerplate bucket.** `binder.summaries.doc`, `stat_refs.doc`,
   `GFR-CKD-EPI-formula*.docx`, `dates4survival.docx`, `vars.sas.script.doc.docx`,
   `Methods-RF and Boosting.docx`, `RF-STAT-Method-Desc.docx`, `ProjectPlan*` and
   `Proposal_*` are copied into most studies. They make up most of the "other" third of
   kept files, and they are why nearly every study has a kept file.
2. **Matching manuscripts by folder as well as by token.** The token rule misses names
   run together with the word (`…Manuscript`), abbreviations (`ms`, `Revised ms`),
   journal names (`jtcvs`) and supplement or table files. Most of these sit under a
   `manuscript/` folder, so a path test would catch them.

## What the catalogue cannot see

The census counts placed files only. 2,178 Word and RTF files, and 2,857 PDFs, sit with no
taxonomy folder above them and belong to no study. That is about 4% of the Word and RTF
total, so the placed-only figures are lower bounds, but only slightly low.
