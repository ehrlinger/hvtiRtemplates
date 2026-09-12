# hvtiRtemplates

Analysis job templates for the HVTI CORR group, plus the prefix taxonomy
that names them. Five exports across three source files:
[`hvti_taxonomy()`](https://ehrlinger.github.io/hvtiRutilities/reference/hvti_taxonomy.html),
[`hvti_non_prefixes()`](https://ehrlinger.github.io/hvtiRutilities/reference/hvti_non_prefixes.html),
[`template_list()`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_list.md),
[`template_path()`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_path.md)
and
[`new_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/new_job.md).

The package is small; the **templates are the product**.
`inst/templates/README.md` promises that files there are supported and
runnable, and that promise is the reason most of the rules below exist.

This file is the operational contract and applies in full. It is tool
neutral, so Codex and any other agent read the same rules. Claude Code
affordances live in `CLAUDE.md`, which imports this file.

## Definition of done

- `devtools::test()` passes.
- `devtools::check()` is **0 errors, 0 warnings, 0 notes**. It reached
  0/0/0 on 2026-08-20.
- `devtools::document()` has been run and `man/` and `NAMESPACE` are
  committed with the source change.
- A new template renders, and has its own `.lintr` entry — see the rules
  below.

## The automated gates

| workflow | fails on |
|----|----|
| `R-CMD-check.yaml` | `R CMD check` across platforms |
| `check-manual.yaml` | the PDF manual build. ⚠️ **Post-merge only**, see below |
| `lint.yaml` | [`lintr::lint_package()`](https://lintr.r-lib.org/reference/lint.html) |
| `pkgdown.yaml` | the site build |
| `spec-counts.yaml` | three checks. `check-spec-counts.py`, the prose in `dev/specs/` must agree with the generated map. `check-flow-counts.py`, every `data-check` anchored number in the job flow diagrams must agree with the maps they copy from. `check-roadmap-counts.py`, the roadmap ledger and `inst/templates/` must agree **in both directions**, so a template no ledger row claims fails the PR just as a row claiming an absent template does. Editing a count without regenerating fails the PR |
| `test-coverage.yaml` | coverage upload |

⚠️ **`check-manual.yaml` is not a PR gate.** Its triggers are `push` to
`main` and `workflow_dispatch`; there is no `pull_request` among them,
so the PDF manual build runs for the first time *after* a change has
already merged. A change that breaks the manual therefore passes every
check on its PR and fails on `main`, where there is no PR left to fix it
in. Every other workflow in this table does run on `pull_request`. If a
change touches Rd markup (Greek, `\eqn{}` content, combining marks,
anything the PDF pipeline renders), build the manual locally before
merging rather than trusting a green PR.

⚠️ **A green `R-CMD-check` job can hide a suite that skipped the tests
you care about.** The job’s conclusion reports whether `R CMD check`
failed, and a `skip_if_not()` is not a failure. Read the `testthat`
summary *inside* the log, not the check mark beside it:

``` sh
gh run view <run-id> --log | grep -E "SKIP [0-9]+ \| PASS"
```

Found the expensive way in `hvtiRlifetables`, whose regression guard for
a shipped bug reported `SKIP 5 | PASS 474` on macOS and Windows against
Linux’s `SKIP 0 | PASS 483`. It covered one platform of four, had never
once run on Windows, and every check stayed green through ten CI runs
and two code reviews. Three independent causes, each hidden behind the
last. Nothing in a conclusion, a check mark, or a review surfaced it;
only the per-platform summary lines did.

⚠️ **And a test FILTER silently decides which code paths CI exercises at
all.** `R-CMD-check.yaml` runs one extra step, scoped to a single matrix
leg, that loads the package from the source tree with `HVTI_JOBS`
pointed at a checked-out catalog. It is the only place the
catalog-reading tests actually run, because the tarball `R CMD check`
builds has no catalog. That step takes a `filter=`, which is ONE regular
expression matched against test-file names, so it is widened by
alternation (`roadmap|taxonomy`), not by adding to a list:

``` sh
gh run view <run-id> --log | grep -E "SKIP [0-9]+ \| PASS"   # read EVERY step, not just the check legs
```

On 2026-09-09 the filter was `"roadmap"` while the change under review
was in `test-taxonomy.R`. That file therefore ran only inside
`R CMD check`, where the catalog is always absent, so its new
catalog-first lookup took the taxonomy fallback on every platform and
the branch the pull request existed to add had **no coverage at all**.
Ten green checks and an approving Copilot review said otherwise. The
tell was in the summaries: `SKIP 3 | PASS 231` on the check legs beside
`SKIP 0 | PASS 5` on the strict step, five being the roadmap file alone.
Widened to `"roadmap|taxonomy"` in
[\#98](https://github.com/ehrlinger/hvtiRtemplates/pull/98).

**Widen the filter whenever a test starts reading the catalog**, and
when a change adds a branch that only runs with the catalog present,
assert it: every template shipped today sits in the folder
[`hvti_taxonomy()`](https://ehrlinger.github.io/hvtiRutilities/reference/hvti_taxonomy.html)
names, so catalog and taxonomy agree and a regression to taxonomy-only
stays green. Drive such a test from a TEMPORARY catalog, so it covers
the divergent case and does not go stale when the real one is edited.
Prove it by mutation, not by counting assertions: revert the code and
confirm the new tests go red.

## Rules for this repo

- **`_pkgdown.yml` deliberately has NO `reference:` section**, so
  pkgdown indexes every export automatically and the index cannot drift
  out of step with `NAMESPACE`. Do not add one. ⚠️ Its sibling
  `hvtiRutilities` does the **opposite**: an explicit index that
  *errors* on a missing topic. Two packages, inverted conventions. Do
  not carry a habit across.
- **Lines are 135 characters here, not 80.** `.lintr` raises
  `line_length_linter` because
  [`hvti_taxonomy()`](https://ehrlinger.github.io/hvtiRutilities/reference/hvti_taxonomy.html)
  is a data table written as code — 42 column-aligned rows whose
  alignment is the only thing making them legible. Every other default
  linter is on and enforced, `commas_linter` included: it has already
  caught taxonomy rows whose alignment slipped. ⚠️ `hvtiRutilities`
  enforces 80. Check `.lintr` before assuming a width.
- **A new template needs its own key in `.lintr`, and the key must be
  the FILE.** A directory key such as `inst/templates` excludes every
  linter on that path **wholesale and silently** — six real indentation
  and brace lints in `ac.qmd` vanished from a clean run that way. Only a
  file key honours a per-linter list. The friction is deliberate: it
  forces a decision per template instead of blanket-exempting the
  directory.
- **Templates carry no study identifiers.** `test-new-job.R` asserts
  that no template matches `/studies/`, a study name, or a built-dataset
  filename. A template that names a study is not a template.
- **Every study-specific line in a template is marked `EDIT:`.** The
  markers are the interface; a job still containing one is unfinished.
  Comments around them should say *why* a choice matters, not merely
  what to type — several exist because the alternative fails quietly.
- **A template is only added once two studies have exercised the
  shape.** A template extracted from a single example encodes that
  study’s choices as though they were general. The second exemplar need
  not be R: `hm` took a SAS job, which states those choices as plainly
  as an R port does. ⚠️ **The gate is open for every prefix the taxonomy
  documents, and nothing is waiting on a second exemplar.** A corpus
  census
  ([`hvtiRutilities::job_census()`](https://ehrlinger.github.io/hvtiRutilities/reference/job_census.html),
  2026-08-27) over all of `/studies` found no prefix anywhere at one
  study; the smallest are `bq` at 2 and `cp`/`pm` at 5. An earlier
  version of this rule named `hz` and `hp` as blocked at one study each.
  That was read off a comparison of two directories and stated as though
  it held for the corpus; both shipped, in 1.0.6 and 1.0.7. **Do not
  quote a per-study count as a gate answer** — run the census.
  `inst/templates/README.md` carries the numbers and the list of what is
  still untemplated.
- **Templates carry their own `format:` block** rather than inheriting
  from a project `_quarto.yml`. A file meant to be copied must not
  depend on the directory it happens to sit in — that is how
  server-rendered reports ended up with sibling `_files/` trees instead
  of being self-contained.
- **Roxygen here is Rd markup, not markdown.** `DESCRIPTION` has no
  `Roxygen: list(markdown = TRUE)`, so backticks and `**bold**` land
  literally in the `.Rd`. Use `\code{}`, `\strong{}`, `\emph{}`,
  `\itemize{}` and `\link{}`.
- **`testthat` edition 3.** There are snapshot tests under
  `tests/testthat/_snaps`; review a snapshot diff rather than accepting
  it reflexively.
- **This repo holds templates only.** The SAS macro corpus was removed
  on 2026-08-14 and lives in `~/Documents/macro.library`. Do not
  reintroduce it here.

## Template naming

A template file is `<prefix>[-<qualifier>].qmd` and lives in a numbered
directory named for the taxonomy folder it scaffolds into,
e.g. `inst/templates/20_distributions/ac.qmd` or
`inst/templates/40_graphs/dp-trends.qmd`.

    00_datasets   10_descriptive   20_distributions   30_analyses
    40_graphs     50_documents                        90_estimates

**The digits order the directories and are ASSIGNED, not derived.**
`estimates` is 90 though it is fifth in the taxonomy, because it holds
saved output rather than jobs. Deriving a number from a row position is
the defect this scheme removed, so do not “fix” 90 to 50. The decade
gaps are deliberate room: a new folder goes in at 25 and shifts nothing.

⚠️ **`inst/templates/` uses the numbered directories. A STUDY does
not.**
[`new_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/new_job.md)
writes into the bare taxonomy name, `distributions/` and `analyses/`,
because that is what studies already have: 63,278 and 119,582 corpus
files respectively. Writing a job into `20_distributions/` would split a
study’s estate across two spellings of one folder.
[`template_list()`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_list.md)
reports `folder` with the digits stripped for the same reason.

**The qualifier names a job type within a prefix, and is optional.**
`dp-trends` is the first template to carry one. The qualifier exists
because `graphs/dp` is `trends`, `spaghetti`, `procs` and more under one
prefix, and a filename that cannot say which job it is, is one a study
author cannot search. Decided 2026-09-02, see
`dev/specs/2026-09-02-dp-dc-decomposition-design.md`.

⚠️ **A prefix may hold SEVERAL ledger rows, keyed on
`(prefix, qualifier)`.** `check-roadmap-counts.py` enforces the pair,
and also enforces that a prefix is **wholly qualified or wholly
unqualified**. A half-decomposed prefix is a state the ledger could
describe and the package would refuse to use, because the ambiguity
error would offer an unqualified row that no caller can ask for.

⚠️ **`qualifier` is `[A-Za-z0-9_]+`, and a prefix may never contain
`-`.** `-` is the filename’s field separator, so a prefix carrying one
would make the name ambiguous.

⚠️
**[`template_path()`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_path.md)
and
[`new_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/new_job.md)
REFUSE to guess when a prefix is ambiguous.** Naming no qualifier where
a prefix carries several is an error listing the choices, never a silent
pick of the first. Selecting with
[`match()`](https://rdrr.io/r/base/match.html) returned the first row
and said nothing about the rest, which is the same shape as the bug that
made `dp` look like one job type.

⭐ **THE ORDINAL IS GONE, dropped 2026-09-03.** Templates were once
`<NN>.<MM>-<prefix>.qmd`, so `03.01-ac.qmd` and `04.05-bh.qmd`. `NN` was
the taxonomy folder’s position and duplicated the directory the file
already sat in; `MM` was a key assigned once per folder, asserting an
order among a folder’s templates that does not exist. Both are removed:
`NN` moved onto the directory where it is the thing rather than a copy,
and `MM` went because nothing needed it. See
`dev/specs/2026-09-03-template-identity-design.md`.

⚠️ **Old filenames are still in the wild, and `04.06` will never be
explained by anything else.** A retirement register used to record that
`04.06-bh` shipped in 1.0.13 and 1.0.14 before `bh` was renumbered to
`04.05`; that register went with the ordinal. So: an `NN.MM` in a
filename is a pre-1.1.0 job, `04.06-bh` and `04.05-bh` are the same
template, and no ordinal will ever be issued again. Do not reintroduce
the field to explain one.

`new_job(prefix, endpoint, type, dir = ".", qualifier = NULL)` writes
`<folder>/<endpoint>-<type>-<prefix>[-<qualifier>].qmd`, where
`<folder>` is the BARE taxonomy name and not the numbered directory the
template sits in, and **refuses to overwrite an existing job**, because
a job file accumulates a study’s edits. `endpoint` and `type` name the
`(endpoint, analysis type)` set the job belongs to; both are required
and both are restricted to `[A-Za-z0-9_]+`, because `-` is the
filename’s field separator and `.` separates the extension.

**A template must have exactly one `^ENDPOINT\s+<-` line and one
`^TYPE\s+<-` line.**
[`new_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/new_job.md)
substitutes both after copying, and hard-stops if either is missing,
duplicated, or moved — a template that fails this check cannot be
scaffolded at all.

## Gotchas

- **`object_usage_linter` can never pass inside `inst/templates/`.** The
  templates call `TemporalHazard` and `hvtiRutilities`, which are the
  *study’s* dependencies and deliberately absent from `DESCRIPTION`, so
  CI has no copy and every call reports “no visible global function”.
  That is why the exclusion exists; it is not licence to disable it in
  `R/`.
- **`object_name_linter` is excluded for templates on purpose.**
  `CLEVEL`, `TIME`, `STATUS`, `DERIVED` and friends are SCREAMING_CASE
  so a study author sees at a glance what to change, and `CLEVEL`
  carries the name of the SAS macro parameter it replaces. Do not
  snake_case them.
- **`commented_code_linter` is excluded for templates on purpose** —
  commented scaffolding such as `# d <- read_built()` is the template
  showing its user what to uncomment.
- ⚠️ **The `nu = 0` warning that stood here is withdrawn, and should not
  be reinstated from an older note.** It said a future `hz` template
  must not ship `nu = 0` while
  [temporal_hazard#143](https://github.com/ehrlinger/temporal_hazard/issues/143)
  was open. That issue closed COMPLETED on 2026-08-25, in two opposite
  directions: the tail-divergence half was **retracted in-thread as not
  a defect** — C case 4 transcribes exactly to R’s Case 2L, `rho`
  included, and production SAS output reproduces at all 14 nomogram
  points — and the identifiability half **shipped** in TemporalHazard
  1.2.5
  ([temporal_hazard#182](https://github.com/ehrlinger/temporal_hazard/pull/182)),
  which warns when a phase has effectively left the model.
  `03.02-hz.qmd` ships `nu = 1` as a neutral `EDIT:` starting value, not
  as a workaround, and a `nu = 0 fixnu` phase transcribed from a SAS fit
  is fine.

## Change discipline

1.  **Think before coding.** Do not assume, ask. If the request is
    ambiguous or a name, path or signature is uncertain, surface the
    confusion rather than running with a guess.
2.  **Simplicity first.** Write the minimum that solves the stated
    problem. No speculative abstractions.
3.  **Surgical changes.** Touch only what the task requires. Do not
    refactor, reformat or re-style adjacent code. Raise nearby problems
    separately rather than folding them in.
4.  **Goal-driven execution.** State what done looks like before
    starting, and use tests as the criterion. If no test covers the
    change, add or propose one.

## Git and versioning

- **Never push to `main`.** Branch, open a PR, let the maintainer merge.

- **`main` is protected by a GitHub ruleset, and nothing in this repo
  records that.** A clone shows no trace of it, so it is stated here.
  The ruleset is named `protect main`, is active on twelve repositories
  in the HVTI R package family, and enforces four rules on the default
  branch: no deletion, no force-push, pull-request-only, and an
  **automatic Copilot code review**. A direct push to `main` is rejected
  by the server, which is the ruleset and not a local hook, and the fix
  is to branch, never to force past it. ⚠️ **Copilot review credits are
  AVAILABLE again, measured 2026-09-09.** Three pull requests drew
  reviews that day:
  [\#95](https://github.com/ehrlinger/hvtiRtemplates/pull/95) and
  [\#98](https://github.com/ehrlinger/hvtiRtemplates/pull/98) here, and
  [hvtiR#57](https://github.com/ehrlinger/hvtiR/pull/57). None returned
  a quota body. The maintainer’s report on 2026-09-03 was that the
  exhaustion would last until October; it did not, and no explanation
  for the early return is available from here. **Measure, do not reason
  from either date.** ⚠️ **Latency is wider than the range recorded
  below, and a slow bot invites a false conclusion.** Measured
  2026-09-09: hvtiR#57 was reviewed 2m48s after opening, and \#98
  12m46s, against the 14-seconds-to-6-minutes range below. \#98 looked
  unrequested at the two-minute mark, was re-requested by script, and
  produced a review at 12m46s. **Do not read that as the re-request
  working.** The timeline shows the ruleset’s own
  `review_requested -> Copilot` at 20:45:13Z, two seconds after the PR
  opened, so an automatic request was already outstanding the whole time
  and the scripted one is not distinguishable from waiting. Widen the
  expectation to at least 15 minutes before concluding anything. ⚠️
  **The timeline resolves “not requested” from “slow”, which the reviews
  list cannot.** This is the better check, and it was not here before
  2026-09-09:

  ``` sh
  gh api --paginate repos/<o>/<r>/issues/<n>/timeline \
    --jq '.[] | select(.event=="review_requested") | "\(.created_at) \(.requested_reviewer.login // "bot")"'
  ```

  A `review_requested` naming Copilot means one is outstanding and the
  answer is to wait. No such event means it never fired, and only then
  is a re-request the right move. ⚠️ **The event count is also how to
  verify a re-request, and it beats polling the reviews list.** Observed
  on \#98: a scripted re-request sent while the automatic request was
  still outstanding added NO event, and the same mutation sent after
  that review had landed added one, taking the count from 1 to 2. The
  mutation returns 200 either way. The consistent reading is that
  `union: true` is a no-op against an outstanding request and only
  registers once the previous one has been fulfilled, which is inference
  from two observations rather than documented behaviour, so check the
  count rather than trusting either the 200 or this sentence. It is a
  cheaper signal than the review-count polling below, because it moves
  immediately instead of after the bot finishes. Count it across pages
  with `wc -l`:

  ``` sh
  gh api --paginate repos/<o>/<r>/issues/<n>/timeline \
    --jq '.[] | select(.event=="review_requested") | .created_at' | wc -l
  ```

  ⚠️ **The quota announces itself, so do not guess.** Once the quota IS
  hit, an unanswered re-request is distinguishable from a slow bot:
  Copilot posts a review saying so, and it is visible in the reviews
  list:

  ``` sh
  gh api --paginate repos/<o>/<r>/pulls/<n>/reviews \
    --jq '.[] | select(.user.login | startswith("copilot")) | "\(.submitted_at) quota=\(.body | test("quota limit"))"' \
    | tail -1
  ```

  `quota=true` on the latest line means the credits are gone. Reviews
  come back oldest first, so the last line printed across all pages is
  the newest review. An empty result on its own is ambiguous; the
  timeline check above is what separates slow from not-requested, so use
  both rather than concluding from this one. ⚠️ **A merge can still
  reach `main` unread, for reasons that outlive the quota.** The
  `copilot_code_review` rule stays in the ruleset and does not block a
  merge, so a PR that draws no review opens and goes green exactly like
  one that did. Three ways that happens even with credits: the review
  does not fire automatically (see \#98 above), the PR was opened
  against a branch other than `main` so the rule never applied, and,
  most often, the review covers only the commit the PR was opened with,
  because the ruleset’s `review_on_push` is off (see below). Nothing
  else in the ruleset reads the diff: it requires no approving review,
  and CI checks compilation, tests, lint and the count guards, none of
  which reads for correctness. ⚠️ **Run `/code-review` locally before
  opening a PR**, and say in the PR body that it stood in for the bot,
  so a reader can tell a reviewed change from an unreviewed one. Do it
  for every substantive push, not only the first, because the bot will
  not. Measured on
  [\#98](https://github.com/ehrlinger/hvtiRtemplates/pull/98): the
  review landed at 20:57:59Z and the commit that carried the whole point
  of the change was pushed at 21:01:52Z, so the standing approval was
  given four minutes before the code it appears to approve existed. For
  scale, so the cost is legible: over 2026-09-02/03 the Copilot reviewer
  found roughly twenty real defects across eight PRs, including a logic
  error that misreported two unqualified templates as a mixed prefix, an
  `NA`-versus-`"NA"` collapse in a uniqueness key written in the branch
  that fixed the same collapse elsewhere, a released recommendation
  built on a sample of two, and nine broken paths in a user-facing table
  in the last PR before the quota bit. Against that, on 2026-09-09 it
  returned two presentation nits on \#95 and nothing on \#98 or
  hvtiR#57, while the three genuine defects those branches carried were
  found by the local review instead. **A bot approval is evidence the
  diff was read, not evidence it was read well.**
  _(History (superseded 2026-09-09): this paragraph read “Every merge NOW reaches `main` unread”, as a consequence of the exhausted quota above. The quota returned; the paragraph is rewritten around the three causes that do not depend on it, all of which were true while the quota was the visible one.History (superseded 2026-09-03 20:00): this paragraph read that credits were “reported EXHAUSTED … but reviews were still arriving”, citing \#79 and \#80 drawing substantive reviews that afternoon, \#80’s at 18:50 UTC. That was accurate when written and the cutoff landed roughly an hour later.)
  ⚠️ **No approving review is required.**
  `required_approving_review_count` is **0** here, measured 2026-09-10,
  so a solo-authored PR merges on its required status checks alone and
  needs neither a second reviewer nor an `--admin` bypass. The gate that
  does exist is `required_status_checks`: ten contexts, all of which
  must report `SUCCESS`, which is why a PR briefly shows `BLOCKED` while
  its checks are still running. Copilot reviews are `COMMENTED`, never
  `APPROVED`, and would not have satisfied an approval rule anyway.
  `require_code_owner_review` is **false**, and no repository in the
  family has a `CODEOWNERS` file.
  _(History (superseded 2026-09-10): this paragraph read “A PR needs one approving review, and you cannot give it to your own PR … `required_approving_review_count` is **1** in eleven of the twelve”, and recommended an admin merge or a second reviewer. That matched the 2026-09-02 measurement below and had stopped being true by 2026-09-10, when [\#101](https://github.com/ehrlinger/hvtiRtemplates/pull/101) showed `CLEAN` with no review decision at all.)
  ⚠️ **The ruleset is near-uniform across the family, with one
  outlier.** Measured over all fifteen `hvti*`/`TemporalHazard`
  repositories on 2026-09-10:

  | repository | approvals | `require_code_owner_review` | `review_on_push` | rules |
  |----|----|----|----|----|
  | twelve, this one included | 0 | false | false | 5, including `required_status_checks` |
  | `hvtiBoostmtree` | **1** | false | false | 4, no `required_status_checks`; also reviews draft PRs |
  | `hvtiEDAreports` | n/a | n/a | n/a | none, because the repository is **archived** and therefore read-only |
  | `temporalHazards` | unknown | unknown | unknown | unreadable: private, and GitHub serves a private repository’s rulesets only on a paid plan |

  The twelve are `hvtiGraphics`, `hvtiPlotR`, `hvtiR`, `hvtiRbootstrap`,
  `hvtiRdatabuild`, `hvtiRimputation`, `hvtiRlifetables`,
  `hvtiRpropensity`, `hvtiRtables`, `hvtiRtemplates`, `hvtiRutilities`
  and `TemporalHazard`. `hvtiBoostmtree` left the `hvtiR` registry at
  1.1.2, replaced by `ggBoostedTrees`, which is the likeliest reason its
  ruleset was not brought along; it is recorded here, not changed. This
  paragraph has now been wrong about the family twice, in opposite
  directions, so the lesson stands: **read the ruleset for the repo you
  are in** rather than trusting any family-wide claim, including this
  one.
  _(History (superseded 2026-09-10): measured over fourteen repositories on 2026-09-02, the table read ten, this one included, at 1 approval, code-owner review false and 4 rules; `TemporalHazard` at 1, false, and 5 with `required_status_checks`; `hvtiGraphics` at **0**, **true** and 4; `hvtiEDAreports` archived; `temporalHazards` unreadable. Before that, from `f0043c0` on 2026-08-20 until 2026-09-02, this paragraph claimed the ruleset was identical across the family, which described `hvtiGraphics` alone.)

  ``` sh
  gh api repos/ehrlinger/<repo>/rules/branches/main \
    --jq '.[] | select(.type=="pull_request") | .parameters'
  ```

  ⚠️ `require_extra_approval_for_unattributed_changes` is **true** in
  all thirteen repositories with a ruleset (measured 2026-09-10). GitHub
  documents it as requiring one additional approval when the Copilot
  coding agent opens a pull request that is not attributed to a person.
  With approvals otherwise at 0, it is the only way this ruleset can
  demand an approval at all, and it does not touch a PR opened from a
  person’s account, whoever wrote the commits. ⚠️ **A stacked PR gets no
  Copilot review, and still reaches `main`.** The ruleset’s condition is
  `ref_name: include: ["~DEFAULT_BRANCH"]`, so `copilot_code_review`
  fires only for a PR opened *against* `main`. Open one against another
  branch — stacking a plan on its design, say — and it never fires. When
  the parent merges, GitHub retargets the base to `main`, but
  **retargeting is not a PR-opened event and does not trigger it
  either**. The PR then sits one click from `main` having been read by
  nobody, and with no approving review required, nothing stands between
  it and a merge but green checks. Observed on
  [\#42](https://github.com/ehrlinger/hvtiRtemplates/pull/42). The fix
  is to open against `main`. ⚠️ **Copilot reviews a PR once, as opened,
  because the ruleset tells it to.** This is a setting, not a limit of
  the bot: `copilot_code_review.review_on_push` is **false** in all
  thirteen repositories with a ruleset (measured 2026-09-10), and
  GitHub’s documentation for that option reads “If this option is not
  selected, Copilot will only review the pull request once.” Turning it
  on would review every push, and would spend Copilot credits on every
  push, the budget that ran out on 2026-09-03; that trade-off is the
  maintainer’s call. While it is off, commits added after the review
  reach `main` read by nothing but CI, and no other setting catches
  that: `dismiss_stale_reviews_on_push` and `require_last_push_approval`
  are both **false** in all thirteen, and with no approval required they
  would gate nothing anyway. Observed on
  [hvtiRlifetables#21](https://github.com/ehrlinger/hvtiRlifetables/pull/21),
  where an approval stood while the branch replaced its entire mechanism
  underneath it, and on
  [\#98](https://github.com/ehrlinger/hvtiRtemplates/pull/98) above.
  _(History (superseded 2026-09-10): this paragraph read “Copilot reviews a PR as opened, and never re-reviews a later push”, as though the bot could not. It can; the ruleset has it switched off.)
  ⚠️ **Re-requesting one CAN be scripted, contrary to what this file
  said until 2026-08-31.** The REST `requested_reviewers` endpoint does
  return 200 and silently do nothing; it answers
  `requested_reviewers: []` under either `Copilot` or
  `copilot-pull-request-reviewer[bot]`. But the conclusion drawn from
  that, that the Reviewers menu was the only route, was wrong. `botIds`
  is a **separate GraphQL input field** from `userIds`, which is why the
  REST `reviewers[]` array cannot express it:

  ``` sh
  gh api graphql -f query='mutation($pr:ID!,$bot:ID!){requestReviews(input:{pullRequestId:$pr,
    botIds:[$bot], union:true}){pullRequest{reviewRequests(first:5){nodes{requestedReviewer{
    __typename ... on Bot{login}}}}}}}' -F pr=<PR_node_id> -F bot=<BOT_node_id>
  ```

  Take the bot’s node id from an existing review **by that bot**,
  filtering explicitly rather than taking the first review, which may be
  a human’s and whose id `botIds` will not accept:

  ``` sh
  gh api repos/<o>/<r>/pulls/<n>/reviews \
    --jq '[.[] | select(.user.login | startswith("copilot"))][0].user.node_id'
  ```

  This needs at least one prior review by the bot on some PR in the
  repo; any of them will do, since the id is per installation rather
  than per PR. `union: true` adds rather than replaces. ⚠️ **Do not
  verify with `gh pr view <n> --json reviewRequests`, which this file
  said until 2026-09-01.** That reads `[]` immediately after a
  re-request that WORKED, so it cannot tell success from failure and its
  emptiness means nothing. Measured twice on
  [\#64](https://github.com/ehrlinger/hvtiRtemplates/pull/64): both
  mutations returned 200, both left `reviewRequests` empty, and both
  produced a review, at 4 minutes and at 14 seconds. The advice was
  right that a 200 proves nothing and wrong about what to check instead.

  **Verify against the reviews list, by counting.** Record the count
  before, then poll until it rises:

  ``` sh
  gh api --paginate repos/<o>/<r>/pulls/<n>/reviews \
    --jq '.[] | select(.user.login | startswith("copilot")) | .id' | wc -l
  ```

  ⚠️ **`--paginate` is not optional.** That endpoint returns 30 per
  page, so a long-running PR can carry the review you are waiting for on
  a later page and the count comes back unchanged. A verification that
  silently undercounts is the same defect as the one this paragraph
  replaced, one endpoint further along. Raised by Copilot on the PR that
  wrote this. ⚠️ **But `--paginate` alone does not make an aggregate
  correct: `--jq` runs once PER PAGE.** An expression that collects into
  an array, `[.[] | ...] | length` or `| last`, therefore prints one
  answer per page rather than one answer. Measured 2026-09-10 with the
  page size forced to 1: the count form printed `1 1 0 1` instead of
  `3`, and the `last | .body` form ended on whichever page came last,
  not on the newest review. The commands in this file emit one line per
  item and let `wc -l` or `tail -1` do the aggregating after the pages
  are joined. `--slurp` would join them first, but gh refuses it
  alongside `--jq`. Raised by Copilot on
  [\#100](https://github.com/ehrlinger/hvtiRtemplates/pull/100), for the
  timeline command; the two reviews commands above had the same defect
  and had carried it since 2026-08-31.

  ⚠️ **Do not key on `commit_id` matching your head SHA.** It usually
  does, and on
  [\#61](https://github.com/ehrlinger/hvtiRtemplates/pull/61) two
  reviews anchored to a commit that was not head, so that test gives
  false negatives. The same PR produced two reviews **two seconds apart
  on the same commit**, so a count can also rise by more than one.
  Timing ranged from 14 seconds to about 6 minutes across five PRs; do
  not treat “roughly three minutes” as a deadline.

  The underlying claim above still holds: **Copilot does not review
  every push.**
  [\#62](https://github.com/ehrlinger/hvtiRtemplates/pull/62) carried 11
  commits and drew exactly one review, anchored to its last commit. That
  is the control which makes the re-request, not the push, the thing
  producing the extra reviews on \#64. ⚠️ **A re-review can re-raise a
  finding the reviewed commit already fixed**, because it anchors
  against the cumulative `base..head` diff rather than the head alone.
  Check the file before acting on one, with a pattern that survives the
  file’s own markup: a grep for `single -e argument` exits 1 against a
  line reading `` single `-e` argument ``, which turns “verified absent”
  into “not looked for”.

- Versions are **straight three digits** (`1.0.2`). Never a `.9000`
  suffix or a fourth digit.

- **Patch-digit bumps only**, as fixes land. Minor and major are the
  maintainer’s decision.

- **Bump when you name a version, not when you merge.** A pull request
  lands without touching `Version:`. Its entry goes under a
  `# hvtiRtemplates (unreleased)` heading in `NEWS.md`, which you add
  when it is not already there. A separate commit then renames that
  heading to the new version and updates `DESCRIPTION` and its `Date`,
  at most once a day. The heading is gone again after a bump, so the
  next change re-adds it. `.claude/house-style.md` carries the rule and
  the reasoning. `NEWS.md` uses plain `# hvtiRtemplates X.Y.Z` headings
  — **no `Version:` line**, unlike ggRandomForests, whose version-grep
  test requires a DCF-style header.

- **A change that ships nothing gets no `NEWS.md` entry and no bump.**
  That is a pull request whose every changed file is left out of the
  tarball `R CMD build` produces, meaning the base branch’s
  `.Rbuildignore` excludes it: here `.github/`, `AGENTS.md` and
  `CLAUDE.md` among others. One shipped file means the change ships, and
  the usual rules apply. No user can observe a change that ships
  nothing, so the pull request and its commit message are the record.
  Read `.Rbuildignore` rather than judging by feel.

## Prose

Documentation prose — README, roxygen `@description` and `@details`,
template narration — follows the house voice. Template prose has a
second audience: a study author reading it while adapting the file, so
it must explain the reasoning, not only the mechanics.
