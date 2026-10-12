* The handoff bundles that jobs save now record `rendered_at`, the start of the
  render that saved them, as ISO 8601 with its time zone. The "About this run" table
  shows it for each upstream handoff, and "not recorded" for a bundle saved before
  this change; the file's modification time is never used in its place. Saving the
  same results again therefore writes a different file. (#306)

* A report that turns out to be a draft after its box was printed no longer reads
  as final. A `stop_here()` that the source scan could not see (inside an `if ()`)
  and that runs, an `lg` job with a covariate whose scale is not chosen, an
  incomplete bootstrap pool in `bc`, `bh`, `bl` or `br`, and a `dc-gfup` follow-up
  figure that was not drawn each mark the run a draft: the end table's status and the
  embedded `run` facts say `draft` (with `stopped_early` for a stop and the reasons
  under `draft_reasons`), and a callout above the table, "This run ended as a
  draft", names each reason. The box under the title is printed first and cannot
  change; the callout is what corrects it. (#306)

* In the "About this run" table, two reads of one dataset whose `WHERE` shows the
  same text because its values are masked (`age >= <value>`) are listed separately;
  a joined dataset's rows no longer read "on NULL patients" and carry no `WHERE`
  row of its own; and a `WHERE` that names a column with a space or backtick is
  shown whole. (#306)
