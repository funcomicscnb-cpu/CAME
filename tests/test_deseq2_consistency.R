#!/usr/bin/env Rscript
# Strict integration/oracle test: deliberately fails without DESeq2 or on fallback.
argv <- commandArgs(trailingOnly = TRUE)
option <- function(key, default) {
  i <- match(key, argv)
  if (is.na(i)) default else argv[[i + 1L]]
}
root <- normalizePath(file.path(dirname(sub('^--file=', '', grep('^--file=', commandArgs(), value = TRUE))), '..'))
scripts <- option('--scripts-dir', file.path(root, 'bin'))
evidence <- option('--evidence-dir', tempfile('came-deseq2-'))
case <- option('--case', 'all')
dir.create(evidence, recursive = TRUE, showWarnings = FALSE)
evidence <- normalizePath(evidence)
if (!requireNamespace('DESeq2', quietly = TRUE)) stop('DESeq2 is required: skipping is not a pass')
writeLines(capture.output(sessionInfo()), file.path(evidence, 'sessionInfo.txt'))
writeLines(c(R.version.string, paste('DESeq2', packageVersion('DESeq2')), paste('scripts', scripts)), file.path(evidence, 'versions.txt'))
writeLines(paste(commandArgs(), collapse = ' '), file.path(evidence, 'invocation.txt'))
write_tsv <- function(x, path) write.table(x, path, sep = '\t', quote = FALSE, row.names = FALSE, na = 'NA')
read_tsv <- function(path) read.delim(path, check.names = FALSE, stringsAsFactors = FALSE)
check <- function(ok, message) if (!isTRUE(ok)) stop(message, call. = FALSE)
# Same-package deterministic oracle: 12 significant digits in CAME TSVs gives
# <5e-12 relative serialization error. 1e-8 allows small fit-order rounding.
# P-values use relative error (including very small values), other fields use
# abs(error)/max(1, abs(reference)); NA masks must match exactly.
compare <- function(actual, expected, name) {
  actual <- as.numeric(actual)
  expected <- as.numeric(expected)
  check(identical(is.na(actual), is.na(expected)), paste(name, 'NA mask differs'))
  finite <- !is.na(expected)
  scale <- if (grepl('p_value|padj|pvalue|BH', name)) pmax(.Machine$double.xmin, abs(expected[finite])) else pmax(1, abs(expected[finite]))
  error <- abs(actual[finite] - expected[finite]) / scale
  worst <- if (length(error)) max(error) else 0
  cat(name, 'max scaled error =', format(worst, digits = 12), '\n',
      file = file.path(evidence, 'comparisons.txt'), append = TRUE)
  check(all(is.finite(error)) && worst <= 1e-8, paste(name, 'numeric mismatch', worst))
}
# Frozen fixture v1 (seed 20261015): heterogeneous NB counts with varied
# dispersion, compositional shifts, sparse/zero rows and a Cook's outlier.
# Row/column permutations are frozen too; exact count bytes are versioned.
fixture <- read_tsv(file.path(root, 'tests', 'fixtures', 'deseq2_counts.tsv'))
x <- as.matrix(fixture[, -1, drop = FALSE])
rownames(x) <- fixture$feature_id
ids <- paste0('s', 1:12)
base_ids <- ids[1:6]
resp_ids <- ids[7:12]
batch <- rep(c('a', 'b', 'c'), 4)
meta <- data.frame(feature_id = rownames(x), feature_type = 'gene', annotation_id = paste0('ann_', rownames(x)))
rna <- cbind(meta, x)
atac <- cbind(meta[1:2], chrom = 'chr1', start = seq_len(nrow(x)) * 100L, end = seq_len(nrow(x)) * 100L + 50L, x)
atac$feature_type <- 'regulatory_element'
gra <- cbind(data.frame(gra_id = rownames(x), gene_orthogroup_id = paste0('og_', rownames(x)), feature_type = 'gra'), x)
for (kind in c('rna', 'atac', 'gra')) write_tsv(get(kind), file.path(evidence, paste0(kind, '.tsv')))
samples <- data.frame(sample_id = c(ids, 'extra'), species = 'synthetic', condition = c(rep('base', 6), rep('resp', 6), 'other'), timepoint = c(rep('t0', 6), rep('t1', 6), 't2'), batch = c(batch, 'a'))
samples <- samples[c(13, 8, 2, 11, 4, 6, 9, 1, 12, 3, 10, 5, 7), ]
# Explicit non-canonical contrast order for RNA/ATAC.
selected <- c(rev(base_ids), resp_ids[c(3, 1, 6, 2, 5, 4)])
contrast <- data.frame(omics_type = 'rnaseq', contrast_name = 'oracle', contrast_type = 'baseline_vs_response', species = 'synthetic', baseline_label = 'base|t0', response_label = 'resp|t1', baseline_sample_ids = paste(selected[1:6], collapse = ','), response_sample_ids = paste(selected[7:12], collapse = ','))
raw <- x[, ids, drop = FALSE]
keep <- rowSums(raw) >= 10 & (rowSums(raw[, base_ids] >= 5) >= 1 | rowSums(raw[, resp_ids] >= 5) >= 1)
check(any(!keep) && any(keep), 'fixture must exercise filtering')
libs <- colSums(x)
descriptive <- sweep(x, 2, libs / median(libs[libs > 0]), '/')
base_mean <- rowMeans(descriptive[, base_ids])
resp_mean <- rowMeans(descriptive[, resp_ids])
descriptive_fc <- log2((resp_mean + 1) / (base_mean + 1))

# Oracle constructs/fits its own DESeqDataSet; never sources CAME code.
oracle <- function(sample_table, order, use_batch, name, keep_rows = keep) {
  group <- factor(ifelse(order %in% resp_ids, 'response', 'baseline'), levels = c('baseline', 'response'))
  cd <- data.frame(row.names = order, group = group)
  design <- ~ group
  if (use_batch) {
    cd$batch <- factor(trimws(as.character(sample_table$batch[match(order, sample_table$sample_id)])))
    design <- ~ batch + group
  }
  dds <- DESeq2::DESeqDataSetFromMatrix(countData = round(x[keep_rows, order, drop = FALSE]), colData = cd, design = design)
  dds <- DESeq2::DESeq(dds, quiet = TRUE)
  expected <- as.data.frame(DESeq2::results(dds, contrast = c('group', 'response', 'baseline'), alpha = 0.05))
  write_tsv(cbind(feature_id = rownames(expected), expected), file.path(evidence, paste0(name, '-oracle.tsv')))
  write_tsv(cbind(sample_id = rownames(cd), cd), file.path(evidence, paste0(name, '-design.tsv')))
  saveRDS(dds, file.path(evidence, paste0(name, '-dds.rds')))
  expected
}
run <- function(kind, table, name, fallback = FALSE, include_zero = FALSE) {
  out <- file.path(evidence, name)
  dir.create(out, showWarnings = FALSE)
  sp <- file.path(out, 'samples.tsv')
  write_tsv(table, sp)
  input <- file.path(out, 'counts.tsv')
  check(file.copy(file.path(evidence, paste0(kind, '.tsv')), input, overwrite = TRUE), 'could not retain case input')
  if (kind == 'gra') {
    script <- 'run_differential_gra_activity.R'
    args <- c('--gra_activity_matrix', input, '--omics_samplesheet', sp, '--aggregation', 'sum', '--baseline_condition', 'base', '--response_condition', 'resp', '--baseline_timepoint', 't0', '--response_timepoint', 't1')
    result <- 'differential_gra_activity.tsv'
    warnings <- 'differential_gra_activity_warnings.tsv'
  } else {
    script <- 'run_differential_analysis.R'
    ct <- contrast
    ct$omics_type <- if (kind == 'rna') 'rnaseq' else 'atacseq'
    cp <- file.path(out, 'contrasts.tsv')
    write_tsv(ct, cp)
    args <- c('--counts', input, '--samples', sp, '--contrasts', cp, '--omics_type', ct$omics_type)
    result <- 'differential_results.tsv'
    warnings <- 'differential_warnings.tsv'
  }
  args <- c(file.path(scripts, script), args, '--output_dir', out, '--min_count', if (include_zero) '0' else '5', '--min_total_count', if (include_zero) '0' else '10', '--min_samples_per_group', '1', '--alpha', '0.05', '--force_fallback', tolower(as.character(fallback)))
  command <- paste(c(shQuote(file.path(R.home('bin'), 'Rscript')), shQuote(args)), collapse = ' ')
  cat(command, '\n', file = file.path(evidence, 'commands.sh'), append = TRUE)
  status <- system2(file.path(R.home('bin'), 'Rscript'), shQuote(args), stdout = file.path(out, 'execution.log'), stderr = file.path(out, 'execution.log'))
  check(status == 0, paste(name, 'execution failed; see', file.path(out, 'execution.log')))
  list(rows = read_tsv(file.path(out, result)), warnings = read_tsv(file.path(out, warnings)), out = out)
}
validate <- function(actual, expected, kind, name, omitted = FALSE) {
  rows <- actual$rows
  feature <- if (kind == 'gra') rows$gra_id else rows$feature_id
  check(identical(feature, rownames(x)), paste(name, 'feature identity/order changed'))
  check(all(rows$method[keep] == 'DESeq2'), paste(name, 'unexpected fallback: successful DESeq2 required'))
  expected <- expected[match(feature[keep], rownames(expected)), , drop = FALSE]
  fields <- c(log2_fold_change = 'log2FoldChange', statistic = 'stat', p_value = 'pvalue', padj = 'padj')
  if (kind != 'gra') fields <- c(fields, base_mean = 'baseMean')
  for (field in names(fields)) compare(rows[[field]][keep], expected[[fields[[field]]]], paste(name, field))
  check(all(rows$method[!keep] == 'not_tested'), paste(name, 'filtered features labelled fitted'))
  check(any(is.na(expected$padj) & !is.na(expected$pvalue)), paste(name, 'fixture must expose independent-filter missingness'))
  if (omitted || kind == 'gra') check(any(is.na(expected$pvalue)), paste(name, 'fixture must expose outlier missingness'))
  compare(rows[[if (kind == 'gra') 'mean_baseline' else 'baseline_mean']], base_mean, paste(name, 'descriptive baseline'))
  compare(rows[[if (kind == 'gra') 'mean_response' else 'response_mean']], resp_mean, paste(name, 'descriptive response'))
  normalized <- read_tsv(file.path(actual$out, if (kind == 'gra') 'normalized_gra_activity.tsv' else 'normalized_counts.tsv'))
  for (id in colnames(x)) compare(normalized[[id]], descriptive[, id], paste(name, 'descriptive', id))
  compare(rows$log2_fold_change[!keep], descriptive_fc[!keep], paste(name, 'filtered descriptive effect'))
  if (kind != 'gra') {
    compare(rows$base_mean[!keep], rowMeans(descriptive[, ids])[!keep], paste(name, 'filtered descriptive base mean'))
    check(any(grepl('Batch covariate omitted', actual$warnings$message)) == omitted, paste(name, 'batch warning mismatch'))
  }
  check(identical(is.na(rows$correction_method), is.na(rows$padj)) && all(rows$correction_method[!is.na(rows$padj)] == 'BH'), paste(name, 'correction labels'))
}
blank <- samples
blank$batch <- ''
if (case %in% c('all', 'effects-rna', 'effects-gra', 'batch-blank')) {
  no_batch <- samples[, setdiff(names(samples), 'batch')]
  if (case %in% c('all', 'effects-rna')) {
    expected <- oracle(no_batch, selected, FALSE, 'rna-group')
    opposition <- sign(expected$log2FoldChange) != sign(descriptive_fc[keep]) & !is.na(expected$log2FoldChange)
    check(sum(opposition) >= 10, 'fixture does not expose effect-direction mismatch')
    write_tsv(data.frame(feature_id = rownames(expected), deseq2 = expected$log2FoldChange, old_descriptive = descriptive_fc[keep], opposing = opposition), file.path(evidence, 'effect-directions.tsv'))
    validate(run('rna', no_batch, 'rna-absent'), expected, 'rna', 'rna-absent', TRUE)
  }
  if (case %in% c('all', 'effects-gra')) {
    # GRA orders selected samples by matrix columns, independently of samplesheet.
    gra_order <- colnames(x)[colnames(x) %in% base_ids]
    gra_order <- c(gra_order, colnames(x)[colnames(x) %in% resp_ids])
    expected_gra <- oracle(samples, gra_order, FALSE, 'gra-group')
    validate(run('gra', samples, 'gra-sum'), expected_gra, 'gra', 'gra-sum')
  }
  if (case %in% c('all', 'batch-blank')) {
    expected <- oracle(blank, selected, FALSE, 'blank-group')
    validate(run('rna', blank, 'rna-blank'), expected, 'rna', 'rna-blank', TRUE)
  }
}
if (case == 'all') {
  # Each omit case uses exactly the group-only reference, preserving all samples.
  variants <- list(na = samples, whitespace = samples, partial = samples, single = samples, confounded = samples, saturated = samples)
  variants$na$batch <- NA_character_
  variants$whitespace$batch <- '   '
  variants$partial$batch[variants$partial$sample_id == 's2'] <- NA_character_
  variants$partial$batch[variants$partial$sample_id == 's7'] <- '  '
  variants$single$batch <- ' one '
  variants$confounded$batch <- variants$confounded$condition
  variants$saturated$batch <- variants$saturated$sample_id
  variants$saturated$batch[variants$saturated$sample_id == 's7'] <- 's1'
  for (name in names(variants)) validate(run('rna', variants[[name]], paste0('rna-', name)), expected, 'rna', paste0('rna-', name), TRUE)
  valid <- samples
  valid$batch <- paste0(' ', valid$batch, ' ')
  valid_expected <- oracle(valid, selected, TRUE, 'valid-batch')
  validate(run('rna', valid, 'rna-valid'), valid_expected, 'rna', 'rna-valid')
  validate(run('atac', valid, 'atac-valid'), valid_expected, 'atac', 'atac-valid')
  zero_expected <- oracle(no_batch, selected, FALSE, 'zero-included', rep(TRUE, nrow(x)))
  zero_actual <- run('rna', no_batch, 'rna-zero-included', include_zero = TRUE)$rows
  check(all(zero_actual$method == 'DESeq2'), 'zero-included unexpected fallback')
  zero_expected <- zero_expected[match(zero_actual$feature_id, rownames(zero_expected)), ]
  check(any(is.na(zero_expected$log2FoldChange)), 'fixture must expose missing effect estimate')
  for (field in c(log2_fold_change = 'log2FoldChange', base_mean = 'baseMean', statistic = 'stat', p_value = 'pvalue', padj = 'padj')) {
    output_field <- c(log2FoldChange = 'log2_fold_change', baseMean = 'base_mean', stat = 'statistic', pvalue = 'p_value', padj = 'padj')[[field]]
    compare(zero_actual[[output_field]], zero_expected[[field]], paste('zero-included', field))
  }
  # Reversing feature rows and sample columns changes no keyed estimates.
  reversed <- rna[nrow(rna):1, c(names(meta), rev(colnames(x)))]
  write_tsv(reversed, file.path(evidence, 'rna.tsv'))
  reordered <- run('rna', valid[nrow(valid):1, ], 'rna-reordered')$rows
  original <- read_tsv(file.path(evidence, 'rna-valid', 'differential_results.tsv'))
  reordered <- reordered[match(original$feature_id, reordered$feature_id), ]
  check(identical(original$method, reordered$method), 'ordering changed method')
  for (field in c('log2_fold_change', 'base_mean', 'statistic', 'p_value', 'padj')) compare(reordered[[field]], original[[field]], paste('ordering', field))
  write_tsv(rna, file.path(evidence, 'rna.tsv'))
  for (kind in c('rna', 'atac', 'gra')) {
    fallback <- run(kind, blank, paste0(kind, '-fallback'), TRUE)$rows
    check(all(grepl('^fallback_', fallback$method[keep])), paste(kind, 'forced fallback label'))
    compare(fallback$log2_fold_change, descriptive_fc, paste(kind, 'fallback effect'))
    p <- vapply(which(keep), function(i) {
      a <- descriptive[i, resp_ids]; b <- descriptive[i, base_ids]
      tt <- try(t.test(a, b), silent = TRUE)
      if (!inherits(tt, 'try-error') && !is.na(tt$p.value)) return(tt$p.value)
      wt <- try(wilcox.test(a, b, exact = FALSE), silent = TRUE)
      if (!inherits(wt, 'try-error')) wt$p.value else NA_real_
    }, numeric(1))
    compare(fallback$p_value[keep], p, paste(kind, 'fallback pvalue'))
    compare(fallback$padj[keep], p.adjust(p, 'BH'), paste(kind, 'fallback BH'))
  }
}
writeLines(paste('PASS', case), file.path(evidence, 'outcome.txt'))
cat('Strict DESeq2 consistency tests passed:', case, '\nEvidence:', evidence, '\n')
