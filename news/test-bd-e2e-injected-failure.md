* A `bd` end-to-end test now checks that its draft fails at the error it plants, not
  earlier. It used to accept any error, so a render that died before writing its
  working file failed a later check and pointed at the wrong cause.
