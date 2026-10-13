# Data delivery EDA report

A standard exploratory report for every data request, plus the runner that
executes the request's queries, applies a notes gate, and assembles the
delivery bundle. The design is in [SPEC.md](SPEC.md); this file covers running
it and where the pieces go.

```
report/          R + Quarto: the report template and its check functions
  eda.qmd        parameterized report (internal and delivery audiences)
  R/checks.R     every check; pure functions returning flags
  R/plots.R      ggplot2 placeholders for the hvtiPlotR postage stamps
  tests/         testthat tests, one planted problem per test
runner/          Python: query execution, rendering, gate, bundle
  deliver.py     `prepare` and `bundle` steps
  test_deliver.py
example/         synthetic request to try it end to end (no patient data)
```

## Requirements

- Quarto 1.4 or later
- R with `arrow`, `dplyr`, `ggplot2`, `jsonlite`, `knitr`, `patchwork`,
  `rmarkdown`, `scales`, `tibble`, `yaml` (and `testthat` for the tests)
- Python 3.10 or later with `pandas`, `pyarrow`, `sqlalchemy`, `pyyaml`
  (`pytest` for the tests), plus the driver for the source: `pyodbc` for SQL
  Server, `snowflake-sqlalchemy` for Snowflake

With uv: `uv add pandas pyarrow sqlalchemy pyyaml pytest`.

## Try it on the synthetic example

```sh
python example/make_example.py                       # builds example/source.sqlite
export EXAMPLE_DB_URL="sqlite:///$PWD/example/source.sqlite"

python runner/deliver.py prepare example/request.yml
```

`prepare` runs both queries, writes parquet, renders the internal report to
`example/work/DR-EXAMPLE-0001/internal/eda-internal.html`, and lists 14 flags
that need notes. One is `LONG-ORPHAN`: the echo query filters by date instead
of joining to the cohort, so echoes for patients outside the cohort leak in.
That one gets fixed, not explained:

```sh
cp example/queries/echo_cohort.sql example/queries/echo.sql
python runner/deliver.py prepare example/request.yml  # 13 flags, orphans gone
```

The rest are explained. `notes.example.yml` holds a data manager's notes for
each one:

```sh
python runner/deliver.py bundle example/request.yml   # refused: no notes yet
cp example/notes.example.yml example/notes.yml
python runner/deliver.py bundle example/request.yml   # builds the bundle
```

The bundle lands in `example/bundle/DR-EXAMPLE-0001/`: parquet data, the
executed `.sql` files, the delivery report, `params.yml`, `notes.yml` and
`manifest.json`.

## What each step guarantees

`prepare`
- Executes the `.sql` files named in the request with bound parameters
  (`:start`, `:end`) and copies those same files into the working directory.
- Renders the internal report, which includes record IDs behind each flag.
- Stops with the guard's message if the data does not match the request
  (`[IN-VAR]`, `[IN-DUPID]`, `[IN-WIDE]`, `[IN-EVENT]`, `[IN-TYPE]`).

`bundle`
- Refuses if any query, data file or the report template changed since
  `prepare`.
- Refuses while any warning or error flag has no note, and prints a
  `notes.yml` skeleton for the missing ones.
- Renders the delivery report and refuses if any flagged record ID appears in it.
- Writes a manifest with hashes, bind values, row counts, the flag summary with
  notes (no IDs), and software versions.

## Writing notes

Notes are keyed by table, variable and check. When one cause raises several
flags, write the note once with a YAML anchor and repeat it with an alias; the
delivery report then shows it once:

```yaml
echo:
  lvef:
    LONG-SHIFT: &lvef2017 "Every 2017 echo has LVEF as a fraction. Multiply 2017 values by 100."
    LONG-JUMP: *lvef2017
    OUT-RANGE: *lvef2017
```

## Connecting a real source

Set `source.url_env` in the request to the name of an environment variable
holding a SQLAlchemy URL, for example
`mssql+pyodbc://@SOURCE_DSN` or `snowflake://user@account/db/schema?warehouse=wh`.
Credentials stay out of the request file.

## Where this goes next

- `report/R/checks.R` becomes exported functions in `hvtiRtemplates`, with the
  tests moving into the package's `tests/testthat/`.
- `report/R/plots.R` is the swap point for `hvtiPlotR`: replace each function
  body with the hvtiPlotR stamp and keep the arguments.
- `runner/` moves to the data management repo in ADO.
- Thresholds in `eda_thresholds()` get tuned on the first month of real
  deliveries.

## Tests

```sh
Rscript -e 'testthat::test_file("report/tests/test-checks.R")'
pytest runner/test_deliver.py      # end-to-end test skips without Quarto, R and arrow
```
