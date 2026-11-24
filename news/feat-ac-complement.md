- `ac` gains `COMPLEMENT` and `Y_LABEL`. `COMPLEMENT <- TRUE` draws the
  manuscript figure as the cumulative incidence, 100% minus survival, rising
  from 0 as a reoperation or readmission figure usually does; its band and
  confidence bars flip with it. `Y_LABEL` names the y-axis, e.g.
  `"Reoperation (%)"`; by default it reads "Survival (%)", or "Cumulative
  incidence (%)" under `COMPLEMENT`. The tables report survival either way.
