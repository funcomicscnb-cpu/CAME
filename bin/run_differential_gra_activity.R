#!/usr/bin/env Rscript

suppressWarnings(options(stringsAsFactors = FALSE))

result_fields <- c(
  "gra_id", "gene_orthogroup_id", "contrast_name", "baseline_label", "response_label",
  "log2_fold_change", "statistic", "p_value", "padj", "correction_method", "mean_baseline", "mean_response",
  "n_baseline", "n_response", "method", "status", "message", "species"
)
normalized_prefix <- c("gra_id", "gene_orthogroup_id", "feature_type")
warning_fields <- c("severity", "contrast_name", "species", "message")

parse_args <- function(argv) {
  args <- list()
  i <- 1
  while (i <= length(argv)) {
    key <- argv[[i]]
    if (!startsWith(key, "--")) {
      stop(paste("Unexpected argument:", key))
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

as_bool <- function(value) {
  tolower(trimws(as.character(value))) %in% c("1", "true", "yes", "y")
}

norm <- function(value) {
  text <- trimws(as.character(value))
  text[tolower(text) %in% c("", "na", "n/a", "nan", "null", "none", ".")] <- ""
  text
}

fmt <- function(value) {
  if (length(value) == 0 || is.na(value) || is.nan(value) || is.infinite(value)) {
    return("NA")
  }
  format(signif(as.numeric(value), 12), scientific = FALSE, trim = TRUE)
}

infer_sep <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "tsv") {
    return("\t")
  }
  if (ext == "csv") {
    return(",")
  }
  sample <- readChar(path, file.info(path)$size, useBytes = TRUE)
  if (gregexpr("\t", sample, fixed = TRUE)[[1]][1] != -1) "\t" else ","
}

read_table <- function(path) {
  if (!file.exists(path)) {
    stop(paste("Missing required file:", path))
  }
  read.delim(path, sep = infer_sep(path), header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
}

write_tsv <- function(path, data, fields) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (nrow(data) == 0) {
    data <- as.data.frame(setNames(rep(list(character()), length(fields)), fields), stringsAsFactors = FALSE)
  } else {
    for (field in fields) {
      if (!field %in% names(data)) {
        data[[field]] <- ""
      }
    }
    data <- data[, fields, drop = FALSE]
  }
  write.table(data, path, sep = "\t", quote = FALSE, row.names = FALSE, col.names = TRUE, na = "NA")
}

strip_yaml_value <- function(value) {
  value <- trimws(sub("#.*$", "", value))
  value <- sub("^['\"]", "", value)
  value <- sub("['\"]$", "", value)
  value
}

profile_contrasts <- function(path) {
  if (path == "" || !file.exists(path)) {
    return(list())
  }
  lines <- readLines(path, warn = FALSE)
  in_contrasts <- FALSE
  contrasts <- list()
  current <- NULL
  for (line in lines) {
    if (grepl("^\\s*contrasts\\s*:", line)) {
      in_contrasts <- TRUE
      next
    }
    if (!in_contrasts) {
      next
    }
    if (!is.null(current) && grepl("^\\S", line)) {
      contrasts[[length(contrasts) + 1]] <- current
      current <- NULL
      break
    }
    if (grepl("^\\s*-\\s*", line)) {
      if (!is.null(current)) {
        contrasts[[length(contrasts) + 1]] <- current
      }
      current <- list()
      remainder <- sub("^\\s*-\\s*", "", line)
      if (grepl("^[A-Za-z_]+\\s*:", remainder)) {
        key <- sub("\\s*:.*$", "", remainder)
        value <- sub("^[A-Za-z_]+\\s*:\\s*", "", remainder)
        current[[key]] <- strip_yaml_value(value)
      }
      next
    }
    if (!is.null(current) && grepl("^\\s*[A-Za-z_]+\\s*:", line)) {
      key <- trimws(sub("\\s*:.*$", "", line))
      value <- sub("^\\s*[A-Za-z_]+\\s*:\\s*", "", line)
      current[[key]] <- strip_yaml_value(value)
    }
  }
  if (!is.null(current)) {
    contrasts[[length(contrasts) + 1]] <- current
  }
  contrasts
}

cli_contrasts <- function(args) {
  values <- c(
    arg_value(args, "baseline_condition"),
    arg_value(args, "response_condition"),
    arg_value(args, "baseline_timepoint"),
    arg_value(args, "response_timepoint")
  )
  supplied <- values[norm(values) != ""]
  if (length(supplied) == 0) {
    return(NULL)
  }
  if (length(supplied) != 4) {
    stop("CLI contrast override requires baseline_condition, response_condition, baseline_timepoint, and response_timepoint")
  }
  list(list(
    name = "cli_baseline_vs_response",
    type = "baseline_vs_response",
    baseline_condition = norm(values[[1]]),
    response_condition = norm(values[[2]]),
    baseline_timepoint = norm(values[[3]]),
    response_timepoint = norm(values[[4]])
  ))
}

load_contrasts <- function(args) {
  override <- cli_contrasts(args)
  if (!is.null(override)) {
    return(override)
  }
  profile_contrasts(arg_value(args, "study_profile"))
}

label <- function(condition, timepoint) {
  if (condition != "" && timepoint != "") {
    return(paste(condition, timepoint, sep = "|"))
  }
  paste0(condition, timepoint)
}

contrast_value <- function(contrast, names) {
  for (name in names) {
    value <- contrast[[name]]
    if (!is.null(value) && norm(value) != "") {
      return(norm(value))
    }
  }
  ""
}

executable_contrasts <- function(samples, contrasts, warnings) {
  rows <- list()
  if (length(contrasts) == 0) {
    warnings <- rbind(warnings, data.frame(severity = "WARNING", contrast_name = "", species = "", message = "No study_profile or complete CLI contrast override was supplied", stringsAsFactors = FALSE))
    return(list(rows = data.frame(), warnings = warnings))
  }
  species_values <- sort(unique(samples$species))
  for (contrast in contrasts) {
    name <- contrast_value(contrast, c("name"))
    if (name == "") {
      name <- "unnamed_contrast"
    }
    ctype <- contrast_value(contrast, c("type"))
    if (ctype == "treated_vs_control") {
      ctype <- "condition_contrast"
    }
    bc <- ""
    rc <- ""
    bt <- ""
    rt <- ""
    if (ctype == "baseline_vs_response") {
      bc <- contrast_value(contrast, c("baseline_condition"))
      rc <- contrast_value(contrast, c("response_condition"))
      bt <- contrast_value(contrast, c("baseline_timepoint"))
      rt <- contrast_value(contrast, c("response_timepoint"))
    } else if (ctype == "condition_contrast") {
      bc <- contrast_value(contrast, c("baseline_condition", "control_condition"))
      rc <- contrast_value(contrast, c("response_condition", "treated_condition"))
      bt <- contrast_value(contrast, c("baseline_timepoint"))
      rt <- contrast_value(contrast, c("response_timepoint"))
    } else {
      warnings <- rbind(warnings, data.frame(severity = "WARNING", contrast_name = name, species = "", message = paste("Unsupported contrast type:", ctype), stringsAsFactors = FALSE))
      next
    }
    for (species in species_values) {
      base <- samples[samples$species == species & samples$condition == bc & samples$timepoint == bt, , drop = FALSE]
      resp <- samples[samples$species == species & samples$condition == rc & samples$timepoint == rt, , drop = FALSE]
      if (nrow(base) == 0 || nrow(resp) == 0) {
        warnings <- rbind(warnings, data.frame(severity = "WARNING", contrast_name = name, species = species, message = "No executable baseline/response sample pair for species", stringsAsFactors = FALSE))
        next
      }
      rows[[length(rows) + 1]] <- data.frame(
        contrast_name = name,
        species = species,
        baseline_label = label(bc, bt),
        response_label = label(rc, rt),
        baseline_sample_ids = paste(base$sample_id, collapse = ","),
        response_sample_ids = paste(resp$sample_id, collapse = ","),
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows) == 0) {
    return(list(rows = data.frame(), warnings = warnings))
  }
  list(rows = do.call(rbind, rows), warnings = warnings)
}

split_ids <- function(value) {
  ids <- trimws(unlist(strsplit(as.character(value), ",", fixed = TRUE)))
  ids[ids != ""]
}

normalize_matrix <- function(matrix_values) {
  libs <- colSums(matrix_values, na.rm = TRUE)
  positive <- libs[libs > 0]
  median_lib <- if (length(positive) == 0) 1 else median(positive)
  size_factors <- ifelse(libs > 0, libs / median_lib, 1)
  sweep(matrix_values, 2, size_factors, "/")
}

fallback_tests <- function(norm_subset, baseline_ids, response_ids, keep) {
  pvals <- rep(NA_real_, nrow(norm_subset))
  stats <- rep(NA_real_, nrow(norm_subset))
  methods <- rep("not_tested", nrow(norm_subset))
  for (idx in which(keep)) {
    baseline <- as.numeric(norm_subset[idx, baseline_ids, drop = TRUE])
    response <- as.numeric(norm_subset[idx, response_ids, drop = TRUE])
    baseline <- baseline[!is.na(baseline)]
    response <- response[!is.na(response)]
    if (length(baseline) < 2 || length(response) < 2) {
      methods[[idx]] <- "fallback_no_test"
      next
    }
    test <- try(t.test(response, baseline), silent = TRUE)
    if (!inherits(test, "try-error") && !is.na(test$p.value)) {
      pvals[[idx]] <- test$p.value
      stats[[idx]] <- unname(test$statistic[[1]])
      methods[[idx]] <- "fallback_t_test"
      next
    }
    test <- try(wilcox.test(response, baseline, exact = FALSE), silent = TRUE)
    if (!inherits(test, "try-error") && !is.na(test$p.value)) {
      pvals[[idx]] <- test$p.value
      stats[[idx]] <- unname(test$statistic[[1]])
      methods[[idx]] <- "fallback_wilcoxon"
    } else {
      methods[[idx]] <- "fallback_no_valid_test"
    }
  }
  list(pvals = pvals, stats = stats, methods = methods)
}

integer_nonnegative_matrix <- function(values) {
  all(!is.na(values)) && all(is.finite(values)) && all(values >= 0) && all(abs(values - round(values)) < 1e-8)
}

deseq_tests <- function(raw_subset, sample_ids, baseline_ids, response_ids, keep, alpha) {
  pvals <- rep(NA_real_, nrow(raw_subset))
  padj <- rep(NA_real_, nrow(raw_subset))
  stats <- rep(NA_real_, nrow(raw_subset))
  methods <- rep("DESeq2", nrow(raw_subset))
  result <- try({
    group <- ifelse(sample_ids %in% response_ids, "response", "baseline")
    group <- factor(group, levels = c("baseline", "response"))
    col_data <- data.frame(row.names = sample_ids, group = group, stringsAsFactors = FALSE)
    dds <- DESeq2::DESeqDataSetFromMatrix(
      countData = round(raw_subset[keep, sample_ids, drop = FALSE]),
      colData = col_data,
      design = ~ group
    )
    dds <- DESeq2::DESeq(dds, quiet = TRUE)
    DESeq2::results(dds, contrast = c("group", "response", "baseline"), alpha = alpha)
  }, silent = TRUE)
  if (inherits(result, "try-error")) {
    return(NULL)
  }
  kept_indices <- which(keep)
  pvals[kept_indices] <- result$pvalue
  padj[kept_indices] <- result$padj
  stats[kept_indices] <- result$stat
  list(pvals = pvals, padj = padj, stats = stats, methods = methods)
}

run_contrast <- function(contrast, feature_meta, raw_matrix, norm_matrix, args, warnings) {
  baseline_ids <- split_ids(contrast$baseline_sample_ids)
  response_ids <- split_ids(contrast$response_sample_ids)
  sample_ids <- c(baseline_ids, response_ids)
  raw_subset <- raw_matrix[, sample_ids, drop = FALSE]
  norm_subset <- norm_matrix[, sample_ids, drop = FALSE]

  baseline_mean <- rowMeans(norm_subset[, baseline_ids, drop = FALSE], na.rm = TRUE)
  response_mean <- rowMeans(norm_subset[, response_ids, drop = FALSE], na.rm = TRUE)
  log2fc <- log2((response_mean + 1) / (baseline_mean + 1))

  min_count <- as.numeric(arg_value(args, "min_count", "10"))
  min_total_count <- as.numeric(arg_value(args, "min_total_count", "10"))
  min_samples_per_group <- as.numeric(arg_value(args, "min_samples_per_group", "1"))
  alpha <- as.numeric(arg_value(args, "alpha", "0.05"))
  total_signal <- rowSums(raw_subset, na.rm = TRUE)
  baseline_pass <- rowSums(raw_subset[, baseline_ids, drop = FALSE] >= min_count, na.rm = TRUE)
  response_pass <- rowSums(raw_subset[, response_ids, drop = FALSE] >= min_count, na.rm = TRUE)
  keep <- total_signal >= min_total_count & (baseline_pass >= min_samples_per_group | response_pass >= min_samples_per_group)

  pvals <- rep(NA_real_, nrow(raw_subset))
  padj <- rep(NA_real_, nrow(raw_subset))
  stats <- rep(NA_real_, nrow(raw_subset))
  methods <- rep("not_tested", nrow(raw_subset))
  status <- ifelse(keep, "OK", "filtered_low_signal")
  message <- ifelse(keep, "", "GRA did not pass low-signal filter")

  enough_replicates <- length(baseline_ids) >= 2 && length(response_ids) >= 2
  used_deseq <- FALSE
  if (any(keep) && enough_replicates) {
    deseq_available <- requireNamespace("DESeq2", quietly = TRUE)
    can_use_deseq <- deseq_available &&
      !as_bool(arg_value(args, "force_fallback", "false")) &&
      arg_value(args, "aggregation", "mean") == "sum" &&
      integer_nonnegative_matrix(raw_subset[, sample_ids, drop = FALSE])
    if (can_use_deseq) {
      tests <- deseq_tests(raw_subset, sample_ids, baseline_ids, response_ids, keep, alpha)
      if (!is.null(tests)) {
        pvals <- tests$pvals
        padj <- tests$padj
        stats <- tests$stats
        methods <- tests$methods
        used_deseq <- TRUE
      } else {
        warnings <- rbind(warnings, data.frame(severity = "WARNING", contrast_name = contrast$contrast_name, species = contrast$species, message = "DESeq2 failed; using fallback tests", stringsAsFactors = FALSE))
      }
    }
    if (!used_deseq) {
      tests <- fallback_tests(norm_subset, baseline_ids, response_ids, keep)
      pvals <- tests$pvals
      stats <- tests$stats
      methods <- tests$methods
      padj[keep] <- p.adjust(pvals[keep], method = "BH")
      if (!as_bool(arg_value(args, "force_fallback", "false"))) {
        warnings <- rbind(warnings, data.frame(severity = "WARNING", contrast_name = contrast$contrast_name, species = contrast$species, message = "Using fallback tests for GRA activity because DESeq2 was unavailable or unsuitable", stringsAsFactors = FALSE))
      }
    }
  } else if (any(keep)) {
    status[keep] <- "no_inferential_test"
    message[keep] <- "Fewer than 2 samples in baseline or response group; p-values are NA"
    methods[keep] <- "fallback_no_test"
    warnings <- rbind(warnings, data.frame(severity = "WARNING", contrast_name = contrast$contrast_name, species = contrast$species, message = "Fewer than 2 samples in baseline or response group; p-values are NA", stringsAsFactors = FALSE))
  }

  no_p <- keep & is.na(pvals) & status == "OK"
  status[no_p] <- "no_valid_test"
  message[no_p] <- "No valid inferential test was available; p-value is NA"

  rows <- data.frame(
    gra_id = feature_meta$gra_id,
    gene_orthogroup_id = feature_meta$gene_orthogroup_id,
    contrast_name = contrast$contrast_name,
    baseline_label = contrast$baseline_label,
    response_label = contrast$response_label,
    log2_fold_change = vapply(log2fc, fmt, character(1)),
    statistic = vapply(stats, fmt, character(1)),
    p_value = vapply(pvals, fmt, character(1)),
    padj = vapply(padj, fmt, character(1)),
    correction_method = ifelse(!is.na(padj), "BH", "NA"),
    mean_baseline = vapply(baseline_mean, fmt, character(1)),
    mean_response = vapply(response_mean, fmt, character(1)),
    n_baseline = as.character(length(baseline_ids)),
    n_response = as.character(length(response_ids)),
    method = methods,
    status = status,
    message = message,
    species = contrast$species,
    stringsAsFactors = FALSE
  )
  list(rows = rows, warnings = warnings)
}

main <- function() {
  args <- parse_args(commandArgs(trailingOnly = TRUE))
  output_dir <- arg_value(args, "output_dir", "results/gra/differential")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  activity <- read_table(arg_value(args, "gra_activity_matrix"))
  missing_meta <- setdiff(normalized_prefix, names(activity))
  if (length(missing_meta) > 0) {
    stop(paste("GRA activity matrix missing required column(s):", paste(missing_meta, collapse = ", ")))
  }
  sample_columns <- setdiff(names(activity), normalized_prefix)
  feature_meta <- activity[, normalized_prefix, drop = FALSE]
  raw_matrix <- as.matrix(activity[, sample_columns, drop = FALSE])
  suppressWarnings(storage.mode(raw_matrix) <- "numeric")
  if (any(is.nan(raw_matrix))) {
    raw_matrix[is.nan(raw_matrix)] <- NA_real_
  }
  norm_matrix <- normalize_matrix(raw_matrix)
  normalized <- cbind(feature_meta, as.data.frame(norm_matrix, check.names = FALSE))
  write_tsv(file.path(output_dir, "normalized_gra_activity.tsv"), normalized, c(normalized_prefix, sample_columns))

  samples <- read_table(arg_value(args, "omics_samplesheet"))
  missing_sample_fields <- setdiff(c("sample_id", "species", "condition", "timepoint"), names(samples))
  if (length(missing_sample_fields) > 0) {
    stop(paste("omics_samplesheet missing required column(s):", paste(missing_sample_fields, collapse = ", ")))
  }
  samples <- samples[samples$sample_id %in% sample_columns, , drop = FALSE]
  samples <- samples[match(sample_columns[sample_columns %in% samples$sample_id], samples$sample_id), , drop = FALSE]
  warnings <- data.frame(severity = character(), contrast_name = character(), species = character(), message = character(), stringsAsFactors = FALSE)
  contrasts <- load_contrasts(args)
  prepared <- executable_contrasts(samples, contrasts, warnings)
  contrast_rows <- prepared$rows
  warnings <- prepared$warnings
  if (nrow(contrast_rows) == 0 || nrow(activity) == 0) {
    write_tsv(file.path(output_dir, "differential_gra_activity.tsv"), data.frame(), result_fields)
    write_tsv(file.path(output_dir, "differential_gra_activity_warnings.tsv"), warnings, warning_fields)
    message("CAME differential GRA summary: contrasts=0 GRAs=", nrow(activity))
    return(0)
  }

  result_rows <- list()
  for (idx in seq_len(nrow(contrast_rows))) {
    result <- run_contrast(contrast_rows[idx, , drop = FALSE], feature_meta, raw_matrix, norm_matrix, args, warnings)
    warnings <- result$warnings
    result_rows[[length(result_rows) + 1]] <- result$rows
  }
  results <- do.call(rbind, result_rows)
  write_tsv(file.path(output_dir, "differential_gra_activity.tsv"), results, result_fields)
  write_tsv(file.path(output_dir, "differential_gra_activity_warnings.tsv"), warnings, warning_fields)
  message("CAME differential GRA summary: contrasts=", nrow(contrast_rows), " GRAs=", nrow(activity))
  0
}

status <- tryCatch(main(), error = function(exc) {
  message("ERROR\trun_differential_gra_activity\t", conditionMessage(exc))
  1
})
quit(status = status)
