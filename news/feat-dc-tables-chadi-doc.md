- `dc-tables` prints its own labels, so a manuscript table no longer carries the
  dataset's analysis labels or raw codes, and nobody edits them in Word. The
  dataset's labels are left as read; only the copy the table is drawn from is
  relabeled. Two optional files at the study root, shared by every table job in
  the study: `table_labels.yml` gives a variable the label its table prints, in
  the format of `labels_overrides.yml`, and `value_labels.yml` gives a coded
  column its level text (NYHA 1 to 4 as I to IV). Every other label is tidied by
  rules: a leading "Preoperative" goes, as does a coding such as "(Y/N)" or
  "(for analysis)"; the label is set in sentence case, keeping the study's
  abbreviations and words already written as acronyms; and `kg/m2` becomes
  `kg/m^2^`. The new study choice `TABLE_LABEL_RULES` turns the rules off
  (`FALSE`) or keeps some of them. The report lists every label and level it
  changed, the rule or file behind each, and every variable with no label. From
  the 2026-10-22 Mitral umbrella meeting's feedback on a study's table.
- The Word file `dc-tables` saves carries what built it as document properties
  (File > Info in Word): the job, its render time and state, the hvtiRtemplates,
  hvtiRtables, flextable and officer versions, and the data it read with its
  checksum. A table that is emailed on can say which release made it without
  anyone finding the report.
