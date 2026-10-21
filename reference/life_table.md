# Kaplan-Meier life tables, as the ac job reports them

The R counterpart of the SAS `%KAPLAN` macro, as the `ac` job calls it.
`life_table()` returns the product-limit life table, overall or one per
stratum. `life_table_at()` reads survival and the number at risk at
reporting horizons, `life_table_tests()` compares strata, and
`life_table_keep()` names the rows all three analyze, so a figure can be
drawn over exactly the same patients.

## Usage

``` r
life_table(
  data,
  time,
  event,
  strata = NULL,
  conf_level = 0.68268948,
  event_only = TRUE
)

life_table_at(
  data,
  time,
  event,
  times,
  labels = NULL,
  strata = NULL,
  conf_level = 0.68268948
)

life_table_tests(data, time, event, strata)

life_table_keep(data, time, event, strata = NULL)
```

## Arguments

- data:

  A data frame, one row per patient.

- time:

  Name of the follow-up time column.

- event:

  Name of the event column, 0/1 or logical.

- strata:

  Name of one stratification column, or `NULL` for the whole cohort.

- conf_level:

  Confidence level of the limits. Default `0.68268948`.

- event_only:

  `TRUE` returns a row per event time only (SAS `PEVENT=1`); `FALSE`
  adds a row per censoring time (`PEVENT=0`).

- times:

  Reporting horizons, in the unit of `time`.

- labels:

  Labels for `times`. `NULL` labels each horizon with its value.

## Value

`life_table()`: a data frame with the columns of
[`TemporalHazard::hzr_kaplan()`](https://ehrlinger.github.io/TemporalHazard/reference/hzr_kaplan.html)
(`time`, `n_risk`, `n_event`, `n_censor`, `survival`, `std_err`,
`cl_lower`, `cl_upper`, `cumhaz`, `hazard`, `density`, `life`), led by
`stratum` when `strata` is given. Its attribute `"counts"` has a row per
stratum with `n`, `n_events`, `n_censored` and `max_fup`, the last
observed time; `"dropped"` is described under Details, or `NULL`.

`life_table_at()`: a data frame with a row per stratum and horizon:
`stratum` when `strata` is given, then `horizon`, `time`, `survival`,
`cl_lower`, `cl_upper` and `n_risk`, with the `"dropped"` attribute.

`life_table_tests()`: a data frame with a row per test: `test`, `chisq`,
`df` and `p_value`, with the `"dropped"` attribute. A stratum with
nobody at risk at any event time adds nothing to the log-rank or
Wilcoxon test and is left out of its degrees of freedom.

`life_table_keep()`: a logical vector, `TRUE` for each analyzed row of
`data`.

## Details

**Rows analyzed.** A row is analyzed when its time and event are both
recorded. With `strata`, a row whose stratum value is missing, or is a
mean-imputed level
([`hvtiRutilities::imputed_levels()`](https://ehrlinger.github.io/hvtiRutilities/reference/imputed_levels.html)),
is dropped too, as `%KAPLAN` drops "invalid strata values". The dropped
rows are not silent: the result carries them in its `"dropped"`
attribute, one row per reason, and the `ac` job prints that table.

**Confidence level.** The default `conf_level` is `%KAPLAN`'s `CLEVEL`
default, `0.68268948`: one standard error, not 95%.

**Reporting horizons.** Survival at a horizon is the last estimate at or
before it, and 1 before the first event. Beyond the last observation the
estimate is not defined and is `NA`, unless survival has already reached
zero. The number at risk is the number of patients whose time is greater
than the horizon: the at-risk count on the first life-table row AFTER
the horizon, when every censored time has a row (`PEVENT=0`). The
estimate comes from the row before, the count from the row after.

**Tests.** `life_table_tests()` reports the three tests SAS
`PROC LIFETEST` prints for strata: the log-rank, the Wilcoxon (Gehan's
weights, the number at risk) and `-2Log(LR)`, the likelihood ratio test
of an exponential model. All three use every analyzed row to the end of
follow-up. To compare curves only up to a horizon, censor the data there
first, in the job.

## Examples

``` r
if (requireNamespace("TemporalHazard", quietly = TRUE)) {
  d <- data.frame(
    years = c(0.2, 0.5, 0.9, 1.3, 2.0, 2.4, 3.1, 4.0, 5.5, 6.0),
    dead  = c(1, 0, 1, 1, 0, 1, 0, 1, 0, 0),
    group = c("a", "b", "a", "b", "a", "b", "a", "b", "a", NA)
  )
  life_table(d, "years", "dead")
  life_table_at(d, "years", "dead", times = c(1, 2, 5), strata = "group")
  life_table_tests(d, "years", "dead", "group")
}
#>        test      chisq df   p_value
#> 1  Log-rank 0.31656099  1 0.5736817
#> 2  Wilcoxon 0.02173913  1 0.8827832
#> 3 -2Log(LR) 0.71392035  1 0.3981454
```
