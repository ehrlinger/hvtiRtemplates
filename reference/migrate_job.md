# Migrate a legacy job into a supported analysis template

Reads a legacy source job and copies its deterministic choices into a
supported template. Writes the migrated job and an evidence report
beside it. Review the remaining `EDIT:` markers before rendering the
job.

## Usage

``` r
migrate_job(
  source,
  endpoint,
  type,
  prefix = NULL,
  qualifier = NULL,
  lst = NULL,
  log = NULL,
  reference = NULL,
  dir = NULL
)
```

## Arguments

- source:

  Path to one legacy source job, relative to the working directory or
  absolute.

- endpoint:

  Endpoint field for the new job's filename.

- type:

  Analysis-type field for the new job's filename.

- prefix:

  Template prefix, such as `"dc"`. Read from the SAS filename when
  `NULL`. When given without `qualifier`, the qualifier is still read
  from the filename's second field if that field names one of this
  prefix's templates.

- qualifier:

  Template qualifier, such as `"tables"`. Read from the SAS filename
  when `NULL`. When given without `prefix`, the prefix is read from the
  filename and this qualifier is used. Filename fields must match
  `[A-Za-z0-9_]+`.

- lst:

  Optional path to a SAS listing, relative to the working directory or
  absolute. Defaults to the same-named file beside `source` when
  present.

- log:

  Optional path to a SAS log, relative to the working directory or
  absolute. Defaults to the same-named file beside `source` when
  present.

- reference:

  Optional vector of paths to output references, such as RTF or DOCX
  files, relative to the working directory or absolute. They record
  comparison targets, not analysis choices.

- dir:

  Any directory in the study, used only to locate the study root.
  Defaults to the directory of `source`.

## Value

The migrated job path, invisibly. The report is written beside it.

## Details

A converter is available for `dc-tables`, `dc-gfup`, `dp-trends`, and
`dp-postage`, each interpreting its own source choices; choices the
interpreter does not recognize remain for review. A template with no
converter yet still migrates: it is scaffolded with every `EDIT:` marker
kept, the evidence travels with it, and the report says the migration
adapter is not yet available.

Relative `source`, `lst`, `log` and `reference` paths resolve against
the working directory, as in any R function; `dir` only locates the
study root. Each file must exist, be readable and lie beneath that root,
and symbolic links are checked after resolution. The evidence files are
never modified. The report records whether the listing and log were
supplied, found beside the source, or not found.

The job uses the filename and study folder selected by
[`add_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md).
Its report replaces the `.qmd` extension with `-migration.md` and
records study-relative evidence paths, SHA-256 checksums, the package
version, translated choices, unresolved choices, and ignored material.
Source text quoted in the report is masked, whichever converter ran:
string literal contents (R raw strings included), SAS and R comment
bodies, `%let` values (whole, even when a macro-quoting function such as
`%str()` holds a semicolon), `%put` text, unquoted `title` and
`footnote` text, and digit runs of five or more are replaced by
placeholders such as `"[string]"` or `[text]`, and Quarto or R Markdown
prose and YAML are withheld. Statement keywords, variable names and
operators remain. Absolute paths in any remaining text are redacted. The
job is not masked. SAS log errors leave a blocking `EDIT:` marker in the
generated job. Listings, RTF files and log messages may contain patient
observations. Their text is withheld; locations remain available for
local review. Logs retain severity, error codes and recognized aggregate
counts only.

Both outputs are prepared as temporary files beside their targets before
placement. Migration refuses to overwrite an existing target, checked
for each output immediately before it is placed. Outputs are placed by
hard link, which cannot replace an existing file; where the filesystem
refuses hard links, the prepared file is renamed into place after a
fresh check, so a concurrent writer landing between that check and the
rename can still be replaced. If placement fails, only the outputs this
call placed are removed, along with its temporary files.

## See also

[`add_job`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md),
[`template_list`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_list.md)
