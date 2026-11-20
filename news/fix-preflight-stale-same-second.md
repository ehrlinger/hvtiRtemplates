* The `study_render` test of a stale job on another host no longer fails at random. It rewrote the run's start
  time from a fresh clock reading, and when that fell one second after the progress file's, the progress was read
  as left over from an earlier run and the job was not seen as stale (#590).
