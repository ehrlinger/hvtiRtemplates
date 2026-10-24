- The box under a report's title no longer names a registered version for a
  working read. With `HVTI_DATA=working` it names the working source file, such
  as `built.csv`, and says "working read, not a registered version", matching
  the "About this run" table. Before, it named the registered version file and
  its registration date, though the job never read them. Any other value of
  `HVTI_DATA` is refused when the data are read, so the box sends the reader to
  "About this run" rather than guess.
