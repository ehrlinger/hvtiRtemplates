# Run sheets: a generated run book for every template

**Date:** 2026-10-26
**Status:** designed, approved in conversation 2026-10-26.
**Reads with:** `2026-10-22-run-job-design.md` (`hvti run`, `run_job()`, `guard_memory()`), and the
working-read gate of PR #421 (a draft may read an unregistered build, a final render may not).
**Packages:** hvtiRtemplates only.

## 1. Why

On 2026-10-23 John asked for run books: guidance that ships with the templates and tells an analyst
how to run a job. That session proposed two layers. Layer 1 shipped in PR #407: every gallery row
links its `add_job()` call to the "Work a job" vignette ("Then run it"). Layer 2 was deferred until
the working-read gate settled. It is a sheet for each template that says what *this* template needs,
how its job is laid out and what comes after it.

The readers are the biostatistics team, and the sheets double as training material. So they are
written in sentences that explain, not in terse labels. **The sheet is the outline, and the template
holds the details.** The sheet says what to have ready, what sections the job walks through, how to
run it and where to go next. The comments at each `EDIT:` marker in the template say what to set and
why. The sheet never repeats them.

The hand-written runbook for one study, `dev/TemporalHazard_runbook.md`, shows what goes wrong. Every
warning in it is real, and it described one study's jobs on one date. A sheet written by hand for each
of 44 templates would drift the same way. So the sheet is **generated from the template**, and a test
fails when the two disagree.

## 2. What a sheet says

One page per template, with up to five sections. "What it does", Prerequisites, Outline and Run it
are always present. Where to go next appears only when a template reads this one's output. The
wording below is for `rfs-fit`, and section 3 lists the variants.

> ## `rfs-fit`: Random survival forest
>
> *What it does.* The catalog's description.
>
> **Prerequisites**
> - A study set up with `_study.yml`. *Start a new study* shows how.
> - The study dataset, named by `DATASET` (`"built"` by default). While you work, a draft can read a
>   build that is not registered yet, and the report says so on its first page. The final render needs
>   the build registered with `hvtiRutilities::update_manifest()`.
> - Packages: randomForestSRC (>= 3.7.0), ggRandomForests (>= 4.0.0), hvtiPlotR (>= 2.8.18) and hvtiRutilities.
>   Each floor is checked when the job starts.
>
> **Outline.** These are the job's own sections, in order. The comments at each `EDIT:` marker say what
> to set and why.
> 1. **Study choices**: 10 choices marked `EDIT:`.
> 2. **Cohort**: reads the data.
> 3. **Forest**: fits the forest and caches it, so a later render reloads it (`REFIT` recomputes it).
>    Saves `rfs.rds`, which **rfs-explain** reads.
> 4. **Does the forest work?**
>
> **Run it.** `render_job(job)` renders a draft. Render early and often; the DRAFT banner lists the
> markers still open. Once none are left, `render_job(job, final = TRUE)` renders the final report, which
> refuses unregistered data and any open marker. *Work a job* walks this loop.
>
> **Where to go next.** **rfs-explain** reads the forest this job saves. Add it to the same set, giving
> it this job's subject and type, because that shared pair is how it finds the forest:
> `add_job("rfs.explain", subject = "<this job's subject>", type = "<this job's type>")`.

## 3. Where each part comes from

| Part | Source | Variants |
|---|---|---|
| Title and "What it does" | the catalog row's `name` and `description` | a deprecated template adds its `deprecation_note` |
| Prerequisites: study | always present | none |
| Prerequisites: data | a literal top-level `DATASET <-` assignment | `.job_setup(..., box_data = FALSE)`, the template's own statement that it reads no registered dataset: "Builds the study dataset rather than reading one; it needs the master snapshot named in its choices." `DATASET <- NULL` with no read: no data line |
| Prerequisites: upstream jobs | the **hand-off graph** (below): each template whose saved file this one reads | "Render **ac** and **hz** first, in this same set. For a final render, render them final from registered data, because a final refuses a hand-off saved from an unregistered build." A read with no producer on disk quotes the `rebuild` text instead ("the companion hm selection runner") |
| Prerequisites: runner | a `.read_bootstrap_artifact()` call | "Its screen runs in a companion script, `<prefix>.<subject>.<type>.runner.R`, which `add_job()` writes beside the job. Run that first; this job reports on what it saved." |
| Prerequisites: packages | `.template_packages()`, already used by `add_job()` and the preflight checks | a package with no floor is listed bare |
| Prerequisites: background | a `guard_long_fit()` call | "The `hvti` command on your PATH, from `install_hvti()`." |
| Outline: sections | the template's `##` and `###` headings, read outside code blocks (R chunks and plain fences alike), in order | `###` nests under its `##`. What sits above the first heading (the setup chunk, the "job this replaces" marker) is a lead entry, "Above the first section", shown only when it has a note. A template with no heading at all gets one entry, "The whole job" |
| Outline: per-section notes | what the code in that section calls: `EDIT:` markers (counted), `read_job_data()` ("reads the data"), `.read_handoff()` ("reads *X*'s hand-off"), `.read_bootstrap_artifact()` ("reads what the runner saved"), `cache_fit()` ("fits and caches"; "`REFIT` recomputes it" when the call passes `refit = REFIT`), `guard_long_fit(why = )` ("long: *why*; runs in the background"), `guard_memory()` ("checks memory against the session's limit first"), and `saveRDS(..., <estimates file>)` ("saves `F`, which *Y* reads", only when a template reads it) | a section with none of these is listed by name alone |
| Run it | whether `guard_long_fit()` is called | guarded: "Start it in the background with `hvti run <folder>/<job>.qmd` (add `--final` for the final), or `run_job(job)` from R. It checks the job before it starts, and `hvti status` follows it." |
| Where to go next | the hand-off graph, read in the other direction | none: the section is left out |

### The hand-off graph

A template that writes `saveRDS(x, set_path("estimates", "rfs.rds"))` is linked to every template that
reads `.read_handoff(set_path("estimates", "rfs.rds"), …)`. Both sides are found by the parser, and a
path assigned once at top level (`MODEL_PATH <- set_path("estimates", "lm-binary.rds")`) counts as
literal. This links ac and hz → hp, hz → hm → hs-setup, the rf and vp fit → explain pairs, sid-fit →
sid-clusters, and vt-fit → vt-explain.

Five reads are not literal. Measured with a prototype of the parser on 2026-10-26:

| consumer | read | catalog `upstream` |
|---|---|---|
| `hs-concordance` | `.model_path[[m]]` | `["hm"]`, already there |
| `lm-checkpred` | `MODEL_PATH`, from `MODEL_FILE`, an `EDIT:` choice | none: this change adds `["lm"]` |
| `lp-mirror` | `MODEL_PATH`, from `MODEL_FILE` | `["lm"]`, narrowed by this change to `["lm-propensity_binary"]`, the bundle its description and its `MODEL_FILE` name. With `"lm"`, every lm model, `lm-checkpred` included, read as a mirror's input |
| `vt-fit` | `.vp_path`, and a reader's argument `p` | none: this change adds `["sid-fit", "vp-fit"]` |
| `vt-explain` | a reader's argument `p` (its `vt.rds` read is literal) | none: this change adds `["sid-clusters"]` |

**For a consumer whose hand-off path is not literal, and only for one, the catalog's `upstream` field
supplies the producers.** A value may be a prefix (`"lm"`, meaning every `lm-*` template that saves a hand-off) or a
template's full name (`"sid-fit"`). A template never links to itself. One read is literal and has no producer
template: `hm` reads `hm-selection.rds`, which its companion selection runner writes, so the sheet
quotes the `rebuild` text ("the companion hm selection runner"). The catalog's other `upstream` and `downstream` values are not used,
because they are hand-written and at least one disagrees with the code: the catalog lists hm → hp, and
`hp` reads `ac.rds` and `hz.rds`, not `hm.rds`. Reconciling the catalog with the generated graph is a
follow-up, not part of this change.

### Literal arguments only

A call is read only from **literal** arguments. When `why`, `role`, `rebuild` or a path is not a string
literal (or a top-level variable bound to one), the sheet uses a generic phrase such as "another job's
hand-off" instead of guessing.

The rf templates gain `guard_long_fit()` on the confidence-bands branch. Their sheets switch to the
background route with no change here, because the sheet reads the guard rather than keeping a list of
which templates are long.

## 4. Architecture

```
inst/templates/*.qmd ──► R/run-sheet.R (internal, new)
inst/extdata/templates.json  .run_sheet_facts(file)   one template: sections, markers, calls, data
                             .handoff_graph(facts)    producer → consumer links, across templates
                             .run_sheet_md(name, ...) the wording, as Markdown; the only place it lives
                             .run_sheets(dir)         every template → list(name, title, markdown, html)
                                │
dev/gallery/gallery.R ──────────┘  writes <study>/run-sheets.json beside gallery-build.csv,
                                │  from the INSTALLED templates, the same ones it rendered
dev/gallery/package.py ─────────┘  writes <out>/sheets/<name>.html, wrapping each sheet's html in
                                │  the page shell; exits when a template on disk has no sheet
dev/gallery/index.html             a "Run sheet" link on each row, beside "Then run it"
```

- **Parsing.** Each R chunk of the `.qmd` (between a ```` ```{r ```` fence and the next ```` ``` ````)
  goes through `parse()`, keeping its line numbers. A recursive walk then visits every call, including
  function bodies and default arguments (`vt-fit` reads its sid hand-off in a default argument). A
  function name matches bare, as `pkg::fn` or as `pkg:::fn`. Comments never reach the parser, so a
  commented-out call states nothing. Every fact keeps its source line, which places it under the
  heading above it.
- **Optional reads.** A call inside an `if` or `switch`, or in a function's body or defaults, runs
  only when a choice takes that branch or something calls the function, so the walk marks it
  `optional`. An optional hand-off read is said as such: "Optional: the jobs it can read from", and
  never "Render X first". On the shipped templates these are `vt-fit`'s screen and SID distance,
  `vt-explain`'s SID strata and `hm`'s selection runner, all of which a default run does without.
  Raised by the Codex review of #430. A required read wrapped in a helper function would read as
  optional too; none ships, and the graph test pins the optional set so one would be noticed.
- **Headings.** Lines matching `^#{2,3} ` outside code fences, so an R comment is never taken for one.
- **The marker helper is shared.** The `EDIT:` token (built, never written literally) and the 96-character
  cut move out of `.guard_edits()` into `.edit_marker_lines(src)`, and both call it. This is the one
  change to existing code, and its purpose is to keep the count from drifting.
- **Wording and markup both stay in R.** `.run_sheet_md()` writes Markdown, which reads well in a
  snapshot. A small `.md_inline_html()` converts the three forms the sheets use (`` `code` ``,
  `**bold**`, `[text](href)`) and escapes everything else. Links to the vignettes are relative to the
  site root, and `package.py` adds the `../../` a page in `gallery/sheets/` needs. `package.py`
  only wraps the html in a page shell that matches the gallery's look. It writes no wording of its own.
- **The sheet links back** to its template's gallery report, and its sections link into *Work a job*
  (`#find-what-you-have-to-change`, `#render-as-you-go`) and *Start a new study*. That is the training
  thread: the sheet outlines, the vignette explains, and the template holds the details.
- **Gallery only.** No new export, and no change to the vignette. The catalog gains one `upstream`
  value (section 3). The sheets are built by an internal function, so adding a console `run_sheet()`
  later is a small step if one is wanted.

## 5. Testing

In `tests/testthat/test-run-sheet.R`:

1. **Every template on disk** produces a sheet with no error, with its "What it does", Prerequisites,
   Outline and Run it sections. This also catches a chunk the parser cannot read.
2. **It agrees with the existing readers.** The sheet's packages are `identical()` to
   `.template_packages(f)`. The outline's marker counts sum to a plain count of lines carrying the
   token. Its headings are the template's headings, in order.
3. **The parse walk agrees with a text scan, on the real templates.** Wherever a template's uncommented
   text contains `.read_handoff(`, `.read_bootstrap_artifact(`, `cache_fit(`, `guard_long_fit(` or
   `guard_memory(`, the sheet must report that fact. A walker that loses a call form fails on a
   shipped template.
4. **The hand-off graph on the real templates.**
   - Every `.read_handoff()` call resolves to a producer on disk: through a literal path, or, for a
     non-literal one, through a catalog `upstream` value that matches templates on disk. The test lists
     exactly which consumers take the catalog route (`hs-concordance`, `lm-checkpred`, `lp-mirror`,
     `vt-fit` and `vt-explain` today) and which literal reads have no producer (`hm`'s
     `hm-selection.rds`), so a new one is a decision rather than an accident.
   - Edges named in section 3 are asserted: ac → hp, hz → hp, rfs-fit → rfs-explain.
5. **Fixture templates written to a temporary file**, one for each variant: a hand-off read in a default
   argument, a `:::` call, a non-literal `rebuild`, a guard with `why`, `box_data = FALSE`,
   `DATASET <- NULL`, a `###` heading, and markers above the first heading. Each fixture's Markdown is
   pinned with `expect_snapshot()`. Snapshots use fixtures, never real templates, so editing a template
   does not churn them.
6. **`.md_inline_html()`** escapes `<`, `>`, `&` and quotes, and converts exactly the three forms.
7. **Mutation proof.** With the walker cut back to top-level calls, tests 3, 4 and 5 must fail. The
   result is recorded in the pull request.
8. **The existing `.guard_edits()` tests stay green** once the marker helper is shared.
9. **The round trip.** `.run_sheets()` through `jsonlite` gives each template's `name`, `title`,
   `markdown` and `html`, the shape `package.py` reads.

`package.py` has no CI tests, so it fails loudly instead when a template has no sheet.

## 6. Rollout

Nothing here renders a job. The site shows the sheets only after the gallery is rebuilt on lri, against
an installed hvtiRtemplates that carries `.run_sheets()`:

```sh
Rscript dev/gallery/gallery.R <study>
python3 dev/gallery/package.py <study> pkgdown/assets/gallery
bash dev/gallery/publish.sh
```

Then rerun `pkgdown.yaml`. That is the release-day gallery rebuild AGENTS.md already prescribes, so it
needs no new step.

## 7. Follow-ups, not in this change

- Reconcile the catalog's hand-written `upstream` and `downstream` with the generated hand-off graph
  (hm → hp is listed and is not in the code), or derive them from it.
- A console `run_sheet()`, if the team asks for one.
- Give the lm family and the two rm templates `##` sections. Seven of them have none (lm-binary has
  two, and rm-linear's only one is "Figures"), so their outline is one entry until they do.
