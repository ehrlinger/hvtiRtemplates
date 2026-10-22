# upgrade_job(): carry every study edit by a three-way merge

Status: **design merged 2026-10-22 (#384).** John settled questions 2 (an R diff3, no git at run time) and
4 (it opens the next minor) the same day, then 1 (no pristine copy) and 3 (dated names for `migrate_job()`):
**approved, all four questions settled.** Supersedes decisions 4 ("prose is not carried") and 5 (fixed
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

So the base must be exact where it can be. Where it has to be inferred, choosing one candidate is not
safe by any rule: a closer text is not proof of ancestry (review finding 1, below). Decision 3 makes
the candidates agree before anything is carried silently.

## Decisions

### 1. The stamp records the template's content hash

From this change on, the stamp is `<!-- hvtiRtemplates: <template> <version> sha256:<64 hex> -->`. The
hash is of the template file as shipped, before `add_job()` writes `SUBJECT`, `TYPE` and the stamp.
Version alone stays readable for old jobs. `.upgrade_report()` already reads the stamp with a regex,
which this widens.

### 2. The package ships the history of its templates

The package ships `inst/extdata/template-history.rds`: every distinct template text that was on
`main` since `d3b741e`, keyed by SHA-256, with an index of (template name, package version, first
and last commit date). It is built from git by `dev/template-history/build.R` and needs nothing from the installed
package.

**The index is built over every first-parent commit, not only those that touch `inst/templates/`**
(review finding 2). A bump commit changes `Version:` and no template, so a walk filtered by path
skips it and indexes the unchanged text under the previous version, while a job scaffolded just
after the bump stamps the new one. Over `d3b741e~1..be576eb` the filtered walk visits 38 of 69
first-parent commits and loses two real pairs for `nb-boostmtree.qmd` alone (1.4.0 at `d39a5eb`,
1.4.1 at `d61ba9a`). The build therefore reads `Version:` and every template at **each** first-parent
commit from `d3b741e` (the first commit that stamps) onward, records every (template, version, text)
triple it sees, and stores each text once, by hash. The texts are deduplicated; the version index is
not.

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
   1.4.2, the three above included. The candidates are every text the index lists for that template
   at that version (decision 2 makes that list complete), each rendered into a job as in decision 4.
   **The upgrade merges against every candidate, not one.** Where the merges agree, the base did not
   matter there, and the merged text stands. Where they disagree, the region is written as a
   conflict that shows each outcome, so the analyst decides it, never a ranking.

   This replaces "the closest candidate, a tie to the older", which review finding 1 broke with a
   four-line counterexample. A job copied from A changed two choice values, and those same values
   happen to be B's defaults. That makes the newer B *strictly* closer, so no tie-break ever runs,
   and the merge against B exits 0 having undone the template's `strict = TRUE` in silence. Scoring
   with choices masked (decision 5) would fix that example, but not the general case: similarity is
   not ancestry. Agreement across all candidates needs no ranking at all.

   The cost is more conflicts when a version had many texts (nine for `nb.boostmtree` 1.4.1), and
   only in the regions where those texts differ. Choices are masked before every candidate merge, so
   they never disagree. The report names the base as inferred, gives the candidate count, and lists
   the disagreement conflicts separately from the job-against-template ones. An inferred upgrade with
   no disagreement and no conflict is still labelled inferred in the report, so a reader can tell it
   from an exact one.
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

- The upgraded job is written with diff3-style markers labelled
  `<<<<<<< job`, `||||||| template <old version>`, `=======` and `>>>>>>> template <new version>`.
  The base section shows the analyst what the template used to say.
- **An engine failure is not a conflict** (review finding 3). With the merge in R (below) there is
  no exit status to misread, the 255 trap the review found in `system2()`. The rule it led to still
  holds. The merge returns its lines and a conflict list. Before anything is written, the upgrade
  checks that the merged lines are non-empty and that the conflict count equals the number of
  `<<<<<<< job` lines. Any error inside the merge aborts **before any study file is touched**, as
  today's code already computes the upgrade before renaming anything.
- The backup and the report are written too. Then `upgrade_job()` signals an error of class
  `hvtiRtemplates_upgrade_conflict`, naming the count and the report. That is an error a script
  cannot step past.
- `.job_setup()` gets a guard that refuses to render a job holding a `^<<<<<<< job$` or
  `^>>>>>>> template ` line, in a draft or a final render alike. A marker in a prose paragraph would
  otherwise render without complaint, and a marker in a chunk would fail with a parse error that
  names no cause.
- A second `upgrade_job()` on a job that still holds conflict markers refuses.

**Engine: a diff3 in R, settled by John on 2026-10-22: git is not used at run time.** It lives in
`R/merge3.R` and is internal, with no new dependency and no `SystemRequirements` change.

- **The line diff.** Lines are mapped to integers. The common prefix and suffix are trimmed, which
  leaves a few dozen lines for a typical job against its template. A longest common subsequence is
  then found by dynamic programming over what remains. Its cost is the product of the two lengths:
  trivial after the trim, and still about a second for a whole 1,000-line file in the worst case.
- **The merge.** The standard diff3 rule over the two diffs from the base (Khanna, Kunal and Pierce,
  2007, "A formal investigation of diff3"). Stable regions, where base, job and template agree,
  separate the unstable ones. In an unstable region: job unchanged gives the template's text,
  template unchanged gives the job's, both the same gives either, and both different gives a
  conflict. Adjacent changes conflict, as they do in diff3, which errs toward stopping.
- **The risk the earlier draft named**, that a hand-written diff is subtly wrong, is met by tests
  rather than by an oracle (see Tests): the algebraic laws every three-way merge obeys, checked over
  generated texts, and hand-written expected outputs for the real cases.

### 7. Backups and reports never collide

The old job is kept as `<job>.qmd.pre-upgrade-<YYYY-MM-DD>` and the report is
`<stem>-upgrade-<YYYY-MM-DD>.md`. A second upgrade the same day gets `-2`, then `-3`. Neither name ends
in `.qmd`, so neither renders. The refusal is still there, but it moves from "this fixed name exists"
to "no free name", which cannot happen in practice. Files made by the current naming (undated) are
left alone and no longer block. Each report names the backup it belongs to, so the pair is never
ambiguous. `migrate_job()`'s `-migration.md` report and any backup it keeps take the same helper (question 3, settled yes).

### 8. The report says what the merge did, and what will refit

New sections, alongside today's Carried / Not placed / New / Markers left. Each names chunk labels
and line ranges, never values:

- **Base**: exact (with hash), inferred (with candidate count), or none (with what that means).
- **Carried from the job**: each hunk of the job's own edits kept outside the choices, by chunk and
  line range. In case 2 this is where the analyst sees `tbl-data` and the `partial.plot()` chunk.
- **Conflicts**: by chunk and line range in the upgraded job, or "None."
- **Cache may be stale** (review finding 4; this was "Will refit"). It lists every chunk that calls
  `cache_fit()` and either changed itself or comes after any changed code chunk, the fit's own and
  upstream ones like `tbl-data` alike. That is a static guess and the report says so. `cache_fit()`
  keys on the code text, the values the call reads, the seed and package versions, so the upgrade
  cannot tell whether a fit will go stale. A listed fit may still match, and an unlisted fit is not
  promised valid. It also does not refit by itself. With the shipped `REFIT <- FALSE`, a stale cache
  stops the render with `hvtiRutilities_stale_cache` until the analyst sets `REFIT`. The section
  says that too, because for a boostmtree fit the refit is half an hour to hours. Adding
  `progress =` to a fit call is one such change, whether the template or the study adds it.

### 9. A job renamed by an upgrade has one live copy

The fourth real failure, in study #1356's `descriptive/`. On 10-20 `upgrade_job()` moved
`cohort-eda-dc-tables.qmd` to the new spelling, `dc.tables.cohort.eda.qmd`. By 10-21 the old-named file
was live again: the study set `BY` and `COMPARE` in it and rendered it, while the new-named copy stayed
at its defaults. On 10-22 the upgrade of the live file refused with "is another copy of this job" and
did not say which copy was live. The stale one was moved aside by hand
(`dc.tables.cohort.eda.qmd.stale-20261020`).

`upgrade_job()` renames the old job and never copies it; every version on `main` does
`file.rename(path, backup)`. So the old name came back from outside the function. The likeliest
causes are an editor saving a buffer it still had open under the old path, or the backup renamed back
by hand. That cannot be checked from here, since the 10-20 `.pre-upgrade` is no longer in the folder.
Either way the function cannot stop it at upgrade time. So the fix has two parts:

- **Rendering refuses two copies.** `.job_setup()` already knows the job's fields. It refuses to render
  a job when another spelling of the same job exists beside it, and names both files and which one
  was modified more recently. A render of either copy then stops on the day the split happens, not
  two days later. This rule is enforced at render time, so it holds whatever recreated the file.
  A stub left at the old name was considered and rejected: the editor's next save overwrites it, and
  the stub would itself count as "another copy".
- **The refusal says which copy is live.** "Another copy" in `upgrade_job()` and in `add_job()` lists
  both paths with their modification times and their stamps, plus the **names** of the choices whose
  values differ between them (never the values). Then it suggests the step: move the stale copy aside,
  then upgrade the live one.

`upgrade_job()` also opens the renamed job in the editor already (`.open_in_editor()`). Its message says
that the old name is now the backup, and that a buffer still open under the old name must be closed
without saving.

Tests: two spellings present make `.job_setup()` stop and name both; the refusal lists differing choice
names and not their values; mutation, removing the guard, turns the first red.

## Interactions

- **#383** (open) should merge first. Its "None." for empty lists stays in every report, and its
  description carry stays as the fallback for decision 3.3. Once a base is found, the merge carries
  the description and the notes above choices on its own, so #383's heuristics and its notes-above-
  choices listing are skipped in that path, not deleted.
- **`progress =` and the cache key.** The merge cannot keep a fit's cache valid when the fit call's
  text changes, and should not try. "Cache may be stale" makes the risk visible before the render. A
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
| a stamp without a hash, three candidates that agree in a region: that region merges cleanly; where they disagree it is a conflict showing each outcome; the report says inferred | decision 3 | one candidate is used |
| the newer-base hazard: job at A, candidates A and B, template C; the template's change lands | decision 3 | same |
| review finding 1's case: job's choice values equal newer B's, so B is strictly closer; the `strict` change becomes a conflict, not a silent revert | decision 3 | one candidate is ranked and used |
| an engine failure (the merge forced to error, or to return a count that disagrees with its markers): error before anything is written; job, backups and reports byte-identical | decision 6 | the consistency check is removed |
| diff3 laws over generated texts (a few hundred seeded cases): merge(x, b, b) = x, merge(b, b, y) = y, merge(x, b, x) = x, swapping job and template swaps the conflict sides only, and a clean merge's output, diffed against base, holds every change from both sides | decision 6 | any branch of the region rule is altered |
| hand-written expected outputs: insert/insert at one place, delete against edit, adjacent edits, edits at the first and last line, an empty base | decision 6 | same |
| an archive built over a bump commit that changes no template maps the text to both versions | decision 2 | the walk is filtered by path |
| no stamp: today's behaviour, and the report opens with "no base" | decision 3 | the fallback is removed |
| every archive entry's text hashes to its key | decision 2 | the archive is hand-edited |
| a fit chunk whose code changes, and one whose code is unchanged but follows a changed `tbl-data`, are both listed under "Cache may be stale" | decision 8 | only the fit chunk's own text is compared |

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

1. ~~A pristine copy as well?~~ **Settled 2026-10-22: no pristine copy.** `add_job()` writes none. The archive covers every released text
   and every text on `main` up to the last bump. The gap is a job scaffolded from a `main` install
   between bumps whose template changes before the next bump. It is real, and it falls to "inferred"
   or "none", both loud. If it bites, a study-level `.hvtiRtemplates/bases/<sha>.qmd` (one file per
   text, not per job) closes it.
2. ~~`git merge-file` or an R diff3?~~ **Settled 2026-10-22: an R diff3; git is not used at run
   time.** Decision 6. The archive in decision 2 is still built from this repo's git history, by a dev
   script at bump time in the repo itself, never in a study and never by `upgrade_job()`.
3. ~~Give `migrate_job()` the dated names too?~~ **Settled 2026-10-22: yes.** The same helper
   (decision 7) names its backup and `-migration-<date>.md` report, so the two follow one convention.
4. ~~Version.~~ **Settled 2026-10-22: it opens the next minor.** John's decision, per the versioning
   rule: the bump that ships it is 1.5.0, and the change lands without touching `Version:`.
