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

script_dir <- function() {
  cmd <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", cmd, value = TRUE)
  if (length(file_arg)) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[[1]]))))
  }
  getwd()
}

source(file.path(script_dir(), "phylo_utils.R"))

RESULT_FIELDS <- c(
  "model_id", "analysis_target", "model_family", "model_type", "comparison_group",
  "response", "predictors", "covariates", "term", "n_species", "estimate",
  "std_error", "statistic", "p_value", "aic", "delta_aic",
  "r_squared_or_pseudo_r2", "phylogeny_id", "status", "message"
)
WARNING_FIELDS <- c("severity", "model_id", "analysis_target", "model_family", "message")
SUPPORTED_FAMILIES <- c("lm", "pgls_brownian", "pgls_pagel_lambda")
PLACEHOLDER_FAMILIES <- c(
  "ou_placeholder",
  "robust_lm_placeholder",
  "multivariate_placeholder",
  "permutation_placeholder"
)

arg_value <- function(args, name, default = "") {
  value <- args[[name]]
  if (is.null(value)) default else value
}

parse_bool <- function(value) {
  tolower(trimws(as.character(value))) %in% c("1", "true", "t", "yes", "y")
}

read_tsv_optional <- function(path) {
  if (is.null(path) || is.na(path) || trimws(path) == "" || !file.exists(path)) {
    return(empty_frame(character()))
  }
  utils::read.delim(path, sep = "\t", header = TRUE, stringsAsFactors = FALSE, check.names = FALSE, na.strings = c("", "NA", "NaN", "nan"))
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

split_terms <- function(value) {
  text <- trimws(as.character(value))
  if (is.na(text) || text == "") {
    return(character())
  }
  trimws(unlist(strsplit(text, "[,;]")))
}

first_nonempty <- function(data, column) {
  if (!column %in% names(data) || nrow(data) == 0) {
    return("")
  }
  values <- as.character(data[[column]])
  values <- values[!is.na(values) & trimws(values) != ""]
  if (length(values)) values[[1]] else ""
}

resolve_manifest_path <- function(path, manifest_path) {
  if (is.na(path) || trimws(path) == "") {
    return("")
  }
  if (grepl("^/", path)) {
    return(path)
  }
  normalizePath(file.path(dirname(normalizePath(manifest_path, mustWork = FALSE)), path), mustWork = FALSE)
}

species_label_map <- function(path) {
  traits <- read_tsv_optional(path)
  if (nrow(traits) == 0 || !"species" %in% names(traits) || !"phylogeny_label" %in% names(traits)) {
    return(list())
  }
  labels <- list()
  for (idx in seq_len(nrow(traits))) {
    species <- as.character(traits$species[[idx]])
    label <- as.character(traits$phylogeny_label[[idx]])
    if (!is.na(species) && species != "" && !is.na(label) && label != "" && is.null(labels[[species]])) {
      labels[[species]] <- label
    }
  }
  labels
}

phylogeny_context <- function(path) {
  manifest <- read_tsv_optional(path)
  if (nrow(manifest) == 0 || !"phylogeny_file" %in% names(manifest)) {
    return(list(phylogeny_id = "", phylogeny_file = ""))
  }
  idx <- 1
  list(
    phylogeny_id = if ("phylogeny_id" %in% names(manifest)) as.character(manifest$phylogeny_id[[idx]]) else "",
    phylogeny_file = resolve_manifest_path(as.character(manifest$phylogeny_file[[idx]]), path)
  )
}

enrich_phylo_columns <- function(data, row) {
  warnings <- empty_frame(WARNING_FIELDS)
  if (!"species" %in% names(data)) {
    return(list(data = data, warnings = warnings))
  }
  if (!"phylogeny_label" %in% names(data)) {
    labels <- species_label_map(as.character(row$species_traits))
    if (length(labels)) {
      data$phylogeny_label <- vapply(as.character(data$species), function(item) {
        value <- labels[[item]]
        if (is.null(value)) "" else value
      }, character(1))
      missing <- unique(as.character(data$species[data$phylogeny_label == ""]))
      if (length(missing)) {
        warnings <- rbind(warnings, warn("WARNING", row, paste("Missing phylogeny labels for species:", paste(missing, collapse = ","))))
      }
    }
  }
  phy <- phylogeny_context(as.character(row$phylogeny_manifest))
  if (!"phylogeny_file" %in% names(data) && phy$phylogeny_file != "") {
    data$phylogeny_file <- phy$phylogeny_file
  }
  if (!"phylogeny_id" %in% names(data) && phy$phylogeny_id != "") {
    data$phylogeny_id <- phy$phylogeny_id
  }
  list(data = data, warnings = warnings)
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

append_result_context <- function(results, row) {
  if (nrow(results) == 0) {
    return(empty_frame(RESULT_FIELDS))
  }
  data.frame(
    model_id = results$model_id,
    analysis_target = as.character(row$analysis_target),
    model_family = as.character(row$model_family),
    model_type = results$model_type,
    comparison_group = paste(as.character(row$analysis_target), results$response, results$predictors, results$covariates, results$term, sep = "|"),
    response = results$response,
    predictors = results$predictors,
    covariates = results$covariates,
    term = results$term,
    n_species = results$n_species,
    estimate = results$estimate,
    std_error = results$std_error,
    statistic = results$statistic,
    p_value = results$p_value,
    aic = results$aic,
    delta_aic = NA_real_,
    r_squared_or_pseudo_r2 = results$r_squared_or_pseudo_r2,
    phylogeny_id = results$phylogeny_id,
    status = results$status,
    message = results$message,
    stringsAsFactors = FALSE
  )
}

append_warning_context <- function(warnings, row) {
  if (nrow(warnings) == 0) {
    return(empty_frame(WARNING_FIELDS))
  }
  data.frame(
    severity = warnings$severity,
    model_id = warnings$model_id,
    analysis_target = as.character(row$analysis_target),
    model_family = as.character(row$model_family),
    message = warnings$message,
    stringsAsFactors = FALSE
  )
}

add_delta_aic <- function(results) {
  if (nrow(results) == 0 || !"aic" %in% names(results)) {
    return(results)
  }
  results$delta_aic <- NA_real_
  ok <- results$status == "OK" & !is.na(suppressWarnings(as.numeric(results$aic)))
  groups <- unique(results$comparison_group[ok])
  for (group in groups) {
    idx <- which(ok & results$comparison_group == group)
    species_counts <- unique(results$n_species[idx])
    if (length(idx) > 1 && length(species_counts) == 1) {
      aic <- suppressWarnings(as.numeric(results$aic[idx]))
      results$delta_aic[idx] <- aic - min(aic, na.rm = TRUE)
    }
  }
  results
}

run_supported_model <- function(row) {
  data <- read_tsv_optional(as.character(row$input_table))
  if (nrow(data) == 0) {
    return(list(results = empty_frame(RESULT_FIELDS), warnings = warn("WARNING", row, "Input table is empty or unavailable")))
  }
  if (!"species" %in% names(data)) {
    return(list(results = empty_frame(RESULT_FIELDS), warnings = warn("WARNING", row, "Input table has no species column; model skipped")))
  }
  duplicated_species <- unique(as.character(data$species[duplicated(data$species)]))
  if (length(duplicated_species)) {
    return(list(results = empty_frame(RESULT_FIELDS), warnings = warn("WARNING", row, paste("Duplicate species rows present; model skipped to avoid silently dropping species:", paste(duplicated_species, collapse = ",")))))
  }
  phylo <- enrich_phylo_columns(data, row)
  data <- phylo$data
  terms <- default_model_terms(row, data)
  if (terms$response == "" || !length(terms$predictors)) {
    return(list(results = empty_frame(RESULT_FIELDS), warnings = warn("WARNING", row, "Supported model requires response and predictors")))
  }
  if (!"phylogeny_label" %in% names(data)) {
    data$phylogeny_label <- as.character(data$species)
  }
  model_type <- as.character(row$model_family)
  phylogeny_id <- first_nonempty(data, "phylogeny_id")
  tree_file <- first_nonempty(data, "phylogeny_file")
  outputs <- run_models(
    data = data,
    response = terms$response,
    predictors = terms$predictors,
    covariates = terms$covariates,
    model_types = model_type,
    model_id = as.character(row$model_id),
    phylogeny_id = phylogeny_id,
    tree_file = tree_file,
    species_col = "species",
    label_col = "phylogeny_label"
  )
  list(
    results = append_result_context(outputs$results, row),
    warnings = rbind(phylo$warnings, append_warning_context(outputs$warnings, row))
  )
}

run_model_comparison <- function(args) {
  manifest <- read_tsv(arg_value(args, "manifest"))
  output_dir <- arg_value(args, "output_dir", "results/advanced_statistics/models")
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
      warning_list[[length(warning_list) + 1]] <- warn("WARNING", row, paste("Placeholder model family is not implemented:", family))
      next
    }
    if (stub) {
      warning_list[[length(warning_list) + 1]] <- warn("WARNING", row, "advanced_statistics_stub=true; model fitting skipped")
      next
    }
    if (!family %in% SUPPORTED_FAMILIES) {
      warning_list[[length(warning_list) + 1]] <- warn("WARNING", row, paste("Unsupported model family:", family))
      next
    }
    fit <- run_supported_model(row)
    if (nrow(fit$results)) {
      result_list[[length(result_list) + 1]] <- fit$results
    }
    if (nrow(fit$warnings)) {
      warning_list[[length(warning_list) + 1]] <- fit$warnings
    }
  }
  results <- if (length(result_list)) do.call(rbind, result_list) else empty_frame(RESULT_FIELDS)
  warnings <- if (length(warning_list)) do.call(rbind, warning_list) else empty_frame(WARNING_FIELDS)
  results <- add_delta_aic(results)
  write_table(file.path(output_dir, "model_comparison_results.tsv"), results, RESULT_FIELDS)
  write_table(file.path(output_dir, "model_comparison_warnings.tsv"), warnings, WARNING_FIELDS)
  cat("CAME advanced model comparison: results=", nrow(results), " warnings=", nrow(warnings), "\n", sep = "")
  0
}

status <- tryCatch(run_model_comparison(parse_args(commandArgs(trailingOnly = TRUE))), error = function(exc) {
  cat("ERROR\trun_model_comparison\t", conditionMessage(exc), "\n", sep = "", file = stderr())
  1
})
quit(status = status)
