# CAME Stage 6 Differential Omics

Stage 6 runs phenotype-agnostic differential RNA-seq and ATAC-seq analysis from Stage 5 raw count matrices. Analyses are stratified by `species`; features are not pooled or projected through orthology.

## Inputs

Required:

- `--run_stage differential_omics`
- `--omics_samplesheet`
- either `--study_profile` or all four CLI contrast params:
  `--baseline_condition`, `--response_condition`, `--baseline_timepoint`, `--response_timepoint`

Counts are resolved from explicit paths when supplied:

- `--rnaseq_counts`
- `--atacseq_counts`

Otherwise Stage 6 looks under `--outdir`:

- `results/rnaseq/counts/gene_counts.tsv`
- `results/atacseq/counts/re_counts.tsv`

If a requested count matrix is absent, run `--run_stage bulk_omics` first with the same `--outdir` or pass the explicit count path.

## Contrasts

CLI contrast params override profile contrasts only when all four values are supplied. Partial CLI overrides fail.

Without CLI overrides, Stage 6 reads `phenotype_index.contrasts` from the study profile and supports the same contrast semantics as phenotype contrasts:

- `baseline_vs_response`
- `condition_contrast` and `treated_vs_control`
- `timepoint_contrast`

Only condition/timepoint labels present in the selected omics metadata are executable. Each executable contrast is materialized independently for each species with both baseline and response samples.

## Differential Engine

DESeq2 is used when available unless `--differential_force_fallback true` is set. The fallback path performs library-size normalization, computes log2 fold change with pseudocount 1, and uses base R tests only when both groups have at least two samples.

When either group has fewer than two samples, Stage 6 still emits normalized means and log2 fold changes, but inferential p-values are `NA` with warnings. Low-count filtered features remain in output with `status=filtered_low_count`.

Batch is used only when a non-empty, multi-level `batch` column is estimable for the selected contrast. Otherwise it is omitted with a warning.

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

Stage 6 does not install packages during normal runs or tests.

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

Stage 6 consumes count matrices from upstream bulk omics. Stage 24 ATAC production real mode uses Bowtie2 and MACS3 and writes `results/atacseq/counts/re_counts.tsv`.

The legacy Stage 5 ATAC-seq scaffold still resolves HMMRATAC in this order:

1. `HMMRATAC` on `PATH`
2. `hmmratac` on `PATH`
3. `$CAME_HMMRATAC_JAR`
4. `--hmmratac_jar`
5. local jar names such as `HMMRATAC.jar`, `hmmratac.jar`, `tools/HMMRATAC.jar`, `environment/tools/HMMRATAC.jar`, or `environment/HMMRATAC.jar`

Stage 24 production ATAC real mode does not use HMMRATAC. Stub mode does not require HMMRATAC.

## Limitations

Stage 6 does not perform orthology projection, regulatory architecture analysis, phenotype-omics association, or candidate ranking. The fallback differential engine is intended for smoke tests and small checks, not as a replacement for DESeq2.
