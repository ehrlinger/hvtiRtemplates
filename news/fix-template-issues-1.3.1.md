* `dc-eda` prints the abbreviation key under a section from the abbreviations
  `label_map()` records for that section's variables, instead of searching the
  shortened labels for each abbreviation. A label that says "SP" in its own
  words and is only cut no longer produces `SP = Surgical procedure` under its
  section (#194).

* No template leaves placeholder prose in the rendered report. Sentences such as
  "Describe the question here." in the `rf*-explain` templates and "Replaces
  `analyses/<job>`: describe its outcome and candidate predictors here." in the
  `rf*-fit`, `ac`, `hz`, `hm`, `hp`, `hs`, `bh`, `bl`, `br`, `bc`, `nb`, `bd`,
  `dc-stddiff`, `dc-tables`, `dc-trends` and `lg` templates now sit inside the
  `EDIT:` marker that asks for them, so resolving the marker removes them (#182).

* The `bh` frequency figure sorts the variables within each phase. Before, one
  ordering across both phases left a variable offered to two phases out of order
  in each facet (#189).

* The `bh` default `CLUSTERS` is an empty list, with a commented example, and an
  empty list reports no clusters instead of stopping. The old default named
  terms such as `early.age` that a small run may never carry, and
  `boot_clusters()` refuses a name no replicate has (#188).

* The `bc` template says what its runner's `BASE` setting does and costs.
  Neither `boot_select()` nor `fit_cox()` can force a term into a Cox model, so
  `BASE` only names a screened candidate whose frequency the tables leave out
  and whose spread the check watches; the old advice to "force at least one
  term" could not be followed (#186).

* `hs-concordance` takes its time and event columns from the `hm` models it
  reads, as `hm`, `hp` and `hs-setup` take theirs from upstream, instead of
  declaring `TIME` and `EVENT` itself. Both settings default to `NULL`; a value
  that differs from a model's recorded one stops the job, and so do models that
  disagree. An `hm` model saved before it recorded its data selection stops the
  job, asking for the `hm` job to be rerun. The `cohort` chunk now follows the
  `models` chunk, because it needs the columns the models record (#176).
