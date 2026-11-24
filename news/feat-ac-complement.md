- `ac` gains `COMPLEMENT` and `Y_LABEL`. `COMPLEMENT <- TRUE` draws the
  manuscript figure as 1 minus Kaplan-Meier, rising from 0; its band,
  confidence bars and captions follow it. That is the cumulative mortality for
  all-cause death, and overstates the cumulative incidence of an event death can
  pre-empt, which the template says beside the option. `Y_LABEL` names the
  y-axis, e.g. `"Mortality (%)"`; by default it reads "Survival (%)", or
  "1 - Kaplan-Meier (%)" under `COMPLEMENT`. The tables report survival either way.
