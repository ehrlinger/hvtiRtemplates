* Two tests from the stale-install guard no longer fail under covr. The test that two studies can load two
  different copies now gives the second study a copy of its own, first on its library path, instead of
  dropping the user library, which cannot hide a copy in a site library. The test that a submitted job returns
  at once runs the install check before it starts the clock, so the time it measures is the submission's.
