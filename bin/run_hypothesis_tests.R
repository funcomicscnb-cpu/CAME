#!/usr/bin/env Rscript

script_dir <- function() {
  cmd <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", cmd, value = TRUE)
  if (length(file_arg)) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[[1]]))))
  }
  getwd()
}

source(file.path(script_dir(), "phylo_utils.R"))

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
      args[[name]] <- TRUE
      index <- index + 1
    } else {
      args[[name]] <- argv[[index + 1]]
      index <- index + 2
    }
  }
  args
}

arg_value <- function(args, name, default = "") {
  if (!is.null(args[[name]])) args[[name]] else default
}

as_list <- function(value) {
  if (is.null(value)) {
    return(list())
  }
  if (is.list(value) && !is.data.frame(value)) {
    return(value)
  }
  as.list(value)
}

as_chr <- function(value) {
  if (is.null(value)) {
    return(character())
  }
  if (is.list(value)) {
    value <- unlist(value)
  }
  trimws(as.character(value))
}

first_chr <- function(value, default = "") {
  values <- as_chr(value)
  values <- values[!is.na(values) & values != ""]
  if (length(values)) values[[1]] else default
}

as_bool <- function(value) {
  if (is.null(value)) {
    return(FALSE)
  }
  if (is.logical(value)) {
    return(isTRUE(value))
  }
  tolower(trimws(as.character(value))) %in% c("true", "t", "1", "yes", "y")
}

safe_id <- function(value) {
  out <- gsub("[^A-Za-z0-9_]+", "_", value)
  out <- gsub("_+", "_", out)
  out <- gsub("^_|_$", "", out)
  if (out == "") "all" else out
}

first_nonempty <- function(data, column) {
  if (!column %in% names(data)) {
    return("")
  }
  values <- unique(as.character(data[[column]][!is.na(data[[column]]) & data[[column]] != ""]))
  if (length(values)) values[[1]] else ""
}

empty_hypothesis_outputs <- function() {
  list(
    summary = empty_frame(c(
      "hypothesis_name", "hypothesis_type", "stage", "stratum", "model_id",
      "model_type", "response", "predictors", "covariates", "term",
      "n_species", "p_value", "status", "message"
    )),
    results = empty_frame(c("hypothesis_name", "hypothesis_type", "stage", "stratum", MODEL_RESULT_FIELDS)),
    residuals = empty_frame(c("hypothesis_name", "hypothesis_type", "stage", "stratum", MODEL_RESIDUAL_FIELDS)),
    warnings = empty_frame(c("hypothesis_name", "hypothesis_type", "stage", "stratum", MODEL_WARNING_FIELDS))
  )
}

append_hypothesis_outputs <- function(left, right) {
  list(
    summary = rbind(left$summary, right$summary),
    results = rbind(left$results, right$results),
    residuals = rbind(left$residuals, right$residuals),
    warnings = rbind(left$warnings, right$warnings)
  )
}

annotate_output <- function(outputs, hypothesis_name, hypothesis_type, stage, stratum) {
  if (nrow(outputs$results)) {
    outputs$results <- cbind(
      hypothesis_name = hypothesis_name,
      hypothesis_type = hypothesis_type,
      stage = stage,
      stratum = stratum,
      outputs$results,
      stringsAsFactors = FALSE
    )
  } else {
    outputs$results <- empty_frame(c("hypothesis_name", "hypothesis_type", "stage", "stratum", MODEL_RESULT_FIELDS))
  }
  if (nrow(outputs$residuals)) {
    outputs$residuals <- cbind(
      hypothesis_name = hypothesis_name,
      hypothesis_type = hypothesis_type,
      stage = stage,
      stratum = stratum,
      outputs$residuals,
      stringsAsFactors = FALSE
    )
  } else {
    outputs$residuals <- empty_frame(c("hypothesis_name", "hypothesis_type", "stage", "stratum", MODEL_RESIDUAL_FIELDS))
  }
  if (nrow(outputs$warnings)) {
    outputs$warnings <- cbind(
      hypothesis_name = hypothesis_name,
      hypothesis_type = hypothesis_type,
      stage = stage,
      stratum = stratum,
      outputs$warnings,
      stringsAsFactors = FALSE
    )
  } else {
    outputs$warnings <- empty_frame(c("hypothesis_name", "hypothesis_type", "stage", "stratum", MODEL_WARNING_FIELDS))
  }
  outputs
}

summary_from_outputs <- function(outputs, hypothesis_name, hypothesis_type, stage, stratum) {
  if (nrow(outputs$results)) {
    return(data.frame(
      hypothesis_name = hypothesis_name,
      hypothesis_type = hypothesis_type,
      stage = stage,
      stratum = stratum,
      model_id = outputs$results$model_id,
      model_type = outputs$results$model_type,
      response = outputs$results$response,
      predictors = outputs$results$predictors,
      covariates = outputs$results$covariates,
      term = outputs$results$term,
      n_species = outputs$results$n_species,
      p_value = outputs$results$p_value,
      status = outputs$results$status,
      message = outputs$results$message,
      stringsAsFactors = FALSE
    ))
  }
  if (nrow(outputs$diagnostics)) {
    return(data.frame(
      hypothesis_name = hypothesis_name,
      hypothesis_type = hypothesis_type,
      stage = stage,
      stratum = stratum,
      model_id = outputs$diagnostics$model_id,
      model_type = outputs$diagnostics$model_type,
      response = outputs$diagnostics$response,
      predictors = outputs$diagnostics$predictors,
      covariates = outputs$diagnostics$covariates,
      term = "",
      n_species = outputs$diagnostics$n_species,
      p_value = NA_real_,
      status = outputs$diagnostics$status,
      message = outputs$diagnostics$message,
      stringsAsFactors = FALSE
    ))
  }
  empty_frame(c(
    "hypothesis_name", "hypothesis_type", "stage", "stratum", "model_id",
    "model_type", "response", "predictors", "covariates", "term",
    "n_species", "p_value", "status", "message"
  ))
}

collect_declared <- function(profile, section) {
  values <- character()
  for (item in as_list(profile[[section]])) {
    if (is.character(item)) {
      values <- c(values, trimws(item))
    } else if (is.list(item)) {
      for (field in c("name", "id", "trait", "variable", "covariate")) {
        if (!is.null(item[[field]]) && trimws(item[[field]]) != "") {
          values <- c(values, trimws(item[[field]]))
          break
        }
      }
    }
  }
  unique(values[values != ""])
}

hypothesis_name <- function(hypothesis, index) {
  name <- as_chr(hypothesis$name)
  if (length(name) && name[[1]] != "") name[[1]] else paste0("hypothesis_", index)
}

normal_hypothesis_type <- function(hypothesis) {
  model_type <- tolower(first_chr(hypothesis$model_type))
  stratify_by <- as_chr(hypothesis$stratify_by)
  response <- first_chr(hypothesis$response)
  covariates <- as_chr(hypothesis$covariates)
  if (length(stratify_by)) {
    return("stratified_model")
  }
  if (model_type %in% c("residual_model", "residual_regression") || grepl("^residual_.+_after_.+", response)) {
    return("residual_model")
  }
  if (model_type %in% c("multivariable_model") || length(covariates)) {
    return("multivariable_model")
  }
  "direct_model"
}

hypothesis_model_types <- function(hypothesis, override = "") {
  if (override != "") {
    return(split_csv(override))
  }
  if (!is.null(hypothesis$model_types)) {
    values <- as_chr(hypothesis$model_types)
    values <- unlist(strsplit(paste(values, collapse = ","), ","))
    return(unique(trimws(values[values != ""])))
  }
  if (!is.null(hypothesis$phylogenetic_model)) {
    return(unique(c("lm", as_chr(hypothesis$phylogenetic_model))))
  }
  if (as_bool(hypothesis$phylogenetic)) {
    return(c("lm", "pgls_brownian"))
  }
  "lm"
}

required_variables_present <- function(data, variables) {
  missing <- variables[!variables %in% names(data)]
  missing[missing != ""]
}

error_hypothesis_output <- function(hypothesis_name, hypothesis_type, stage, stratum, model_id, message) {
  outputs <- empty_hypothesis_outputs()
  outputs$summary <- data.frame(
    hypothesis_name = hypothesis_name,
    hypothesis_type = hypothesis_type,
    stage = stage,
    stratum = stratum,
    model_id = model_id,
    model_type = "",
    response = "",
    predictors = "",
    covariates = "",
    term = "",
    n_species = 0,
    p_value = NA_real_,
    status = "ERROR",
    message = message,
    stringsAsFactors = FALSE
  )
  outputs$warnings <- data.frame(
    hypothesis_name = hypothesis_name,
    hypothesis_type = hypothesis_type,
    stage = stage,
    stratum = stratum,
    model_id = model_id,
    model_type = "",
    severity = "ERROR",
    message = message,
    stringsAsFactors = FALSE
  )
  outputs
}

run_annotated_model <- function(data, hypothesis_name, hypothesis_type, stage, stratum, response, predictors, covariates, model_types, phylogeny_id, tree_file, species_col, label_col) {
  model_id <- paste(safe_id(hypothesis_name), safe_id(stage), safe_id(stratum), sep = "__")
  missing <- required_variables_present(data, unique(c(response, predictors, covariates, species_col, label_col)))
  if (length(missing)) {
    return(error_hypothesis_output(hypothesis_name, hypothesis_type, stage, stratum, model_id, paste("Missing required model variable(s):", paste(missing, collapse = ", "))))
  }
  raw <- run_models(
    data = data,
    response = response,
    predictors = predictors,
    covariates = covariates,
    model_types = model_types,
    model_id = model_id,
    phylogeny_id = phylogeny_id,
    tree_file = tree_file,
    species_col = species_col,
    label_col = label_col
  )
  summary <- summary_from_outputs(raw, hypothesis_name, hypothesis_type, stage, stratum)
  annotated <- annotate_output(raw, hypothesis_name, hypothesis_type, stage, stratum)
  annotated$summary <- summary
  annotated
}

parse_residual_response <- function(response) {
  matched <- regexec("^residual_(.+)_after_(.+)$", response)
  pieces <- regmatches(response, matched)[[1]]
  if (length(pieces) == 3) {
    list(response = pieces[[2]], covariates = unlist(strsplit(pieces[[3]], "_and_")))
  } else {
    list(response = response, covariates = character())
  }
}

resolve_residual_parts <- function(hypothesis, profile, data) {
  response <- first_chr(hypothesis$response)
  covariates <- as_chr(hypothesis$covariates)
  parsed <- parse_residual_response(response)
  raw_response <- parsed$response
  parsed_covariates <- parsed$covariates
  if (!raw_response %in% names(data)) {
    declared_external <- collect_declared(profile, "external_traits")
    present_external <- declared_external[declared_external %in% names(data)]
    if (length(present_external) == 1) {
      raw_response <- present_external[[1]]
    }
  }
  if (!length(covariates)) {
    covariates <- parsed_covariates
  }
  covariates <- covariates[covariates != ""]
  if (length(covariates)) {
    unresolved <- covariates[!covariates %in% names(data)]
    if (length(unresolved)) {
      declared_covariates <- collect_declared(profile, "covariates")
      present_covariates <- declared_covariates[declared_covariates %in% names(data)]
      if (length(present_covariates) == length(unresolved)) {
        covariates[covariates %in% unresolved] <- present_covariates
      }
    }
  }
  list(response = raw_response, covariates = unique(covariates))
}

residual_column_name <- function(hypothesis_name, model_type) {
  paste0(safe_id(hypothesis_name), "__", safe_id(model_type), "__residual")
}

add_residual_column <- function(data, residuals, column_name, species_col) {
  data[[column_name]] <- NA_real_
  if (!nrow(residuals)) {
    return(data)
  }
  values <- residuals$residual
  names(values) <- residuals$species
  matched <- as.character(data[[species_col]]) %in% names(values)
  data[[column_name]][matched] <- as.numeric(values[as.character(data[[species_col]][matched])])
  data
}

run_residual_hypothesis <- function(data, hypothesis, profile, name, htype, stratum, model_types, phylogeny_id, tree_file, species_col, label_col) {
  predictors <- as_chr(hypothesis$predictors)
  parts <- resolve_residual_parts(hypothesis, profile, data)
  if (!length(parts$covariates)) {
    return(error_hypothesis_output(name, htype, "residual_stage1", stratum, paste(safe_id(name), "residual_stage1", sep = "__"), "Residual model requires at least one covariate"))
  }
  outputs <- empty_hypothesis_outputs()
  for (model_type in model_types) {
    stage1 <- run_annotated_model(
      data = data,
      hypothesis_name = name,
      hypothesis_type = htype,
      stage = "residual_stage1",
      stratum = stratum,
      response = parts$response,
      predictors = parts$covariates,
      covariates = character(),
      model_types = model_type,
      phylogeny_id = phylogeny_id,
      tree_file = tree_file,
      species_col = species_col,
      label_col = label_col
    )
    outputs <- append_hypothesis_outputs(outputs, stage1)
    if (any(stage1$summary$status == "ERROR", na.rm = TRUE)) {
      next
    }
    residual_name <- residual_column_name(name, model_type)
    data_with_residual <- add_residual_column(data, stage1$residuals, residual_name, species_col)
    stage2 <- run_annotated_model(
      data = data_with_residual,
      hypothesis_name = name,
      hypothesis_type = htype,
      stage = "residual_stage2",
      stratum = stratum,
      response = residual_name,
      predictors = predictors,
      covariates = character(),
      model_types = model_type,
      phylogeny_id = phylogeny_id,
      tree_file = tree_file,
      species_col = species_col,
      label_col = label_col
    )
    outputs <- append_hypothesis_outputs(outputs, stage2)
  }
  outputs
}

run_nonresidual_hypothesis <- function(data, hypothesis, name, htype, stratum, model_types, phylogeny_id, tree_file, species_col, label_col) {
  response <- first_chr(hypothesis$response)
  predictors <- as_chr(hypothesis$predictors)
  covariates <- if (htype == "direct_model") character() else as_chr(hypothesis$covariates)
  stage <- if (htype == "stratified_model") "stratified_model" else htype
  run_annotated_model(
    data = data,
    hypothesis_name = name,
    hypothesis_type = htype,
    stage = stage,
    stratum = stratum,
    response = response,
    predictors = predictors,
    covariates = covariates,
    model_types = model_types,
    phylogeny_id = phylogeny_id,
    tree_file = tree_file,
    species_col = species_col,
    label_col = label_col
  )
}

split_strata <- function(data, stratify_by) {
  if (!length(stratify_by)) {
    return(list(all = data))
  }
  missing <- stratify_by[!stratify_by %in% names(data)]
  if (length(missing)) {
    stop("Missing stratify_by column(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }
  key <- apply(data[, stratify_by, drop = FALSE], 1, paste, collapse = "__")
  split(data, key)
}

run_one_hypothesis <- function(data, hypothesis, profile, index, override_model_types, phylogeny_id, tree_file, species_col, label_col) {
  name <- hypothesis_name(hypothesis, index)
  htype <- normal_hypothesis_type(hypothesis)
  model_types <- hypothesis_model_types(hypothesis, override_model_types)
  stratify_by <- as_chr(hypothesis$stratify_by)
  outputs <- empty_hypothesis_outputs()
  strata <- tryCatch(split_strata(data, stratify_by), error = function(exc) exc)
  if (inherits(strata, "error")) {
    return(error_hypothesis_output(name, htype, htype, "all", safe_id(name), conditionMessage(strata)))
  }
  for (stratum in names(strata)) {
    stratum_data <- strata[[stratum]]
    if (htype == "residual_model") {
      out <- run_residual_hypothesis(stratum_data, hypothesis, profile, name, htype, stratum, model_types, phylogeny_id, tree_file, species_col, label_col)
    } else {
      out <- run_nonresidual_hypothesis(stratum_data, hypothesis, name, htype, stratum, model_types, phylogeny_id, tree_file, species_col, label_col)
    }
    outputs <- append_hypothesis_outputs(outputs, out)
  }
  outputs
}

main <- function() {
  args <- parse_args(commandArgs(trailingOnly = TRUE))
  input <- arg_value(args, "input")
  profile_path <- arg_value(args, "study_profile")
  output_dir <- arg_value(args, "output_dir", "results/hypotheses")
  if (input == "" || profile_path == "") {
    stop("--input and --study_profile are required", call. = FALSE)
  }
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("R package yaml is required to read study profiles", call. = FALSE)
  }
  data <- read_tsv(input)
  profile <- yaml::read_yaml(profile_path)
  hypotheses <- as_list(profile$hypotheses)
  species_col <- arg_value(args, "species_col", "species")
  label_col <- arg_value(args, "phylogeny_label_col", "phylogeny_label")
  phylogeny_id <- arg_value(args, "phylogeny_id", first_nonempty(data, "phylogeny_id"))
  tree_file <- arg_value(args, "phylogeny_file", first_nonempty(data, "phylogeny_file"))
  override_model_types <- arg_value(args, "model_types", "")

  outputs <- empty_hypothesis_outputs()
  if (!length(hypotheses)) {
    outputs$warnings <- data.frame(
      hypothesis_name = "",
      hypothesis_type = "",
      stage = "",
      stratum = "",
      model_id = "",
      model_type = "",
      severity = "WARNING",
      message = "Study profile contains no hypotheses",
      stringsAsFactors = FALSE
    )
  } else {
    for (index in seq_along(hypotheses)) {
      hypothesis <- hypotheses[[index]]
      if (!is.list(hypothesis)) {
        outputs <- append_hypothesis_outputs(outputs, error_hypothesis_output(paste0("hypothesis_", index), "unknown", "parse", "all", paste0("hypothesis_", index), "Hypothesis entry is not a mapping"))
        next
      }
      out <- run_one_hypothesis(data, hypothesis, profile, index, override_model_types, phylogeny_id, tree_file, species_col, label_col)
      outputs <- append_hypothesis_outputs(outputs, out)
    }
  }

  write_tsv(file.path(output_dir, "hypothesis_test_summary.tsv"), outputs$summary)
  write_tsv(file.path(output_dir, "hypothesis_model_results.tsv"), outputs$results)
  write_tsv(file.path(output_dir, "hypothesis_residuals.tsv"), outputs$residuals)
  write_tsv(file.path(output_dir, "hypothesis_warnings.tsv"), outputs$warnings)
  cat(
    "CAME hypothesis test summary:",
    "summary_rows=", nrow(outputs$summary),
    "result_rows=", nrow(outputs$results),
    "warning_rows=", nrow(outputs$warnings),
    "\n"
  )
  if (any(outputs$summary$status == "ERROR", na.rm = TRUE) || any(outputs$warnings$severity == "ERROR", na.rm = TRUE)) {
    quit(status = 1)
  }
}

tryCatch(main(), error = function(exc) {
  cat("ERROR\trun_hypothesis_tests\t", conditionMessage(exc), "\n", sep = "", file = stderr())
  quit(status = 1)
})
