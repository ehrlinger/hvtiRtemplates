# Breaking the study build and `vars` into single-purpose actions

**Date:** 2026-10-14
**Status:** design. Sections 3 to 5 were decided by John Ehrlinger on 2026-10-14, in the order
they appear. The census (section 6) is staged on the share and has not been run; its numbers
will be added here when it has, and may move items in section 4.
**Reads with:** `2026-10-13-dataset-creation-design.md` (the master, the study overlay, `bd`'s
cut, sub-projects A to F); hvtiRdatabuild `dev/specs/2026-09-23-cardiac-master-view-design.md`
(query, rename, correct, derive for the master); `2026-09-29-template-data-contract-design.md`
(`read_job_data()`, `WHERE`, the selection record).
**Origin:** the 2026-10-14 Biostats Teams Training, where a walkthrough of a study's `vars`
program showed recodes, age dichotomies, coronary categories, dummy NYHA, missing indicators by
a 5 to 30% rule, log, inverse and square transforms, mean imputation for screening, balancing
scores and match partners, a final variable list, and corrections and patient removals that
do not belong there.
**Packages:** hvtiRdatabuild (the primitives), hvtiRtemplates (`bd`, the vars template, the
`read_job_data()` hook, the adoption job), a private Azure DevOps repository (the rules).

This note is self-contained. It assumes no memory of the session that produced it.

⚠️ No study, variable value or patient identifier appears here. Variable names such as
`ccfid`, `age_ln` or `avstsev` are column names, not values.

## 1. The problem

A SAS study carries two data programs, and neither does one thing.

- **`bd.*.sas` builds `built`.** It reads the dated warehouse pulls, then mixes joins, keeps and
  drops, row deletions, key-matched value fixes, interval derivations, lab joins inside time
  windows, and diagnostic `proc print` and `proc means` output in one file. Sibling programs
  in the same folder (`tp.bd.mult.imput`, `tp.bd.opt_match`, `tp.bd.gmatch_greedy_mayo`,
  `tp.bd.propen.before_after`) show that imputation and matching sometimes live as `bd.*`
  programs rather than in `vars`.
- **`vars.sas` is a runtime macro, not a build step.** Its header calls it the "macro to bring
  in variables for analysis". Each analysis job runs `%inc vars; %vars(...)`, so its output is
  never saved and every job recomputes it. Its arguments are already a module switchboard:
  `IMPUTE` (informative imputing), `MISSING` (mean standardisation), `PROPEN` and `MATCH`
  (merge a score or a match indicator from a dataset another job wrote) and `TRANSF`
  (transforms). The modules exist in spirit; they are knotted into one macro of about 900
  lines that each study copies and edits.
- **`bd.SAStoR.sas`, the bridge to R, runs `%vars` too.** It reads `built`, runs `%vars` with
  its defaults, `keep`s a hand-picked column list and writes the XPORT file R reads. So every
  legacy study already in R carries `vars` output inside its dataset, and that `keep` list is
  the study's de facto variable list.

The copies drift, and the drift carries defects. In one sampled study's `vars.sas`, a coronary
indicator is set to `10` where its three siblings are set to `1`, and the mitral and tricuspid
stenosis-severity fills test the *aortic* severity's missingness, a copy-paste of the aortic
line. Neither would survive a test of one action; both survive a 900-line file.

Two questions from the training are answered here: whether `vars` is still needed (section 3,
decisions 1 and 2) and where study-specific corrections and study-differing rules live
(decisions 3 and 4).

## 2. The boundary this design keeps

From the training, restated as the rule every action is checked against:

- **`bd`** queries, joins, applies corrections, sets the cohort and computes standard
  derivations (intervals, age). It writes `built`.
- **A study job may filter rows and drop columns. It never corrects a value.** Corrections go
  through the study overlay (dataset-creation section 5) so they can later move into the
  warehouse's append-only corrections layer.
- Multiple imputation comes out of `vars` (agreed at the training).

## 3. Decisions

| # | question | answer |
|---|---|---|
| 1 | Where do the deterministic variable actions run (recode, dichotomize, dummies, transforms, missing indicators)? | **As small functions, called by each job.** The study's `R/vars.R` composes them; `.job_setup()` already sources the study's `R/`. Nothing extra is written to disk. Closest to `%vars`, but each action is one call that can be read and tested |
| 2 | How are imputation, balancing scores and match partners produced? | **Each by its own job, saving a small keyed artifact:** `id → score`, `id → match id`, `m × id → completed values`. Analysis jobs join the artifact by key. Seeded once, reviewable, never recomputed per job, never written back into `built` |
| 3 | Where do the rules that differ by study or umbrella live (regurgitation across sources as a maximum or by echo priority, pre-operative AFib blanking post-operative AFib, a mitral cleanup that must not run in aorta studies)? | **Mechanism in a shared library, policy as data.** The primitives (section 5.1) are generic, tested and public. Which primitive applies to which columns for which umbrella is a rule row, kept private (decision 4) |
| 4 | Where are the rule rows kept? | **A private Azure DevOps repository, checked out read-only under `/programs/development/` on the share,** so jobs read it directly. It is version-controlled and reviewed there until it moves into a database table for management, loaded from the same rows |
| 5 | Which rows define an aggregate (the missing-indicator rule, mean-impute screening)? | **The whole `built`, then the job subsets,** as SAS does today. So the vars step runs after the read and before `WHERE` (section 5.3). Computing on the job's cohort was considered and not chosen; it would change numbers relative to the SAS jobs being ported |

## 4. The actions, and where each lives

Each row is one verb. `B` actions are sections of the one `bd` job; `V` actions are functions a
job calls through `vars`; `J` actions are their own jobs.

| # | action | does | home | in SAS today |
|---|---|---|---|---|
| B0 | **adopt** | registers a legacy SAStoR dataset, recording that SAS applied `vars` and the `keep` list | adoption job (#225, sub-project B) | `bd.SAStoR.sas` |
| B1 | **cut** | reads the corrected base, pinned with `as_of` | `bd` | `set modules.bd*_&PULLDT` |
| B2 | **join** | attaches a source by key. A **windowed join** (the latest pre-operative lab before the operation) is a named kind, because its time rule is the part people get wrong | `bd` | `merge`, `proc sql`, lab programs |
| B3 | **correct** | applies the study overlay's cells | `bd` (designed in dataset-creation section 5) | `if ccfid = ... then` |
| B4 | **cohort** | removes rows, each rule with a reason and a count | `bd` for the study's population; `WHERE` in a job | `if ... then delete` |
| B5 | **derive** | standard derivations (intervals, age, BSA) from the master's own definitions | `bd` | scattered through `bd` |
| B6 | **select** | keeps or drops columns | `bd` | `keep`, `drop` |
| B7 | **register** | writes `built` and registers a dated version | `bd` | none |
| V1 | **recode** | categorical recode | vars function | `vars.sas` blocks |
| V2 | **dichotomize** | cut-points and groupings into a new column | vars function | `vars.sas` |
| V3 | **dummies** | indicator columns from a categorical | vars function | `vars.sas` |
| V4 | **rule** | a study- or umbrella-differing derivation, from a rule row | vars function | `tp.vars.<umbrella>` |
| V5 | **transform** | log, inverse, square, with their scale constants | vars function | `%ln`, `%inv` |
| V6 | **missing flags** | indicators by the 5 to 30% rule, on the whole `built` | vars function | the flag block |
| V7 | **screening fill** | mean fill for screening only, on the whole `built`, with the means recorded | vars function | `MISSING=` (`proc standard replace`) |
| V9 | **informative fill** | a missing value set to a stated constant (`if x = . then x = <constant>`), recorded per column | vars function | `IMPUTE=` |
| V8 | **variable sets** | named variable lists for analyses | data in the study's `R/`, not a function | `%let` lists, SAStoR's `keep` |
| J1 | **impute** | `m` completed datasets, keyed and seeded | own job (`mi`) | `proc mi`, `tp.bd.mult.imput` |
| J2 | **balancing score** | `id → score` | own job (`lm-propensity_*`, `rm-balancing_continuous`) | `PROPEN=` |
| J3 | **match** | `id → match id` | own job; prefix open (section 8) | `MATCH=`, `tp.bd.*match*` |
| | **diagnostics** | prints and summaries of intermediate data | `dt` job, or `bd`'s report | `proc print`, `proc means` in `bd` |

Three rules follow, each checkable by the census and later by a test:

1. **`bd` never recodes or transforms.**
2. **`vars` never filters rows and never corrects a value.** A correction found in a `vars`
   program moves to the overlay (B3); a patient removal moves to the cohort (B4).
3. **A J action never writes into `built`.**

## 5. Mechanism

### 5.1 Primitives, in hvtiRdatabuild

`recode()`, `dichotomize()`, `dummies()`, `transform_ln()`, `transform_inv()`, `transform_sq()`,
`missing_flags(rule = c(0.05, 0.30))`, `screening_fill()`, and the rule primitives
`max_across()`, `coalesce_by_priority()` and `set_missing_if()`. Names are working names and
settle in the implementation plan. Each one:

- takes a data frame and returns it, so a study's `vars` is a pipe of calls;
- attaches an **action record**: the action, its inputs and outputs, how many values it set,
  and, for an aggregate, the statistics it used;
- **is idempotent, or refuses.** If its output column already exists it checks that the
  values agree and stops, naming the column, if they do not. This matters for adopted studies
  (B0), whose data already carry SAS's `vars` output: a second pass must not silently
  transform twice or replace one definition of `age_ln` with another.

### 5.2 Rules, in a private repository

A rule row names the umbrella, the output column, the primitive, its inputs and arguments,
an owner and a date. Umbrella sets (aorta, CABG, valve anatomy and pathology, supplemental,
matching the `tp.vars.*` modules that exist today) are the rows that share an umbrella. A
study picks its umbrellas in a study choice marked `EDIT:`. A job records the rules file's
commit and SHA-256 in its provenance, as it records the overlay's.

The rows are data, not code, so loading them into a database table later changes where they
are read from and nothing about what they say. That is also why they do not conflict with the
master port's derivations written as SQL (dataset-creation decision 8): those define the
master's standard columns (B5); these define study analysis variables.

### 5.3 The hook in `read_job_data()`

`read_job_data()` gains a `vars` argument, a function, run **after the read and before
`WHERE`**. That is the SAS order (`%vars`, then subset), and it is what makes decision 5 hold
without a second read: aggregates see the whole `built`. Row-wise actions give the same values
either way. The action records travel in the selection record and print in "About this run".

### 5.4 Keyed artifacts

Each J job writes a parquet keyed by `ID` (and the imputation number for J1), registered like
any dataset with the `built` version it was computed from. An analysis job joins one with a
helper, working name `join_artifact(d, "propen")`, which **stops if the artifact was computed
from a different `built` version** than the job read, since a score fitted to last month's
cohort is wrong for this month's without anything looking wrong.

## 6. The census

`dev/specs/artifacts/2026-10-14-bd-vars-census.py`, staged on the share at
`general/_development/bd-vars-census-20261014/` with `RUN-INSTRUCTIONS.md`, run on the server
over `/studies`. Tests: `dev/specs/artifacts/test_bd_vars_census.py`.

- **Files.** Every `bd*`, `vars*` and `*SAStoR*` program under a study's `datasets/` or
  `00_datasets/`; `tp.*` copies are reported separately as templates. Job programs elsewhere
  in the study are read only for their `%vars(...)` calls.
- **Classifier.** Comments stripped, split into statements, one category per statement:
  query, join, correction, patient removal, row filter, column drop, standard derivation,
  recode, dichotomize, missing flag, missing fill, transform, mean impute, MI,
  balancing and match, variable list, diagnostic, other. `%*` macro comments are stripped with
  the other comment forms. Patient removal and missing fill are
  added to the categories asked for, because the training showed both and neither fits another
  category. It also counts the `tp.vars.*` modules each program includes and whether a SAStoR
  program calls `%vars`.
- **What it answers.** How many studies' build and vars programs contain each category (the
  latest copy of each program in each study, so dated copies such as `bd.data050415` do not
  inflate the count while distinct programs such as `bd.mult.imput` are all kept), and which
  `%vars` switches jobs actually turn on. The switches map to actions as `IMPUTE` to V9,
  `MISSING` to V7, `PROPEN` to J2, `MATCH` to J3 and `TRANSF` to V5, so only `PROPEN` and
  `MATCH` are evidence of J-action use; multiple imputation (J1) is counted from the
  programs' own `proc mi` and imputation-macro statements.
- **Privacy.** A correction is recognised by its shape, a patient key compared with a literal,
  and the literal is never written. The private CSV (paths, hashes, counts) stays on the
  share; the public JSON holds aggregate counts only and is the file to commit. `tp.vars.*`
  module names stay in the private CSV, because a module can be named for a study; the public
  JSON gives only how many programs include one.
- **Coverage.** A file or folder the scan cannot read is listed in a private
  `-unreadable.txt`, the public JSON is marked `"coverage": "incomplete"`, and the run exits 2,
  so a partial census cannot pass as a complete one.
- **Blind spots.** Macro-generated code is not expanded; a `proc sql` step is classified by
  keyword, not parsed; precedence between categories is the order of the tests in
  `classify()`.

## 7. Sub-projects

Lettered after dataset-creation's A to F, skipping J so it is not read as a J action.

| | sub-project | package | depends on |
|---|---|---|---|
| **G** | Run the census; add its numbers to section 6; move any action in section 4 the numbers contradict | hvtiRtemplates | none |
| **H** | The primitives with action records and idempotence (5.1) | hvtiRdatabuild | none |
| **I** | The private rules repository: row schema, umbrella sets ported from `tp.vars.*`, the CI check that every row names an existing primitive | ADO | H |
| **K** | The `vars` hook in `read_job_data()` (5.3) and a `vars.R` template for a study's `R/` | hvtiRtemplates | H |
| **L** | Keyed artifacts and `join_artifact()` (5.4); the `mi`, balancing and match jobs write them | hvtiRtemplates | dataset-creation A |
| **M** | `bd`'s sections as B1 to B7, each reporting its counts | hvtiRtemplates | dataset-creation D, E |

B0, adoption, is dataset-creation sub-project B (#225); this design adds only that its
provenance records `vars applied by SAS` and the `keep` list as the study's first variable set.

## 8. Open

1. **The match job's prefix.** `cm` is Cox matching in the taxonomy; a match-partner job may
   need a new row or a qualifier. Decide when L is planned.
2. **The rules repository's name and its path under `/programs/development/`**, and who
   reviews rule rows.
3. **Whether `dt` takes over `bd`'s diagnostic output** or `bd`'s report keeps it.
4. **Idempotence tolerance** for adopted data: exact equality, or a tolerance for floating
   transforms written through XPORT.
5. **Whether `si` (single imputation) survives** once screening fill (V7) is a function and
   multiple imputation (J1) a job.

## 9. Out of scope

The master's own build (hvtiRdatabuild's cardiac master design), the overlay's format
(dataset-creation section 7, item 2), and any change to the SAS workflow, which is being
retired and is left as it is.
