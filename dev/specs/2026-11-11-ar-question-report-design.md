# The `ar` analysis report: one research question, answered from finished jobs

**Date:** 2026-11-11
**Status:** design. Sections 3 to 7 decided by John Ehrlinger on 2026-11-11.
Section 9 is open. Nothing is built.
**Reads with:** `2026-08-21-template-set-layout-design.md`, which defines the
`(subject, type)` set and the folders an item is resolved in, and
`2026-09-25-eda-composite-design.md`, which set the rule that a combined report
must not be a second copy of the code it combines.
**Packages:** `hvtiRtemplates` only, for the template, the helpers and the
boilerplate. The publication phase in section 8 will draw on `hvtiRtables`.

This note is self-contained. It assumes no memory of the session that produced
it.

⚠️ No study, variable or patient identifier appears here.

## 1. What was asked

An analysis report for **one research question**. The analyst pastes the
question from the protocol, then lists the pieces of evidence that answer it:
figures and tables that finished jobs have already produced. Beside each piece
the analyst writes how it bears on the question.

The report goes to the researchers, and **they choose what is published.** So
the report is a menu of candidate exhibits, each complete enough to stand on
its own, and not a draft manuscript. A researcher should be able to reply "use
items 2, 4 and 5" and lift the methods, results and interpretation for those
items into the paper.

## 2. What exists

| piece | where | what it gives this design |
|---|---|---|
| `ar`, "Analysis report", folder `documents` | `hvti_taxonomy()` | the prefix and folder. No template uses it yet |
| the `.provenance.json` sidecar | written beside every job's HTML by `.embed_provenance()`, `R/provenance.R` | the job, the datasets read, the artifacts saved, the run facts, the source checksum and any partial-render record |
| `extra =` on `.embed_provenance()` | `R/provenance.R` | a place for a template to add fields to its own sidecar |
| results folders | `graphs/`, `estimates/`, `documents/`, each under `<subject>-<type>/` | where a job's figures, fits and tables already land |
| the `EDIT:` marker guard | `.job_setup()`, `R/job-setup.R` | reports a job left unfinished |

The gap is that a sidecar records **what ran**, not **what method was used**.
It knows the job used a given package version on a given dataset. It does not
know the model was a three-phase parametric hazard. Only the template knows
that, and only the job knows which of the template's choices the analyst kept.

## 3. Decided: everything lives in the `ar` job file

The job scaffolds as any other: `add_job("ar", subject, type)` writes
`50_documents/ar.<subject>.<type>.qmd`, or `documents/` in a legacy study. It
opens with the standard `setup` chunk, then the question, then one section per
item:

```markdown
QUESTION <- "…"   # EDIT: pasted from the protocol

## Freedom from reintervention  {item="hz.death.hz#fig-hazard"}

::: methods
<!-- boilerplate from the hz job lands here once; edit freely -->
:::

::: results
:::

::: interpretation
:::
```

**An item is named by its job and chunk label**, `<job>#<label>`, where `<job>`
is the source job's file name without `.qmd`. The analyst names the chunk they
saw in the job's report, not a file path they would have to look up.

Rejected:

- **The question and items in a YAML file, the text in the `.qmd`.** Two files
  to keep in step, and no other template works that way.
- **The text in the source jobs, and `ar` only collecting it.** One `hz` job
  can serve two questions, and its interpretation differs between them.
  Interpretation belongs to the question.

## 4. Decided: jobs save each labeled exhibit, and the sidecar maps label to file

Option A of three. A job saves each figure and table it wants citable, and its
sidecar records `label -> file`:

- a figure: the PNG the job already writes to `graphs/<subject>-<type>/`;
- a table: the table object as `.rds` in `documents/<subject>-<type>/`, beside
  any DOCX the job writes.

A small saving helper in the templates does both the save and the sidecar
entry, so a template cannot record a label without the file or the reverse.
`ar` renders by reading those files. **It re-runs nothing.**

Rejected:

- **Copying the fragment out of the job's rendered HTML** by its Quarto id. It
  needs no template change, but it rests on Quarto's HTML structure, which is
  not an interface and can change in any release.
- **Quarto's `{{< embed >}}` shortcode.** Embedding from a `.qmd` executes that
  document, which would re-run the fits. Confirm against the installed Quarto
  documentation before revisiting this.

The saved table object is also what the publication phase (section 8) formats.

## 5. Decided: Methods boilerplate, written by the template, pasted once

### 5.1 Who writes it

**Each analysis template writes its own boilerplate paragraph,** filled from
the job's live choices: "Survival was estimated by the Kaplan–Meier method
(n = `r n`, events = `r ev`)." A `methods` chunk records
`{template, text, sha256}` in the sidecar through `extra =`. The code that made
a choice is the code that describes it, so the paragraph cannot describe a
default the analyst changed.

Rejected: a lookup table in `ar` keyed on prefix. It knows only the template's
defaults, and a Methods paragraph describing a default the analyst overrode
would reach a manuscript unnoticed.

### 5.2 Which templates

**`30_analyses` and `20_distributions`** (`ac` and `hz`). `ac` and `hz` are
analyses in every sense but their folder, and nearly every survival paper
describes both. The descriptive templates whose conventions a Methods section
states (`dc-tables`, `dc-stddiff`, `lg`) can join later through the same
mechanism. Graphs and dataset templates show results described elsewhere and
get none.

The boilerplate is expected to improve as the templates do and as the group's
understanding of each method sharpens. It is a starting text, not a fixed one.

### 5.3 Rollout

One template at a time, starting with the templates the first two study
questions use (section 7). A template without boilerplate yet still yields a
**floor**: software, versions, dataset, n and render date, all from the
sidecar, with a callout saying the paragraph is versions and data only.

### 5.4 Paste once, flag drift

`ar_paste_methods()` writes the boilerplate into each **empty** `::: methods`
div and records the pasted text's sha in an HTML comment inside the div. It
runs from the console, never during render: a render that edits its own
source breaks the source checksum `.embed_provenance()` records, and that
guard exists on purpose. **It never touches a div that already holds text.**

At render, `ar` compares the sha in each div with the sha in the source job's
current sidecar. A mismatch prints a callout on that item: the job was
re-rendered with different choices since this text was pasted, compare and
update. It warns and does not stop, because the analyst may have rewritten the
paragraph deliberately.

## 6. Decided: what the report shows, and when it stops

### 6.1 Each item is a candidate exhibit

Items are numbered, Item 1 to n, so a researcher can answer by number. Each
carries:

| piece | shown as |
|---|---|
| a figure | embedded, with a download link to its PNG |
| a table | a real HTML table the researcher can copy |
| an `.rds` estimate | not shown. Loaded so the Results text can quote it: ``r ar_value("hz.death.hz#est-survival", "surv_5y")``, named `<job>#<label>` like an item, since a job can save several |
| the source job | a link to its full HTML report |
| methods, results, interpretation | the analyst's text in its three divs |

`ar_value()` exists so Results numbers come from the fit and not from
retyping, which goes stale after a re-render without anyone noticing.

Code stays folded, as in every job report. The audience reads results.

### 6.2 Stops and callouts

| condition | action | why |
|---|---|---|
| a label no sidecar lists | **stop**, name the item | evidence must not drop out silently |
| a listed file that is missing | **stop**, name the item and the file | the same |
| the source job rendered in part (`partial` in its sidecar) | **stop** | a `stop_here()` result is a draft, not evidence |
| `ar_value()` names a field the object lacks | **stop**, list the fields it has | a misspelled field must not render as empty text |
| the source `.qmd` edited since its last render (file sha differs from the sidecar's) | callout: re-render the job | the exhibit may no longer match the code |
| boilerplate drift (5.4) | callout | the analyst may have meant it |
| a template with no boilerplate yet (5.3) | callout | shows the rollout gap instead of hiding it |
| an empty `::: methods` div | callout: run `ar_paste_methods()` | |

`QUESTION` and each item section carry an `EDIT:` marker, and the existing
marker guard reports any left behind.

## 7. Decided: testing and the gate

**Tests,** on a synthetic study built from `dev/demo`: one `hz` job and one
`bh` job rendered, and an `ar` job citing three items. They assert that items
resolve by label; that each stop in 6.2 stops and each callout prints; that
`ar_paste_methods()` fills only empty divs and leaves an edited one byte for
byte; and that drift fires after a source job is re-rendered with a changed
choice. Each new branch is proved by mutation, per `AGENTS.md`: revert the code
and confirm the test goes red.

**The gate.** `ar` ships **in flight**, as `vt-fit` did, until two real study
questions have used it. Its boilerplate rollout starts with the templates those
two questions draw on. `ar.qmd` gets its own file key in `.lintr`, and a ledger
row so `check-roadmap-counts.py` agrees.

**Order of work:**

1. The saving helper and the sidecar's `label -> file` map (section 4).
2. The `methods` chunk and boilerplate on the first two templates (section 5).
3. The `ar` template, `ar_items()`, `ar_value()` and `ar_paste_methods()`.
4. A gallery entry, so the group can read a rendered `ar` without running one.

## 8. Deferred: the publication phase

After the researchers choose, a separate step formats **only the chosen
items** for the manuscript: CORR DOCX tables through `hvtiRtables`, figures at
manuscript size, and a by-section view that gathers every chosen item's
methods, then results, then interpretation, under Methods, Results and
Discussion. It reads the objects section 4 saves. It gets its own spec once
the `ar` report has been used.

## 9. Open

1. **Exported or internal helpers.** `ar_paste_methods()` is run by the
   analyst and must be exported. `ar_value()` is called from the job and could
   stay internal behind `hvtiRtemplates:::`, as `.job_setup()` does. Decide
   when building step 3.
2. **The saving helper's name and home.** `hvtiRtemplates` for now. If
   `hvtiPlotR` or `hvtiRtables` grows a saving function the templates already
   call, the label map may belong there instead.
3. **Which two study questions go first.** That choice sets the first
   boilerplate templates.
