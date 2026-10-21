# Background jobs: long renders that outlive a Workbench session

**Date:** 2026-10-20
**Status:** designed, not built. Approved in conversation 2026-10-20 (approach A).
**Reads with:** `2026-10-01-nb-boostmtree-design.md` (the template that prompted this).
**Packages:** hvtiRtemplates only.

## 1. The problem

A cross-validated `nb-boostmtree` fit at study size runs for hours to days. On the
team's Posit Workbench, a session is ended about 2 hours after login. What survives
depends on how the render was started:

| started from | survives the 2-hour limit? |
|---|---|
| a terminal, with `nohup` | yes (observed) |
| RStudio's Render button (an in-session background job) | unknown |
| running chunks in the console | no: the fit dies with the session |

So the safe path today is a terminal command most users will not type, and the
natural path, running chunks in the console, loses the fit. `cache_fit()` already
saves a fit the moment it finishes, so what is at risk is a fit still computing.

## 2. What we build

Two pieces, both general rather than `nb-boostmtree`-specific, because other long
templates (the `rf*-fit` forests, varPro, the bootstraps) will want the same.

### 2a. `submit_job()` and `job_status()`

```r
submit_job(path, final = FALSE)   # starts the render detached; returns at once
job_status(path)                  # reads and reports the status
```

- `submit_job()` writes a small runner script and starts it detached, through the
  shell: `setsid nohup <Rscript> <runner> > <log> 2>&1 &`. `setsid` takes it out
  of the session's process group as well as ignoring hangups. Where `setsid` is
  absent (macOS) it uses `nohup` alone. On Windows it stops with a message: there
  is no equivalent.
- `<Rscript>` is `file.path(R.home("bin"), "Rscript")`: the R that called
  `submit_job()`, so a 4.6 session cannot launch a 4.4 render.
- The working directory is the study root, so the study's `renv` and `.Renviron`
  apply (including `OPENBLAS_NUM_THREADS=1` where a study sets it).
- The runner calls `hvtiRtemplates::render_job(path, final = final)` unchanged: a
  background render is exactly an ordinary render.
- Three entries beside the job (the last is transient):
  - `<job>.run.log`: everything the render prints.
  - `<job>.run.lock`: a directory taken (mkdir is atomic) while `submit_job()`
    checks the status and launches, so two callers cannot both start a render.
    Removed on exit; a crashed submit can leave it, and the refusal says to
    delete it.
  - `<job>.run.yml`: the status. The runner writes `state: running`, `pid`,
    `created` (the process creation time, so a reused pid is not mistaken for
    the job), `host`, `r_version`, `started` before rendering, then on exit `state: finished` or
    `failed`, `exit_code`, `ended`, `elapsed`.
- `job_status()` reads the file. A process that was killed outright never writes
  its end state, so for `state: running` it checks whether `pid` is alive and
  reports `running` or `vanished`; where `created` was recorded it must match
  too, and a status without it is judged by `pid` alone.
- `submit_job()` refuses to start while the status reads `running` and that `pid`
  is alive.
- Both return the status invisibly as a list; `job_status()` also prints one line.

### 2b. `guard_long_fit()`

```r
hvtiRtemplates::guard_long_fit("nb-boostmtree-fit", dir = CACHE_DIR,
                               why = "a boostmtree fit with cross-validation takes hours")
```

Called in a template's fit chunk just before its expensive `cache_fit()`.

- Stops when `interactive()` is `TRUE` and `<dir>/<name>.rds` does not exist. The
  message gives `why` and the exact call: `submit_job("<this job>.qmd")`.
- Does nothing in a render (terminal or `submit_job()`: `interactive()` is
  `FALSE`), once the cache exists (the chunk only loads it), or when
  `options(hvtiRtemplates.allow_interactive_fit = TRUE)` is set for a deliberate
  small test.
- Lives in hvtiRtemplates, not in `cache_fit()` (hvtiRutilities): whether a
  computation is too long for the console is a template's judgement, and this
  avoids a release across two packages. Exported, so a study's own long jobs can
  use it.
- `nb-boostmtree` adopts it in this change. Other templates adopt it one at a
  time, each when a measured run time justifies it.

## 3. Testing

- `submit_job()` / `job_status()`, against a stand-in `.qmd` that sleeps a few
  seconds and writes a file: returns at once; `running` then `finished` with exit
  0; a failing job reads `failed` with a non-zero code; a killed process reads
  `vanished`; a second submit while running is refused. Skipped on Windows and on
  CRAN (they start real processes).
- `guard_long_fit()`, with `interactive()` mocked: errors naming `submit_job()`
  when interactive with no cache; quiet when the cache exists, the option is set,
  or not interactive. A test runs `nb-boostmtree`'s fit chunk interactively to
  prove the template calls it.
- Mutation: removing the guard call from the template, or the runner's status
  write, makes the corresponding tests fail.
- **Server proof, before anyone relies on it:** a script staged in
  `/studies/general/_development/` submits a 3-hour job (a sleep loop writing a
  heartbeat each minute) from an ordinary Workbench session. If the heartbeat
  runs past 2 hours, the detach works. If not, `submit_job()` needs the Workbench
  Launcher (approach B below) instead.

## 4. Documentation

Roxygen for all three exports in Rd markup, each with `\value`;
`inst/templates/README.md` gains a short "Long-running jobs" section; a news
fragment.

## 5. Approaches not taken

- **B. Workbench Launcher jobs** (`rstudioapi::launcherSubmitJob()`): the
  cleanest isolation, run outside the session altogether, but only if the
  Launcher is configured here, and only callable from inside RStudio. Kept as
  the fallback inside `submit_job()` should the server proof fail.
- **C. Documentation only** ("render from a terminal with `nohup`"): no code,
  but relies on every user remembering, and leaves the console trap open.
- **Checkpointing inside the fit** (resume a half-finished boostmtree fit): would
  need changes to the fork's fitting loop. Out of scope; the detach removes the
  common cause of lost fits.
