# CAME Differential Omics

CAME runs phenotype-agnostic differential RNA-seq and ATAC-seq analysis from raw count matrices. Analyses are stratified by `species`; features are not pooled or projected through orthology.

## Inputs

Required:

- `--run_stage differential_omics`
- `--omics_samplesheet`
- either `--study_profile` or all four CLI contrast params:
  `--baseline_condition`, `--response_condition`, `--baseline_timepoint`, `--response_timepoint`

Counts are resolved from explicit paths when supplied:

- `--rnaseq_counts`
- `--atacseq_counts`

Otherwise CAME looks under `--outdir`:

- `results/rnaseq/counts/gene_counts.tsv`
- `results/atacseq/counts/re_counts.tsv`

If a requested count matrix is absent, run `--run_stage bulk_omics` first with the same `--outdir` or pass the explicit count path.

## Contrasts

CLI contrast params override profile contrasts only when all four values are supplied. Partial CLI overrides fail.

Without CLI overrides, CAME reads `phenotype_index.contrasts` from the study profile and supports the same contrast semantics as phenotype contrasts:

- `baseline_vs_response`
- `condition_contrast` and `treated_vs_control`
- `timepoint_contrast`

Only condition/timepoint labels present in the selected omics metadata are executable. Each executable contrast is materialized independently for each species with both baseline and response samples.

## Differential Engine

For contrasts with at least two samples per group and features passing the low-count filter, CAME attempts DESeq2 when available unless `--differential_force_fallback true` is set. A DESeq2 fitting error triggers fallback and a `WARNING` in `differential_warnings.tsv`. Result rows and `differential_summary.tsv` report the method used. The fallback path performs library-size normalization, computes log2 fold change with pseudocount 1, and uses base R tests only when both groups have at least two samples.

When either group has fewer than two samples, CAME still emits normalized means and log2 fold changes, but inferential p-values are `NA` with warnings. Low-count filtered features remain in output with `status=filtered_low_count`.

Batch is used as `~ batch + group` only when every selected sample has a known batch, there are at least two batch levels, and the design is full rank with residual degrees of freedom. Text is trimmed; R `NA`, empty and whitespace-only values are missing. If batch is absent, entirely or partially missing, single-level, confounded with group, or otherwise non-estimable (including a saturated design), the entire batch covariate is omitted with a warning and the fit uses `~ group`. All selected samples are retained; missing batches are not imputed. Batch is assessed separately for each contrast.

### Field provenance

| Fields | Successful DESeq2 rows | Fallback or filtered rows |
| --- | --- | --- |
| `log2_fold_change` | DESeq2 `log2FoldChange` for explicit `group`, `response`, `baseline` contrast; no shrinkage | Existing `log2((response_mean + 1) / (baseline_mean + 1))` |
| `base_mean` | DESeq2 `baseMean` from the same fit | Descriptive mean across selected samples |
| `statistic`, `p_value`, `padj` | DESeq2 `stat`, `pvalue`, `padj`, including missing values and default independent-filtering/outlier behavior | Existing base R tests and BH adjustment; filtered rows have no test |
| `baseline_mean`, `response_mean` | Descriptive means from the global matrix below | Same descriptive means |
| `method` | `DESeq2` for fitted rows; `not_tested` for filtered rows | `fallback_t_test`, `fallback_wilcoxon` or `fallback_no_valid_test` for passing rows; `fallback_no_test` for filtered rows |

`normalized_counts.tsv` is a global descriptive total-count-scaled matrix: each input sample column is divided by its total count divided by the median positive library total (zero-total columns use factor 1). Scaling uses all input features and samples before contrast selection and low-count filtering. Group means use the selected columns of this matrix. Neither the file nor these group means are contrast-specific DESeq2-normalized counts or batch-adjusted model estimates; their ratio can disagree in direction with the fitted effect under compositional imbalance. DESeq2 fits only passing features and selected samples and estimates its own size factors. Successful fit values, including `NA`, are never filled from descriptive estimates.

Filtered rows always carry `status=filtered_low_count` and descriptive effect and mean values, but their `method` depends on the path taken for the contrast. After a successful DESeq2 fit it is `not_tested`. When fallback tests run (DESeq2 unavailable, `--differential_force_fallback true`, or a DESeq2 fitting error) it is `fallback_no_test`. When no inferential path runs (fewer than two samples per group, or no passing features) it is `not_tested`. Because `fallback_no_test` also labels passing rows in contrasts with fewer than two samples per group, use `status`, not `method`, to identify filtered rows.

Output headers are unchanged. Numeric fields in `differential_results.tsv` are written with an explicit 12 significant digits; earlier v0.1 development builds used R's default of 7 significant digits. This serialization change also applies to fallback rows, whose calculations are unchanged. `normalized_counts.tsv` serialization is unchanged.

## Outputs

Outputs are written under `results/differential_omics/` by default:

- `input/differential_samples.tsv`
- `input/differential_contrasts.tsv`
- `input/differential_input_manifest.tsv`
- `rnaseq/differential_results.tsv`
- `rnaseq/normalized_counts.tsv`
- `rnaseq/differential_warnings.tsv`
- `atacseq/differential_results.tsv`
- `atacseq/normalized_counts.tsv`
- `atacseq/differential_warnings.tsv`
- `summary/differential_omics_summary.tsv`
- `summary/differential_outputs_manifest.tsv`

Result tables start with:

`omics_type`, `contrast_name`, `contrast_type`, `species`, `feature_id`, `feature_type`, `baseline_label`, `response_label`, `n_baseline`, `n_response`, `base_mean`, `baseline_mean`, `response_mean`, `log2_fold_change`, `statistic`, `p_value`, `padj`, `correction_method`, `method`, `status`, `message`

`correction_method` is `BH` when an adjusted p-value is reported and `NA` for untested rows.

RNA-seq appends `annotation_id`; ATAC-seq appends `chrom`, `start`, `end`.

## Setup

CAME does not install packages during normal runs or tests.

Use the opt-in setup helper to inspect local tools:

```bash
sh environment/install_local.sh --check-only
```

Installation actions require explicit flags:

```bash
sh environment/install_local.sh --create-conda-env
sh environment/install_local.sh --install-r
sh environment/install_local.sh --install-hmmratac --hmmratac-jar /path/to/HMMRATAC.jar
```

The installer does not edit global shell configuration.

## Real-Mode Upstream Notes

CAME consumes count matrices from upstream bulk omics. ATAC production real mode uses Bowtie2 and MACS3 and writes `results/atacseq/counts/re_counts.tsv`.

The legacy ATAC-seq compatibility path still resolves HMMRATAC in this order:

1. `HMMRATAC` on `PATH`
2. `hmmratac` on `PATH`
3. `$CAME_HMMRATAC_JAR`
4. `--hmmratac_jar`
5. local jar names such as `HMMRATAC.jar`, `hmmratac.jar`, `tools/HMMRATAC.jar`, `environment/tools/HMMRATAC.jar`, or `environment/HMMRATAC.jar`

Production ATAC real mode does not use HMMRATAC. Stub mode does not require HMMRATAC.

## Limitations

CAME does not perform orthology projection, regulatory architecture analysis, phenotype-omics association, or candidate ranking. The fallback differential engine is intended for smoke tests and small checks, not as a replacement for DESeq2.
