MODEL_RESULT_FIELDS <- c(
  "model_id", "model_type", "response", "predictors", "covariates", "term",
  "n_species", "estimate", "std_error", "statistic", "p_value", "aic",
  "r_squared_or_pseudo_r2", "phylogeny_id", "status", "message"
)

MODEL_DIAGNOSTIC_FIELDS <- c(
  "model_id", "model_type", "response", "predictors", "covariates",
  "n_species", "df_residual", "aic", "r_squared_or_pseudo_r2",
  "phylogeny_id", "status", "message"
)

MODEL_RESIDUAL_FIELDS <- c(
  "model_id", "model_type", "species", "phylogeny_label", "response",
  "observed", "fitted", "residual", "status"
)

MODEL_WARNING_FIELDS <- c("model_id", "model_type", "severity", "message")

`%||%` <- function(left, right) {
  if (is.null(left) || length(left) == 0 || is.na(left) || identical(left, "")) {
    right
  } else {
    left
  }
}

empty_frame <- function(fields) {
  out <- as.data.frame(setNames(rep(list(character()), length(fields)), fields), stringsAsFactors = FALSE)
  out
}

read_tsv <- function(path) {
  if (!file.exists(path)) {
    stop("Input table does not exist: ", path, call. = FALSE)
  }
  utils::read.delim(path, sep = "\t", header = TRUE, stringsAsFactors = FALSE, check.names = FALSE, na.strings = c("", "NA", "NaN"))
}

write_tsv <- function(path, data, fields = NULL) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (is.null(data) || nrow(data) == 0) {
    if (is.null(fields)) {
      fields <- character()
    }
    data <- empty_frame(fields)
  }
  if (!is.null(fields)) {
    for (field in fields) {
      if (!field %in% names(data)) {
        data[[field]] <- character(nrow(data))
      }
    }
    data <- data[, fields, drop = FALSE]
  }
  utils::write.table(data, path, sep = "\t", quote = FALSE, row.names = FALSE, na = "NA")
}

split_csv <- function(value) {
  if (is.null(value) || length(value) == 0 || is.na(value) || trimws(value) == "") {
    return(character())
  }
  trimws(unlist(strsplit(as.character(value), ",")))
}

collapse_terms <- function(value) {
  terms <- value[!is.na(value) & value != ""]
  if (!length(terms)) {
    return("")
  }
  paste(terms, collapse = ",")
}

safe_model_terms <- function(terms) {
  bad <- terms[!grepl("^[A-Za-z_][A-Za-z0-9_]*$", terms)]
  if (length(bad)) {
    stop("Unsafe model variable names: ", paste(bad, collapse = ", "), call. = FALSE)
  }
}

model_formula <- function(response, predictors, covariates = character()) {
  terms <- unique(c(predictors, covariates))
  safe_model_terms(c(response, terms))
  stats::reformulate(terms, response = response)
}

as_numeric_column <- function(value) {
  suppressWarnings(as.numeric(value))
}

warning_row <- function(model_id, model_type, severity, message) {
  data.frame(
    model_id = model_id,
    model_type = model_type,
    severity = severity,
    message = message,
    stringsAsFactors = FALSE
  )
}

error_outputs <- function(model_id, model_type, response, predictors, covariates, phylogeny_id, message) {
  list(
    results = data.frame(
      model_id = model_id,
      model_type = model_type,
      response = response,
      predictors = collapse_terms(predictors),
      covariates = collapse_terms(covariates),
      term = "",
      n_species = 0,
      estimate = NA_real_,
      std_error = NA_real_,
      statistic = NA_real_,
      p_value = NA_real_,
      aic = NA_real_,
      r_squared_or_pseudo_r2 = NA_real_,
      phylogeny_id = phylogeny_id,
      status = "ERROR",
      message = message,
      stringsAsFactors = FALSE
    ),
    diagnostics = data.frame(
      model_id = model_id,
      model_type = model_type,
      response = response,
      predictors = collapse_terms(predictors),
      covariates = collapse_terms(covariates),
      n_species = 0,
      df_residual = NA_real_,
      aic = NA_real_,
      r_squared_or_pseudo_r2 = NA_real_,
      phylogeny_id = phylogeny_id,
      status = "ERROR",
      message = message,
      stringsAsFactors = FALSE
    ),
    residuals = empty_frame(MODEL_RESIDUAL_FIELDS),
    warnings = warning_row(model_id, model_type, "ERROR", message)
  )
}

skip_outputs <- function(model_id, model_type, response, predictors, covariates, phylogeny_id, message) {
  list(
    results = empty_frame(MODEL_RESULT_FIELDS),
    diagnostics = data.frame(
      model_id = model_id,
      model_type = model_type,
      response = response,
      predictors = collapse_terms(predictors),
      covariates = collapse_terms(covariates),
      n_species = 0,
      df_residual = NA_real_,
      aic = NA_real_,
      r_squared_or_pseudo_r2 = NA_real_,
      phylogeny_id = phylogeny_id,
      status = "WARNING",
      message = message,
      stringsAsFactors = FALSE
    ),
    residuals = empty_frame(MODEL_RESIDUAL_FIELDS),
    warnings = warning_row(model_id, model_type, "WARNING", message)
  )
}

complete_model_data <- function(data, response, predictors, covariates, species_col, label_col, model_id, model_type) {
  required <- unique(c(species_col, label_col, response, predictors, covariates))
  missing <- setdiff(required, names(data))
  if (length(missing)) {
    stop("Model variables are absent from input table: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  model_data <- data[, required, drop = FALSE]
  for (field in unique(c(response, predictors, covariates))) {
    model_data[[field]] <- as_numeric_column(model_data[[field]])
  }
  incomplete <- !stats::complete.cases(model_data[, unique(c(response, predictors, covariates)), drop = FALSE])
  warnings <- empty_frame(MODEL_WARNING_FIELDS)
  if (any(incomplete)) {
    dropped <- paste(model_data[[species_col]][incomplete], collapse = ",")
    warnings <- rbind(warnings, warning_row(model_id, model_type, "WARNING", paste0("Dropped species with missing model values: ", dropped)))
  }
  model_data <- model_data[!incomplete, , drop = FALSE]
  model_data <- model_data[!duplicated(model_data[[species_col]]), , drop = FALSE]
  if (nrow(model_data) < 3) {
    stop("Fewer than 3 species remain after filtering model-ready data", call. = FALSE)
  }
  list(data = model_data, warnings = warnings)
}

require_phylo_packages <- function(model_type) {
  missing <- character()
  for (pkg in c("ape", "nlme")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      missing <- c(missing, pkg)
    }
  }
  if (length(missing)) {
    stop(
      "Missing required R package(s) for ", model_type, ": ",
      paste(missing, collapse = ", "),
      ". Install them or request lm-only models.",
      call. = FALSE
    )
  }
}

prepare_phylo_tree <- function(data, tree_file, species_col, label_col, model_id, model_type) {
  require_phylo_packages(model_type)
  if (is.null(tree_file) || is.na(tree_file) || trimws(tree_file) == "") {
    stop("Phylogenetic model requested but no phylogeny_file is available", call. = FALSE)
  }
  if (!file.exists(tree_file)) {
    stop("Phylogeny file does not exist: ", tree_file, call. = FALSE)
  }
  tree <- ape::read.tree(tree_file)
  warnings <- empty_frame(MODEL_WARNING_FIELDS)
  if (is.null(tree$edge.length)) {
    tree <- ape::compute.brlen(tree)
    warnings <- rbind(warnings, warning_row(model_id, model_type, "WARNING", "Tree had no branch lengths; assigned default branch lengths"))
  }
  labels <- as.character(data[[label_col]])
  species <- as.character(data[[species_col]])
  if (anyDuplicated(labels)) {
    dup <- unique(labels[duplicated(labels)])
    stop("Duplicate phylogeny labels in model data: ", paste(dup, collapse = ","), call. = FALSE)
  }
  present <- labels %in% tree$tip.label
  if (any(!present)) {
    dropped_species <- paste(species[!present], collapse = ",")
    warnings <- rbind(warnings, warning_row(model_id, model_type, "WARNING", paste0("Dropped species absent from tree: ", dropped_species)))
  }
  data <- data[present, , drop = FALSE]
  labels <- labels[present]
  if (nrow(data) < 3) {
    stop("Fewer than 3 species remain after matching model data to tree tips", call. = FALSE)
  }
  dropped_tips <- setdiff(tree$tip.label, labels)
  if (length(dropped_tips)) {
    warnings <- rbind(warnings, warning_row(model_id, model_type, "WARNING", paste0("Dropped tree tips absent from model data: ", paste(dropped_tips, collapse = ","))))
    tree <- ape::drop.tip(tree, dropped_tips)
  }
  list(tree = tree, data = data, warnings = warnings)
}

coefficient_results <- function(coefs, model_id, model_type, response, predictors, covariates, n_species, aic, r2, phylogeny_id) {
  terms <- rownames(coefs)
  terms <- terms[terms != "(Intercept)"]
  if (!length(terms)) {
    return(empty_frame(MODEL_RESULT_FIELDS))
  }
  rows <- lapply(terms, function(term) {
    row <- coefs[term, ]
    statistic_name <- intersect(c("t value", "t-value", "z value"), colnames(coefs))[1]
    p_name <- intersect(c("Pr(>|t|)", "p-value", "Pr(>|z|)"), colnames(coefs))[1]
    estimate_name <- intersect(c("Estimate", "Value"), colnames(coefs))[1]
    stderr_name <- intersect(c("Std. Error", "Std.Error"), colnames(coefs))[1]
    data.frame(
      model_id = model_id,
      model_type = model_type,
      response = response,
      predictors = collapse_terms(predictors),
      covariates = collapse_terms(covariates),
      term = term,
      n_species = n_species,
      estimate = as.numeric(row[[estimate_name]]),
      std_error = as.numeric(row[[stderr_name]]),
      statistic = as.numeric(row[[statistic_name]]),
      p_value = as.numeric(row[[p_name]]),
      aic = aic,
      r_squared_or_pseudo_r2 = r2,
      phylogeny_id = phylogeny_id,
      status = "OK",
      message = "",
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

residual_rows <- function(fit, data, model_id, model_type, response, species_col, label_col) {
  data.frame(
    model_id = model_id,
    model_type = model_type,
    species = as.character(data[[species_col]]),
    phylogeny_label = as.character(data[[label_col]]),
    response = response,
    observed = as.numeric(data[[response]]),
    fitted = as.numeric(stats::fitted(fit)),
    residual = as.numeric(stats::residuals(fit)),
    status = "OK",
    stringsAsFactors = FALSE
  )
}

diagnostic_row <- function(fit, model_id, model_type, response, predictors, covariates, n_species, r2, phylogeny_id, status = "OK", message = "") {
  data.frame(
    model_id = model_id,
    model_type = model_type,
    response = response,
    predictors = collapse_terms(predictors),
    covariates = collapse_terms(covariates),
    n_species = n_species,
    df_residual = stats::df.residual(fit) %||% NA_real_,
    aic = as.numeric(stats::AIC(fit)),
    r_squared_or_pseudo_r2 = r2,
    phylogeny_id = phylogeny_id,
    status = status,
    message = message,
    stringsAsFactors = FALSE
  )
}

fit_lm_model <- function(data, response, predictors, covariates, model_id, phylogeny_id, species_col, label_col) {
  form <- model_formula(response, predictors, covariates)
  fit <- stats::lm(form, data = data)
  summary_fit <- summary(fit)
  coefs <- summary_fit$coefficients
  r2 <- unname(summary_fit$r.squared)
  list(
    results = coefficient_results(coefs, model_id, "lm", response, predictors, covariates, nrow(data), as.numeric(stats::AIC(fit)), r2, phylogeny_id),
    diagnostics = diagnostic_row(fit, model_id, "lm", response, predictors, covariates, nrow(data), r2, phylogeny_id),
    residuals = residual_rows(fit, data, model_id, "lm", response, species_col, label_col),
    warnings = empty_frame(MODEL_WARNING_FIELDS)
  )
}

fit_pgls_model <- function(data, response, predictors, covariates, model_id, model_type, phylogeny_id, tree_file, species_col, label_col) {
  tree_context <- prepare_phylo_tree(data, tree_file, species_col, label_col, model_id, model_type)
  data <- tree_context$data
  form <- model_formula(response, predictors, covariates)
  correlation_form <- stats::as.formula(paste("~", label_col))
  correlation <- switch(
    model_type,
    pgls_brownian = ape::corBrownian(value = 1, phy = tree_context$tree, form = correlation_form),
    pgls_pagel_lambda = ape::corPagel(value = 0.5, phy = tree_context$tree, fixed = FALSE, form = correlation_form),
    stop("Unsupported PGLS model type: ", model_type, call. = FALSE)
  )
  fit <- nlme::gls(form, data = data, correlation = correlation, method = "ML")
  summary_fit <- summary(fit)
  coefs <- summary_fit$tTable
  observed <- as.numeric(data[[response]])
  fitted <- as.numeric(stats::fitted(fit))
  pseudo_r2 <- if (length(unique(fitted)) > 1 && length(unique(observed)) > 1) {
    stats::cor(observed, fitted)^2
  } else {
    NA_real_
  }
  list(
    results = coefficient_results(coefs, model_id, model_type, response, predictors, covariates, nrow(data), as.numeric(stats::AIC(fit)), pseudo_r2, phylogeny_id),
    diagnostics = diagnostic_row(fit, model_id, model_type, response, predictors, covariates, nrow(data), pseudo_r2, phylogeny_id),
    residuals = residual_rows(fit, data, model_id, model_type, response, species_col, label_col),
    warnings = tree_context$warnings
  )
}

fit_one_model <- function(data, response, predictors, covariates, model_type, model_id, phylogeny_id, tree_file, species_col = "species", label_col = "phylogeny_label") {
  if (model_type == "phylo_anova") {
    return(skip_outputs(model_id, model_type, response, predictors, covariates, phylogeny_id, "phylo_anova is validated but deferred for a later CAME stage"))
  }
  tryCatch({
    complete <- complete_model_data(data, response, predictors, covariates, species_col, label_col, model_id, model_type)
    if (model_type == "lm") {
      out <- fit_lm_model(complete$data, response, predictors, covariates, model_id, phylogeny_id, species_col, label_col)
    } else if (model_type %in% c("pgls_brownian", "pgls_pagel_lambda")) {
      if (model_type == "pgls_pagel_lambda") {
        require_phylo_packages(model_type)
        if (!exists("corPagel", envir = asNamespace("ape"), inherits = FALSE)) {
          out <- skip_outputs(model_id, model_type, response, predictors, covariates, phylogeny_id, "Pagel lambda support is unavailable in the installed ape package")
          out$warnings <- rbind(complete$warnings, out$warnings)
          return(out)
        }
      }
      out <- fit_pgls_model(complete$data, response, predictors, covariates, model_id, model_type, phylogeny_id, tree_file, species_col, label_col)
    } else {
      stop("Unsupported model_type: ", model_type, call. = FALSE)
    }
    out$warnings <- rbind(complete$warnings, out$warnings)
    out
  }, error = function(exc) {
    error_outputs(model_id, model_type, response, predictors, covariates, phylogeny_id, conditionMessage(exc))
  })
}

run_models <- function(data, response, predictors, covariates = character(), model_types = c("lm"), model_id = "model", phylogeny_id = "", tree_file = "", species_col = "species", label_col = "phylogeny_label") {
  outputs <- lapply(model_types, function(model_type) {
    fit_one_model(
      data = data,
      response = response,
      predictors = predictors,
      covariates = covariates,
      model_type = model_type,
      model_id = model_id,
      phylogeny_id = phylogeny_id,
      tree_file = tree_file,
      species_col = species_col,
      label_col = label_col
    )
  })
  list(
    results = do.call(rbind, lapply(outputs, `[[`, "results")),
    diagnostics = do.call(rbind, lapply(outputs, `[[`, "diagnostics")),
    residuals = do.call(rbind, lapply(outputs, `[[`, "residuals")),
    warnings = do.call(rbind, lapply(outputs, `[[`, "warnings"))
  )
}

has_error_status <- function(outputs) {
  any(outputs$results$status == "ERROR", na.rm = TRUE) ||
    any(outputs$diagnostics$status == "ERROR", na.rm = TRUE) ||
    any(outputs$warnings$severity == "ERROR", na.rm = TRUE)
}
