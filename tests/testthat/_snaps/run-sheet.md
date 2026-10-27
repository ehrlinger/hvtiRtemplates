# a guarded, cached fit that another template reads

    Code
      cat(.fixture_sheets()[["zz-fit"]]$markdown)
    Output
      # zz-fit: Demo: fit
      
      ## What it does
      
      Fits the demo. [See the report it produces](reports/zz-fit.html) on the gallery's synthetic study.
      
      ## Prerequisites
      
      - **A study.** The job runs inside a study folder set up with `_study.yml`. [Start a new study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.html) shows how.
      - **The study's data.** `DATASET` names the registered dataset it reads (`"built"` unless you change it). A draft can read a build that is not registered yet, so you can start before the build is final, and the report then says it is a draft. A final render reads registered data only: register the build with `hvtiRutilities::update_manifest()` first.
      - **Packages:** `stats` (>= 4.0.0). The job checks each floor when it starts, so an older library stops it at the top rather than partway through.
      - **The `hvti` command.** A long job starts from a terminal with `hvti run`; `install_hvti()` puts the command on your PATH, once.
      
      ## Outline
      
      These are the job's own sections, in order. The detail lives in the template: the comments at each `EDIT:` marker say what to set and why, and [Work a job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change) shows three ways to find them.
      
      1. **Above the first section**: 1 choice marked `EDIT:`.
      1. **Study choices**: 2 choices marked `EDIT:`.
      1. **Fit**: a long fit (it takes hours at study size) that will not start in an interactive session, so the job runs in the background; checks the fit's memory need against this session's limit before it starts; reads the study data; fits and caches its results, so a later render reloads them (`REFIT <- TRUE` recomputes them).
      1. **Save**: saves `zz.rds`, which **zz-explain** reads and **zz-boot** can read.
      
      ## Run it
      
      **Run it in the background.** The fit is long (it takes hours at study size), and a fit run in the console dies with the session. From a terminal in the study, `hvti run 30_analyses/zz.fit.<subject>.<type>.qmd` (`analyses/` in an older study whose folders carry no number) checks the job, then renders it in the background on the R the study's `renv.lock` records; add `--final` for the final render. From R, `run_job(job)` does the same. `hvti status` follows it and `hvti cancel` stops it. Once the fit is cached, its chunks run interactively and load it.
      
      **Render a draft as you go.** `render_job(job)` runs the whole job in a clean R session and writes the report beside it. Render early and often: while any `EDIT:` marker is left, the report opens with a DRAFT banner listing them, and its numbers are not a result. [Work a job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#render-as-you-go) explains why to render rather than run chunks by hand.
      
      **Then the final.** Once no marker is left, `render_job(job, final = TRUE)` renders the accepted result. It refuses an open marker, a skipped chunk, `stop_here()` and unregistered data, and it records the job's provenance beside the report.
      
      ## Where to go next
      
      - **zz-explain** reads what this job saves (`zz.rds`). Add it to the same set, with this job's `subject` and `type`, because that shared pair is how it finds the file: `add_job("zz.explain", subject = "<subject>", type = "<type>")`.
      - **zz-boot** can read what this job saves; its choices marked `EDIT:` name the file and its set. Add it with `add_job("zz.boot", subject = "<subject>", type = "<type>")`.

# a template that reads another's hand-off, with a ### section

    Code
      cat(.fixture_sheets()[["zz-explain"]]$markdown)
    Output
      # zz-explain: Demo: explain
      
      ## What it does
      
      Explains the demo fit. [See the report it produces](reports/zz-explain.html) on the gallery's synthetic study.
      
      ## Prerequisites
      
      - **A study.** The job runs inside a study folder set up with `_study.yml`. [Start a new study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.html) shows how.
      - **The job it reads from.** Render **zz-fit** first, in this same set: the same `subject` and `type` as this job, which is how it finds what that job saved (`zz.rds`). For a final render, render it final too: a final render refuses a hand-off saved from unregistered data.
      - **Packages:** `stats` (>= 4.0.0). The job checks each floor when it starts, so an older library stops it at the top rather than partway through.
      
      ## Outline
      
      These are the job's own sections, in order. The detail lives in the template: the comments at each `EDIT:` marker say what to set and why, and [Work a job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change) shows three ways to find them.
      
      1. **Study choices**: 1 choice marked `EDIT:`.
      1. **Upstream**: reads what **zz-fit** saved (`zz.rds`).
         - **What the fit says**
      
      ## Run it
      
      **Render a draft as you go.** `render_job(job)` runs the whole job in a clean R session and writes the report beside it. Render early and often: while any `EDIT:` marker is left, the report opens with a DRAFT banner listing them, and its numbers are not a result. [Work a job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#render-as-you-go) explains why to render rather than run chunks by hand.
      
      **Then the final.** Once no marker is left, `render_job(job, final = TRUE)` renders the accepted result. It refuses an open marker, a skipped chunk, `stop_here()` and unregistered data, and it records the job's provenance beside the report.

# a template that builds its dataset and has no sections

    Code
      cat(.fixture_sheets()[["zz-build"]]$markdown)
    Output
      # zz-build: Demo: build
      
      ## What it does
      
      Builds the demo data. [See the report it produces](reports/zz-build.html) on the gallery's synthetic study.
      
      ## Prerequisites
      
      - **A study.** The job runs inside a study folder set up with `_study.yml`. [Start a new study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.html) shows how.
      - **No dataset to read.** This job builds the study dataset rather than reading one; the choices marked `EDIT:` say what it starts from.
      - **Packages:** `stats` (>= 4.0.0). The job checks each floor when it starts, so an older library stops it at the top rather than partway through.
      
      ## Outline
      
      These are the job's own sections, in order. The detail lives in the template: the comments at each `EDIT:` marker say what to set and why, and [Work a job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change) shows three ways to find them.
      
      1. **The whole job**: 1 choice marked `EDIT:`.
      
      ## Run it
      
      **Render a draft as you go.** `render_job(job)` runs the whole job in a clean R session and writes the report beside it. Render early and often: while any `EDIT:` marker is left, the report opens with a DRAFT banner listing them, and its numbers are not a result. [Work a job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#render-as-you-go) explains why to render rather than run chunks by hand.
      
      **Then the final.** Once no marker is left, `render_job(job, final = TRUE)` renders the accepted result. It refuses an open marker, a skipped chunk, `stop_here()` and unregistered data, and it records the job's provenance beside the report.

# a deprecated template with a runner, a catalog-route read and a runner's file

    Code
      cat(.fixture_sheets()[["zz-boot"]]$markdown)
    Output
      # zz-boot: Demo: boot
      
      ## What it does
      
      Screens the demo. Use zz-fit instead. [See the report it produces](reports/zz-boot.html) on the gallery's synthetic study.
      
      ## Prerequisites
      
      - **A study.** The job runs inside a study folder set up with `_study.yml`. [Start a new study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.html) shows how.
      - **The job it reads from.** Render **zz-fit** first; its choices marked `EDIT:` name the file it saved and the set it sits in. For a final render, render it final too: a final render refuses a hand-off saved from unregistered data.
      - **Run the companion runner first.** It writes `runs.rds`, which this job reads.
      - **Its bootstrap runner, run first.** The screen runs in a companion script, `zz.<subject>.<type>.runner.R`, which `add_job()` writes beside the job. This job reports on what the runner saved.
      - **Packages:** `stats` (>= 4.0.0). The job checks each floor when it starts, so an older library stops it at the top rather than partway through.
      
      ## Outline
      
      These are the job's own sections, in order. The detail lives in the template: the comments at each `EDIT:` marker say what to set and why, and [Work a job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change) shows three ways to find them.
      
      1. **Study choices**
      1. **The screen**: reads what the bootstrap runner saved; reads a saved result from the job its choices name; reads `runs.rds`, which the companion runner writes.
      
      ## Run it
      
      **Render a draft as you go.** `render_job(job)` runs the whole job in a clean R session and writes the report beside it. Render early and often: while any `EDIT:` marker is left, the report opens with a DRAFT banner listing them, and its numbers are not a result. [Work a job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#render-as-you-go) explains why to render rather than run chunks by hand.
      
      **Then the final.** Once no marker is left, `render_job(job, final = TRUE)` renders the accepted result. It refuses an open marker, a skipped chunk, `stop_here()` and unregistered data, and it records the job's provenance beside the report.

