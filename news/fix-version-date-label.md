* A report's one-line box and its "About this run" table now call a dataset
  version's date what it is. The box reads `dated 2026-10-21`, not
  `registered 2026-10-21`, and the table's row is `Version date`, not
  `Registered`. The date is the version's extract date, the source file's
  modification date or the date given at registration, and never the day the
  version was registered, which the manifest does not record; read as a
  registration date, it made a version registered on a later day look like an
  older one. An analysis set still reads `written <date>`. The provenance JSON
  keeps the key `registered`, so reports rendered before and after read alike.
