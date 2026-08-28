# Running TemporalHazard jobs

**Status:** operational guidance, vignette-ready prose. Not yet a vignette; see
"Promoting this to a vignette" at the end.
**Origin:** written from the `survival` (AVR / LV function) study, 2026-08-19,
after two production bootstrap screens of 13 and 19 hours.

Every warning here is attached to something that actually went wrong. Numbers
from that study appear as **measurements, not as settings** — your pool, your
cohort and your machine will give different ones, and several of the mistakes
below happened precisely because a figure measured on one configuration was
reused on another.

---

## 1. Before any job that costs more than a coffee

### Check you are running the R you think you are

`Rscript` on a terminal's `PATH` is often **not** the R an IDE uses. When it
isn't, the `renv` library is invisible to it and package fallbacks fire silently.

Measured once: the terminal's `Rscript` was an older R, so `hvtiRutilities` was
unavailable, the study's data reader fell back to `haven::read_sas()`, and the
0/1 clinical columns arrived numeric instead of factor. The candidate pool would
have been 230 instead of 160, inside a job that runs for hours with its output
redirected to a log nobody reads until it finishes. A warning is not enough for
that; the runner should hard-stop.

Use `"$R_HOME/bin/Rscript"` and the question does not arise.

### Check WHICH BUILD of the package you have

A version string may not identify the code. In that study,
`TemporalHazard 1.2.0` existed as two different codebases: `main` without the
`score` selection criterion, and `dev` with it. A job passing
`criterion = "score"` fails at `match.arg` under one and runs under the other,
and the version reported in a filed result cannot tell them apart.

```bash
"$R_HOME/bin/Rscript" -e 'd <- packageDescription("TemporalHazard"); g <- function(f) if (is.null(d[[f]])) "-" else d[[f]]; cat("version:", g("Version"), "\nref/sha:", g("RemoteRef"), "/", g("RemoteSha"), "\ncriterion:", deparse(formals(TemporalHazard::hzr_stepwise)$criterion), "\n")'
```

If `RemoteSha` is `-`, the library copy was installed from local source and
carries no provenance at all. Reinstall by commit
(`renv::install("<owner>/<repo>@<sha>")`) so the record exists, and check it
against `renv.lock`.

---

## 2. Long jobs: snapshot, smoke, launch, watch

### Launch from a snapshot, never from the working file

**`Rscript` reads and evaluates a file INCREMENTALLY.** It does not parse up
front. A script edited while it is running has the file changing under the
interpreter's read position.

This cost nine hours: 25 processes were mid-run, the working script was edited
to add an unrelated feature, and every one of them died at the save step with a
syntax error after completing its computation. Nothing scientific was lost only
because the seeds were derived from the chunk number and the resamples could be
reproduced.

```bash
cp -p scripts/<job>-run.R _output/run-snapshot.R
cmp -s scripts/<job>-run.R _output/run-snapshot.R && echo "snapshot matches"
```

Launch the snapshot. Edit the working file freely thereafter.

### Smoke first

A preflight should exercise the **actual configuration** — same pool extraction,
same coercion, same base model — and write nothing. Put it inside the runner
rather than in a script of its own, so it cannot drift from the thing it vouches
for.

The expensive part of a screen is usually the POOL, not the replicate count:
every forward step scores every candidate. So a useful smoke shrinks the step
cap and traces one selection, rather than shrinking the number of replicates.

Report a **lower bound** from it and label it as one. Cost per step rises with
model size, so extrapolating the first few steps understates, often severalfold.

### Chunk anything measured in hours

`hzr_bootstrap()` writes nothing until its final replicate. A run that dies at
90% leaves nothing at all. Chunks are restartable, each lands a usable screen on
its own, and they pool exactly because a bootstrap replicate is an iid draw.

- **Derive each chunk's seed from its chunk number.** Two chunks sharing a seed
  contain the same replicates; pooling them counts each twice and reports a
  Monte-Carlo error the run does not have.
- **Pay the pilot cost knowingly.** Each chunk runs one pilot selection before
  its replicate loop, so N chunks cost N-1 extra selections. A few percent, in
  exchange for never losing more than one chunk's work.
- **Refuse to overwrite an existing chunk**, and check before the work as well
  as at save time. Discovering the clash at the end wastes the whole run.

### Watching

Report a **delta rate between calls**, not `done / elapsed`. The cumulative
figure is dragged down by the pilot phase, which is over: measured once at 22/h
cumulative against a 75/h steady state.

Then guard the delta as well:

- **Refuse the first window if it starts at zero replicates** — it spans the
  pilot transition and reads far too low.
- **A short window is dominated by granularity.** Chunks tick in whole
  replicates; a two-replicate window once reported 13/h against a true 39/h.
- **Distinguish "not started", "running" and "dead".** A monitor that printed
  `pilot` for any last log line without a percentage hid 25 dead processes for
  hours, because that is also what a crashed chunk looks like. Three states
  minimum.
- **Expect "chunks landed" to stay at 0 for almost the whole run.** Parallel
  chunks of equal size cross their last replicate together. The replicate count
  is the progress signal; `landed` jumping to N is the finish, not a fault.

### Verify the pool before reading anything

Pooling is legitimate only if every chunk drew from the same data, ran the same
screen, and no two shared a seed. Check each rather than assume it, because none
of them fails loudly on its own: a dataset rewritten mid-run gives chunks that
each look fine and describe different cohorts.

⚠️ **Check ABSENCE before agreement.** In R, `format(NULL)` is the string
`"NULL"`, so a field that no chunk records compares equal across all of them and
passes unanimously. A step-cap guard was vacuous in a test fixture for exactly
this reason, and the suite was green.

---

## 3. Runtime does not transfer between configurations

Cost scales with the candidate count, because every step scores every candidate.
On one study, the same job took **13 hours over 189 candidates and 19 hours over
226**. A figure quoted from a different pool will be wrong by that much, and a
runtime note in a script comment goes stale the moment the pool changes.

Quote a runtime **with the pool it was measured on**, or not at all.

### And check what a recorded elapsed time actually wrapped

A runner that stores `elapsed_mins` may have started its clock around one phase
only. In the study this came from, `elapsed_mins` timed the stepwise call and
nothing else: reading a 23.8 MB dataset, coercing 255 columns and fitting the
base model all sat outside it. A stored 3.1 minutes therefore meant a script
wall time several minutes longer, and quoting the stored number as "how long the
job takes" set a false expectation that only surfaced when someone watched a
terminal.

Either wrap the whole script, or name the phase in the field: `stepwise_mins`
cannot be misread the way `elapsed_mins` can.

### Is it worth converting the input to parquet first?

Decide it by measurement, not by preference. The quantity is **read time x
number of reads, against total compute**.

Measured on the study this runbook came from: `read_built()` takes **1.3 s** for
3049 rows x 908 columns from a 22.8 MB `.sas7bdat`. Each of 25 chunks reads it
once, so the whole 19-hour run spends about **33 seconds** on input. Converting
would optimise 0.05% of the job, and would add a derived artefact that can go
stale against a mutable source. Not worth it there.

**That ratio inverts quickly.** Converting SAS datasets over 1 GB to parquet has
been dramatically faster in this group's experience (John Ehrlinger, 2026-08-19).
Two things drive it beyond raw size:

- **Re-reads multiply.** A chunked job reads once per chunk, and interactive
  work re-reads on every iteration. A 60-second read is invisible in a batch job
  and intolerable in a development loop.
- **Width matters more than length.** `.sas7bdat` must be read whole. Parquet is
  columnar, so a job using 250 of 908 columns reads only those. On wide clinical
  extracts that is the larger win.

**The caveat holds at any size.** A converted copy is a DERIVED artefact, and the
source here lives on a mutable share that has been rewritten mid-analysis. Key
the conversion to the source's checksum and refuse to use it when they disagree,
or the speed is bought with the exact silent-staleness failure the rest of this
runbook is about.

**Best case: don't convert, emit.** If the dataset builder writes parquet
directly, the parquet IS the artefact of record and there is no derived copy to
keep in step. That is the direction `hvtiRdatasets` is taking, and it is worth
waiting for rather than caching around.

---

## 4. Rendering and acceptance

### Grep the OUTPUT, not process stderr

knitr catches an error, renders it into the document as `## Error`, and exits
clean. A stderr grep on that pipeline is a check that cannot go red — a parse
error once rendered as success this way.

```r
p <- tempfile(fileext = ".md")
knitr::knit("report.qmd", output = p, quiet = TRUE)
txt <- readLines(p, warn = FALSE)
grep("^## (Error|Warning)", txt, value = TRUE)
```

### A syntax check is not an acceptance check

`knitr::purl()` plus `parse()` proves the R parses. It does not prove it runs. A
variable referenced from a chunk above the one defining it passes `parse()` and
fails at render. Knit it.

### Know which warnings are the guards working

A report full of deliberate checks will emit warnings **on purpose**. A
monotonicity check firing on a selection path, or a non-positive-definite notice
superseded by a second solve, is the machinery doing its job. Distinguishing
those from real problems is a human's task and the report should make it
possible, by explaining each expected warning where it appears.

---

## 5. Reporting

Covered in full by `2026-08-19-report-design-learnings.md`. The operational
short form:

- **Stamp every report** with when and where it was produced, distinguishing a
  render stamp from a run stamp, and degrade to file mtime **with an explicit
  label** rather than silently.
- **Declare expected totals** for a chunked job. Nothing in a chunk knows how
  many siblings it has, so a partial pool is otherwise indistinguishable from a
  small complete one.
- **Never let a degenerate value print as a finding.** A survival of 0.0% resting
  on one patient, or a hazard ratio of 1.0 from a degenerate IQR, reads as a
  result. Print `NA`, or print the support beside it.
- **Do not prune competing transformations from a candidate pool.** Group them
  when READING the result instead.

---

## 6. Standing constraints worth stating in any study

- **Where the analysis tree has no version control**, copy a file aside before
  rewriting it and log decisions to a `docs/` directory. There is no undo.
- **Do not install into a shared `renv` library while jobs are running.**
  `renv::install()` plus `snapshot()` is additive and safe; `renv::restore()`
  can swap a package under live processes. And never install from a machine
  whose platform differs from the library's.
- **Treat the output directory as shared state.** While a long job runs, nothing
  else should write there.

---

## Promoting this to a vignette

The prose is vignette-ready. To ship it:

1. Move to `vignettes/TemporalHazard_runbook.qmd` with a vignette header.
2. Add `VignetteBuilder: quarto` to `DESCRIPTION` and `quarto` to `Suggests` if
   not already present.
3. Decide what runs at build time. Most of this is shell and long jobs, so the
   honest choice is `eval = FALSE` throughout, with any live chunk limited to
   the cheap verification commands in section 1.
4. Check the build time against the package's overall `R CMD check` budget.
