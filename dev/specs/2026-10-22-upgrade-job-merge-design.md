# upgrade_job(): carry every study edit by a three-way merge

Status: **design, for John's approval.** Supersedes decisions 4 ("prose is not carried") and 5 (fixed
backup name) of [`2026-10-12-upgrade-job-design.md`](2026-10-12-upgrade-job-design.md), and takes up the
three-way merge that design's decision 7 left for later. Plan:
[`2026-10-22-upgrade-job-merge-plan.md`](2026-10-22-upgrade-job-merge-plan.md).

## Problem

`upgrade_job()` carries the `edit-*` choices by name and rebuilds everything else from the current
template. It does that because the 2026-10-12 design had no base: without the template text the job
was copied from, an analyst's edit cannot be told from the old template's wording. The report lists
chunks that "differ from the current template", and the edits in them are gone from the upgraded job.

Measured on 2026-10-22, upgrading three real jobs from 1.4.1 to 1.4.2 on lri:

1. **COMMENCE `nb.boostmtree.avmngrad.boost`.** The job's description reverted to the template's
   `EDIT:` comment, and a two-line note above `PREDICTORS` vanished.
2. **Study #1356 `nb.boostmtree.mv_regn.boost`.** The `tbl-data` chunk lost the line that collapses
   grade 3 into grade 2. Without it the analysis silently goes from three ordered grades to four.
   `partial.plot()` lost `n.points = 10`, which the study set because 25 grid values would run for
   days. Inline comments on choice lines and comment blocks above them were lost too. The report's
   only signal was "`tbl-data` ... differs from the current template".
3. **`cohort-eda-dc-tables`.** The upgrade refused twice, because a `.pre-upgrade` from 10-15 and an
   `-upgrade.md` from 10-20 were already there, and both had to be renamed by hand.

Case 2 is the serious one: a change to the analysis, with nothing the analyst would notice. #383
fixes the description in case 1 by a heuristic, and lists the dropped notes. It cannot fix case 2,
because code outside the choices has no name to carry by.

## What the stamp makes possible

Since `d3b741e` (2026-10-12) `add_job()` writes `<!-- hvtiRtemplates: <template> <version> -->`
after the front matter. That says which template a job came from and at which package version. With
the template text for that version, the upgrade has all three inputs of a merge:

- **base**: the template as `add_job()` copied it into the job;
- **job**: the job as the study left it;
- **template**: the current template, staged by `add_job()` exactly as today.

A line the study changed and the template did not is kept. A line the template changed and the study
did not takes the template's text. A line both changed is a **conflict**. It is written into the job
with conflict markers and the upgrade stops, never picking a side for the analyst.

### Measured: a version string does not name a base

Every commit on `main` since `d3b741e`, read for its `Version:` and its template files: **70 of the
146 (version, template) pairs had more than one text.** `nb.boostmtree` at "1.4.1" had **nine**.
`Version:` moves at most once a day and many pull requests merge between bumps, and studies install
from `main`, so "1.4.1" names a range of texts, not one.

Choosing among those nine matters. On a scratch copy of study #1356's `.pre-upgrade` (copied off the
share; only `git merge-file` ran, no R), merged against the current template on `main`:

| base | lines the job differs from base | conflicts |
|---|---|---|
| tag `v1.4.1` | 96 | 4 |
| the text closest to the job | 46 | 2 |

**With either base, the grade collapse and `n.points = 10` survived**, where today's upgrade dropped
both. The two conflicts left with the closest base are real ones. The job had added a `progress =`
callback to the `boostmtree()` call on the line where the template added `mtry = MTRY`, and had
edited the install comment the template rewrote for 2.0.7. Both need the analyst's decision.

A wrong base fails in one of two directions, and they are not equally safe:

- **An older base** sees template lines the job never had as study edits. The result is extra
  conflicts, which are loud.
- **A newer base** sees the job's old template text as the study's choice, so it keeps it and
  undoes the template's change in silence. Suppose the template went A → B → C, the job was copied
  at A, and the base is taken to be B. The job's A then looks like a study edit against B, so the
  merge keeps A.

So the base must be exact where it can be. Where it has to be inferred, the inference must lean
older.

## Decisions

### 1. The stamp records the template's content hash

From this change on, the stamp is `<!-- hvtiRtemplates: <template> <version> sha256:<64 hex> -->`. The
hash is of the template file as shipped, before `add_job()` writes `SUBJECT`, `TYPE` and the stamp.
Version alone stays readable for old jobs. `.upgrade_report()` already reads the stamp with a regex,
which this widens.

### 2. The package ships the history of its templates

The package ships `inst/extdata/template-history.rds`: every distinct template text that was on
`main` since `d3b741e`, keyed by SHA-256, with an index of (template name, package version, first
and last commit date). It is built from git by `dev/template-history/build.R`, which reads
`git rev-list --first-parent` over `inst/templates/` and needs nothing from the installed package.

- **Size, measured:** 164 distinct texts, 3.5 MB raw, **133 KB** compressed with `xz`. One file in
  the tarball, because `xz` compresses the near-duplicates against one another and per-file `gzip`
  cannot.
- **When it is rebuilt:** in the version-bump commit, next to `news.py collect`, so each release
  carries every text that was on `main` before it. The current templates are not in it; a lookup
  reads `inst/templates/` as well.
- **Not a git dependency at run time.** lri has no clone of this repo, and the installed package has
  no history. Reading the archive is `readRDS()`.

Rejected: **old templates fetched by tag at upgrade time.** That needs network access and a tag per
text, and a tag names one text where the stamp's version names up to nine.

Rejected as the main source, open as an addition (question 1): **a pristine copy beside each job.**
It would be exact even for an install from `main` between bumps, which the archive cannot cover until
the next bump. But it would do nothing for the jobs already in studies, it can be edited or deleted,
and it doubles the files an analyst sees.

### 3. Finding the base: exact, then inferred, then none

In order, and the report says which one was used:

1. **Exact.** The stamp carries a hash, and the archive or `inst/templates/` has that text.
2. **Inferred.** The stamp carries a version but no hash. That is every job stamped from 1.3.x to
   1.4.2, the three above included. The candidates are the texts the index lists for that template at
   that version. Each is rendered into a job as in decision 4, and the one whose line diff against
   the job is smallest is the base. A tie goes to the **older** text, for the reason above. The
   report names the base as inferred, says how many candidates there were, and gives each carried
   hunk a line under "Carried" for the analyst to confirm.
3. **None.** No stamp, or a hash the archive has never seen (an install from `main` after the last
   bump). The upgrade falls back to today's behaviour: carry the choices, list the rest, with #383's
   description carry and "None." for empty sections. The report opens by saying that no base was
   found and that edits outside the choices were not carried. `upgrade_job(path, base = <file>)`
   lets an analyst name a base by hand: a template file from an old tag, say.

### 4. The base is rendered as add_job() would have written it

The archive holds template files, and the job is a template file after `add_job()`. Before the merge,
the base goes through the same steps `add_job()` took: `SUBJECT` and `TYPE` take the job's values,
and the job's own stamp line is inserted where `.stamp_job()` puts it. The steps are shared code, a
`.scaffold_lines(template_lines, subject, type, stamp)` that `add_job()` itself calls, so the two
cannot drift apart.

That way the lines `add_job()` writes are never seen as study edits. The stamp line differs only
between base and template, so it takes the template's new stamp, and the upgraded job then names the
version it now descends from.

### 5. Choices are merged as units, and always carry the job's value

Run naively, a line merge of the choices block conflicts all the time. The block is dense, and the
template often rewords a comment or adds a choice right beside a line the study changed. Before
the merge, each top-level choice in an `edit-*` chunk, its whole lines including a trailing comment,
is replaced in all three texts by a single line `#<<upgrade_job choice NAME>>`. After the merge, each
such line gets the job's text back.

This is today's rule (decision 3 of the 2026-10-12 design): a choice is the study's decision, even
when it was left at the default. So a template that changes a default never moves a job's choice in
silence. The report gets a new line for that case: "`NAME`: the template's default changed; the job
keeps its value." Unplaced, new and duplicated choices are handled as today, from the same
`.job_choices()` parse.

The comment lines above a choice are merged line by line. The study's note above `PREDICTORS` is
kept, and so is a reworded template comment the study had not touched. When the study deleted an
`EDIT:` line and the template reworded it, the conflict resolves to the deletion, because a marker
the study resolved stays resolved, as today. The report lists each one under "Markers resolved in the
old job".

A choice line holding two statements (`A <- 1; B <- 2`) cannot be masked as one unit. The upgrade
stops and names the line, rather than guessing.

### 6. Conflicts stop the upgrade, loudly, and the job will not render

- The upgraded job is written with `git merge-file --diff3` markers labelled
  `<<<<<<< job`, `||||||| template <old version>`, `=======` and `>>>>>>> template <new version>`.
  The base section shows the analyst what the template used to say.
- The backup and the report are written too. Then `upgrade_job()` signals an error of class
  `hvtiRtemplates_upgrade_conflict`, naming the count and the report. That is an error a script
  cannot step past.
- `.job_setup()` gets a guard that refuses to render a job holding a `^<<<<<<< job$` or
  `^>>>>>>> template ` line, in a draft or a final render alike. A marker in a prose paragraph would
  otherwise render without complaint, and a marker in a chunk would fail with a parse error that
  names no cause.
- A second `upgrade_job()` on a job that still holds conflict markers refuses.

**Engine: `git merge-file`.** It is very likely on lri, since studies there carry `.git` folders
even though nobody uses them; `git --version` on lri confirms it before implementation. It is on
every CI runner and on a Mac with the command-line tools. It returns the conflict count as
its exit status. An R diff3 would mean writing and maintaining a Myers diff, which is the kind of
code that is subtly wrong for a year. `SystemRequirements` gains git, and an install without it
gets a clear error from `upgrade_job()` naming the fallback. Open as question 2.

### 7. Backups and reports never collide

The old job is kept as `<job>.qmd.pre-upgrade-<YYYY-MM-DD>` and the report is
`<stem>-upgrade-<YYYY-MM-DD>.md`. A second upgrade the same day gets `-2`, then `-3`. Neither name ends
in `.qmd`, so neither renders. The refusal is still there, but it moves from "this fixed name exists"
to "no free name", which cannot happen in practice. Files made by the current naming (undated) are
left alone and no longer block. Each report names the backup it belongs to, so the pair is never
ambiguous. `migrate_job()`'s `-migration.md` takes the same helper; question 3.

### 8. The report says what the merge did, and what will refit

New sections, alongside today's Carried / Not placed / New / Markers left. Each names chunk labels
and line ranges, never values:

- **Base**: exact (with hash), inferred (with candidate count), or none (with what that means).
- **Carried from the job**: each hunk of the job's own edits kept outside the choices, by chunk and
  line range. In case 2 this is where the analyst sees `tbl-data` and the `partial.plot()` chunk.
- **Conflicts**: by chunk and line range in the upgraded job, or "None."
- **Will refit**: every chunk that calls `cache_fit()` whose code text changed in the upgrade.
  `cache_fit()` keys on the code text, so the next render refits it, and for a boostmtree job that is
  half an hour to hours. Adding `progress =` to a fit call is exactly such a change, whether the
  template or the study adds it.

## Interactions

- **#383** (open) should merge first. Its "None." for empty lists stays in every report, and its
  description carry stays as the fallback for decision 3.3. Once a base is found, the merge carries
  the description and the notes above choices on its own, so #383's heuristics and its notes-above-
  choices listing are skipped in that path, not deleted.
- **`progress =` and the cache key.** The merge cannot keep a fit's cache valid when the fit call's
  text changes, and should not try. "Will refit" makes the cost visible before the render. A
  separate point for the job-progress work: the templates could pass the callback through `get()`,
  as they already do for `CORES`, so that adding it does not key the fit. That belongs to that design,
  not here.
- **`migrate_job()`** writes its output through `add_job()`, so a migrated job is stamped, now with a
  hash, and its later upgrades find an exact base. Everything the converter filled in counts as the
  study's edits, which is right. Nothing else changes there.
- **Runners** stay out of scope, as in the 2026-10-12 design.

## Tests

Synthetic only. The three real `.pre-upgrade` files can hold patient-adjacent values and do not
leave the share. Each test is driven through an internal seam,
`.upgrade_merge(job, base, template)`, from small texts the test writes. That way a test does not go
stale when a real template is edited, which is the AGENTS.md rule for catalog-dependent branches. One
end-to-end test runs `upgrade_job()` on a job scaffolded from an archived `nb.boostmtree` text.

| test | reproduces | goes red when |
|---|---|---|
| description prose replacing the template's opening `EDIT:` comment is kept | case 1 | the merge is replaced by today's rebuild |
| a two-line note above a choice is kept, and the template's reworded comment on another choice lands | case 1 | same |
| an added line in a non-`edit` chunk (`d[[.response]][...] <- 2`) is kept verbatim, and the template's change three lines below lands | case 2 | same |
| an argument added inside a call (`n.points = 10`) is kept | case 2 | same |
| an inline comment on a choice line is kept | case 2 | masking drops trailing comments |
| study changes a value, template rewords the comment above it and adds a choice beside it: no conflict | decision 5 | masking is removed |
| template changes a default the job left alone: the job keeps its value, and the report says so | decision 5 | the job takes the template's default |
| both sides change one line: error of class `hvtiRtemplates_upgrade_conflict`, markers in the file, backup and report written, conflict listed | decision 6 | the merge takes either side |
| `.job_setup()` stops on a job with conflict markers, draft or final | decision 6 | the guard is removed |
| two upgrades in one day write `-2` names and overwrite nothing; an undated `.pre-upgrade` does not block | case 3 | naming reverts to the fixed name |
| a stamp without a hash, three candidates: the closest is chosen, a tie goes to the older, the report says inferred | decision 3 | the newest candidate is taken |
| the newer-base hazard: job at A, candidates A and B, template C; the template's change lands | decision 3 | same |
| no stamp: today's behaviour, and the report opens with "no base" | decision 3 | the fallback is removed |
| every archive entry's text hashes to its key | decision 2 | the archive is hand-edited |
| a fit chunk whose code changes is listed under "Will refit" | decision 8 | the section is removed |

"Goes red" is the mutation to run. Each is reverted in a scratch commit and the named tests must fail
before the change is called done.

A last check against the real failures, run by John on lri (never from the Mac): upgrade a copy of each
of the three jobs' `.pre-upgrade` files in `/studies/general/_development`. The grade collapse,
`n.points = 10`, the PREDICTORS note and the description must come through, and conflicts must be
listed rather than resolved.

## Out of scope

- Merging at a finer grain than lines. The `progress =` / `mtry = MTRY` conflict above sits on one
  line, and an argument-aware merge could resolve it. It could also resolve it wrongly, and a conflict
  is cheap to read.
- Upgrading runners; batch upgrades.
- Backfilling hashes into existing stamps. Inference covers them, and rewriting a study's job to add
  a hash is an edit nobody asked for.

## Questions for John

1. **A pristine copy as well?** Recommended: **no** for now. The archive covers every released text
   and every text on `main` up to the last bump. The gap is a job scaffolded from a `main` install
   between bumps whose template changes before the next bump. It is real, and it falls to "inferred"
   or "none", both loud. If it bites, a study-level `.hvtiRtemplates/bases/<sha>.qmd` (one file per
   text, not per job) closes it.
2. **`git merge-file` or an R diff3?** Recommended: git, for the reasons in decision 6.
3. **Give `migrate_job()` the dated names too?** Recommended: yes, the same helper and a few lines,
   so the two reports do not follow two conventions.
4. **Version.** This changes an exported function's behaviour. It ships as a patch under the current
   minor, unless you want it to be the change that opens the next one.
