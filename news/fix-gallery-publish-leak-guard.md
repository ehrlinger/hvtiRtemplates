* `sid-clusters` no longer prints the study's full path into its report. The
  registration step's captured `register_data()` and `update_manifest()` output
  printed as the chunk's value, and it opens with the study root; it is now
  discarded.
