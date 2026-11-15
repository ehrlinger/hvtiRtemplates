- `render_job()` now says plainly when Quarto itself crashed. Quarto's bundled Deno runtime can die as it starts,
  on macOS at least, and the quarto package then reports an unrelated error, "Could not evaluate cli `{}`
  expression: `QUARTO_DENO`". Such a render now stops with an error of class `hvtiRtemplates_quarto_crashed`
  saying that Quarto crashed, not the job, and to render again. A job's own failure is reported as before.
