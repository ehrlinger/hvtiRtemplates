- The hazard-chain templates (`ac`, `hz`, `hm`, `hp`, `hs-concordance`,
  `hs-score`, `hs-setup`, `bc`, `bh`, `bl` and `br`), their runners and `ar`
  ship the example subject `"dead"` in place of `"dead_pa"`, so the gallery's
  `add_job()` calls read `subject = "dead", type = "hz"`. The `_pa` suffix
  named nothing a new user could look up. `ac`'s header now says that subject
  and type are names you choose, kept the same along a chain. A job already in
  a study keeps the subject it was scaffolded with.
