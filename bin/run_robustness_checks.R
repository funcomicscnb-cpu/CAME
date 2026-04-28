#!/usr/bin/env Rscript

suppressWarnings(options(stringsAsFactors = FALSE))

parse_args <- function(argv) {
  args <- list()
  index <- 1
  while (index <= length(argv)) {
    key <- argv[[index]]
    if (!startsWith(key, "--")) {
      stop("Unexpected argument: ", key, call. = FALSE)
    }
    name <- sub("^--", "", key)
    if (index == length(argv) || startsWith(argv[[index + 1]], "--")) {
      args[[name]] <- "true"
      index <- index + 1
    } else {
      args[[name]] <- argv[[index + 1]]
      index <- index + 2
    }
  }
  args
}

RESULT_FIELDS <- c("model_id", "analysis_target", "model_family", "check_type", "metric", "species", "value", "status", "message")
WARNING_FIELDS <- c("severity", "model_id", "analysis_target", "model_family", "message")
PLACEHOLDER_FAMILIES <- c("ou_placeholder", "robust_lm_placeholder", "multivariate_placeholder", "permutation_placeholder")

arg_value <- function(args, name, default = "") {
  value <- args[[name]]
  if (is.null(value)) default else value
}

parse_bool <- function(value) {
  tolower(trimws(as.character(value))) %in% c("1", "true", "t", "yes", "y")
}

empty_frame <- function(fields) {
  as.data.frame(setNames(rep(list(character()), length(fields)), fields), stringsAsFactors = FALSE)
}

read_tsv <- function(path) {
  if (!file.exists(path)) {
    stop("Input table does not exist: ", path, call. = FALSE)
  }
  utils::read.delim(path, sep = "\t", header = TRUE, stringsAsFactors = FALSE, check.names = FALSE, na.strings = c("", "NA", "NaN", "nan"))
}

read_tsv_optional <- function(path) {
  if (is.null(path) || is.na(path) || trimws(path) == "" || !file.exists(path)) {
    return(empty_frame(character()))
  }
  read_tsv(path)
}

write_table <- function(path, data, fields) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (is.null(data) || nrow(data) == 0) {
    data <- empty_frame(fields)
  } else {
    for (field in fields) {
      if (!field %in% names(data)) {
        data[[field]] <- ""
      }
    }
    data <- data[, fields, drop = FALSE]
  }
  utils::write.table(data, path, sep = "\t", quote = FALSE, row.names = FALSE, na = "NA")
}

split_terms <- function(value) {
  text <- trimws(as.character(value))
  if (is.na(text) || text == "") {
    return(character())
  }
  trimws(unlist(strsplit(text, "[,;]")))
}

warn <- function(severity, row, message) {
  data.frame(
    severity = severity,
    model_id = as.character(row$model_id),
    analysis_target = as.character(row$analysis_target),
    model_family = as.character(row$model_family),
    message = message,
    stringsAsFactors = FALSE
  )
}

result_row <- function(row, check_type, metric, species, value, status = "OK", message = "") {
  data.frame(
    model_id = as.character(row$model_id),
    analysis_target = as.character(row$analysis_target),
    model_family = as.character(row$model_family),
    check_type = check_type,
    metric = metric,
    species = species,
    value = as.character(value),
    status = status,
    message = message,
    stringsAsFactors = FALSE
  )
}

safe_model_terms <- function(terms) {
  bad <- terms[!grepl("^[A-Za-z_][A-Za-z0-9_]*$", terms)]
  if (length(bad)) {
    stop("Unsafe model variable names: ", paste(bad, collapse = ", "), call. = FALSE)
  }
}

default_model_terms <- function(row, data) {
  response <- as.character(row$response)
  predictors <- split_terms(row$predictors)
  covariates <- split_terms(row$covariates)
  if (response == "" && "feature_response_value" %in% names(data)) {
    response <- "feature_response_value"
  } else if (response == "" && "phenotype_index_response" %in% names(data)) {
    response <- "phenotype_index_response"
  }
  if (!length(predictors) && "phenotype_response_value" %in% names(data)) {
    predictors <- "phenotype_response_value"
  }
  list(response = response, predictors = predictors, covariates = covariates)
}

numeric_complete_data <- function(data, terms) {
  fields <- unique(c("species", terms$response, terms$predictors, terms$covariates))
  missing <- setdiff(fields, names(data))
  if (length(missing)) {
    stop("Missing model column(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }
  out <- data[, fields, drop = FALSE]
  for (field in setdiff(fields, "species")) {
    out[[field]] <- suppressWarnings(as.numeric(out[[field]]))
  }
  out
}

missingness_results <- function(row, data, terms) {
  fields <- unique(c(terms$response, terms$predictors, terms$covariates))
  rows <- list()
  for (field in fields) {
    if (!field %in% names(data)) {
      rows[[length(rows) + 1]] <- result_row(row, "missingness", field, "", "column_missing", "WARNING", "Column absent from input table")
    } else {
      values <- suppressWarnings(as.numeric(data[[field]]))
      rows[[length(rows) + 1]] <- result_row(row, "missingness", field, "", sum(is.na(values)), "OK", "")
    }
  }
  if (length(rows)) do.call(rbind, rows) else empty_frame(RESULT_FIELDS)
}

small_n_check <- function(row, complete) {
  min_species <- suppressWarnings(as.integer(row$min_species))
  if (is.na(min_species) || min_species < 1) {
    min_species <- 3
  }
  n_species <- length(unique(as.character(complete$species[stats::complete.cases(complete[, setdiff(names(complete), "species"), drop = FALSE])])))
  status <- if (n_species < min_species || n_species < 5) "WARNING" else "OK"
  message <- if (n_species < min_species) {
    paste("Fewer than configured min_species:", n_species, "<", min_species)
  } else if (n_species < 5) {
    "Small species count; estimates may be unstable"
  } else {
    ""
  }
  result_row(row, "small_n", "n_complete_species", "", n_species, status, message)
}

leave_one_species_out <- function(row, complete, terms) {
  if (as.character(row$model_family) != "lm") {
    return(empty_frame(RESULT_FIELDS))
  }
  if (length(terms$predictors) < 1) {
    return(empty_frame(RESULT_FIELDS))
  }
  if (anyDuplicated(complete$species)) {
    return(result_row(row, "leave_one_species_out", "estimate", "", "", "WARNING", "Duplicate species rows present; leave-one-species-out skipped"))
  }
  fields <- setdiff(names(complete), "species")
  complete <- complete[stats::complete.cases(complete[, fields, drop = FALSE]), , drop = FALSE]
  if (nrow(complete) < 4) {
    return(result_row(row, "leave_one_species_out", "estimate", "", "", "WARNING", "Fewer than 4 complete species; leave-one-species-out skipped"))
  }
  safe_model_terms(c(terms$response, terms$predictors, terms$covariates))
  formula <- stats::reformulate(unique(c(terms$predictors, terms$covariates)), response = terms$response)
  target_term <- terms$predictors[[1]]
  rows <- list()
  for (species in sort(unique(as.character(complete$species)))) {
    subset <- complete[as.character(complete$species) != species, , drop = FALSE]
    fit <- try(stats::lm(formula, data = subset), silent = TRUE)
    if (inherits(fit, "try-error")) {
      rows[[length(rows) + 1]] <- result_row(row, "leave_one_species_out", "estimate", species, "", "WARNING", paste("LM failed:", as.character(fit)))
      next
    }
    coefs <- summary(fit)$coefficients
    if (!target_term %in% rownames(coefs)) {
      rows[[length(rows) + 1]] <- result_row(row, "leave_one_species_out", "estimate", species, "", "WARNING", "Primary predictor coefficient was not estimable")
    } else {
      rows[[length(rows) + 1]] <- result_row(row, "leave_one_species_out", "estimate", species, coefs[target_term, "Estimate"], "OK", "")
    }
  }
  do.call(rbind, rows)
}

metric_sensitivity <- function(row, data, terms) {
  if (as.character(row$model_family) != "lm" || !length(terms$predictors)) {
    return(empty_frame(RESULT_FIELDS))
  }
  response <- terms$response
  candidates <- character()
  if (response == "phenotype_index_response") {
    candidates <- intersect(c("phenotype_index_difference", "phenotype_index_fold_change", "phenotype_index_log2_fold_change"), names(data))
  }
  if (!length(candidates)) {
    return(empty_frame(RESULT_FIELDS))
  }
  rows <- list()
  for (candidate in candidates) {
    alt_terms <- terms
    alt_terms$response <- candidate
    complete <- try(numeric_complete_data(data, alt_terms), silent = TRUE)
    if (inherits(complete, "try-error")) {
      next
    }
    fields <- setdiff(names(complete), "species")
    complete <- complete[stats::complete.cases(complete[, fields, drop = FALSE]), , drop = FALSE]
    if (nrow(complete) < 3 || anyDuplicated(complete$species)) {
      rows[[length(rows) + 1]] <- result_row(row, "response_metric_sensitivity", candidate, "", "", "WARNING", "Alternate response metric had insufficient or duplicate species data")
      next
    }
    safe_model_terms(c(alt_terms$response, alt_terms$predictors, alt_terms$covariates))
    fit <- try(stats::lm(stats::reformulate(unique(c(alt_terms$predictors, alt_terms$covariates)), response = alt_terms$response), data = complete), silent = TRUE)
    if (inherits(fit, "try-error")) {
      rows[[length(rows) + 1]] <- result_row(row, "response_metric_sensitivity", candidate, "", "", "WARNING", paste("LM failed:", as.character(fit)))
      next
    }
    term <- alt_terms$predictors[[1]]
    coefs <- summary(fit)$coefficients
    value <- if (term %in% rownames(coefs)) coefs[term, "Estimate"] else ""
    status <- if (term %in% rownames(coefs)) "OK" else "WARNING"
    message <- if (status == "OK") "" else "Primary predictor coefficient was not estimable"
    rows[[length(rows) + 1]] <- result_row(row, "response_metric_sensitivity", candidate, "", value, status, message)
  }
  if (length(rows)) do.call(rbind, rows) else empty_frame(RESULT_FIELDS)
}

run_row_checks <- function(row) {
  data <- read_tsv_optional(as.character(row$input_table))
  if (nrow(data) == 0) {
    return(list(results = empty_frame(RESULT_FIELDS), warnings = warn("WARNING", row, "Input table is empty or unavailable")))
  }
  if (!"species" %in% names(data)) {
    return(list(results = empty_frame(RESULT_FIELDS), warnings = warn("WARNING", row, "Input table has no species column; robustness checks are limited")))
  }
  terms <- default_model_terms(row, data)
  if (terms$response == "" || !length(terms$predictors)) {
    return(list(results = empty_frame(RESULT_FIELDS), warnings = warn("WARNING", row, "Robustness checks require response and predictors")))
  }
  results <- list()
  warnings <- list()
  results[[length(results) + 1]] <- missingness_results(row, data, terms)
  complete <- try(numeric_complete_data(data, terms), silent = TRUE)
  if (inherits(complete, "try-error")) {
    warnings[[length(warnings) + 1]] <- warn("WARNING", row, as.character(complete))
  } else {
    results[[length(results) + 1]] <- small_n_check(row, complete)
    results[[length(results) + 1]] <- leave_one_species_out(row, complete, terms)
    results[[length(results) + 1]] <- metric_sensitivity(row, data, terms)
  }
  list(
    results = if (length(results)) do.call(rbind, results) else empty_frame(RESULT_FIELDS),
    warnings = if (length(warnings)) do.call(rbind, warnings) else empty_frame(WARNING_FIELDS)
  )
}

run_robustness <- function(args) {
  manifest <- read_tsv(arg_value(args, "manifest"))
  output_dir <- arg_value(args, "output_dir", "results/advanced_statistics/robustness")
  stub <- parse_bool(arg_value(args, "advanced_statistics_stub", "true"))
  rows <- manifest[manifest$enabled == "true" & manifest$status == "READY", , drop = FALSE]
  result_list <- list()
  warning_list <- list()
  if (nrow(rows) == 0) {
    warning_list[[1]] <- data.frame(severity = "WARNING", model_id = "", analysis_target = "", model_family = "", message = "No enabled READY advanced models were available", stringsAsFactors = FALSE)
  }
  for (idx in seq_len(nrow(rows))) {
    row <- rows[idx, , drop = FALSE]
    family <- as.character(row$model_family)
    if (family %in% PLACEHOLDER_FAMILIES) {
      warning_list[[length(warning_list) + 1]] <- warn("WARNING", row, paste("Heavier robustness method is deferred for placeholder family:", family))
      next
    }
    if (stub) {
      warning_list[[length(warning_list) + 1]] <- warn("WARNING", row, "advanced_statistics_stub=true; robustness fitting skipped")
      next
    }
    checks <- run_row_checks(row)
    if (nrow(checks$results)) {
      result_list[[length(result_list) + 1]] <- checks$results
    }
    if (nrow(checks$warnings)) {
      warning_list[[length(warning_list) + 1]] <- checks$warnings
    }
  }
  results <- if (length(result_list)) do.call(rbind, result_list) else empty_frame(RESULT_FIELDS)
  warnings <- if (length(warning_list)) do.call(rbind, warning_list) else empty_frame(WARNING_FIELDS)
  write_table(file.path(output_dir, "robustness_check_results.tsv"), results, RESULT_FIELDS)
  write_table(file.path(output_dir, "robustness_warnings.tsv"), warnings, WARNING_FIELDS)
  cat("CAME advanced robustness checks: results=", nrow(results), " warnings=", nrow(warnings), "\n", sep = "")
  0
}

status <- tryCatch(run_robustness(parse_args(commandArgs(trailingOnly = TRUE))), error = function(exc) {
  cat("ERROR\trun_robustness_checks\t", conditionMessage(exc), "\n", sep = "", file = stderr())
  1
})
quit(status = status)
