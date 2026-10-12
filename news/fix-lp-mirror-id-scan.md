* A `lp-mirror` test no longer fails on Windows: its check for patient identifiers
  looked for any seven-digit number starting 91 or 92, which matched a file size
  in the provenance. It now looks for the test data's own identifiers.
