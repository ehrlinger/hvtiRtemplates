# Refuse a fit that this session's memory cap cannot hold

Call this at the top of a fit chunk, with the memory the fit is expected
to need. It reads the memory limit of the session (the Linux cgroup,
falling back to the machine's physical memory) and stops, in the first
minutes of a render, when the need exceeds 90 percent of it. The refusal
names the Workbench profile that would hold the fit and, when
`cores_fit` is given, the largest `cores` that would fit in this
session.

## Usage

``` r
guard_memory(
  need_gib,
  why,
  cores = NULL,
  cores_fit = NULL,
  proc = "/proc/self/cgroup",
  sys = "/sys/fs/cgroup"
)
```

## Arguments

- need_gib:

  Expected peak memory of the fit, in GiB. `0` (a cached re-render) and
  `NA` (no estimate) pass.

- why:

  Character(1). What needs the memory, in a few words, for the message,
  best with the counts the estimate was made from ("this boostmtree fit
  (1,391 patients, 4,771 visits, continuous)").

- cores:

  Number of parallel workers the fit would use, a whole number of at
  least 1, or `NULL`.

- cores_fit:

  A function taking a number of cores and returning the GiB the fit
  would need, or `NULL`. Used only to name a core count that fits.

- proc, sys:

  Paths of the cgroup files, for tests. The defaults read the running
  session.

## Value

The session's memory limit in GiB, invisibly, when the fit fits.
Otherwise an error whose text begins `memory:`.

## Details

A detached job counts against its submitting session's cgroup, so this
is the cap the fit will hit. On cgroup v1 the recorded peak is the
session's, not the job's alone. Workbench enforces about 1.2 times the
memory its profile advertises, and the profile caps used here are those
enforced values.

## Examples

``` r
# \donttest{
# Without a cgroup (macOS, Windows) this falls back to the machine's physical memory.
guard_memory(1, "a small fit")
# }
```
