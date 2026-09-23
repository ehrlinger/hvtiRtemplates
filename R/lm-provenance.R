.lm_compact <- function(x) {
  x[!vapply(x, is.null, logical(1L))]
}

.lm_runtime_method <- function(meta, models) {
  if (!is.null(meta$method)) return(meta$method)
  if (!is.list(models) || !length(models)) return(NULL)
  methods <- vapply(models, function(model) {
    if (inherits(model, "glm")) {
      family <- stats::family(model)
      return(paste0(model$method, ":", family$family, "(", family$link, ")"))
    }
    if (inherits(model, "polr")) return(paste0("polr:", model$method))
    if (inherits(model, "multinom")) return("multinom")
    NA_character_
  }, character(1L))
  methods <- unique(methods[!is.na(methods)])
  if (length(methods) == 1L) methods[[1L]] else NULL
}

.lm_model_provenance <- function(meta, models) {
  model <- list(
    formula = paste(deparse(meta$formula), collapse = " "),
    family = meta$model_family,
    method = .lm_runtime_method(meta, models),
    predictors = attr(stats::terms(meta$formula), "term.labels"),
    imputation = list(
      variable = meta$imputation_col,
      n = meta$n_imputations,
      stacked = !is.null(meta$n_imputations) && meta$n_imputations > 1L
    )
  )
  if (is.null(meta$imputation_col) && is.null(meta$n_imputations)) {
    model$imputation <- NULL
  }
  .lm_compact(model)
}

.lm_fit_target <- function(meta) {
  if (!is.null(meta$treatment_col)) {
    return(list(
      name = "treatment",
      value = .lm_compact(list(
        variable = meta$treatment_col,
        accepted_levels = meta$treatment_levels,
        observed_levels = meta$treatment_levels,
        treated_level = meta$treated_level,
        reference_level = meta$ref_level,
        cumulative_direction = meta$cumulative_direction
      ))
    ))
  }

  name <- if (identical(meta$model_family, "count")) "exposure" else "outcome"
  list(
    name = name,
    value = .lm_compact(list(
      variable = meta$outcome_col,
      accepted_levels = meta$outcome_levels,
      observed_levels = meta$outcome_levels,
      event_level = meta$event_level,
      reference_level = meta$reference_level,
      cumulative_direction = meta$cumulative_direction
    ))
  )
}

.lm_fit_cohort <- function(meta, status) {
  required <- c("imputation", "n_input", "n_analyzed", "n_excluded")
  if (!is.data.frame(status) || !all(required %in% names(status)) || !nrow(status)) {
    stop("The logistic fit has no complete runtime row-accounting table.", call. = FALSE)
  }
  by_imputation <- unname(lapply(seq_len(nrow(status)), function(i) {
    as.list(status[i, required, drop = FALSE])
  }))
  stacked <- !is.null(meta$imputation_col) && !is.null(meta$n_imputations) && meta$n_imputations > 1L
  cohort <- list(
    count_unit = if (stacked) "stacked_imputation_rows" else "rows",
    n_input = as.integer(sum(status$n_input)),
    n_analyzed = as.integer(sum(status$n_analyzed)),
    n_excluded = as.integer(sum(status$n_excluded)),
    by_imputation = by_imputation
  )
  if (stacked && length(unique(status$n_input)) == 1L) {
    cohort$n_unique_people_input <- status$n_input[[1L]]
  }
  cohort
}

.lm_fit_provenance <- function(fit) {
  meta <- fit$meta
  target <- .lm_fit_target(meta)
  analysis <- list(model = .lm_model_provenance(meta, fit$models))
  analysis[[target$name]] <- target$value
  analysis <- analysis[c(target$name, "model")]
  list(
    analysis = analysis,
    cohort = .lm_fit_cohort(meta, fit$tables$fit_status)
  )
}

.lm_validation_provenance <- function(validation) {
  meta <- validation$meta
  performance <- validation$tables$performance
  if (!is.data.frame(performance) || nrow(performance) != 1L ||
        !all(c("n", "observed") %in% names(performance))) {
    stop("The logistic validation has no complete runtime performance table.", call. = FALSE)
  }
  observed_levels <- meta$outcome_levels
  event <- meta$event_level
  non_event <- setdiff(meta$outcome_levels, event)
  if (performance$observed[[1L]] == 0L) observed_levels <- setdiff(observed_levels, event)
  if (performance$observed[[1L]] == performance$n[[1L]]) observed_levels <- setdiff(observed_levels, non_event)
  list(
    analysis = list(
      outcome = list(
        variable = meta$outcome_col,
        accepted_levels = meta$outcome_levels,
        observed_levels = observed_levels,
        event_level = event
      ),
      model = .lm_model_provenance(meta, validation$models)
    ),
    cohort = list(
      count_unit = "validation_rows",
      n_input = meta$n_input,
      n_analyzed = meta$n_analyzed,
      n_excluded = meta$n_excluded
    )
  )
}
