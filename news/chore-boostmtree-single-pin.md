* `boostmtree` is no longer pinned in this package's `Remotes:`. It comes in
  through `ggBoostedTrees`, which imports it and carries the one pin to the
  CCF fork. Two pins for one package made the dependency install fail
  whenever they disagreed, as when `ggBoostedTrees` moved to `v2.0.11-ccf`
  before this package did. `nb-boostmtree`'s install line still names the
  fork's tag (`v2.0.11-ccf`) and is updated by hand when `ggBoostedTrees`
  moves its pin.
