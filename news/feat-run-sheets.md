* Every template in the gallery now has a run sheet, a page linked from its row beside "Then run it". The
  sheet outlines the job, and the template keeps the details. It says what to have ready, such as the
  registered data (a draft can read an unregistered build and a final render cannot), the jobs to render
  first in the same set, a bootstrap runner and the package floors. A saved result the job reads only when
  a choice asks for it, such as `vt-fit`'s screen or `hm`'s selection runner, is said as optional. It lists the job's own sections with
  what each one does, says how to run the job (in the background with `hvti run` when the fit is guarded as
  long) and names the jobs that read what it saves. Every sheet is generated from its template, so it
  cannot drift from it. The catalog's `upstream` now names what `lm-checkpred`, `vt-fit` and `vt-explain`
  read, and narrows `lp-mirror`'s to `lm-propensity_binary`.
