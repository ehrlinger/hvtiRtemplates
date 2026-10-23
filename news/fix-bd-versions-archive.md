- The `bd` tests count a dataset's registered versions in `datasets/_archive/` as
  well as `datasets/`. hvtiRutilities moves earlier versions there on registration
  since its `_archive/` change, which made two `bd` tests fail on every pull request.
