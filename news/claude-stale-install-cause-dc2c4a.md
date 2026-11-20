* The render tests' stale-install check now tells a copy that is found but cannot load, because an import is missing
  from the library path the render's R uses, from a copy that is not installed. It used to skip with "not installed
  where a render's R process looks" either way, which sent the reader to reinstall a package already there; the skip
  now names the copy's library and the load error (#491). The check does not model `hvti`'s choice of the study
  lock's R under `HVTI_R_ROOT`, and a comment at `.quarto_rscript()` says why: no test renders through that R (#492).
