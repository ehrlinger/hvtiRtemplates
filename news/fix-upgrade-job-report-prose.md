* `upgrade_job()` carries the job's own description. Where the template opens
  with an `EDIT:` comment asking which job this replaces, the text the old job
  wrote there, once its marker is deleted, is kept instead of the comment
  returning, which had left an upgraded, finished job with an open marker and
  without its description.
* The `upgrade_job()` report lists comment lines above a carried choice that the
  current template lacks, under "Review", since they are not carried, and has a
  new "Description" section saying what happened to the job's description.
* An empty "Carried", "Not placed", "New" or "Markers left" list in the
  `upgrade_job()` report reads "None." rather than one blank entry.
