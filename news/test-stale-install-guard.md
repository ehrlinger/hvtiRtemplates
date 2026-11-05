* A render test now skips, naming the installed copy and how to replace it, when the
  installed hvtiRtemplates is not the code under test. A render's R process loads the
  installed package, not the source `devtools::load_all()` loaded, so a stale install
  made three render tests fail with the old code's output. The check compares the
  namespace's functions and constants and the installed files, not the version, which
  stays the same across many pull requests. It reads the copy the render's own R
  process would load, in the directory it starts in, and a submission test that is
  refused before any process starts still runs (#489 review).
