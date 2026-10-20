* `nb-boostmtree`'s setup chunk, when boostmtree is missing or too old, now
  gives the install line for boostmtree 2.0.7 (`v2.0.7-ccf`). Its forked
  workers each use one BLAS thread, so a server whose R links a multithreaded
  OpenBLAS is no longer overloaded: at 1,000 patients on 4 cores, 616 s where
  2.0.6 took 1,488 s. The floor stays at 2.0.4.
