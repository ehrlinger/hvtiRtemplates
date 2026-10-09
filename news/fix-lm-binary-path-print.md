* `lm-binary` no longer prints the saved model's full path in its report. A
  bare `MODEL_PATH` line showed the absolute path, study folder included, in a
  report meant to be shared. A test now stops any template from printing a path
  variable this way.
