# hvtiRtemplates Repository Implementation Plan

> **Migrated 2026-08-18** from `/Volumes/qhsstudies/cardiac/valves/aortic/replacement/pericardial/lv_function/survival/analyses/R_hazard/docs/plans/2026-08-13-hvtirtemplates-repository.md`.
> Cross-references to the other migrated documents have been repointed to their
> paths in this repository; the text is otherwise unchanged. Study folders on the
> share do not host git repositories, so the design record lives with the package
> that owns the migration programme. `specs/artifacts/README.md` records what
> moved and from where.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create `hvtiRtemplates` as a versioned R package repository that carries the institutional SAS template corpus and the SAS macro library under git, preserving the macro library's existing 2014–2019 history, and exposing the corpus through `template_list()` and `corpus_manifest()`.

**Architecture:** A GitHub-installed R package whose `inst/` holds three trees: `templates/` (supported R templates, seeded in stage 3), `corpus/` (the SAS and legacy-R reference specification), and `macros/` (the SAS macro library, imported with `git subtree` so its commit history survives). Import happens before any cleaning, so every removal is a reviewable `git rm` rather than a file that silently never arrived.

**Tech Stack:** R (>= 4.1.0), `usethis`, `testthat` (3rd edition), `roxygen2`, git, `gh` CLI.

**Spec:** `dev/specs/2026-08-13-templates-and-provenance-design.md`, stage 2 of section 12.

## Global Constraints

- **Version is `1.0.0`.** A straight three-digit semantic version. Never a `.9000` suffix, never a fourth digit. Do not roll the MINOR or MAJOR digit in this plan; patch bumps only if a version-grep test requires one, and surface it if so.
- **Never push directly to `main`.** After Task 1 creates the repository, all work happens on branch `feat/import-corpus` and lands through a PR. If a push is rejected for requiring a pull request, stop — do not force-push.
- **Import before cleaning, always.** Never filter, exclude, or `.gitignore` a file during import in order to avoid committing it. Import everything, then remove it in a separate commit. A removal is recoverable; a file that was never committed is not. This is the plan's central rule.
- **`macro.library`'s git history must be preserved.** Its 357 commits (2014-09-19 to 2019-05-01) are the only surviving macro provenance. Use `git subtree add`, never `cp -r` followed by `git add`.
- **Nothing in this plan writes to the study tree** at `/Volumes/qhsstudies/...`. That tree is NO GIT and out of scope. This plan's only interaction with it is reading this document.
- **Nothing in this plan modifies `~/Documents/template`.** It is read-only source. `~/Documents/macro.library` is written exactly once, in Task 2, to capture its uncommitted delta.
- **`inst/corpus/` and `inst/macros/` are reference specification, not runnable assets.** No task makes them executable, tested, or supported. The institutional SAS licence expires 2026-09-29.
- **No PHI** in any file, commit message, or test fixture. The corpus is code and macros only; if any file is found to contain patient data, stop and report rather than committing it.

## Source Inventory

Measured 2026-08-13. Verification steps below depend on these numbers; if a count differs when the task runs, stop and report rather than adjusting the expectation.

**`~/Documents/template`** — no version control, 11 MB

| | Count |
|---|---|
| All files (excluding `.Rproj.user/`) | 450 |
| Inside `*/templates/` directories | 417 |
| — `.sas` | 242 |
| — R-family (`.R` `.r` `.qmd` `.Rmd` `.rmd` `.Rnw` `.S`) | 126 |
| — office / PDF / binary | 35 |
| — under an `archive/` subdirectory | 59 |
| Outside `*/templates/` (READMEs, reference docs) | 33 |

**`~/Documents/macro.library`** — git repo, no remote, branch `master`, 3 MB

| | Count |
|---|---|
| Files excluding `.git/` | 579 |
| Files excluding `.git/` and `CVS/` | 565 |
| Editor/VCS cruft (`*~`, `*.BAK`, `.DS_Store`) | 42 |
| Git-tracked | 522 |
| Uncommitted working-tree changes | 255 |
| Commits | 357 (`2014-09-19` → `2019-05-01`) |

## File Structure

**Created (in the new `hvtiRtemplates` repository):**

| Path | Responsibility |
|---|---|
| `DESCRIPTION` | package metadata; version `1.0.0` |
| `NAMESPACE` | roxygen-generated |
| `NEWS.md` | version log; line 2 carries the exact `DESCRIPTION` version |
| `.Rbuildignore` | excludes dev files from the tarball |
| `.gitignore` | R package standard |
| `LICENSE` / `LICENSE.md` | GPL-3, matching `hvtiRutilities` |
| `R/corpus.R` | `corpus_manifest()`, `corpus_path()` |
| `R/templates.R` | `template_list()`, `template_path()` |
| `R/taxonomy.R` | the prefix → folder → description table, as data |
| `inst/templates/` | supported R templates; holds only `README.md` until stage 3 |
| `inst/corpus/sas/` | 242 `tp.*.sas`, study-folder structure preserved |
| `inst/corpus/r/` | 126 legacy R-family templates, structure preserved |
| `inst/corpus/assets/` | 35 office/PDF/binary assets |
| `inst/corpus/docs/` | the 33 files outside `templates/` — READMEs and reference documents |
| `inst/macros/` | the macro library, imported with history |
| `tests/testthat/test-taxonomy.R` | taxonomy is complete and internally consistent |
| `tests/testthat/test-corpus.R` | corpus file counts match a recorded expectation |
| `tests/testthat/test-templates.R` | `template_list()` agrees with `inst/templates/` |
| `man/` | roxygen-generated |
| `README.md` | what the package is; the reference-not-runnable statement |

**Layout note.** The spec's section 3.2 sketched `inst/sas/` and `inst/macros/`. This plan refines that to `inst/corpus/{sas,r,assets,docs}/` plus `inst/macros/`, because the corpus is not only SAS — 126 legacy R-family files carry the same reference value and the same non-runnable status. The distinction that matters is *supported* (`inst/templates/`) versus *reference* (`inst/corpus/`), not SAS versus R.

**Study-folder structure is preserved inside `inst/corpus/`** (`analyses/`, `datasets/`, `descriptive/`, `distributions/`, `documents/`, `graphs/`). The prefix → folder mapping is encoded in that layout, and Task 8's taxonomy table is checked against it.

---

### Task 1: Create the package skeleton and the repository

**Files:**
- Create: `~/Documents/GitHub/hvtiRtemplates/DESCRIPTION`
- Create: `~/Documents/GitHub/hvtiRtemplates/NEWS.md`
- Create: `~/Documents/GitHub/hvtiRtemplates/.Rbuildignore`
- Create: `~/Documents/GitHub/hvtiRtemplates/.gitignore`
- Create: `~/Documents/GitHub/hvtiRtemplates/README.md`

**Interfaces:**
- Consumes: nothing
- Produces: a git repository at `~/Documents/GitHub/hvtiRtemplates` on branch `main`, with a GitHub remote, that passes `R CMD check` as an empty package

- [ ] **Step 1: Create the directory and initialise git**

```bash
mkdir -p ~/Documents/GitHub/hvtiRtemplates && cd ~/Documents/GitHub/hvtiRtemplates && git init -b main
```

Expected: `Initialized empty Git repository`.

- [ ] **Step 2: Write `DESCRIPTION`**

Matches the field order and style of `~/Documents/GitHub/hvtiRutilities/DESCRIPTION`.

```
Package: hvtiRtemplates
Type: Package
Title: Analysis Job Templates and the Legacy SAS Corpus for the HVTI CORR Group
Version: 1.0.0
Date: 2026-08-13
Authors@R: c(
    person(
      "John", "Ehrlinger",
      email = "john.ehrlinger@gmail.com",
      role = c("aut", "cre")
    )
  )
Maintainer: John Ehrlinger <john.ehrlinger@gmail.com>
License: GPL-3
Encoding: UTF-8
URL: https://github.com/ehrlinger/hvtiRtemplates
BugReports: https://github.com/ehrlinger/hvtiRtemplates/issues
Description: Versioned analysis job templates for the clinical investigations
  statistics group within The Heart \& Vascular Institute at the Cleveland
  Clinic. Also carries the legacy SAS template corpus and SAS macro library as
  a reference specification, so that the behaviour reproduced by the R
  templates has a citable source under version control.
Depends:
    R (>= 4.1.0)
Suggests:
    testthat (>= 3.0.0)
Config/testthat/edition: 3
RoxygenNote: 7.3.2
```

- [ ] **Step 3: Write `NEWS.md`**

Line 2 must carry the exact `DESCRIPTION` version — a later version-grep test depends on it.

```markdown
# hvtiRtemplates
Version: 1.0.0

## hvtiRtemplates 1.0.0

* Initial release.
* Carries the legacy SAS template corpus (417 files) and the SAS macro
  library (579 files, history from 2014) as a reference specification.
```

- [ ] **Step 4: Write `.gitignore`**

```gitignore
.Rproj.user
.Rhistory
.RData
.Ruserdata
*.Rproj
docs/
inst/doc
.DS_Store
```

- [ ] **Step 5: Write `.Rbuildignore`**

```
^.*\.Rproj$
^\.Rproj\.user$
^\.github$
^README\.Rmd$
^LICENSE\.md$
^docs$
^_pkgdown\.yml$
```

- [ ] **Step 6: Write a placeholder `README.md`**

```markdown
# hvtiRtemplates

Versioned analysis job templates for the HVTI CORR group, plus the legacy SAS
template corpus and macro library as a reference specification.

Full documentation is added in Task 9.
```

- [ ] **Step 7: Add the GPL-3 licence**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && Rscript -e 'usethis::use_gpl3_license()'
```

Expected: writes `LICENSE.md` and adds a `License:` field already present in `DESCRIPTION` (no change there).

- [ ] **Step 8: Verify it checks as an empty package**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && R CMD build . && R CMD check hvtiRtemplates_1.0.0.tar.gz --no-manual
```

Expected: `Status: OK`, or NOTEs only. Any WARNING or ERROR stops the task.

```bash
cd ~/Documents/GitHub/hvtiRtemplates && rm -f hvtiRtemplates_1.0.0.tar.gz && rm -rf hvtiRtemplates.Rcheck
```

- [ ] **Step 9: Commit and create the GitHub repository**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git add -A && git commit -m "feat: hvtiRtemplates package skeleton

Versioned home for analysis job templates and for the legacy SAS corpus,
which has never been under version control. Empty of content; the corpus
imports follow."
```

```bash
cd ~/Documents/GitHub/hvtiRtemplates && gh repo create ehrlinger/hvtiRtemplates --private --source=. --remote=origin --push
```

Expected: repository created, `main` pushed. This is the one commit that lands on `main` directly — it creates the branch. Everything after this goes through a PR.

- [ ] **Step 10: Create the working branch**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git checkout -b feat/import-corpus
```

---

### Task 2: Capture the macro library's uncommitted delta

**Files:**
- Modify: `~/Documents/GitHub/hvtiRtemplates` — none
- Modify: `~/Documents/macro.library` — one commit on `master`

**Interfaces:**
- Consumes: nothing
- Produces: `~/Documents/macro.library` with a clean working tree, so Task 3's `git subtree add` imports the current state rather than the 2019 state

This runs before any import. The 255 uncommitted changes are the 2019→2026 delta and exist in exactly one place; a subtree import of `master` would silently omit every one of them.

- [ ] **Step 1: Record what is about to be committed**

```bash
cd ~/Documents/macro.library && git status --porcelain | awk '{print $1}' | sort | uniq -c
```

Expected: a mix of `M` (modified) and `??` (untracked) totalling 255. Record the breakdown — Step 4 verifies against it.

- [ ] **Step 2: Confirm no PHI and no large binaries entered the tree**

```bash
cd ~/Documents/macro.library && git status --porcelain | awk '{print $2}' | while read -r f; do
  [ -f "$f" ] && find "$f" -size +2M -printf '%s\t%p\n' 2>/dev/null
done
```

Expected: no output. **If any file over 2 MB appears, stop and report** — the macro library is source code and a large binary is a sign something else was copied in.

```bash
cd ~/Documents/macro.library && git status --porcelain | awk '{print $2}' | grep -iE '\.(sas7bdat|xpt|csv|xlsx)$'
```

Expected: no output. Those extensions are data, and data must not enter this repository. **If any appear, stop and report.**

- [ ] **Step 3: Commit everything**

```bash
cd ~/Documents/macro.library && git add -A && git commit -m "chore: capture working-tree state as of 2026-08-13

The cron that produced this repository's daily commits stopped on
2019-05-01. Everything since then sat uncommitted in the working tree and
existed nowhere else. This commit captures that delta as one lump before the
directory is imported into hvtiRtemplates.

The lump is not attributable to dates within 2019-2026; it is a single
observation of the end state. That limit is recorded in the spec."
```

- [ ] **Step 4: Verify the tree is clean**

```bash
cd ~/Documents/macro.library && git status --porcelain | wc -l && git log --oneline -1
```

Expected: `0`, then the new commit. Tracked file count should now be 579 minus any `.gitignore`d paths:

```bash
cd ~/Documents/macro.library && git ls-files | wc -l
```

Expected: `579`. If it is lower, a `.gitignore` is excluding files — read it and report before continuing, because the plan's central rule is that nothing is excluded at import time.

---

### Task 3: Import the macro library with its history

**Files:**
- Create: `~/Documents/GitHub/hvtiRtemplates/inst/macros/` (579 files, via subtree)

**Interfaces:**
- Consumes: the clean `macro.library` from Task 2
- Produces: `inst/macros/` populated, and `git log -- inst/macros` showing commits back to 2014-09-19

- [ ] **Step 1: Add the macro library as a subtree**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git subtree add --prefix=inst/macros ~/Documents/macro.library master
```

Expected: `Added dir 'inst/macros'`. This creates a merge commit that grafts all 358 commits of history under the prefix.

**If this fails with "working tree has modifications", commit or stash first.** Do not fall back to `cp -r` — the history is the point of the task.

- [ ] **Step 2: Verify the history came across**

**Do not filter by pathspec.** `git subtree add` grafts the imported history with its *original* root-level paths — the 2014 commit that added `kaplan` records it as `kaplan`, not `inst/macros/kaplan`. So `git log -- inst/macros` matches only the merge commit and reports `1`, on a correct import as well as a broken one. It is not a usable check.

Verify against the branch instead:

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git rev-list --count HEAD
```

Expected: `362` — Task 1's two commits, the macro library's 359, and the subtree merge.

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git log --format='%ad %h %s' --date=short | sort | head -1
```

Expected: `2014-09-19 58489ae Initial Repository Commit`. **This is the verification that matters**: it proves the import preserved provenance rather than flattening it.

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git log --format='%h %p %s' -1 HEAD
```

Expected: a merge commit with **two** parents — Task 1's HEAD and `macro.library`'s HEAD. One parent means the history did not graft.

- [ ] **Step 3: Verify the file count**

Check the commit tree, not the working directory:

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git ls-tree -r HEAD --name-only inst/macros | wc -l
```

Expected: `552` — `git subtree add` imports *tracked* files only, and `macro.library`'s SAS-era `.gitignore` leaves 27 present files untracked (8 data files and ~8 binary documents deliberately, per the Task 2 decision; the rest editor backups).

```bash
cd ~/Documents/GitHub/hvtiRtemplates && find inst/macros -type f | wc -l
```

Expected on macOS: `549`, three fewer than the tree. This is **not** a defect. Three file pairs in the source differ only by case (`CR_CIF_CP_variance.sas~` and `.SAS~`, and two others), which git indexes separately but which collide on a case-insensitive APFS volume. All 552 are in the commit and all 552 check out on the case-sensitive Linux server. Verify rather than assume:

```bash
cd ~/Documents/GitHub/hvtiRtemplates && comm -23 <(git ls-tree -r HEAD --name-only inst/macros | sort) <(find inst/macros -type f | sort)
```

Expected: the three `.SAS~` paths and nothing else with a different basename. (A file whose name contains non-UTF8 bytes also appears here as a quoting artifact and is present on disk.)

- [ ] **Step 4: Verify a known macro is present and unchanged**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && head -3 inst/macros/kaplan && git log --oneline -- inst/macros/kaplan | wc -l
```

Expected: the header beginning `* <2003-10-17> This date is an upper bound on the last modified date`, and a commit count of `2` (its 2014 import plus the subtree merge). `kaplan` has never been modified, which is a useful fact for parity work.

- [ ] **Step 5: Commit**

`git subtree add` already committed. Verify and move on:

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git status --porcelain | wc -l && git log --oneline -1
```

Expected: `0`, and a commit named `Add 'inst/macros/' from commit ...`.

---

### Task 4: Import the SAS and legacy-R corpus

**Files:**
- Create: `~/Documents/GitHub/hvtiRtemplates/inst/corpus/sas/` (242 files)
- Create: `~/Documents/GitHub/hvtiRtemplates/inst/corpus/r/` (126 files)
- Create: `~/Documents/GitHub/hvtiRtemplates/inst/corpus/assets/` (35 files)
- Create: `~/Documents/GitHub/hvtiRtemplates/inst/corpus/docs/` (33 files)

**Interfaces:**
- Consumes: `~/Documents/template` (read-only)
- Produces: `inst/corpus/` holding all 450 source files, study-folder structure preserved

`~/Documents/template` has no version control, so there is no history to preserve — this is a plain copy. Everything is imported including cruft; Task 5 removes it in a reviewable commit.

- [ ] **Step 1: Create the destination directories**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && mkdir -p inst/corpus/{sas,r,assets,docs} inst/templates
```

- [ ] **Step 2: Copy the SAS corpus, preserving study-folder structure**

```bash
cd ~/Documents/template && find . -path '*/templates/*' -name '*.sas' -not -path './.Rproj.user/*' \
  | sed 's|^\./||' \
  | while read -r f; do
      dest=~/Documents/GitHub/hvtiRtemplates/inst/corpus/sas/$(echo "$f" | sed 's|/templates/|/|')
      mkdir -p "$(dirname "$dest")" && cp -p "$f" "$dest"
    done
find ~/Documents/GitHub/hvtiRtemplates/inst/corpus/sas -type f | wc -l
```

Expected: `242`. The `sed` drops the `templates/` level, so `distributions/templates/tp.hz.dead.sas` lands at `inst/corpus/sas/distributions/tp.hz.dead.sas`. `archive/` subdirectories are preserved.

- [ ] **Step 3: Copy the legacy R-family corpus**

```bash
cd ~/Documents/template && find . -path '*/templates/*' -not -path './.Rproj.user/*' \
  \( -name '*.R' -o -name '*.r' -o -name '*.qmd' -o -name '*.Rmd' -o -name '*.rmd' -o -name '*.Rnw' -o -name '*.S' \) \
  | sed 's|^\./||' \
  | while read -r f; do
      dest=~/Documents/GitHub/hvtiRtemplates/inst/corpus/r/$(echo "$f" | sed 's|/templates/|/|')
      mkdir -p "$(dirname "$dest")" && cp -p "$f" "$dest"
    done
find ~/Documents/GitHub/hvtiRtemplates/inst/corpus/r -type f | wc -l
```

Expected: `126`.

- [ ] **Step 4: Copy the binary and office assets**

```bash
cd ~/Documents/template && find . -path '*/templates/*' -not -path './.Rproj.user/*' \
  \( -name '*.pdf' -o -name '*.pptx' -o -name '*.pot' -o -name '*.doc' -o -name '*.docx' \
     -o -name '*.db' -o -name '*.html' \) \
  | sed 's|^\./||' \
  | while read -r f; do
      dest=~/Documents/GitHub/hvtiRtemplates/inst/corpus/assets/$(echo "$f" | sed 's|/templates/|/|')
      mkdir -p "$(dirname "$dest")" && cp -p "$f" "$dest"
    done
find ~/Documents/GitHub/hvtiRtemplates/inst/corpus/assets -type f | wc -l
```

Expected: `35`.

- [ ] **Step 5: Copy everything else — the remaining files inside `templates/`, and the 33 outside**

```bash
cd ~/Documents/template && find . -path '*/templates/*' -type f -not -path './.Rproj.user/*' \
  \( ! -name '*.sas' ! -name '*.R' ! -name '*.r' ! -name '*.qmd' ! -name '*.Rmd' ! -name '*.rmd' \
     ! -name '*.Rnw' ! -name '*.S' ! -name '*.pdf' ! -name '*.pptx' ! -name '*.pot' \
     ! -name '*.doc' ! -name '*.docx' ! -name '*.db' ! -name '*.html' \) \
  | sed 's|^\./||' \
  | while read -r f; do
      dest=~/Documents/GitHub/hvtiRtemplates/inst/corpus/docs/$(echo "$f" | sed 's|/templates/|/|')
      mkdir -p "$(dirname "$dest")" && cp -p "$f" "$dest"
    done

cd ~/Documents/template && find . -type f -not -path './.Rproj.user/*' -not -path '*/templates/*' \
  | sed 's|^\./||' \
  | while read -r f; do
      dest=~/Documents/GitHub/hvtiRtemplates/inst/corpus/docs/_root/$f
      mkdir -p "$(dirname "$dest")" && cp -p "$f" "$dest"
    done
find ~/Documents/GitHub/hvtiRtemplates/inst/corpus/docs -type f | wc -l
```

Expected: `47` — 14 leftovers from inside `templates/` (the `.bib`, `.yml`, `.md`, `.lst` and extensionless files) plus the 33 root-level files under `_root/`.

- [ ] **Step 6: Verify nothing was dropped**

```bash
echo "source: $(find ~/Documents/template -type f -not -path '*/.Rproj.user/*' | wc -l)"
echo "dest:   $(find ~/Documents/GitHub/hvtiRtemplates/inst/corpus -type f | wc -l)"
```

Expected: both `450`. **If they differ, stop and report** — a file matched no rule, and the plan's central rule is that nothing is dropped at import.

**Ten of the 450 will not be committed**, and that is correct. The repository's `.gitignore` excludes `.DS_Store`, `.Rhistory`, `.RData` and `*.Rproj`, which covers eight `.DS_Store` files, two `.Rhistory` files and `template.Rproj`. So Step 8 commits **440** files while 450 sit on disk.

This does not violate the import-before-cleaning rule. That rule protects *content* — a template, a macro, a document someone wrote. OS metadata and an IDE project file are not content, they are artifacts of the machine the corpus happened to sit on, and no version of this corpus should ever carry them. Verify the number rather than assuming it:

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git add --dry-run inst/corpus 2>/dev/null | wc -l
```

Expected: `440`. If it is not, list what git is skipping (`git status --ignored --porcelain inst/corpus | grep '^!!'`) and report before committing.

- [ ] **Step 7: Write a placeholder so `inst/templates/` survives the commit**

```bash
cat > ~/Documents/GitHub/hvtiRtemplates/inst/templates/README.md <<'EOF'
# Supported R job templates

Empty until stage 3 of the templates-and-provenance design, which moves the
five `R_hazard` templates (`ac`, `hz`, `hp`, `bh`, `hm`) here.

Files in this directory are **supported and runnable**. Files under
`inst/corpus/` are neither — they are the reference specification that these
templates reproduce.
EOF
```

- [ ] **Step 8: Commit**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git add inst/corpus inst/templates && git commit -m "feat: import the legacy template corpus

450 files from ~/Documents/template, which has never been under version
control. Imported verbatim, cruft included -- .DS_Store, Thumbs.db, editor
backups and all. The next commit removes them, so the removal is reviewable
and reversible. A file excluded at import would have been neither.

Study-folder structure is preserved because the prefix-to-folder taxonomy is
encoded in it. The templates/ level is dropped as redundant under corpus/."
```

---

### Task 5: Remove the cruft, reviewably

**Files:**
- Delete: cruft under `inst/corpus/` and `inst/macros/`

**Interfaces:**
- Consumes: the imports from Tasks 3 and 4
- Produces: a corpus free of editor backups, OS metadata and dead VCS state, with every removal recoverable from the preceding commit

- [ ] **Step 1: List exactly what will be removed**

Build the list from `git ls-files`, **not** `find`. Only tracked files can be removed with `git rm`, and the working tree also holds gitignored OS metadata that was never committed — `find` would list those and every `git rm` would then fail.

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git ls-files \
  | grep -E '(~$|\.BAK$|/CVS/|\.DS_Store$|Thumbs\.db$|\.Rhistory$|\.~[0-9.]+~$)' \
  | sort | tee /tmp/hvti-cruft.txt | wc -l
```

Expected: `53` — 52 from the macro import (38 editor `~` backups and CVS-era `.~1.2.~` revision files, plus 14 `CVS/` metadata files) and `Thumbs.db` from the template corpus's office-template directory. Read `/tmp/hvti-cruft.txt` in full before proceeding.

Then remove the untracked OS metadata that came across on disk but was never committed, so the working tree matches the commit:

```bash
cd ~/Documents/GitHub/hvtiRtemplates && find inst/corpus \( -name '.DS_Store' -o -name '.Rhistory' -o -name '*.Rproj' \) -delete
```

**Do not add any pattern to this list beyond the six above.** `_Old`, `-copy`, `.2013` and date-stamped files are *content*, not cruft; they are Task 6's subject and must survive this commit.

- [ ] **Step 1b: Check every `*~` file for an original before removing it**

A `*~` file is an editor backup only if there is something it is a backup *of*. Where no non-`~` sibling exists, the `~` file is not a copy — it is the only copy, and the suffix is the whole reason it looks disposable.

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git ls-files | grep '~$' | grep -v '\.~[0-9.]*~$' | while read -r f; do
  base="${f%\~}"
  git ls-files | grep -qix "$base" || echo "ORPHAN: $f"
done
```

Expected on this corpus: **four orphans** —

```
inst/macros/CR_compare_CP_test.sas~
inst/macros/hazplot_jr.sas~
inst/macros/kaplan_tvc_jr.sas~
inst/macros/plot_94.sas~
```

**Remove these from `/tmp/hvti-cruft.txt` before Step 2**, then restore them under content names (trailing `~` stripped) in their own commit. Renaming matters: a file called `foo.sas~` is what the next person grepping for backups deletes, which is precisely how these nearly went.

They are not scratch. `hazplot_jr.sas~` differs materially from the tracked `hazplot.sas` (no `cl=&CLEVEL` parameter), and `kaplan_tvc_jr.sas~` implements an Extended Kaplan-Meier estimator for a time-varying covariate following Snapinn, Jiang & Iglewicz (2005), authored by Jeevanantham Rajeswaran and dated 2014-11-06. A pattern-matched bulk delete would have taken a methods implementation with it.

**Generalise this.** The six cruft patterns are heuristics about *intent* inferred from a filename, and a heuristic that is right 21 times out of 25 still destroys content four times. Any bulk removal keyed on filename shape needs a check that the file is what its name implies before the removal runs.

- [ ] **Step 2: Remove them**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && xargs -a /tmp/hvti-cruft.txt git rm -q --
find inst -type d -empty -delete
```

- [ ] **Step 3: Verify the cruft is gone and the content is not**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && find inst -name '*~' -o -name '*.BAK' -o -name '.DS_Store' -o -path '*/CVS/*' | wc -l
```

Expected: `0`.

```bash
cd ~/Documents/GitHub/hvtiRtemplates && ls inst/corpus/r/analyses/tp.BoostmtreeLongitudinal_w_notes_032423-copy.R \
  inst/corpus/r/graphs/tp.lp.mirror_histo_before_after_wt_Old.R \
  inst/corpus/sas/descriptive/tp.dc.tables.ods.2013.sas
```

Expected: all three present. These are Task 6's subject and must not have been swept up here.

- [ ] **Step 4: Verify the removals are recoverable**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git show HEAD:inst/macros/kaplan.\~1.1.1.1.\~ | head -2
```

Expected: file content prints. This proves the previous commit holds what was just removed, which is why import-then-remove was worth the extra commit.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git commit -m "chore: remove editor backups, OS metadata and dead CVS state

Six patterns only: *~, *.BAK, .DS_Store, Thumbs.db, .Rhistory, and CVS/
directories whose repository at /u00/programs/CVS no longer exists.

Everything removed here is in the parent commit. Files whose names encode a
generation (-copy, _Old, .2013, date stamps) are deliberately NOT touched --
they are content, and the next commit resolves them into rename history."
```

---

### Task 6: Resolve the filename generations into git history

**Files:**
- Rename/delete under `inst/corpus/`

**Interfaces:**
- Consumes: the cleaned corpus from Task 5
- Produces: one canonical file per generation group, with the superseded versions reachable through `git log --follow`

Seven groups, identified 2026-08-13. Each is handled as: verify which file is current, `git rm` the superseded one, commit with a message recording what it was. The content is not lost — it stays in the Task 4 commit — but the working tree stops presenting a choice with no information to make it on.

- [ ] **Step 1: Compare each group before deciding**

```bash
cd ~/Documents/GitHub/hvtiRtemplates/inst/corpus && \
diff r/analyses/tp.BoostmtreeLongitudinal_w_notes_032423.R r/analyses/tp.BoostmtreeLongitudinal_w_notes_032423-copy.R | head -20
```

```bash
cd ~/Documents/GitHub/hvtiRtemplates/inst/corpus && \
diff r/graphs/tp.lp.mirror_histo_before_after_wt.R r/graphs/tp.lp.mirror_histo_before_after_wt_Old.R | head -20
```

```bash
cd ~/Documents/GitHub/hvtiRtemplates/inst/corpus && \
diff sas/datasets/tp.bd.SAStoR.sas sas/datasets/tp.bd.SAStoR_old.sas | head -20
```

Record whether each pair is identical or differs. An identical pair is an unambiguous removal; a differing pair needs the newer `mtime` to decide, and the decision goes in the commit message.

- [ ] **Step 2: Remove the unambiguously superseded files**

These four carry an explicit "this is not current" marker in the name:

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git rm -q \
  inst/corpus/r/analyses/tp.BoostmtreeLongitudinal_w_notes_032423-copy.R \
  inst/corpus/r/graphs/tp.lp.mirror_histo_before_after_wt_Old.R \
  inst/corpus/sas/datasets/tp.bd.SAStoR_old.sas \
  inst/corpus/r/graphs/archive/old_rplots/tp.lp.propen.cov_balance_old.R
```

- [ ] **Step 3: Resolve the `gfup` group**

Six generations across two directories:

```bash
cd ~/Documents/GitHub/hvtiRtemplates/inst/corpus && ls -la \
  r/descriptive/tp.dp.gfup.R \
  r/descriptive/archive/tp.dp.gfup.11.8.2023.R \
  r/descriptive/archive/tp.dp.gfup.5.3.2023.R \
  r/descriptive/archive/tp.dp.gfup_13oct21.rmd \
  r/descriptive/archive/tp.dp.gfup.R \
  r/descriptive/archive/tp.dp.gfup_EAL.R \
  sas/descriptive/tp.dc.gfup.sas \
  sas/descriptive/tp.dc.gfup_121106.sas 2>/dev/null
```

Keep `r/descriptive/tp.dp.gfup.R` (the un-suffixed file outside `archive/`) and `sas/descriptive/tp.dc.gfup.sas`. The dated variants are already under `archive/`, which is where superseded work belongs — **leave them there rather than deleting them.** `archive/` is a legitimate signal; a bare `_Old` suffix in the live directory is not.

Remove only the dated variant sitting in the live directory:

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git rm -q inst/corpus/sas/descriptive/tp.dc.gfup_121106.sas
```

- [ ] **Step 4: Keep the remaining dated files, and record why**

`tp.bd.SAStoR_2014.sas` and `tp.dc.tables.ods.2013.sas` sit alongside un-dated siblings, but the date may name the *data vintage* or SAS version the template targets rather than a version of the template itself. **Both are kept.** Do not remove either in this task.

Read the headers and record what they say, so the next reader does not redo this:

```bash
cd ~/Documents/GitHub/hvtiRtemplates/inst/corpus && head -20 sas/datasets/tp.bd.SAStoR_2014.sas && echo "=====" && head -20 sas/descriptive/tp.dc.tables.ods.2013.sas
```

Paste the finding into the Step 7 commit message. Keeping them is the conservative choice and costs nothing: git carries both either way, and a wrong removal here would be a guess presented as a decision. If the headers show unambiguously that one is a plain older copy, note that too — a later commit can remove it deliberately, with the reasoning already written down.

**The file counts after this task are fixed at 240 SAS and 123 R**, and Task 8's tests assert exactly those numbers. Removing anything further here breaks them.

- [ ] **Step 5: Verify the working tree still holds one obvious choice per group**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && find inst/corpus -type f \( -name '*-copy*' -o -name '*_Old*' -o -name '*_old*' \) -not -path '*/archive/*'
```

Expected: no output.

- [ ] **Step 6: Verify the removed content is still reachable**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git log --oneline --diff-filter=D --name-only -1 | head -10
```

Expected: the deletion commit listing the removed paths. Any of them can be restored with `git show <commit>^:<path>`.

- [ ] **Step 7: Commit**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git commit -m "chore: resolve filename generations into git history

The corpus versioned itself with filenames because it had no VCS: -copy,
_Old, _old, and date stamps. Now that it has one, the working tree should
present one file per template and let git carry the rest.

Removed the four files whose names explicitly mark them superseded, plus
tp.dc.gfup_121106.sas which duplicated tp.dc.gfup.sas in the live directory.
Every one remains reachable in the import commit.

Files already under archive/ are left alone: that directory is a deliberate
signal, unlike a suffix on a file sitting in the live folder. Dated files
whose date may name a data vintage rather than a template version are also
left alone -- see the header note recorded during review."
```

---

### Task 7: The taxonomy, as data

**Files:**
- Create: `~/Documents/GitHub/hvtiRtemplates/R/taxonomy.R`
- Test: `~/Documents/GitHub/hvtiRtemplates/tests/testthat/test-taxonomy.R`

**Interfaces:**
- Consumes: `inst/corpus/` from Tasks 4–6
- Produces: `hvti_taxonomy() -> data.frame` with columns `prefix` (character), `name` (character), `folder` (character), `description` (character); one row per analysis prefix

The prefix → folder mapping currently lives in a README table that has already drifted from reality — it documents an `organize_templates.sh` and an `01_data_engineering.qmd` set, neither of which exists. Encoding it as data makes it testable against the corpus, so it cannot drift silently again.

- [ ] **Step 1: Set up testthat**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && Rscript -e 'usethis::use_testthat(3)'
```

Expected: creates `tests/testthat.R` and `tests/testthat/`.

- [ ] **Step 2: Write the failing test**

Create `tests/testthat/test-taxonomy.R`:

```r
test_that("hvti_taxonomy() has the expected shape", {
  tx <- hvti_taxonomy()
  expect_s3_class(tx, "data.frame")
  expect_named(tx, c("prefix", "name", "folder", "description"))
  expect_gt(nrow(tx), 25)
  expect_false(any(duplicated(tx$prefix)))
  expect_true(all(nzchar(tx$description)))
})

test_that("every taxonomy folder exists somewhere in the corpus", {
  # Checked across the whole corpus, not just corpus/sas: the `documents`
  # folder holds only .doc/.Rnw/.qmd templates and has no SAS files at all,
  # so a sas-only check would fail on a correct taxonomy.
  tx <- hvti_taxonomy()
  root <- system.file("corpus", package = "hvtiRtemplates")
  skip_if(root == "", "corpus not installed")
  dirs <- basename(list.dirs(root, full.names = TRUE, recursive = TRUE))
  expect_true(all(unique(tx$folder) %in% dirs))
})

test_that("every prefix-shaped field in the corpus is classified", {
  # Not every `tp.X.…` file uses the prefix system: `tp.PPTs.R` and
  # `tp.plots.sas` are utilities whose second field is just a word. So the
  # test does not demand a taxonomy row for every X -- it demands that every X
  # is *classified*, either as an analysis prefix or explicitly as not one.
  #
  # That distinction is the whole value of the test. Demanding a taxonomy row
  # for every X would push `PPTs` and `test` into the taxonomy as if they were
  # analysis types; allowing unknowns through silently would let a genuinely
  # new prefix arrive undocumented, which is how the README drifted in the
  # first place. A new file with an unclassified second field fails the build
  # until someone decides which it is.
  root <- system.file("corpus", package = "hvtiRtemplates")
  skip_if(root == "", "corpus not installed")
  files <- list.files(root, pattern = "^tp\\.", recursive = TRUE)
  found <- unique(vapply(strsplit(basename(files), ".", fixed = TRUE),
                         function(x) if (length(x) > 1) x[[2]] else NA_character_,
                         character(1)))
  found <- found[!is.na(found) & nchar(found) <= 5]
  unclassified <- setdiff(found, c(hvti_taxonomy()$prefix, hvti_non_prefixes()))
  expect_equal(unclassified, character(0),
               info = paste("unclassified second field(s):",
                            paste(unclassified, collapse = ", "),
                            "- add to hvti_taxonomy() if an analysis prefix,",
                            "or to hvti_non_prefixes() if not"))
})

test_that("the taxonomy and the non-prefix list are disjoint", {
  expect_equal(intersect(hvti_taxonomy()$prefix, hvti_non_prefixes()),
               character(0))
})
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && Rscript -e 'devtools::test()'
```

Expected: FAIL with `could not find function "hvti_taxonomy"`.

- [ ] **Step 4: Write the implementation**

Create `R/taxonomy.R`. Contents transcribed from the prefix table in `~/Documents/template/README.md`:

```r
#' Analysis prefix taxonomy
#'
#' The two-letter prefix system inherited from the original CORR analysis
#' binder. The prefix encodes both the type of analysis and the folder the job
#' belongs in.
#'
#' This is data rather than documentation on purpose. The same table lived in a
#' README and drifted from the corpus it described; as a function it is checked
#' by the test suite against the files actually present.
#'
#' @return A data frame with columns `prefix`, `name`, `folder`, `description`.
#' @export
#' @examples
#' head(hvti_taxonomy())
hvti_taxonomy <- function() {
  tx <- rbind.data.frame(
    c("bd",    "Build",                     "datasets",      "assembles raw sources into the analytic dataset"),
    c("vars",  "Variables",                 "datasets",      "macro enhancing the dataset with temp vars, imputations, propensity"),
    c("dt",    "Data check",                "datasets",      "initial QC of the build dataset"),
    c("dc",    "Descriptive",               "descriptive",   "Table 1s, covariate summaries, balance tables"),
    c("lg",    "Logit trends",              "descriptive",   "variable transformation and linearity checks"),
    c("rg",    "Regression trends",         "descriptive",   "trend checks for continuous and polytomous outcomes"),
    c("ac",    "Actuarial",                 "distributions", "Kaplan-Meier / non-parametric life table"),
    c("hz",    "Hazard fit",                "distributions", "fits the underlying hazard distribution"),
    c("hs",    "Hazard setup",              "distributions", "patient-level survival predictions from the HM model"),
    c("cd",    "Cumulative distribution",   "distributions", "cumulative distribution plots; follow-up summaries"),
    c("nd",    "Nonparametric distributions","distributions","distribution estimates stratified by group"),
    c("hm",    "Hazard model",              "analyses",      "risk factor analysis; builds on the HZ fit"),
    c("mm",    "Mixed model",               "analyses",      "continuous repeated-measures longitudinal analysis"),
    c("gm",    "Generalized model",         "analyses",      "repeated-measures ordinal / count models"),
    c("lm",    "Logistic model",            "analyses",      "logistic regression; propensity score development"),
    c("bh",    "Bootstrap hazard",          "analyses",      "bootstrap variable selection or fixed-set hazard models"),
    c("bl",    "Bootstrap logistic",        "analyses",      "bootstrap variable selection or fixed-set logistic models"),
    c("bc",    "Bootstrap Cox",             "analyses",      "bootstrap variable selection or fixed-set Cox models"),
    c("bn",    "Bootstrap nonparametric",   "analyses",      "bootstrap confidence intervals for nonparametric estimates"),
    c("bq",    "Bootstrap quantile",        "analyses",      "quantile regression with bagging"),
    c("br",    "Bootstrap regression",      "analyses",      "linear regression with bagging"),
    c("nm",    "Nonparametric model",       "analyses",      "nonparametric regression models"),
    c("rf",    "Random forest",             "analyses",      "random forest and randomForestSRC models"),
    c("pm",    "Propensity model",          "analyses",      "count outcome with balancing score"),
    c("rm",    "Regression model",          "analyses",      "linear regression with balancing score"),
    c("cm",    "Cox matching",              "analyses",      "Cox PH with propensity matching / IPTW"),
    c("ls",    "Life table / STS",          "analyses",      "STS observed-versus-predicted analyses"),
    c("hp",    "Hazard plot",               "graphs",        "overlays actuarial and predicted survival; patient-specific curves"),
    c("mp",    "Mixed model plot",          "graphs",        "individual and population-level trends from MM"),
    c("lp",    "Logistic plot",             "graphs",        "ordinal or binary logistic model results"),
    c("np",    "Nonparametric plot",        "graphs",        "nonparametric distribution figures"),
    c("dp",    "Descriptive plot",          "graphs",        "bar, scatter, spaghetti, sankey, bubble plots"),
    c("fp",    "Forest plot",               "graphs",        "odds ratio or hazard ratio forest plots"),
    c("gp",    "Generalized model plot",    "graphs",        "depicts generalized / longitudinal model results"),
    c("cp",    "Cumulative probability plot","graphs",       "cumulative probability figures"),
    c("ce",    "Competing events",          "graphs",        "competing risks / multistate figures"),
    c("rp",    "Regression plot",           "graphs",        "regression and balance figures"),
    c("ar",    "Analysis report",           "documents",     "the written analysis report"),
    stringsAsFactors = FALSE
  )
  names(tx) <- c("prefix", "name", "folder", "description")
  tx
}

#' Second fields that are not analysis prefixes
#'
#' Some corpus files are named `tp.<word>.<ext>` where `<word>` is a utility
#' name rather than an analysis prefix — `tp.plots.sas`, `tp.PPTs.R`. They are
#' listed here so the test suite can tell "not a prefix" apart from "a prefix
#' nobody documented". Without this distinction the taxonomy either fills with
#' non-prefixes or stops catching real omissions.
#'
#' @return A character vector.
#' @export
#' @examples
#' hvti_non_prefixes()
hvti_non_prefixes <- function() {
  c("plots", "ppt", "PPTs", "test", "pp")
}
```

Add these rows to the taxonomy alongside the ones above — they appear in the corpus and are genuine analysis prefixes:

```r
    c("rfsrc", "Random forest (SRC)",       "analyses",      "randomForestSRC survival, regression and classification models"),
    c("rfc",   "Random forest classifier",  "analyses",      "random forest classification reporting"),
    c("rfs",   "Random forest survival",    "analyses",      "random forest survival analysis reporting"),
    c("nb",    "Notebook",                  "analyses",      "boosting notebooks (Boostmtree, BoostMLR)"),
```

**Do not simply accept this list.** Task 7 Step 5 runs the test, and if it names a second field not covered by either function, read the files that produced it and decide which list it belongs in. The counts as of 2026-08-13 are: 46 distinct fields of five characters or fewer across the corpus.

- [ ] **Step 5: Document and run the tests**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && Rscript -e 'devtools::document(); devtools::test()'
```

Expected: `FAIL 0`. **If the third test fails**, it has found a prefix present in the corpus and absent from the table above — read the names it reports and add those rows. That is the test doing its job, not a defect.

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git add R/taxonomy.R man NAMESPACE tests && git commit -m "feat: encode the prefix taxonomy as data

The same table lived in the library README and drifted from the corpus it
described -- it documents an organize_templates.sh and an 01_data_engineering
set, neither of which exists. As a function it is checked by the suite against
the files actually present, so it cannot drift silently again.

The third test is the load-bearing one: any prefix appearing in the corpus and
missing from the table fails the build."
```

---

### Task 8: `corpus_manifest()` and `template_list()`

**Files:**
- Create: `~/Documents/GitHub/hvtiRtemplates/R/corpus.R`
- Create: `~/Documents/GitHub/hvtiRtemplates/R/templates.R`
- Test: `~/Documents/GitHub/hvtiRtemplates/tests/testthat/test-corpus.R`
- Test: `~/Documents/GitHub/hvtiRtemplates/tests/testthat/test-templates.R`

**Interfaces:**
- Consumes: `hvti_taxonomy()` from Task 7; the corpus from Tasks 4–6
- Produces:
  - `corpus_manifest() -> data.frame` with columns `file`, `prefix`, `folder`, `kind`, `bytes`
  - `corpus_path(...) -> character(1)`
  - `template_list() -> data.frame` with columns `name`, `prefix`, `folder`, `file`
  - `template_path(name) -> character(1)`

`template_list()` returns zero rows until stage 3 adds templates. That is correct, not a stub: the function is what stage 3 fills, and having it here means stage 3 adds files rather than API.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-corpus.R`:

```r
test_that("corpus_manifest() describes every corpus file", {
  m <- corpus_manifest()
  expect_s3_class(m, "data.frame")
  expect_named(m, c("file", "prefix", "folder", "kind", "bytes"))
  expect_gt(nrow(m), 400)
  expect_true(all(m$bytes > 0))
  expect_true(all(m$kind %in% c("sas", "r", "assets", "docs")))
})

test_that("corpus file counts match the recorded import", {
  # 242 SAS and 126 R-family imported in Task 4. Task 6 removed 2 SAS and 3 R
  # files whose names marked them superseded, then restored one of the three:
  # tp.lp.propen.cov_balance_old.R turned out to target a different study
  # (aortic/pericardial/ischemia/2010) from its sibling (mitral/degeneration/
  # complex), making it a distinct instantiation rather than an older draft.
  # It is back under the name tp.lp.propen.cov_balance_ischemia2010.R.
  #
  # These numbers are the point of the test: a partial copy or a silent
  # deletion fails the build rather than looking like a smaller corpus.
  m <- corpus_manifest()
  expect_equal(sum(m$kind == "sas"), 240)
  expect_equal(sum(m$kind == "r"), 124)
})

test_that("corpus_path() resolves a known file", {
  p <- corpus_path("sas", "distributions", "tp.hz.dead.sas")
  expect_true(file.exists(p))
})

test_that("corpus_path() errors on a missing file", {
  expect_error(corpus_path("sas", "distributions", "nope.sas"), "not found")
})

test_that("prefix classification covers files that lack the tp. marker", {
  # Task 7's classification test only scanned basenames matching `^tp\.`, but
  # the corpus also holds files named `<prefix>.<description>...` with no `tp.`
  # marker at all -- `ar.a1c.hdeath.R`, `dp.estimates.errorbar.pdf`,
  # `lp.hdeath.Minimal.depth.pdf`. Every prefix used that way happens to be
  # classified today, so that test passes; but a new file in that style with an
  # undocumented prefix would never be seen. This closes the hole.
  #
  # Scope is inst/corpus only. inst/macros does not use the prefix convention
  # -- its files are named for the macro they define (`kaplan`, `cumhaz`) --
  # so scanning it would produce noise, not coverage.
  root <- system.file("corpus", package = "hvtiRtemplates")
  skip_if(root == "", "corpus not installed")
  files <- basename(list.files(root, recursive = TRUE))
  files <- sub("^tp\\.", "", files)
  first <- sub("\\..*$", "", files)
  candidates <- unique(first[grepl("^[A-Za-z]{2,5}$", first)])
  unclassified <- setdiff(candidates,
                          c(hvti_taxonomy()$prefix, hvti_non_prefixes()))
  expect_equal(unclassified, character(0),
               info = paste("unclassified prefix-shaped field(s):",
                            paste(unclassified, collapse = ", ")))
})
```

Create `tests/testthat/test-templates.R`:

```r
test_that("template_list() has the expected shape", {
  tl <- template_list()
  expect_s3_class(tl, "data.frame")
  expect_named(tl, c("name", "prefix", "folder", "file"))
})

test_that("every listed template exists and every template file is listed", {
  tl <- template_list()
  dir <- system.file("templates", package = "hvtiRtemplates")
  skip_if(dir == "", "templates not installed")
  on_disk <- setdiff(list.files(dir, pattern = "[.]qmd$"), character(0))
  expect_setequal(basename(tl$file), on_disk)
  expect_true(all(file.exists(tl$file)))
})

test_that("every template prefix is in the taxonomy", {
  tl <- template_list()
  expect_true(all(tl$prefix %in% hvti_taxonomy()$prefix))
})
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && Rscript -e 'devtools::test()'
```

Expected: FAIL with `could not find function "corpus_manifest"` and `"template_list"`.

- [ ] **Step 3: Write `R/corpus.R`**

```r
#' Describe the legacy reference corpus
#'
#' The corpus is the SAS template library and the legacy R-family templates as
#' they stood when the group migrated to R. It is a **reference specification,
#' not a runnable asset**: nothing here is tested, supported, or maintained.
#' The institutional SAS licence expires 2026-09-29.
#'
#' @return A data frame with one row per corpus file: `file` (full path),
#'   `prefix` (analysis prefix, `NA` where the name does not carry one),
#'   `folder` (study folder), `kind` (`"sas"`, `"r"`, `"assets"` or `"docs"`)
#'   and `bytes`.
#' @export
#' @examples
#' m <- corpus_manifest()
#' table(m$kind)
corpus_manifest <- function() {
  root <- system.file("corpus", package = "hvtiRtemplates")
  if (!nzchar(root)) {
    stop("the corpus is not installed with this package", call. = FALSE)
  }
  files <- list.files(root, recursive = TRUE, full.names = TRUE)
  rel <- substring(files, nchar(root) + 2L)
  parts <- strsplit(rel, "/", fixed = TRUE)

  data.frame(
    file   = files,
    prefix = vapply(basename(files), .prefix_of, character(1), USE.NAMES = FALSE),
    folder = vapply(parts, function(p) if (length(p) > 1L) p[[2L]] else NA_character_,
                    character(1)),
    kind   = vapply(parts, `[[`, character(1), 1L),
    bytes  = file.size(files),
    stringsAsFactors = FALSE
  )
}

# tp.<prefix>.<rest> -- returns NA for anything not matching that shape.
# Prefixes are short; a long second field means the name is not prefixed.
.prefix_of <- function(name) {
  p <- strsplit(name, ".", fixed = TRUE)[[1L]]
  if (length(p) < 3L || !identical(p[[1L]], "tp")) return(NA_character_)
  if (nchar(p[[2L]]) > 5L) return(NA_character_)
  p[[2L]]
}

#' Path to a file in the reference corpus
#'
#' @param ... Path components below `inst/corpus`, e.g.
#'   `corpus_path("sas", "distributions", "tp.hz.dead.sas")`.
#' @return The full path, as `character(1)`.
#' @export
#' @examples
#' corpus_path("sas", "distributions", "tp.hz.dead.sas")
corpus_path <- function(...) {
  p <- system.file("corpus", ..., package = "hvtiRtemplates")
  if (!nzchar(p)) {
    stop("not found in the corpus: ", file.path(...), call. = FALSE)
  }
  p
}
```

- [ ] **Step 4: Write `R/templates.R`**

```r
#' List the supported R job templates
#'
#' Unlike [corpus_manifest()], these templates are supported: they render, they
#' are tested, and they are the intended starting point for a new analysis job.
#'
#' Returns zero rows until the templates are added in stage 3 of the
#' templates-and-provenance design.
#'
#' @return A data frame with columns `name`, `prefix`, `folder` and `file`.
#' @export
#' @examples
#' template_list()
template_list <- function() {
  dir <- system.file("templates", package = "hvtiRtemplates")
  files <- if (nzchar(dir)) {
    list.files(dir, pattern = "[.]qmd$", full.names = TRUE)
  } else {
    character(0)
  }
  name <- sub("[.]qmd$", "", basename(files))
  tx <- hvti_taxonomy()

  data.frame(
    name   = name,
    prefix = name,
    folder = tx$folder[match(name, tx$prefix)],
    file   = files,
    stringsAsFactors = FALSE
  )
}

#' Path to a supported template
#'
#' @param name Template name, e.g. `"hz"`. See [template_list()].
#' @return The full path, as `character(1)`.
#' @export
#' @examples
#' try(template_path("hz"))
template_path <- function(name) {
  tl <- template_list()
  i <- match(name, tl$name)
  if (is.na(i)) {
    stop("unknown template: ", name,
         if (nrow(tl)) paste0(". Available: ", paste(tl$name, collapse = ", "))
         else ". No templates are installed yet.",
         call. = FALSE)
  }
  tl$file[[i]]
}
```

- [ ] **Step 5: Install, document and run the tests**

`corpus_manifest()` reads through `system.file()`, so the package must be installed for the tests to see `inst/`:

```bash
cd ~/Documents/GitHub/hvtiRtemplates && Rscript -e 'devtools::document(); devtools::install(quick = TRUE, upgrade = "never"); devtools::test()'
```

Expected: `FAIL 0`.

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git add R man NAMESPACE tests && git commit -m "feat: add corpus_manifest(), corpus_path(), template_list(), template_path()

corpus_manifest() records the file counts as a test, so a partial copy or a
silent deletion fails the build rather than looking like a smaller corpus.

template_list() returns zero rows until stage 3 adds the templates. That is
the point: stage 3 adds files, not API."
```

---

### Task 9: Documentation and the PR

**Files:**
- Modify: `~/Documents/GitHub/hvtiRtemplates/README.md`
- Create: `~/Documents/GitHub/hvtiRtemplates/inst/corpus/README.md`

**Interfaces:**
- Consumes: everything above
- Produces: a merged PR

- [ ] **Step 1: Write `inst/corpus/README.md`**

```markdown
# Reference corpus — not runnable

Everything under this directory is the SAS-era template library and the legacy
R-family templates as they stood at the migration to R. It is carried here so
that the behaviour the supported templates reproduce has a citable source under
version control.

**Nothing here is supported.** It is not tested, not maintained, and not
guaranteed to run. The institutional SAS licence expires 2026-09-29.

| Directory | Contents |
|---|---|
| `sas/` | 242 SAS templates, study-folder structure preserved |
| `r/` | 126 legacy R-family templates (`.R`, `.qmd`, `.Rmd`, `.Rnw`, `.S`) |
| `assets/` | office templates, PDFs and example figures |
| `docs/` | READMEs and reference documents, including the original library README under `_root/` |

## Provenance of this corpus

Imported 2026-08-13 from `~/Documents/template`, which had **never been under
version control**. It versioned itself with filenames — `-copy`, `_Old`,
`.BAK`, date stamps and `archive/` directories. Those generations were resolved
into git history at import; see the commits on `feat/import-corpus`.

`macros/` is different: it arrived with real history, 2014-09-19 to 2019-05-01,
imported via `git subtree` so that history survives. Before 2014 nothing
survives — the CVS repository at `/u00/programs/CVS` is gone. After 2019-05-01
the cron that produced its daily commits stopped, so the 2019-2026 period is
captured as a single commit with no internal dates.

**Consequence for parity work.** A SAS result filed before this import was
produced by a macro version that cannot be identified, because `%inc` bound
late to a mutable directory with no version. A parity mismatch against a stored
`.lst` therefore has an irreducibly ambiguous cause. Do not spend effort
resolving one on the assumption that the macro is knowable.
```

- [ ] **Step 2: Write the full `README.md`**

````markdown
# hvtiRtemplates

Versioned analysis job templates for the HVTI CORR group at the Cleveland
Clinic, plus the legacy SAS template corpus and macro library as a reference
specification.

## Install

```r
renv::install("ehrlinger/hvtiRtemplates")
```

## What is here

| Directory | Status | Contents |
|---|---|---|
| `inst/templates/` | **supported** | R job templates. Empty until stage 3. |
| `inst/corpus/` | reference only | 450 legacy SAS and R templates |
| `inst/macros/` | reference only | 579 SAS macro library files, history from 2014 |

The distinction is load-bearing. `inst/templates/` is tested and maintained;
`inst/corpus/` and `inst/macros/` are a citable record of what the R templates
reproduce, and nothing more.

## Why this package exists

Study analyses were created by copying template files into a new study folder
and editing them. Two things followed: improvements stayed in the study where
they were made, and — the problem that actually hurts — a filed result could
not say what produced it. SAS bound its analysis logic with
`%inc kaplan`, resolving at run time against a mutable directory with no
version, so the `.lst` filed in 2006 was produced by a `kaplan` nobody can now
identify.

The design rule is **bind late, to something versioned**. Late binding is right;
SAS could not make it safe because there was no version to pin. `renv.lock`
supplies that, so a study can use the latest while working and pin it on filing.

See `dev/specs/2026-08-13-templates-and-provenance-design.md`
in the AVR/LV-function survival study for the full design.

## API

| Function | Returns |
|---|---|
| `hvti_taxonomy()` | the analysis prefix table: prefix, name, folder, description |
| `template_list()` | supported templates: name, prefix, folder, file |
| `template_path(name)` | path to one supported template |
| `corpus_manifest()` | every reference-corpus file: file, prefix, folder, kind, bytes |
| `corpus_path(...)` | path to one reference-corpus file |
````

- [ ] **Step 3: Exclude the review scratch directory before checking**

Task execution writes review packages to `.superpowers/sdd/` in the repository. `R CMD check` reports hidden directories in the tarball as a NOTE, and the directory is scratch that must never ship. Append to `.gitignore`:

```gitignore
.superpowers/
```

And to `.Rbuildignore`:

```
^\.superpowers$
```

Verify:

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git check-ignore -q .superpowers/sdd/x.diff && echo "ignored (correct)" || echo "NOT ignored — stop and report"
```

- [ ] **Step 4: Run the full check**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && R CMD build . && R CMD check hvtiRtemplates_1.0.0.tar.gz --no-manual
```

Expected: `Status: OK` or NOTEs only. A NOTE about installed package size is expected and acceptable — the corpus is ~14 MB and that is the point of the package.

**This package is not a CRAN target**, so the release gate in the global instructions is not triggered. `R CMD check` must still pass.

```bash
cd ~/Documents/GitHub/hvtiRtemplates && rm -f hvtiRtemplates_1.0.0.tar.gz && rm -rf hvtiRtemplates.Rcheck
```

- [ ] **Step 1b: Make the manifest tests value-bearing**

Task 8's corpus tests assert the *shape* of `corpus_manifest()` — column names, row count, that `kind` falls in a known set — but never assert what `prefix` or `folder` actually equals for a known file. A `.prefix_of()` that returned the third dot-field instead of the second, or a `folder` derivation off by one path component, would pass all 23 tests.

Append to `tests/testthat/test-corpus.R`:

```r
test_that("corpus_manifest() derives prefix and folder correctly", {
  # Shape assertions cannot catch a wrong derivation -- these can. tp.hz.dead.sas
  # is a stable landmark: it is the hazard-fit template, it lives in
  # distributions/, and it is what the R hz template reproduces.
  m <- corpus_manifest()
  skip_if(nrow(m) == 0, "corpus not installed")

  row <- m[basename(m$file) == "tp.hz.dead.sas", ]
  expect_equal(nrow(row), 1)
  expect_equal(row$prefix, "hz")
  expect_equal(row$folder, "distributions")
  expect_equal(row$kind, "sas")

  # A file nested deeper than one level: folder must still be the study folder,
  # not the subdirectory.
  deep <- m[basename(m$file) == "tp.dp.QOL_boxplot.R", ]
  expect_equal(nrow(deep), 1)
  expect_equal(deep$folder, "graphs")

  # A name that does not carry an analysis prefix must yield NA, not a guess.
  expect_true(all(is.na(m$prefix[basename(m$file) == "references.bib"])))
})
```

Run the suite and confirm it passes. **If `tp.dp.QOL_boxplot.R` is not present at a nested path, substitute another file that is** — find one with `Rscript -e 'm <- hvtiRtemplates::corpus_manifest(); head(m$file[lengths(strsplit(m$file, "/")) > 8])'` — and say in your report which you used and why.

- [ ] **Step 2b: Remove two files that can never ship**

`inst/corpus/docs/_root/.renvignore` and `inst/corpus/docs/_root/.vscode/settings.json` are tracked in git but absent from the installed package — `R CMD INSTALL` skips dot-prefixed paths under `inst/`. So `corpus_manifest()` reports 433 files while git tracks 435, and that discrepancy has no explanation a reader could reach.

They are also the same class already excluded at import: tooling configuration for the directory the corpus happened to live in, not corpus content. The ten `.DS_Store`/`.Rhistory`/`.Rproj` files were dropped on exactly this reasoning; these two only survived because they sit in a subdirectory the `.gitignore` patterns did not name.

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git rm -q 'inst/corpus/docs/_root/.renvignore' 'inst/corpus/docs/_root/.vscode/settings.json'
```

Then re-install and confirm the two counts now agree:

```bash
cd ~/Documents/GitHub/hvtiRtemplates && Rscript -e 'devtools::install(quick = TRUE, upgrade = FALSE)' >/dev/null 2>&1 && Rscript -e 'cat("manifest:", nrow(hvtiRtemplates::corpus_manifest()), "\n")' && echo "git: $(git ls-files inst/corpus | wc -l)"
```

Expected: both `433`. The `docs` kind count drops from 35 to 33.

- [ ] **Step 3b: Resolve the RoxygenNote mismatch**

`DESCRIPTION` says `RoxygenNote: 7.3.2` while the committed `man/*.Rd` were generated by roxygen2 8.1.0 — Task 7's implementer reverted the stamp to keep that commit surgical, which left the field claiming something untrue. The field exists precisely to record which roxygen produced the docs.

```bash
cd ~/Documents/GitHub/hvtiRtemplates && Rscript -e 'devtools::document()' && grep RoxygenNote DESCRIPTION
```

Expected: the stamp now matches the installed roxygen2. Confirm `git diff --stat` shows only `DESCRIPTION` and, if roxygen reformatted them, `man/*.Rd` — **if it shows changes to `R/` or `NAMESPACE`, stop and report.**

- [ ] **Step 4: Verify the version-grep invariant**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && grep '^Version:' DESCRIPTION && sed -n '2p' NEWS.md
```

Expected: both read `1.0.0` (NEWS.md line 2 as `Version: 1.0.0`).

- [ ] **Step 5: Commit and open the PR**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git add README.md inst/corpus/README.md && git commit -m "docs: state what is supported and what is reference only

The corpus README carries the provenance limits explicitly, including that a
parity mismatch against a pre-2026 .lst has an irreducibly ambiguous cause.
That is a fact worth writing down once rather than rediscovering."
```

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git push -u origin feat/import-corpus
```

```bash
cd ~/Documents/GitHub/hvtiRtemplates && gh pr create --title "Import the legacy template corpus and macro library" --body "$(cat <<'EOF'
Stage 2 of the templates-and-provenance design.

Puts twenty years of un-versioned institutional assets under git:

- **450 files** from `~/Documents/template`, which had no version control and versioned itself with `-copy`, `_Old`, `.BAK` and date stamps.
- **579 files** from `~/Documents/macro.library`, imported with `git subtree` so its real history — 357 commits, 2014-09-19 to 2019-05-01 — survives. Its 255 uncommitted working-tree changes were captured first; they existed nowhere else.

Everything was imported before anything was cleaned, so each removal is a reviewable `git rm` against a commit that holds the original. A file excluded at import would have been neither reviewable nor recoverable.

`hvti_taxonomy()` encodes the prefix table as data and tests it against the corpus. The same table lived in a README and had already drifted — it documents an `organize_templates.sh` and an `01_data_engineering.qmd` set, neither of which exists.

`inst/templates/` is empty by design. Stage 3 fills it; the API is here so that stage adds files rather than interface.

Known limit, recorded in `inst/corpus/README.md`: macro provenance before 2014 is gone with the CVS repository, and 2019-2026 is one undated commit. A parity mismatch against a pre-2026 `.lst` has an irreducibly ambiguous cause.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 6: Report the PR URL and stop**

Do not merge. The user merges.

---

## Verification against the spec's stage-2 scope

| Spec requirement | Task |
|---|---|
| Create the package | 1 |
| Import 242 SAS templates into `inst/` | 4 |
| Import the macro library into `inst/` | 3 |
| Preserve `macro.library` git history | 2, 3 |
| Resolve filename generations into git history | 5, 6 |
| Ship `template_list()` | 8 |
| Success criterion 7 (corpus under version control, generations in history) | 3–6 |

**Deferred to stage 3, deliberately:** `new_job()`, `template_manifest()`, the `hvti:` YAML stamp, and the five R templates. None is needed for the corpus to be versioned, and stage 2 is useful on its own if stage 3 never runs.

**Not in any stage:** converting, testing, or supporting the SAS corpus. It is reference specification (spec section 9).
