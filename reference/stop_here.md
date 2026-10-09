# Render a job only down to this point

Called in a chunk of a job, `stop_here()` ends the render there: the
report keeps everything above it and leaves out everything below. It is
how a part-built job is rendered, in place of commenting its unfinished
sections out. To leave out one chunk in the middle instead, give that
chunk a `skip` option with the reason:
`#| skip: "waiting on the corrected coding"`.

## Usage

``` r
stop_here(envir = parent.frame())
```

## Arguments

- envir:

  The environment the job's chunks run in, where its data provenance,
  `SUBJECT` and `TYPE` are found. The default is right inside a chunk.

## Value

Outside a render, `NULL`, invisibly. Inside one, the job's provenance
block, for the chunk to print as the last output of the report.

## Details

Both are allowed in a draft and refused in a final render, by the same
rule as an unresolved `EDIT:` marker. A draft lists each one, with its
line and reason, in a callout at the top of the report, so a partial
report cannot pass for a whole one.
[`render_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/render_job.md)
with `final = TRUE`, or any render with `HVTI_TEMPLATE_STRICT` set,
stops while any remains. Both are found by reading the job's source, so
they show in a diff and in review, as commented-out code does not. A
`stop_here()` the source scan cannot see, as inside an `if ()` or called
with an argument, refuses a final render itself when it runs, and in a
draft is recorded in the report's provenance as a stop.

A `skip` must give a reason as a non-empty quoted string; `skip: true`
is an error. A skipped chunk is neither run nor shown, so a later chunk
that needs what it would have made fails: use `stop_here()` above both
instead.

Outside a render, run line by line or with Run All, `stop_here()` does
nothing, so the chunks below it still run interactively.

A job's provenance is embedded by its last chunk, which a stopped render
never reaches, so `stop_here()` embeds it instead: the data the job
read, its subject and type, and the partial-render points. Call it on
its own line at the end of a chunk, so the chunk shows what it returns.

## See also

[`render_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/render_job.md)

## Examples

``` r
# Outside a render it does nothing.
stop_here()
```
