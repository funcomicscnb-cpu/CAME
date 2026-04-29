#!/usr/bin/env Rscript

suppressWarnings(options(stringsAsFactors = FALSE))

result_fields <- c(
  "feature_layer", "feature_id", "contrast_name", "baseline_label", "response_label",
  "phenotype_index_name", "phenotype_response_id", "phenotype_response_metric",
  "feature_response_metric", "model_type", "n_species", "estimate", "std_error",
  "statistic", "p_value", "aic", "r_squared_or_pseudo_r2", "phylogeny_id",
  "status", "warning"
)
warning_fields <- c(
  "severity", "feature_layer", "feature_id", "contrast_name",
  "phenotype_response_id", "model_type", "message"
)
layers <- c("expression", "accessibility", "gra_activity")

parse_args <- function(argv) {
  args <- list()
  i <- 1
  while (i <= length(argv)) {
    key <- argv[[i]]
    if (!startsWith(key, "--")) {
      stop(paste("Unexpected argument:", key), call. = FALSE)
    }
    name <- sub("^--", "", key)
    if (i == length(argv) || startsWith(argv[[i + 1]], "--")) {
      args[[name]] <- "true"
      i <- i + 1
    } else {
      args[[name]] <- argv[[i + 1]]
      i <- i + 2
    }
  }
  args
}

arg_value <- function(args, name, default = "") {
  value <- args[[name]]
  if (is.null(value)) default else value
}

split_csv <- function(value) {
  if (is.null(value) || is.na(value) || trimws(value) == "") {
    return(character())
  }
  trimws(unlist(strsplit(as.character(value), ",")))
}

empty_frame <- function(fields) {
  as.data.frame(setNames(rep(list(character()), length(fields)), fields), stringsAsFactors = FALSE)
}

read_tsv <- function(path, required = TRUE) {
  if (path == "" || !file.exists(path)) {
    if (required) {
      stop(paste("Missing required table:", path), call. = FALSE)
    }
    return(empty_frame(character()))
  }
  utils::read.delim(path, sep = "\t", header = TRUE, check.names = FALSE, stringsAsFactors = FALSE, na.strings = c("", "NA", "NaN", "nan"))
}

write_tsv <- function(path, data, fields) {
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
  utils::write.table(data, path, sep = "\t", quote = FALSE, row.names = FALSE, col.names = TRUE, na = "NA")
}

fmt_num <- function(value) {
  if (length(value) == 0 || is.na(value) || is.nan(value) || is.infinite(value)) {
    return(NA_real_)
  }
  as.numeric(value)
}

warning_row <- function(group, model_type, severity, message) {
  data.frame(
    severity = severity,
    feature_layer = first_value(group, "feature_layer"),
    feature_id = first_value(group, "feature_id"),
    contrast_name = first_value(group, "contrast_name"),
    phenotype_response_id = first_value(group, "phenotype_response_id"),
    model_type = model_type,
    message = message,
    stringsAsFactors = FALSE
  )
}

first_value <- function(data, field) {
  if (!field %in% names(data) || nrow(data) == 0) {
    return("")
  }
  value <- as.character(data[[field]][[1]])
  if (is.na(value)) "" else value
}

result_row <- function(group, model_type, n_species, estimate, std_error, statistic, p_value, aic, r2, phylogeny_id, status, warning) {
  data.frame(
    feature_layer = first_value(group, "feature_layer"),
    feature_id = first_value(group, "feature_id"),
    contrast_name = first_value(group, "contrast_name"),
    baseline_label = first_value(group, "baseline_label"),
    response_label = first_value(group, "response_label"),
    phenotype_index_name = first_value(group, "phenotype_index_name"),
    phenotype_response_id = first_value(group, "phenotype_response_id"),
    phenotype_response_metric = first_value(group, "phenotype_response_metric"),
    feature_response_metric = first_value(group, "feature_response_metric"),
    model_type = model_type,
    n_species = as.integer(n_species),
    estimate = fmt_num(estimate),
    std_error = fmt_num(std_error),
    statistic = fmt_num(statistic),
    p_value = fmt_num(p_value),
    aic = fmt_num(aic),
    r_squared_or_pseudo_r2 = fmt_num(r2),
    phylogeny_id = phylogeny_id,
    status = status,
    warning = warning,
    stringsAsFactors = FALSE
  )
}

skip_result <- function(group, model_type, message, phylogeny_id = "") {
  result_row(group, model_type, 0, NA_real_, NA_real_, NA_real_, NA_real_, NA_real_, NA_real_, phylogeny_id, "SKIPPED", message)
}

required_columns <- function(data, fields, source) {
  missing <- setdiff(fields, names(data))
  if (length(missing)) {
    stop(paste(source, "missing required column(s):", paste(missing, collapse = ", ")), call. = FALSE)
  }
}

group_key <- function(data) {
  fields <- c(
    "feature_layer", "contrast_name", "baseline_label", "response_label",
    "feature_id", "phenotype_index_name", "phenotype_response_id",
    "phenotype_response_metric", "feature_response_metric"
  )
  apply(data[, fields, drop = FALSE], 1, paste, collapse = "\r")
}

species_traits_map <- function(path) {
  traits <- read_tsv(path, required = FALSE)
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

resolve_path <- function(path, manifest_path, base_dir) {
  if (is.na(path) || trimws(path) == "") {
    return("")
  }
  if (grepl("^/", path)) {
    return(path)
  }
  root <- if (!is.na(base_dir) && trimws(base_dir) != "") base_dir else dirname(normalizePath(manifest_path, mustWork = FALSE))
  normalizePath(file.path(root, path), mustWork = FALSE)
}

phylogeny_map <- function(path, base_dir) {
  manifest <- read_tsv(path, required = FALSE)
  if (nrow(manifest) == 0 || !"phylogeny_file" %in% names(manifest)) {
    return(list(by_species = list(), default = NULL))
  }
  by_species <- list()
  default <- NULL
  for (idx in seq_len(nrow(manifest))) {
    record <- list(
      phylogeny_id = if ("phylogeny_id" %in% names(manifest)) as.character(manifest$phylogeny_id[[idx]]) else "",
      phylogeny_file = resolve_path(as.character(manifest$phylogeny_file[[idx]]), path, base_dir)
    )
    species <- if ("species" %in% names(manifest)) as.character(manifest$species[[idx]]) else ""
    if (is.na(species) || species == "") {
      if (is.null(default)) {
        default <- record
      }
    } else if (is.null(by_species[[species]])) {
      by_species[[species]] <- record
    }
  }
  list(by_species = by_species, default = default)
}

group_phylogeny <- function(group, phylo) {
  species <- sort(unique(as.character(group$species)))
  records <- list()
  for (item in species) {
    record <- phylo$by_species[[item]]
    if (is.null(record)) {
      record <- phylo$default
    }
    if (!is.null(record)) {
      records[[length(records) + 1]] <- record
    }
  }
  if (!length(records)) {
    return(list(phylogeny_id = "", phylogeny_file = ""))
  }
  ids <- unique(vapply(records, `[[`, character(1), "phylogeny_id"))
  files <- unique(vapply(records, `[[`, character(1), "phylogeny_file"))
  list(phylogeny_id = ids[[1]], phylogeny_file = files[[1]], multiple = length(files) > 1)
}

model_data <- function(group, min_species) {
  data <- data.frame(
    species = as.character(group$species),
    phenotype_response_value = suppressWarnings(as.numeric(group$phenotype_response_value)),
    feature_response_value = suppressWarnings(as.numeric(group$feature_response_value)),
    stringsAsFactors = FALSE
  )
  if (anyDuplicated(data$species)) {
    dup <- unique(data$species[duplicated(data$species)])
    return(list(ok = FALSE, message = paste("Duplicate species rows in model group:", paste(dup, collapse = ",")), data = data))
  }
  bad <- is.na(data$phenotype_response_value) | is.na(data$feature_response_value)
  if (any(bad)) {
    return(list(ok = FALSE, message = paste("Non-numeric model value for species:", paste(data$species[bad], collapse = ",")), data = data))
  }
  if (nrow(data) < min_species) {
    return(list(ok = FALSE, message = paste("Fewer than", min_species, "species available for model"), data = data))
  }
  if (length(unique(data$phenotype_response_value)) < 2) {
    return(list(ok = FALSE, message = "Phenotype response has fewer than two unique values", data = data))
  }
  if (length(unique(data$feature_response_value)) < 2) {
    return(list(ok = FALSE, message = "Feature response has fewer than two unique values", data = data))
  }
  list(ok = TRUE, message = "", data = data)
}

fit_lm <- function(group, min_species) {
  prepared <- model_data(group, min_species)
  if (!prepared$ok) {
    return(list(result = skip_result(group, "lm", prepared$message), warning = warning_row(group, "lm", "WARNING", prepared$message)))
  }
  fit <- try(stats::lm(feature_response_value ~ phenotype_response_value, data = prepared$data), silent = TRUE)
  if (inherits(fit, "try-error")) {
    message <- paste("LM failed:", as.character(fit))
    return(list(result = skip_result(group, "lm", message), warning = warning_row(group, "lm", "WARNING", message)))
  }
  coefs <- summary(fit)$coefficients
  if (!"phenotype_response_value" %in% rownames(coefs)) {
    message <- "LM coefficient for phenotype_response_value was not estimable"
    return(list(result = skip_result(group, "lm", message), warning = warning_row(group, "lm", "WARNING", message)))
  }
  row <- coefs["phenotype_response_value", ]
  result <- result_row(
    group, "lm", nrow(prepared$data),
    row[["Estimate"]], row[["Std. Error"]], row[["t value"]], row[["Pr(>|t|)"]],
    stats::AIC(fit), summary(fit)$r.squared, "", "OK", ""
  )
  list(result = result, warning = empty_frame(warning_fields))
}

fit_pgls <- function(group, min_species, labels, phylo) {
  phy <- group_phylogeny(group, phylo)
  prepared <- model_data(group, min_species)
  if (!prepared$ok) {
    return(list(result = skip_result(group, "pgls_brownian", prepared$message, phy$phylogeny_id), warning = warning_row(group, "pgls_brownian", "WARNING", prepared$message)))
  }
  data <- prepared$data
  small_n_warning <- empty_frame(warning_fields)
  if (nrow(data) < 6) {
    small_n_warning <- warning_row(
      group,
      "pgls_brownian",
      "WARNING",
      sprintf("Only %d species available. PGLS with fewer than 6 species has low power and unstable phylogenetic parameter estimates; treat results as exploratory.", nrow(data))
    )
  }
  pgls_warning <- function(message) {
    rbind(small_n_warning, warning_row(group, "pgls_brownian", "WARNING", message))
  }
  if (!requireNamespace("ape", quietly = TRUE) || !requireNamespace("nlme", quietly = TRUE)) {
    message <- "PGLS skipped because R package ape or nlme is unavailable"
    return(list(result = skip_result(group, "pgls_brownian", message, phy$phylogeny_id), warning = pgls_warning(message)))
  }
  if (isTRUE(phy$multiple)) {
    message <- "PGLS skipped because species map to multiple phylogeny files"
    return(list(result = skip_result(group, "pgls_brownian", message, phy$phylogeny_id), warning = pgls_warning(message)))
  }
  if (phy$phylogeny_file == "" || !file.exists(phy$phylogeny_file)) {
    message <- paste("PGLS skipped because phylogeny file is unavailable:", phy$phylogeny_file)
    return(list(result = skip_result(group, "pgls_brownian", message, phy$phylogeny_id), warning = pgls_warning(message)))
  }
  data$phylogeny_label <- vapply(data$species, function(item) {
    value <- labels[[item]]
    if (is.null(value)) "" else value
  }, character(1))
  if (any(data$phylogeny_label == "")) {
    missing <- paste(data$species[data$phylogeny_label == ""], collapse = ",")
    message <- paste("PGLS skipped because species lack phylogeny labels:", missing)
    return(list(result = skip_result(group, "pgls_brownian", message, phy$phylogeny_id), warning = pgls_warning(message)))
  }
  tree <- try(ape::read.tree(phy$phylogeny_file), silent = TRUE)
  if (inherits(tree, "try-error")) {
    message <- paste("PGLS skipped because tree could not be read:", as.character(tree))
    return(list(result = skip_result(group, "pgls_brownian", message, phy$phylogeny_id), warning = pgls_warning(message)))
  }
  absent <- data$phylogeny_label[!data$phylogeny_label %in% tree$tip.label]
  if (length(absent)) {
    species <- paste(data$species[data$phylogeny_label %in% absent], collapse = ",")
    message <- paste("PGLS skipped because model species are absent from tree:", species)
    return(list(result = skip_result(group, "pgls_brownian", message, phy$phylogeny_id), warning = pgls_warning(message)))
  }
  if (is.null(tree$edge.length)) {
    tree <- ape::compute.brlen(tree)
  }
  extra_tips <- setdiff(tree$tip.label, data$phylogeny_label)
  if (length(extra_tips)) {
    tree <- ape::drop.tip(tree, extra_tips)
  }
  fit <- try({
    correlation <- ape::corBrownian(value = 1, phy = tree, form = ~ phylogeny_label)
    nlme::gls(feature_response_value ~ phenotype_response_value, data = data, correlation = correlation, method = "ML")
  }, silent = TRUE)
  if (inherits(fit, "try-error")) {
    message <- paste("PGLS failed:", as.character(fit))
    return(list(result = skip_result(group, "pgls_brownian", message, phy$phylogeny_id), warning = pgls_warning(message)))
  }
  coefs <- summary(fit)$tTable
  if (!"phenotype_response_value" %in% rownames(coefs)) {
    message <- "PGLS coefficient for phenotype_response_value was not estimable"
    return(list(result = skip_result(group, "pgls_brownian", message, phy$phylogeny_id), warning = pgls_warning(message)))
  }
  row <- coefs["phenotype_response_value", ]
  fitted <- as.numeric(stats::fitted(fit))
  observed <- data$feature_response_value
  pseudo_r2 <- if (length(unique(fitted)) > 1 && length(unique(observed)) > 1) stats::cor(observed, fitted)^2 else NA_real_
  result <- result_row(
    group, "pgls_brownian", nrow(data),
    row[["Value"]], row[["Std.Error"]], row[["t-value"]], row[["p-value"]],
    stats::AIC(fit), pseudo_r2, phy$phylogeny_id, "OK", ""
  )
  list(result = result, warning = small_n_warning)
}

run_associations <- function(args) {
  model_table <- read_tsv(arg_value(args, "model_table", "results/integration/input/phenotype_omics_model_table.tsv"))
  required_columns(model_table, c(
    "species", "contrast_name", "baseline_label", "response_label", "phenotype_index_name",
    "phenotype_response_id", "phenotype_response_metric", "phenotype_response_value",
    "feature_layer", "feature_id", "feature_response_metric", "feature_response_value"
  ), "model table")
  output_dir <- arg_value(args, "output_dir", "results/integration/associations")
  min_species <- as.integer(arg_value(args, "min_species", "3"))
  model_types <- split_csv(arg_value(args, "model_types", "lm"))
  if (!length(model_types)) {
    model_types <- "lm"
  }
  labels <- species_traits_map(arg_value(args, "species_traits"))
  phylo <- phylogeny_map(arg_value(args, "phylogeny_manifest"), arg_value(args, "phylogeny_base_dir"))

  if (nrow(model_table) == 0) {
    all_results <- empty_frame(result_fields)
    warnings <- data.frame(
      severity = "WARNING", feature_layer = "", feature_id = "", contrast_name = "",
      phenotype_response_id = "", model_type = "", message = "Model table is empty",
      stringsAsFactors = FALSE
    )
  } else {
    keys <- group_key(model_table)
    result_list <- list()
    warning_list <- list()
    for (key in sort(unique(keys))) {
      group <- model_table[keys == key, , drop = FALSE]
      for (model_type in model_types) {
        if (model_type == "lm") {
          fit <- fit_lm(group, min_species)
        } else if (model_type == "pgls_brownian") {
          fit <- fit_pgls(group, min_species, labels, phylo)
        } else {
          message <- paste("Unsupported model type:", model_type)
          fit <- list(result = skip_result(group, model_type, message), warning = warning_row(group, model_type, "WARNING", message))
        }
        result_list[[length(result_list) + 1]] <- fit$result
        if (nrow(fit$warning)) {
          warning_list[[length(warning_list) + 1]] <- fit$warning
        }
      }
    }
    all_results <- do.call(rbind, result_list)
    warnings <- if (length(warning_list)) do.call(rbind, warning_list) else empty_frame(warning_fields)
  }

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  write_tsv(file.path(output_dir, "phenotype_expression_associations.tsv"), all_results[all_results$feature_layer == "expression", , drop = FALSE], result_fields)
  write_tsv(file.path(output_dir, "phenotype_accessibility_associations.tsv"), all_results[all_results$feature_layer == "accessibility", , drop = FALSE], result_fields)
  write_tsv(file.path(output_dir, "phenotype_gra_associations.tsv"), all_results[all_results$feature_layer == "gra_activity", , drop = FALSE], result_fields)
  write_tsv(file.path(output_dir, "phenotype_omics_association_warnings.tsv"), warnings, warning_fields)
  cat(
    "CAME phenotype-omics association summary:",
    "models=", nrow(all_results),
    "warnings=", nrow(warnings),
    "\n"
  )
  0
}

status <- tryCatch(run_associations(parse_args(commandArgs(trailingOnly = TRUE))), error = function(exc) {
  cat("ERROR\trun_phenotype_omics_associations\t", conditionMessage(exc), "\n", sep = "", file = stderr())
  1
})
quit(status = status)
