* `nb-boostmtree`'s setup chunk, when boostmtree is missing or too old, now
  gives the install line for boostmtree 2.0.6 (`v2.0.6-ccf`), whose forked
  workers need about a third of the memory, so more `CORES` fit in a session.
  The fit is the same. The floor stays at 2.0.4.
