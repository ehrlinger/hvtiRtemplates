# hvtiRtemplates

Analysis job templates for the HVTI CORR group, plus the prefix taxonomy that names them.
Five exports across three source files: `hvti_taxonomy()`, `hvti_non_prefixes()`,
`template_list()`, `template_path()` and `new_job()`.

The package is small; the **templates are the product**. `inst/templates/README.md` promises
that files there are supported and runnable, and that promise is the reason most of the rules
below exist.

This file is the operational contract and applies in full. It is tool neutral, so Codex and
any other agent read the same rules. Claude Code affordances live in `CLAUDE.md`, which
imports this file.

## Definition of done

- `devtools::test()` passes.
- `devtools::check()` is **0 errors, 0 warnings, 0 notes**. It reached 0/0/0 on 2026-08-20.
- `devtools::document()` has been run and `man/` and `NAMESPACE` are committed with the
  source change.
- A new template renders, and has its own `.lintr` entry — see the rules below.

## The automated gates

| workflow | fails on |
|---|---|
| `R-CMD-check.yaml` | `R CMD check` across platforms |
| `check-manual.yaml` | the PDF manual build. ⚠️ **Post-merge only**, see below |
| `lint.yaml` | `lintr::lint_package()` |
| `pkgdown.yaml` | the site build |
| `spec-counts.yaml` | three checks. `check-spec-counts.py`, the prose in `dev/specs/` must agree with the generated map. `check-flow-counts.py`, every `data-check` anchored number in the job flow diagrams must agree with the maps they copy from. `check-roadmap-counts.py`, the roadmap ledger and `inst/templates/` must agree **in both directions**, so a template no ledger row claims fails the PR just as a row claiming an absent template does. Editing a count without regenerating fails the PR |
| `test-coverage.yaml` | coverage upload |

⚠️ **`check-manual.yaml` is not a PR gate.** Its triggers are `push` to `main`, `release`
and `workflow_dispatch`; there is no `pull_request` among them, so the PDF manual build
runs for the first time *after* a change has already merged. A change that breaks the
manual therefore passes every check on its PR and fails on `main`, where there is no PR
left to fix it in. Every other workflow in this table does run on `pull_request`. If a
change touches Rd markup (Greek, `\eqn{}` content, combining marks, anything the PDF
pipeline renders), build the manual locally before merging rather than trusting a green
PR.

⚠️ **A green `R-CMD-check` job can hide a suite that skipped the tests you care about.**
The job's conclusion reports whether `R CMD check` failed, and a `skip_if_not()` is not a
failure. Read the `testthat` summary *inside* the log, not the check mark beside it:

```sh
gh run view <run-id> --log | grep -E "SKIP [0-9]+ \| PASS"
```

Found the expensive way in `hvtiRlifetables`, whose regression guard for a shipped bug
reported `SKIP 5 | PASS 474` on macOS and Windows against Linux's `SKIP 0 | PASS 483`. It
covered one platform of four, had never once run on Windows, and every check stayed green
through ten CI runs and two code reviews. Three independent causes, each hidden behind the
last. Nothing in a conclusion, a check mark, or a review surfaced it; only the
per-platform summary lines did.

## Rules for this repo

- **`_pkgdown.yml` deliberately has NO `reference:` section**, so pkgdown indexes every
  export automatically and the index cannot drift out of step with `NAMESPACE`. Do not add
  one.
  ⚠️ Its sibling `hvtiRutilities` does the **opposite**: an explicit index that *errors* on a
  missing topic. Two packages, inverted conventions. Do not carry a habit across.
- **Lines are 135 characters here, not 80.** `.lintr` raises `line_length_linter` because
  `hvti_taxonomy()` is a data table written as code — 42 column-aligned rows whose alignment
  is the only thing making them legible. Every other default linter is on and enforced,
  `commas_linter` included: it has already caught taxonomy rows whose alignment slipped.
  ⚠️ `hvtiRutilities` enforces 80. Check `.lintr` before assuming a width.
- **A new template needs its own key in `.lintr`, and the key must be the FILE.** A directory
  key such as `inst/templates` excludes every linter on that path **wholesale and silently** —
  six real indentation and brace lints in `ac.qmd` vanished from a clean run that way. Only a
  file key honours a per-linter list. The friction is deliberate: it forces a decision per
  template instead of blanket-exempting the directory.
- **Templates carry no study identifiers.** `test-new-job.R` asserts that no template matches
  `/studies/`, a study name, or a built-dataset filename. A template that names a study is not
  a template.
- **Every study-specific line in a template is marked `EDIT:`.** The markers are the interface;
  a job still containing one is unfinished. Comments around them should say *why* a choice
  matters, not merely what to type — several exist because the alternative fails quietly.
- **A template is only added once two studies have exercised the shape.** A template
  extracted from a single example encodes that study's choices as though they were general.
  The second exemplar need not be R: `hm` took a SAS job, which states those choices as
  plainly as an R port does.
  ⚠️ **The gate is open for every prefix the taxonomy documents, and nothing is waiting on
  a second exemplar.** A corpus census (`hvtiRutilities::job_census()`, 2026-08-27) over all
  of `/studies` found no prefix anywhere at one study; the smallest are `bq` at 2 and
  `cp`/`pm` at 5. An earlier version of this rule named `hz` and `hp` as blocked at one study
  each. That was read off a comparison of two directories and stated as though it held for
  the corpus; both shipped, in 1.0.6 and 1.0.7. **Do not quote a per-study count as a gate
  answer** — run the census. `inst/templates/README.md` carries the numbers and the list of
  what is still untemplated.
- **Templates carry their own `format:` block** rather than inheriting from a project
  `_quarto.yml`. A file meant to be copied must not depend on the directory it happens to sit
  in — that is how server-rendered reports ended up with sibling `_files/` trees instead of
  being self-contained.
- **Roxygen here is Rd markup, not markdown.** `DESCRIPTION` has no
  `Roxygen: list(markdown = TRUE)`, so backticks and `**bold**` land literally in the `.Rd`.
  Use `\code{}`, `\strong{}`, `\emph{}`, `\itemize{}` and `\link{}`.
- **`testthat` edition 3.** There are snapshot tests under `tests/testthat/_snaps`; review a
  snapshot diff rather than accepting it reflexively.
- **This repo holds templates only.** The SAS macro corpus was removed on 2026-08-14 and
  lives in `~/Documents/macro.library`. Do not reintroduce it here.

## Template naming

A template file is `<NN.MM>-<prefix>.qmd` and lives in the taxonomy folder it scaffolds into
— e.g. `inst/templates/distributions/03.01-ac.qmd`. `.template_fields()` parses the name by
pattern, not by splitting on `.`: that character is both a field separator inside the ordinal
and the extension separator, so a split-based parser cannot tell the two apart. Prefixes come
from `hvti_taxonomy()`.

`new_job(prefix, endpoint, type, dir)` writes `<folder>/<endpoint>-<type>-<NN.MM>-<prefix>.qmd`
and **refuses to overwrite an existing job**, because a job file accumulates a study's edits.
`endpoint` and `type` name the `(endpoint, analysis type)` set the job belongs to; both are
required and both are restricted to `[A-Za-z0-9_]+`, because `-` is the filename's field
separator and `.` is reserved to the ordinal.

**A template must have exactly one `^ENDPOINT\s+<- ` line and one `^TYPE\s+<- ` line.**
`new_job()` substitutes both after copying, and hard-stops if either is missing, duplicated, or
moved — a template that fails this check cannot be scaffolded at all.

## Gotchas

- **`object_usage_linter` can never pass inside `inst/templates/`.** The templates call
  `TemporalHazard` and `hvtiRutilities`, which are the *study's* dependencies and deliberately
  absent from `DESCRIPTION`, so CI has no copy and every call reports "no visible global
  function". That is why the exclusion exists; it is not licence to disable it in `R/`.
- **`object_name_linter` is excluded for templates on purpose.** `CLEVEL`, `TIME`, `STATUS`,
  `DERIVED` and friends are SCREAMING_CASE so a study author sees at a glance what to change,
  and `CLEVEL` carries the name of the SAS macro parameter it replaces. Do not snake_case them.
- **`commented_code_linter` is excluded for templates on purpose** — commented scaffolding such
  as `# d <- read_built()` is the template showing its user what to uncomment.
- ⚠️ **The `nu = 0` warning that stood here is withdrawn, and should not be
  reinstated from an older note.** It said a future `hz` template must not ship `nu = 0`
  while [temporal_hazard#143](https://github.com/ehrlinger/temporal_hazard/issues/143) was
  open. That issue closed COMPLETED on 2026-08-25, in two opposite directions: the
  tail-divergence half was **retracted in-thread as not a defect** — C case 4 transcribes
  exactly to R's Case 2L, `rho` included, and production SAS output reproduces at all 14
  nomogram points — and the identifiability half **shipped** in TemporalHazard 1.2.5
  ([temporal_hazard#182](https://github.com/ehrlinger/temporal_hazard/pull/182)), which warns
  when a phase has effectively left the model. `03.02-hz.qmd` ships `nu = 1` as a neutral
  `EDIT:` starting value, not as a workaround, and a `nu = 0 fixnu` phase transcribed from a
  SAS fit is fine.

## Change discipline

1. **Think before coding.** Do not assume, ask. If the request is ambiguous or a name, path or
   signature is uncertain, surface the confusion rather than running with a guess.
2. **Simplicity first.** Write the minimum that solves the stated problem. No speculative
   abstractions.
3. **Surgical changes.** Touch only what the task requires. Do not refactor, reformat or
   re-style adjacent code. Raise nearby problems separately rather than folding them in.
4. **Goal-driven execution.** State what done looks like before starting, and use tests as the
   criterion. If no test covers the change, add or propose one.

## Git and versioning

- **Never push to `main`.** Branch, open a PR, let the maintainer merge.
- **`main` is protected by a GitHub ruleset, and nothing in this repo records that.** A clone
  shows no trace of it, so it is stated here. The ruleset is named `protect main`, is
  identical across all twelve repositories in the HVTI R package family, and enforces four
  rules on the default branch: no deletion, no force-push, pull-request-only, and an
  **automatic Copilot code review**. A direct push to `main` is rejected by the server —
  that is the ruleset, not a local hook, and the fix is to branch, never to force past it.
  ⚠️ It currently requires **zero approvals**. `require_code_owner_review` is set but inert
  because no repository in the family has a `CODEOWNERS` file, so a PR can merge unreviewed.
  Adding `CODEOWNERS` makes that flag live and changes who can merge what.
  ⚠️ **A stacked PR gets no Copilot review, and still reaches `main`.** The ruleset's
  condition is `ref_name: include: ["~DEFAULT_BRANCH"]`, so `copilot_code_review` fires only
  for a PR opened *against* `main`. Open one against another branch — stacking a plan on its
  design, say — and it never fires. When the parent merges, GitHub retargets the base to
  `main`, but **retargeting is not a PR-opened event and does not trigger it either**. The PR
  then sits one click from `main` having been read by nobody, which the zero-approvals rule
  above does nothing to catch. Observed on
  [#42](https://github.com/ehrlinger/hvtiRtemplates/pull/42).
  The fix is to open against `main`.
  ⚠️ **Copilot reviews a PR as opened, and never re-reviews a later push.** Commits added
  after it runs reach `main` unread, which the zero-approvals rule does nothing to catch.
  Observed on [hvtiRlifetables#21](https://github.com/ehrlinger/hvtiRlifetables/pull/21),
  where an approval stood while the branch replaced its entire mechanism underneath it.
  ⚠️ **Re-requesting one CAN be scripted, contrary to what this file said until 2026-08-31.**
  The REST `requested_reviewers` endpoint does return 200 and silently do nothing; it
  answers `requested_reviewers: []` under either `Copilot` or
  `copilot-pull-request-reviewer[bot]`. But the conclusion drawn from that, that the
  Reviewers menu was the only route, was wrong. `botIds` is a **separate GraphQL input
  field** from `userIds`, which is why the REST `reviewers[]` array cannot express it:

  ```sh
  gh api graphql -f query='mutation($pr:ID!,$bot:ID!){requestReviews(input:{pullRequestId:$pr,
    botIds:[$bot], union:true}){pullRequest{reviewRequests(first:5){nodes{requestedReviewer{
    __typename ... on Bot{login}}}}}}}' -F pr=<PR_node_id> -F bot=<BOT_node_id>
  ```

  Take the bot's node id from any existing review by it
  (`gh api repos/<o>/<r>/pulls/<n>/reviews --jq '.[0].user.node_id'`); `union: true` adds
  rather than replaces. The review lands roughly three minutes later. **Verify with
  `gh pr view <n> --json reviewRequests`, never the mutation's 200**, since trusting a 200
  is what made the REST endpoint look like it worked in the first place.
  ⚠️ **A re-review can re-raise a finding the reviewed commit already fixed**, because it
  anchors against the cumulative `base..head` diff rather than the head alone. Check the
  file before acting on one, with a pattern that survives the file's own markup: a grep for
  `single -e argument` exits 1 against a line reading ``single `-e` argument``, which turns
  "verified absent" into "not looked for".
- Versions are **straight three digits** (`1.0.2`). Never a `.9000` suffix or a fourth digit.
- **Patch-digit bumps only**, as fixes land. Minor and major are the maintainer's decision.
- Bump `DESCRIPTION`, refresh its `Date`, and add the matching `NEWS.md` entry in the same
  commit. `NEWS.md` uses plain `# hvtiRtemplates X.Y.Z` headings — **no `Version:` line**,
  unlike ggRandomForests, whose version-grep test requires a DCF-style header.

## Prose

Documentation prose — README, roxygen `@description` and `@details`, template narration —
follows the house voice. Template prose has a second audience: a study author reading it while
adapting the file, so it must explain the reasoning, not only the mechanics.
