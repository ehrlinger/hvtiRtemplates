# Install the hvti command

Copies the `hvti` shell command into a directory on your `PATH`.
`hvti run job.qmd` then starts
[`run_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/run_job.md)
on the R that the study's `renv.lock` records, from a terminal,
whichever R your own session would have started. `hvti status` and
`hvti cancel` do the same for
[`job_status`](https://ehrlinger.github.io/hvtiRtemplates/reference/job_status.md)
and
[`cancel_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/cancel_job.md).

## Usage

``` r
install_hvti(dir)
```

## Arguments

- dir:

  Character(1). The directory to install into, created if absent,
  usually `"~/bin"`. It should be on your `PATH`; a message gives the
  line to add if not.

## Value

Invisibly, the path of the installed command.

## Details

The command is a copy, not a symlink. The library path it would point at
changes with the R version, and surviving that change is what the
command is for. Run `install_hvti("~/bin")` again after updating the
package;
[`run_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/run_job.md)
warns, once per session, when the copy on your `PATH` is older than the
one the package ships. It writes only into `dir`, which has no default:
`install_hvti("~/bin")` is the usual call.

## See also

[`run_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/run_job.md)

## Examples

``` r
if (.Platform$OS.type != "windows") {
  d <- tempfile("bin")
  install_hvti(d)
  unlink(d, recursive = TRUE)
}
#> Add it to your PATH: echo 'export PATH="/tmp/RtmpUAfVBO/bin1bf14490c922:$PATH"' >> ~/.profile
```
