# Template sets: how a study scaffolds a chain of jobs

**Date:** 2026-08-21
**Status:** design, approved in outline. No code has been changed by this note.
**Scope:** stage 1 only — the layout and naming convention, applied to the one
template that exists. `new_job_set()` is deferred to its own spec.
**Reach:** §§1–4 and 6–10 are local to this package. **§5.2 is normative for the
whole hvtiverse** — it fixes where every package ships its parity machinery, and
it is documented rather than enforced.
**Supersedes:** nothing. Extends the layout sketch in
`2026-08-18-preserve-root-predim-avail-parity-design.md` §3.

---

## 1. The problem

A study does not run one job. It runs a **chain**: for a given endpoint, an
actuarial life table, then a parametric hazard fit over the same data, then a
figure overlaying both. `preserve_root` records the shape exactly — `01-ac-dead_pa`,
`02-hz-dead_pa`, `03-hp-dead_pa`. Three jobs, one endpoint, one order.

The package cannot express that. `new_job()` copies a single file into a flat
`qmd/` directory and names it `<prefix>.<basename>.qmd`. Nothing records that
the three files belong together, nothing records which runs first, and the
ordering that `preserve_root` does carry is hand-typed into filenames.

Three naming conventions are live in the repository today and they disagree:

| source | shape |
|---|---|
| `hvti_taxonomy()$folder` | `distributions/`, `graphs/`, … — the legacy SAS binder |
| `new_job()` | flat `qmd/ac.dead_pa.qmd` |
| `preserve_root`, in practice | flat `qmd/01-ac-dead_pa.qmd` |

The convention real work converged on is the one the package does not produce.

## 2. What a template set is

**A template set is an ordered chain of job templates instantiated for one
(endpoint, analysis type) pair.** The pair is the unit a study author works
through to completion; the order is what makes the workflow reproducible.
Everything below follows from those two facts.

**The endpoint alone is not the unit, and this is not a refinement — it is a
correctness requirement.** One endpoint is analysed by several methods: death by
parametric hazard (`hz`), death by random-forest survival (`rfs`), death under
competing risks (`ce`), and longitudinal `rfsrc` work arriving soon. The
divergent jobs stay distinct because each method has its own prefix. The *shared
upstream* does not: a death-hazard set and a death-RFS set both begin from the
same Kaplan-Meier life table, and keyed on endpoint alone both would be
`dead_pa-03.01-ac.qmd`. Two sets, one filename.

So the type is carried by **every** job in a set, not only by the divergent one.
This duplicates the shared upstream — `ac` runs once per set rather than once
per endpoint — which is a real cost, accepted because the alternative makes the
type field optional and the naming rule conditional. A uniformly named,
self-contained set is worth one repeated life table.

## 3. The layout rule

Jobs live under the canonical taxonomy folders, and **never more than one layer
beneath them**. Within any folder:

> **Authored files sit flat. Generated artifacts sit under `<set>/`,**
> where `<set>` is `<endpoint>-<type>`.

```
<study_root>/
├── _quarto.yml
├── datasets/       01.01-bd.qmd                    built.rds
├── descriptive/    dead_pa-hz-02.01-dc.qmd
├── distributions/  dead_pa-hz-03.01-ac.qmd    dead_pa-hz-03.02-hz.qmd
│                   dead_pa-rfs-03.01-ac.qmd
├── analyses/       dead_pa-hz-04.01-hm.qmd    dead_pa-rfs-04.19-rfs.qmd
├── estimates/                                 dead_pa-hz/ac.rds
├── graphs/         dead_pa-hz-05.01-hp.qmd    dead_pa-hz/hp-fig1.png
├── documents/      manuscript.qmd
└── parity/         dead_pa-hz-03.01-ac-parity.qmd  dead_pa-hz/ac-diff.csv
```

Each folder's shape *follows from* the rule rather than being declared:
`distributions/` is flat because it holds only source, `estimates/` is nested
because it holds only artifacts, `graphs/` shows both because it holds both.

**Why the asymmetry is right.** Authored files are few, named, and
hand-navigated; a study has two or three `.qmd` per set in a folder. Generated
artifacts are many, machine-named, and swept; one `hp` job emits a dozen figures.
An endpoint directory earns its keep at twenty `.png` and costs more than it
returns at two `.qmd`.

**`datasets/` and `documents/` take no endpoint layer.** `datasets/` holds the
canonical data used throughout the study; `documents/` holds the deliverable.
Neither is endpoint-specific, so neither gets the subdivision.

**The set fragments across folders, and that is acceptable**, because the
ordinal is global to the set rather than per-folder. `dead_pa-hz-05.01-hp.qmd`
announces itself as a later step than `dead_pa-hz-03.02-hz.qmd` despite sitting in a
different directory, and `ls */dead_pa-*` recovers the whole chain in order.

**This preserves the existing root-resolution idiom.** Every authored job is
exactly one level below the study root, so `ac.qmd`'s
`.root <- if (file.exists("_quarto.yml")) "." else ".."` still resolves
correctly and needs no change. Only `estimates/<set>/` is two deep, and
nothing renders from there. An earlier draft of this design nested source by
endpoint as well; that would have broken the idiom in every template, and
flattening the source removed the cost entirely.

## 4. Names

| thing | shape | example |
|---|---|---|
| template | `inst/templates/<folder>/<NN.MM>-<prefix>.qmd` | `inst/templates/distributions/03.01-ac.qmd` |
| scaffolded job | `<folder>/<endpoint>-<type>-<NN.MM>-<prefix>.qmd` | `distributions/dead_pa-hz-03.01-ac.qmd` |
| artifact | `<kind>/<endpoint>-<type>/<prefix>.<ext>` | `estimates/dead_pa-hz/ac.rds` |

Four fields, `-` separated, with `.` reserved for inside the ordinal:
**endpoint, type, ordinal, prefix.**

**The endpoint leads, the type follows it.** In a flat folder holding several
sets, leading with the endpoint keeps all of one endpoint's work contiguous under
`ls`, and the type then splits it by method — recovering in a filename what a
subdirectory would otherwise have bought. Leading with the type instead would
group by method across endpoints, which suits building one method over many
endpoints rather than working an endpoint through to completion.

**The type is a separate field, not joined to the endpoint.** `dead_pa` already
contains an underscore, so `dead_pa_hz` marks no boundary a reader or a regex can
find. A `-` delimited field does.

**A template carries neither endpoint nor type.** Both are supplied at scaffold
time, and `AGENTS.md`'s "templates carry no study identifiers" applies to the name
as much as to the contents.

## 5. The ordinal

`NN.MM`: major from the taxonomy folder, minor the next free position within it.
Both parts zero-padded to two digits.

| major | folder |
|---|---|
| `01` | `datasets` |
| `02` | `descriptive` |
| `03` | `distributions` |
| `04` | `analyses` |
| `05` | `graphs` |
| `06` | `documents` |

**The ordinal is global, not set-relative.** It is fixed per prefix and identical
in every study, so `03.01` means `ac` everywhere and a reader moving between
studies reads the same landmarks. The consequence is that scaffolded sets have
**gaps** — `ac`, `hz`, `hp` produce `03.01`, `03.02`, `05.01`, not `01/02/03` —
and a gap positively says "no descriptive job here" rather than being silent.
This is a deliberate divergence from `preserve_root`'s contiguous numbering,
and it is forced: a set-relative number is not knowable until scaffold time and
therefore cannot live in the template's own filename.

**Two-part rather than decade.** An earlier draft assigned decades — `datasets`
10s, `distributions` 30s — which caps a folder at ten templates. `analyses` has
twenty prefixes. The two-part form has no ceiling, states the hierarchy on its
face rather than hiding it in a tens digit, and keeps the property that made
decades attractive: a new template takes the next free minor and **nothing
renumbers**.

**Zero-padded because the ordering is the workflow.** Unpadded, `ls` sorts
`04.10` before `04.2`. A mis-sorted listing of a reproducible chain is a silent
failure, and one character prevents it.

**The filename is authoritative; the taxonomy is the cross-check.** The ordinal
lives in exactly one place — the template's name — and a test asserts that the
ordinals are consistent with `hvti_taxonomy()` row order and that each major
matches the folder the template sits in. Drift becomes a red test rather than a
discovery. This is the same move that made the taxonomy data instead of a README
table, and for the same reason: the README table drifted.

### 5.1 Parity jobs

A migration study pairs each job with a comparison job checking the R result
against the SAS reference. These live in a **top-level `parity/` folder** that
obeys the same rule as every other — authored files flat, generated comparison
output under `<set>/`:

```
parity/   dead_pa-hz-03.01-ac-parity.qmd      dead_pa-hz/ac-diff.csv
```

**`parity/` is deliberately not a taxonomy folder, and parity is not a prefix.**
The taxonomy is the vocabulary of templatable job types, and parity is neither
templatable nor a type:

- **It is a modality of an existing job, not a job.** It is 1:1 with the job it
  checks and optional — "a future job with no SAS counterpart simply has no file
  in `parity/`". A prefix names one slot, but a study needs parity of `ac`, of
  `hz` and of `hp`. One prefix cannot express "parity of X".
- **It will probably never be templated.** The `preserve_root` design records
  that `lv_function`'s parity pass "transfers to none of these" — different
  likelihood branch, conservation path and sample-size regime. `AGENTS.md`'s
  two-studies gate would never open. Parity jobs are hand-written per study,
  which makes this a layout convention rather than anything `new_job()` touches.
- **It is transient.** It exists to retire SAS. Keeping it in one directory
  makes the eventual cleanup a single delete rather than a sweep across five
  analysis folders, and keeps migration scaffolding out of the permanent tree.

**A parity job borrows the ordinal of the job it checks** — `dead_pa-hz-03.01-ac-parity`
against `dead_pa-hz-03.01-ac`, as `preserve_root` already does. So parity adds no row
to the table in §5. Giving it a seventh major would be actively wrong: parity runs
interleaved with the chain, immediately after the job it checks, not appended
after all of them.

**The `-parity` suffix stays**, redundant with the folder name though it is.
Without it the parity file and its analysis job have identical filenames, and a
study author has two editor tabs both reading `dead_pa-hz-03.01-ac.qmd` with nothing
to tell them apart. Same reason the endpoint is in the filename.

### 5.2 The package side of parity, across the hvtiverse

§5.1 places the parity *jobs*, which live in the study. The parity *machinery* —
the parsers that read the SAS reference output — lives in whichever package owns
the functions being checked. Today that is `TemporalHazard`. It will not stay
that way: parity work is already anticipated against other hvtiverse packages,
so the shape has to be settled before it is copied rather than after.

**Only `temporal_hazard` implements it today.** A survey of all twelve hvtiverse
repositories found `inst/sas-parity/` in exactly one of them. The convention
therefore exists in a single place and is about to be copied eleven times, which
is the moment to write it down.

**The convention has three parts:**

| part | path | why |
|---|---|---|
| the helper | `inst/sas-parity/helper-sas-parity.R` | ships with the installed package |
| the shim | `tests/testthat/helper-sas-parity.R` | preserves testthat's auto-sourcing |
| the reach | `system.file("sas-parity", ..., package = "<pkg>")` | how a study or sibling package loads it |

**Why `inst/` and not `tests/`.** `R CMD INSTALL` skips `tests/` unless
`--install-tests` is passed, so parsers kept there are unreachable after a plain
`install.packages()` or `remotes::install_github()`. A downstream study checking
its own SAS output against them had no route short of cloning the repository.
Everything under `inst/` installs unconditionally. This rationale is currently
recorded only in the header of `temporal_hazard`'s shim; it is reproduced here
because it is the part that will otherwise be lost and rediscovered.

**Why the shim rather than sourcing from `inst/` in each test file.** testthat
auto-sources `tests/testthat/helper-*.R`. Keeping a shim there means test files
see the parser functions exactly as they did when the parsers lived in `tests/`,
and no test file had to change when they moved.

**The filename is uniform across packages.** Every package uses
`helper-sas-parity.R`; `system.file(..., package = )` disambiguates, so there is
no collision to design around and no per-package naming scheme to remember.

**The folder is `sas-parity`, named for what it compares against.** Not `parity`.
The reference is SAS, the comparison is transient, and a name that says so ages
better than one that does not.

**This convention is not enforceable from here.** `hvtiRtemplates` has no reach
into another repository's CI, so a package can diverge from this section without
anything going red. That is the same prose-drifts-from-code failure that produced
`hvti_taxonomy()` and `check-spec-counts.py`, and stating the convention does not
fix it — see §9.

## 6. The endpoint is declared, not derived

A scaffolded job declares its endpoint once, as an `EDIT:` marker near the top,
and computes its artifact paths from it:

```r
# EDIT: the endpoint this job analyses, and the analysis type it belongs to.
# Together they name the set. Their pair names the directory this job's estimates
# and figures are written to, so no output path below needs editing. Both must
# match the corresponding fields in this file's own name.
ENDPOINT <- "dead_pa"
TYPE     <- "hz"
```

Deriving it from the path instead would be free but fragile — it breaks the
moment someone renames a file, and it breaks quietly. Declaring it matches the
contract the templates already have, where every study-specific value is marked
rather than inferred, and it extends `ac.qmd`'s existing aim that no path in the
document needs editing to outputs as well as inputs.

## 7. Stage 1 — what this spec builds

Only the layout and naming, applied to the one template that exists.

1. **Move the template** — `inst/templates/ac.qmd` →
   `inst/templates/distributions/03.01-ac.qmd`.
2. **`template_list()`** — glob recursively; derive `folder` from the directory
   rather than by joining through the taxonomy; add an `ordinal` column parsed
   from the filename.
3. **Replace `.prefix_of()`** — its dot-splitting heuristic (drop a leading
   `tp.`, reject a first field over five characters) exists only because legacy
   names were unstructured. The new name is fully structured, so a regex over
   `^(\d{2})\.(\d{2})-(.+)$` replaces the heuristic and the guesswork with it.
4. **`new_job()`** — write
   `<dir>/<folder>/<endpoint>-<type>-<NN.MM>-<prefix>.qmd`, taking `type` as an
   argument alongside `endpoint`.
   Keep the refusal to overwrite: a job file accumulates a study's edits.
5. **`ac.qmd`** — add the `ENDPOINT` and `TYPE` markers and route outputs
   through `estimates/<endpoint>-<type>/`.
6. **`.lintr`** — the file key becomes
   `inst/templates/distributions/03.01-ac.qmd`. It must stay a file key: a
   directory key excludes every linter on the path wholesale and silently.
7. **Tests** — update the `expect_match(out, "ac[.]dead_pa[.]qmd$")` pin, which
   is a snapshot of the old shape rather than an independent constraint; add the
   ordinal-vs-taxonomy consistency test from §5.
8. **`inst/templates/README.md`** — document the layout rule, since it is the
   file a study author reads before scaffolding anything.

## 8. Deferred

**`new_job_set()`** — the function that instantiates a whole chain. It cannot be
exercised today: `inst/templates/` holds only `ac.qmd`, and `hz` and `hp` are
deliberately absent until a second study has run them. Building the plural now
would ship an untested multi-job path against templates that do not exist. It
gets its own spec once they land.

The `preserve_root` work in progress is what opens that gate — but via its
**analysis** jobs, not its parity pass. `preserve_root` is the second study to
run `ac`, `hz` and `hp`, which is what satisfies `AGENTS.md`'s two-studies rule.
Its parity jobs satisfy nothing, for the reasons in §5.1.

## 9. Open — not decided here

- **`new_job()`'s contract breaks twice.** The output path changes, and
  `basename=` wants to become `endpoint=` with `dir=` defaulting to the study
  root rather than `"qmd"`. Written as `1.0.2 → 1.0.3` because `AGENTS.md`
  reserves the minor digit for the maintainer; it is minor-shaped and that call
  is not this spec's to make.
- **`hs` is misfiled.** `hvti_taxonomy()` files it under `distributions` but
  describes it as "patient-level survival predictions from the HM model". If it
  consumes `hm`, it belongs downstream of `analyses`, and its row position
  breaks the ordinal cross-check in §5. One row, but a taxonomy edit.
- **`hz` stays in `distributions`.** Reviewed and left alone: the line between
  `distributions` and `analyses` is covariates. `hz` fits the hazard shape
  unadjusted; `hm` is "risk factor analysis; builds on the HZ fit". `ac` and `hz`
  are the same curve by different machinery, which is why `hp` overlays them.
- **`estimates/` is not in the taxonomy.** This design uses it as a first-class
  artifact directory, and `preserve_root`'s tree has one, but `hvti_taxonomy()`
  has no `estimates` row — its six folders are `datasets`, `descriptive`,
  `distributions`, `analyses`, `graphs`, `documents`. Nothing breaks, because
  only *source* folders are joined through the taxonomy and
  `test-taxonomy.R` checks that direction only. But the design depends on a
  directory the taxonomy does not know exists, which is precisely the drift the
  taxonomy function was written to prevent. Either add the row or state in
  `inst/templates/README.md` that artifact kinds are deliberately outside the
  prefix taxonomy.
- **The folder is `descriptive`, singular.** Worth flagging because it reads as
  a typo next to `datasets`, `analyses`, `graphs` and `documents`, and was
  written as `descriptives` twice during this design. If it is going to be
  misremembered every time, renaming it is cheaper than correcting it — but it
  is a taxonomy edit and a behaviour change for any study already using the
  folder.
- **§5.2 has no teeth.** The package-side parity convention is documented and
  unenforced. Options, in ascending cost: a shared reusable workflow each repo
  calls; a test in `hvtiverse` asserting every member package's parity layout; or
  a scaffold shipped from here that a package author copies rather than
  reconstructs. Worth deciding before the second package implements parity, since
  after that the divergence already exists.
- **The taxonomy `folder` column conflates two things.** `distributions`,
  `descriptive` and `analyses` classify by analysis *type*; `datasets`,
  `estimates`, `graphs` and `documents` classify by artifact *kind*. Under this
  design the type-half never surfaces to a user — it is a sort key and nothing
  more — so the conflation is quieter than it was, but it is still one column
  doing two jobs. Splitting it is additive and therefore patch-safe; it is not
  required by anything above.

## 10. Definition of done

- `devtools::test()` passes, including the new ordinal-vs-taxonomy test.
- `devtools::check()` is 0 errors, 0 warnings, 0 notes.
- `devtools::document()` run; `man/` and `NAMESPACE` committed with the source.
- `lintr::lint_package()` clean with the relocated `.lintr` file key.
- The relocated template still renders.
- `DESCRIPTION` version and `Date` bumped, with the matching `NEWS.md` entry in
  the same commit.
