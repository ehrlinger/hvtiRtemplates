# upgrade_job() three-way merge: implementation plan

Design: [`2026-10-22-upgrade-job-merge-design.md`](2026-10-22-upgrade-job-merge-design.md). **Do not
start until John has approved the design and answered its four questions.** Branch from `origin/main`
after #383 has merged, in a worktree of its own. Every task is test-first: write the test, watch it
fail for the right reason, then write the code.

## Task 0: confirm the ground

- Questions 1 and 3 answered. (2 and 4 are settled: an R diff3, and the next minor, 1.5.0.)
- Confirm #383 is on `main` and read its final `.upgrade_report()`, because tasks 6 and 7 build on it.

## Task 1: shared scaffolding steps (decision 4)

- Pull the `SUBJECT`/`TYPE` substitution and the stamp insertion out of `add_job()` into
  `.scaffold_lines(lines, subject, type, stamp)` in `R/add-job.R`. `add_job()` calls it, and its
  behaviour does not change.
- Test: `add_job()` output is byte-identical before and after (snapshot one template's output first).

## Task 2: the hash in the stamp (decision 1)

- `.stamp_job()` writes `sha256:<hex>` of the template file as shipped. Widen the stamp regex in
  `.upgrade_report()` to read both forms.
- Tests: a new job's stamp hash equals `digest::digest(file = template, algo = "sha256")`, and an old
  stamp without a hash still parses.

## Task 3: the template archive (decision 2)

- `dev/template-history/build.R`: walk **every** commit of `git rev-list --first-parent d3b741e~1..HEAD`,
  with no path filter, so that a bump commit that changes no template still maps its texts to the new
  version (review finding 2). At each commit, read `Version:` and every `.qmd` under `inst/templates/`.
  Record each (template, version, text hash) triple with first and last commit dates, store each text
  once by hash, and write `inst/extdata/template-history.rds` (`compress = "xz"`).
- `.template_history()` reads it once per session. `.base_candidates(template, version, hash)`
  returns the exact text, or the candidates for a version, or none; it reads `inst/templates/` as well.
- Add the `build.R` run to the bump procedure beside `news.py collect` (`.claude/house-style.md`'s
  source in the vault, then recompose; `AGENTS.md`'s "Bump when you name a version").
- Tests: every entry hashes to its key; a hash that is present returns one text; a version returns
  its candidates oldest first; a fixture repo whose bump commit changes no template maps the text to
  both versions. Measure the tarball before and after: expect about +135 KB.

## Task 3b: the R diff3 (decision 6)

- `R/merge3.R`: `.line_diff(a, b)` (integer-map lines, trim the common prefix and suffix, LCS by
  dynamic programming) and `.merge3(job, base, template, labels)` returning the merged lines and the
  conflict list. Internal, no new dependency.
- Tests first: the law-based rows and the hand-written rows of the design's table. Mutate each branch
  of the region rule and confirm red.

## Task 4: the merge seam (decisions 5, 6)

- `.upgrade_merge(job, base, template, labels)` in `R/upgrade-job.R` returns the merged lines, the
  conflict ranges, the carried hunks and the resolved-marker list. Steps: mask choices in all three
  (stop on a two-statement line), call `.merge3()`, then check that the output is non-empty and that
  the conflict count matches the `<<<<<<< job` lines; any error aborts before any study file is
  touched (review finding 3). Unmask with the job's text,
  then auto-resolve conflicts that are only the deletion of `EDIT:` lines.
- Tests: the design's table rows for cases 1 and 2, masking, defaults, and marker resolution, each
  driven from small texts written in the test.

## Task 5: base resolution (decision 3)

- Exact, then inferred, then none. Inferred merges against **every** candidate and turns each region
  where the merged texts disagree into a conflict showing every outcome; no candidate is ranked
  (review finding 1). `upgrade_job()` gains
  `base = NULL`, a path to a template file to use as the base.
- Tests: the inference rows, the newer-base hazard row and review finding 1's strictly-closer case,
  from a temporary archive; and the engine-failure row (task 4).

## Task 6: conflicts stop the upgrade (decision 6)

- Write the job, the backup and the report, then signal `hvtiRtemplates_upgrade_conflict`. Refuse to
  upgrade a job that still holds conflict markers.
- Add the conflict guard to `.job_setup()` in `R/job-setup.R`, for draft and final renders alike.
- Tests: the conflict row and the guard row.

## Task 7: names and report (decisions 7, 8)

- `.free_name(stem, suffix, date)` returns the first free `...-YYYY-MM-DD[-N]`, treating a dangling
  symlink as taken (keep today's `taken()`). It is used for the backup and the report, and for
  `migrate_job()` if question 3 is a yes.
- Report sections: Base, Carried from the job, Conflicts, Cache may be stale (the fit's own chunk changed, or any code
  chunk before it did; worded as a possibility, with the `REFIT` behaviour), Markers resolved in the old job.
  Each names labels and lines, never values, and an empty section reads "None." (from #383).
- Update the roxygen in Rd markup: the `@description` paragraph on backups, `@details` on what is
  carried, and a `@section` on conflicts. Then run `devtools::document()`.
- Tests: the naming row and the refit row.

## Task 7b: one live copy (decision 9)

- `.job_setup()` refuses to render when another spelling of the same job (current, pre-2026-10,
  renamed-template) sits in the study, naming both and the newer by mtime.
- The "another copy" refusal in `upgrade_job()` and `add_job()` lists both paths, mtimes, stamps and
  the names of choices whose values differ. The success message warns that a buffer still open under
  the old name must be closed unsaved.
- Tests: the two decision-9 rows, proven by removing the guard.

## Task 8: end-to-end and mutation

- One `upgrade_job()` test from a job scaffolded out of an archived `nb.boostmtree` 1.4.1 text, with
  the case 1 and case 2 edits applied, asserting each edit is either in the job or on the job side of
  a conflict.
- Run every mutation in the design's "goes red when" column in a scratch commit; record the result
  in the PR body.

## Task 9: gates

- `news/<branch>.md` fragment; no `Version:` edit.
- `devtools::document()`, `devtools::test()` in a private library with `NOT_CRAN=true` and
  `_R_CHECK_LIMIT_CORES_=TRUE`; `devtools::check()` 0/0/0; `lintr::lint_package()` clean at 135
  columns.
- Local `/code-review` (Copilot's quota is exhausted), and say so in the PR body.
- Hand John the lri check from the design's Tests section: copies in `/studies/general/_development`,
  never the study folders.
