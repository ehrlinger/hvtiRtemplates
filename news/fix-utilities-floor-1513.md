* hvtiRtemplates now needs hvtiRutilities 1.5.13 or later. That release reads a label
  file's unquoted `No` and `Yes` as the text written, so a `value_labels.yml` declaring
  `0: No` / `1: Yes` prints No and Yes in a table rather than FALSE and TRUE. 1.5.1 asked
  for this release in its NEWS but declared only `>= 1.5.12`.
