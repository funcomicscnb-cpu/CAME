#!/usr/bin/env Rscript

suppressWarnings(options(stringsAsFactors = FALSE))

base_fields <- c(
  "omics_type", "contrast_name", "contrast_type", "species", "feature_id", "feature_type",
  "baseline_label", "response_label", "n_baseline", "n_response", "base_mean",
  "baseline_mean", "response_mean", "log2_fold_change", "statistic", "p_value",
  "padj", "method", "status", "message"
)
metadata_fields_by_type <- list(
  rnaseq = c("feature_id", "feature_type", "annotation_id"),
  atacseq = c("feature_id", "feature_type", "chrom", "start", "end")
)
extra_fields_by_type <- list(
  rnaseq = c("annotation_id"),
  atacseq = c("chrom", "start", "end")
)

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

fmt <- function(value) {
  if (length(value) == 0 || is.na(value) || is.nan(value) || is.infinite(value)) {
    return("NA")
  }
  format(signif(as.numeric(value), 12), scientific = FALSE, trim = TRUE)
}

split_ids <- function(value) {
  ids <- trimws(unlist(strsplit(as.character(value), ",", fixed = TRUE)))
  ids[ids != ""]
}

read_tsv <- function(path) {
  if (!file.exists(path)) {
    stop(paste("Missing required file:", path))
  }
  read.delim(path, sep = "\t", header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
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

empty_outputs <- function(output_dir, omics_type, reason) {
  extras <- extra_fields_by_type[[omics_type]]
  result_fields <- c(base_fields, extras)
  write_tsv(file.path(output_dir, "differential_results.tsv"), data.frame(), result_fields)
  write_tsv(file.path(output_dir, "normalized_counts.tsv"), data.frame(), metadata_fields_by_type[[omics_type]])
  warnings <- data.frame(
    severity = "INFO", omics_type = omics_type, species = "", contrast_name = "",
    message = reason, stringsAsFactors = FALSE
  )
  summary <- data.frame(
    omics_type = omics_type, contrast_name = "", species = "", status = "SKIPPED",
    n_features = "0", n_tested = "0", n_filtered = "0", n_significant = "0",
    method = "", warnings = reason, stringsAsFactors = FALSE
  )
  write_tsv(file.path(output_dir, "differential_warnings.tsv"), warnings, c("severity", "omics_type", "species", "contrast_name", "message"))
  write_tsv(file.path(output_dir, "differential_summary.tsv"), summary, c("omics_type", "contrast_name", "species", "status", "n_features", "n_tested", "n_filtered", "n_significant", "method", "warnings"))
}

normalize_counts <- function(count_matrix) {
  libs <- colSums(count_matrix, na.rm = TRUE)
  positive <- libs[libs > 0]
  median_lib <- if (length(positive) == 0) 1 else median(positive)
  size_factors <- ifelse(libs > 0, libs / median_lib, 1)
  sweep(count_matrix, 2, size_factors, "/")
}

batch_is_valid <- function(sample_rows, group_values) {
  if (!"batch" %in% names(sample_rows)) {
    return(FALSE)
  }
  batch <- trimws(sample_rows$batch)
  if (all(batch == "")) {
    return(FALSE)
  }
  batch[batch == ""] <- "missing_batch"
  if (length(unique(batch)) < 2) {
    return(FALSE)
  }
  design <- try(model.matrix(~ batch + group_values), silent = TRUE)
  if (inherits(design, "try-error")) {
    return(FALSE)
  }
  qr(design)$rank == ncol(design)
}

fallback_tests <- function(norm_subset, baseline_ids, response_ids, keep) {
  pvals <- rep(NA_real_, nrow(norm_subset))
  stats <- rep(NA_real_, nrow(norm_subset))
  methods <- rep("fallback_no_test", nrow(norm_subset))
  for (idx in which(keep)) {
    baseline <- as.numeric(norm_subset[idx, baseline_ids, drop = TRUE])
    response <- as.numeric(norm_subset[idx, response_ids, drop = TRUE])
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

deseq_tests <- function(count_subset, sample_rows, baseline_ids, response_ids, keep, alpha, warnings, contrast) {
  pvals <- rep(NA_real_, nrow(count_subset))
  padj <- rep(NA_real_, nrow(count_subset))
  stats <- rep(NA_real_, nrow(count_subset))
  methods <- rep("DESeq2", nrow(count_subset))
  group <- ifelse(sample_rows$sample_id %in% response_ids, "response", "baseline")
  group <- factor(group, levels = c("baseline", "response"))
  use_batch <- batch_is_valid(sample_rows, group)
  if (!use_batch) {
    warnings <- rbind(
      warnings,
      data.frame(
        severity = "WARNING", omics_type = contrast$omics_type, species = contrast$species,
        contrast_name = contrast$contrast_name,
        message = "Batch covariate omitted because it is absent, single-level, or not estimable",
        stringsAsFactors = FALSE
      )
    )
  }
  result <- try({
    col_data <- data.frame(row.names = sample_rows$sample_id, group = group, stringsAsFactors = FALSE)
    design_formula <- ~ group
    if (use_batch) {
      batch <- trimws(sample_rows$batch)
      batch[batch == ""] <- "missing_batch"
      col_data$batch <- factor(batch)
      design_formula <- ~ batch + group
    }
    dds <- DESeq2::DESeqDataSetFromMatrix(
      countData = round(count_subset[keep, sample_rows$sample_id, drop = FALSE]),
      colData = col_data,
      design = design_formula
    )
    dds <- DESeq2::DESeq(dds, quiet = TRUE)
    res <- DESeq2::results(dds, contrast = c("group", "response", "baseline"), alpha = alpha)
    res
  }, silent = TRUE)
  if (inherits(result, "try-error")) {
    warnings <- rbind(
      warnings,
      data.frame(
        severity = "WARNING", omics_type = contrast$omics_type, species = contrast$species,
        contrast_name = contrast$contrast_name,
        message = paste("DESeq2 failed; using fallback tests:", as.character(result)),
        stringsAsFactors = FALSE
      )
    )
    return(c(fallback_tests(normalize_counts(count_subset), baseline_ids, response_ids, keep), list(warnings = warnings)))
  }
  kept_indices <- which(keep)
  pvals[kept_indices] <- result$pvalue
  padj[kept_indices] <- result$padj
  stats[kept_indices] <- result$stat
  list(pvals = pvals, padj = padj, stats = stats, methods = methods, warnings = warnings)
}

run_contrast <- function(contrast, counts_df, feature_meta, count_matrix, norm_matrix, samples, args, deseq_available, warnings) {
  baseline_ids <- split_ids(contrast$baseline_sample_ids)
  response_ids <- split_ids(contrast$response_sample_ids)
  selected_ids <- c(baseline_ids, response_ids)
  sample_rows <- samples[match(selected_ids, samples$sample_id), , drop = FALSE]
  raw_subset <- count_matrix[, selected_ids, drop = FALSE]
  norm_subset <- norm_matrix[, selected_ids, drop = FALSE]
  baseline_mean <- rowMeans(norm_subset[, baseline_ids, drop = FALSE], na.rm = TRUE)
  response_mean <- rowMeans(norm_subset[, response_ids, drop = FALSE], na.rm = TRUE)
  base_mean <- rowMeans(norm_subset, na.rm = TRUE)
  log2fc <- log2((response_mean + 1) / (baseline_mean + 1))

  min_count <- as.numeric(arg_value(args, "min_count", "10"))
  min_total_count <- as.numeric(arg_value(args, "min_total_count", "10"))
  min_samples_per_group <- as.numeric(arg_value(args, "min_samples_per_group", "1"))
  alpha <- as.numeric(arg_value(args, "alpha", "0.05"))
  total_count <- rowSums(raw_subset, na.rm = TRUE)
  baseline_pass <- rowSums(raw_subset[, baseline_ids, drop = FALSE] >= min_count, na.rm = TRUE)
  response_pass <- rowSums(raw_subset[, response_ids, drop = FALSE] >= min_count, na.rm = TRUE)
  keep <- total_count >= min_total_count & (baseline_pass >= min_samples_per_group | response_pass >= min_samples_per_group)

  n_baseline <- length(baseline_ids)
  n_response <- length(response_ids)
  pvals <- rep(NA_real_, nrow(counts_df))
  padj <- rep(NA_real_, nrow(counts_df))
  stats <- rep(NA_real_, nrow(counts_df))
  methods <- rep("not_tested", nrow(counts_df))
  status <- ifelse(keep, "OK", "filtered_low_count")
  message <- ifelse(keep, "", "Feature did not pass low-count filter")

  if (n_baseline < 2 || n_response < 2) {
    status[keep] <- "no_inferential_test"
    message[keep] <- "Fewer than 2 samples in baseline or response group; p-values are NA"
    methods[keep] <- "fallback_no_test"
    warnings <- rbind(
      warnings,
      data.frame(
        severity = "WARNING", omics_type = contrast$omics_type, species = contrast$species,
        contrast_name = contrast$contrast_name,
        message = "Fewer than 2 samples in baseline or response group; p-values are NA",
        stringsAsFactors = FALSE
      )
    )
  } else if (any(keep)) {
    if (deseq_available && !as_bool(arg_value(args, "force_fallback", "false"))) {
      tests <- deseq_tests(count_matrix, sample_rows, baseline_ids, response_ids, keep, alpha, warnings, contrast)
      pvals <- tests$pvals
      stats <- tests$stats
      methods <- tests$methods
      warnings <- tests$warnings
      if (!is.null(tests$padj)) {
        padj <- tests$padj
      } else {
        padj[keep] <- p.adjust(pvals[keep], method = "BH")
      }
    } else {
      methods[keep] <- "fallback_t_test"
      tests <- fallback_tests(norm_subset, baseline_ids, response_ids, keep)
      pvals <- tests$pvals
      stats <- tests$stats
      methods <- tests$methods
      padj[keep] <- p.adjust(pvals[keep], method = "BH")
      if (!as_bool(arg_value(args, "force_fallback", "false"))) {
        warnings <- rbind(
          warnings,
          data.frame(
            severity = "WARNING", omics_type = contrast$omics_type, species = contrast$species,
            contrast_name = contrast$contrast_name,
            message = "DESeq2 is not available; using fallback tests",
            stringsAsFactors = FALSE
          )
        )
      }
    }
    no_p <- keep & is.na(pvals)
    status[no_p] <- "no_valid_test"
    message[no_p] <- "No valid inferential test was available; p-value is NA"
  }

  rows <- cbind(
    data.frame(
      omics_type = contrast$omics_type,
      contrast_name = contrast$contrast_name,
      contrast_type = contrast$contrast_type,
      species = contrast$species,
      feature_id = feature_meta$feature_id,
      feature_type = feature_meta$feature_type,
      baseline_label = contrast$baseline_label,
      response_label = contrast$response_label,
      n_baseline = as.character(n_baseline),
      n_response = as.character(n_response),
      base_mean = vapply(base_mean, fmt, character(1)),
      baseline_mean = vapply(baseline_mean, fmt, character(1)),
      response_mean = vapply(response_mean, fmt, character(1)),
      log2_fold_change = vapply(log2fc, fmt, character(1)),
      statistic = vapply(stats, fmt, character(1)),
      p_value = vapply(pvals, fmt, character(1)),
      padj = vapply(padj, fmt, character(1)),
      method = methods,
      status = status,
      message = message,
      stringsAsFactors = FALSE
    ),
    feature_meta[, extra_fields_by_type[[contrast$omics_type]], drop = FALSE]
  )
  summary <- data.frame(
    omics_type = contrast$omics_type,
    contrast_name = contrast$contrast_name,
    species = contrast$species,
    status = ifelse(any(status == "OK"), "OK", "WARNING"),
    n_features = as.character(nrow(rows)),
    n_tested = as.character(sum(status == "OK", na.rm = TRUE)),
    n_filtered = as.character(sum(status == "filtered_low_count", na.rm = TRUE)),
    n_significant = as.character(sum(!is.na(padj) & padj <= alpha, na.rm = TRUE)),
    method = paste(sort(unique(methods[methods != "not_tested"])), collapse = ","),
    warnings = paste(warnings$message[warnings$contrast_name == contrast$contrast_name & warnings$species == contrast$species], collapse = "; "),
    stringsAsFactors = FALSE
  )
  list(rows = rows, summary = summary, warnings = warnings)
}

main <- function() {
  args <- parse_args(commandArgs(trailingOnly = TRUE))
  omics_type <- arg_value(args, "omics_type")
  output_dir <- arg_value(args, "output_dir", omics_type)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  samples <- read_tsv(arg_value(args, "samples"))
  contrasts <- read_tsv(arg_value(args, "contrasts"))
  if (nrow(contrasts) == 0 || nrow(samples) == 0) {
    empty_outputs(output_dir, omics_type, "No executable contrasts for this assay")
    return(0)
  }
  counts_path <- arg_value(args, "counts")
  if (!file.exists(counts_path)) {
    stop(paste("Missing count matrix:", counts_path))
  }
  counts_df <- read_tsv(counts_path)
  metadata_fields <- metadata_fields_by_type[[omics_type]]
  missing_metadata <- setdiff(metadata_fields, names(counts_df))
  if (length(missing_metadata) > 0) {
    stop(paste("Count matrix missing feature column(s):", paste(missing_metadata, collapse = ", ")))
  }
  sample_ids <- samples$sample_id
  missing_samples <- setdiff(sample_ids, names(counts_df))
  if (length(missing_samples) > 0) {
    stop(paste("Count matrix missing sample column(s):", paste(missing_samples, collapse = ", ")))
  }
  feature_meta <- counts_df[, metadata_fields, drop = FALSE]
  count_matrix <- as.matrix(counts_df[, sample_ids, drop = FALSE])
  suppressWarnings(storage.mode(count_matrix) <- "numeric")
  if (any(is.na(count_matrix))) {
    stop("Count matrix contains non-numeric sample values")
  }
  norm_matrix <- normalize_counts(count_matrix)
  normalized_df <- cbind(feature_meta, as.data.frame(norm_matrix, check.names = FALSE))
  write_tsv(file.path(output_dir, "normalized_counts.tsv"), normalized_df, c(metadata_fields, sample_ids))

  warnings <- data.frame(severity = character(), omics_type = character(), species = character(), contrast_name = character(), message = character(), stringsAsFactors = FALSE)
  deseq_available <- requireNamespace("DESeq2", quietly = TRUE)
  result_rows <- list()
  summary_rows <- list()
  for (idx in seq_len(nrow(contrasts))) {
    contrast <- contrasts[idx, , drop = FALSE]
    result <- run_contrast(contrast, counts_df, feature_meta, count_matrix, norm_matrix, samples, args, deseq_available, warnings)
    warnings <- result$warnings
    result_rows[[length(result_rows) + 1]] <- result$rows
    summary_rows[[length(summary_rows) + 1]] <- result$summary
  }
  results <- do.call(rbind, result_rows)
  summary <- do.call(rbind, summary_rows)
  result_fields <- c(base_fields, extra_fields_by_type[[omics_type]])
  write_tsv(file.path(output_dir, "differential_results.tsv"), results, result_fields)
  write_tsv(file.path(output_dir, "differential_warnings.tsv"), warnings, c("severity", "omics_type", "species", "contrast_name", "message"))
  write_tsv(file.path(output_dir, "differential_summary.tsv"), summary, c("omics_type", "contrast_name", "species", "status", "n_features", "n_tested", "n_filtered", "n_significant", "method", "warnings"))
  message(
    "CAME differential ", omics_type, " summary: contrasts=", nrow(contrasts),
    " features=", nrow(counts_df), " DESeq2=", ifelse(deseq_available, "available", "unavailable")
  )
  0
}

status <- tryCatch(main(), error = function(exc) {
  message("ERROR\trun_differential_analysis\t", conditionMessage(exc))
  1
})
quit(status = status)
