#!/usr/bin/env Rscript

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

script_dir <- function() {
  cmd <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", cmd, value = TRUE)
  if (length(file_arg)) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[[1]]))))
  }
  getwd()
}

source(file.path(script_dir(), "phylo_utils.R"))

arg_value <- function(args, name, default = "") {
  if (!is.null(args[[name]])) {
    args[[name]]
  } else {
    default
  }
}

profile_variables <- function(profile) {
  values <- character()
  for (section in c("external_traits", "covariates")) {
    items <- profile[[section]]
    if (is.null(items)) {
      next
    }
    for (item in items) {
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
  }
  unique(values[values != ""])
}

first_nonempty <- function(data, column) {
  if (!column %in% names(data)) {
    return("")
  }
  values <- unique(as.character(data[[column]][!is.na(data[[column]]) & data[[column]] != ""]))
  if (length(values)) values[[1]] else ""
}

append_outputs <- function(left, right) {
  list(
    results = rbind(left$results, right$results),
    diagnostics = rbind(left$diagnostics, right$diagnostics),
    residuals = rbind(left$residuals, right$residuals),
    warnings = rbind(left$warnings, right$warnings)
  )
}

empty_outputs <- function() {
  list(
    results = empty_frame(MODEL_RESULT_FIELDS),
    diagnostics = empty_frame(MODEL_DIAGNOSTIC_FIELDS),
    residuals = empty_frame(MODEL_RESIDUAL_FIELDS),
    warnings = empty_frame(MODEL_WARNING_FIELDS)
  )
}

run_profile_screen <- function(data, args, model_types, phylogeny_id, tree_file, species_col, label_col) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("R package yaml is required when --study_profile is used", call. = FALSE)
  }
  profile <- yaml::read_yaml(arg_value(args, "study_profile"))
  response <- arg_value(args, "response", "phenotype_index_response")
  variables <- profile_variables(profile)
  variables <- variables[variables %in% names(data)]
  if (!length(variables)) {
    out <- empty_outputs()
    out$warnings <- rbind(out$warnings, warning_row("profile_screen", "lm", "WARNING", "No external_traits or covariates from study_profile were present in the model table"))
    return(out)
  }
  outputs <- empty_outputs()
  for (variable in variables) {
    model_id <- paste("profile_screen", response, variable, sep = "__")
    out <- run_models(
      data = data,
      response = response,
      predictors = variable,
      covariates = character(),
      model_types = model_types,
      model_id = model_id,
      phylogeny_id = phylogeny_id,
      tree_file = tree_file,
      species_col = species_col,
      label_col = label_col
    )
    outputs <- append_outputs(outputs, out)
  }
  outputs
}

main <- function() {
  args <- parse_args(commandArgs(trailingOnly = TRUE))
  input <- arg_value(args, "input")
  output_dir <- arg_value(args, "output_dir", "results/phylo/models")
  if (input == "") {
    stop("--input is required", call. = FALSE)
  }
  data <- read_tsv(input)
  model_types <- split_csv(arg_value(args, "model_types", "lm"))
  if (!length(model_types)) {
    model_types <- "lm"
  }
  species_col <- arg_value(args, "species_col", "species")
  label_col <- arg_value(args, "phylogeny_label_col", "phylogeny_label")
  phylogeny_id <- arg_value(args, "phylogeny_id", first_nonempty(data, "phylogeny_id"))
  tree_file <- arg_value(args, "phylogeny_file", first_nonempty(data, "phylogeny_file"))

  if (arg_value(args, "response") == "" && arg_value(args, "study_profile") != "") {
    outputs <- run_profile_screen(data, args, model_types, phylogeny_id, tree_file, species_col, label_col)
  } else {
    response <- arg_value(args, "response")
    predictors <- split_csv(arg_value(args, "predictors"))
    covariates <- split_csv(arg_value(args, "covariates"))
    model_id <- arg_value(args, "model_id", "model")
    if (response == "" || !length(predictors)) {
      stop("Explicit model mode requires --response and --predictors", call. = FALSE)
    }
    outputs <- run_models(
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
  }

  write_tsv(file.path(output_dir, "model_results.tsv"), outputs$results, MODEL_RESULT_FIELDS)
  write_tsv(file.path(output_dir, "model_diagnostics.tsv"), outputs$diagnostics, MODEL_DIAGNOSTIC_FIELDS)
  write_tsv(file.path(output_dir, "model_residuals.tsv"), outputs$residuals, MODEL_RESIDUAL_FIELDS)
  write_tsv(file.path(output_dir, "model_warnings.tsv"), outputs$warnings, MODEL_WARNING_FIELDS)
  cat(
    "CAME phylogenetic model summary:",
    "results=", nrow(outputs$results),
    "diagnostics=", nrow(outputs$diagnostics),
    "warnings=", nrow(outputs$warnings),
    "\n"
  )
  if (has_error_status(outputs)) {
    quit(status = 1)
  }
}

tryCatch(main(), error = function(exc) {
  cat("ERROR\trun_phylo_model\t", conditionMessage(exc), "\n", sep = "", file = stderr())
  quit(status = 1)
})
