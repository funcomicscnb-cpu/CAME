# CAME Stage 5 Bulk Omics

Stage 5 adds the first generic bulk omics workflow layer for CAME. It defines metadata-aware RNA-seq and ATAC-seq interfaces, deterministic stub outputs for tests, and stable count matrix contracts for later differential analysis stages.

This stage remains phenotype-agnostic. It does not implement phenotype-omics association, regulatory architecture comparisons, orthology projection, or DESeq2 contrasts.

## Modes

`--omics_stub true` is the default. Stub mode does not require real FASTQ files, reference genomes, indexes, or bioinformatics executables. It creates small deterministic placeholder QC, alignment, peak, count, summary, and MultiQC-style files.

`--omics_stub false` enables real-mode interfaces. Real mode checks required executables before each process and fails clearly if tools or required reference assets are unavailable. CAME does not install FastQC, STAR, featureCounts, BWA, samtools, HMMRATAC, bedtools, or MultiQC.

## Inputs

Required for `--run_stage bulk_omics`:

- `--omics_samplesheet`
- `--reference_manifest`

Useful parameters:

- `--omics_types rnaseq,atacseq`
- `--omics_stub true|false`
- `--outdir results`

Required omics columns:

`sample_id`, `species`, `individual_id`, `replicate_id`, `omics_type`, `condition`, `timepoint`, `reference_id`, `fastq_1`, `read_layout`

For paired-end rows, `fastq_2` is also required. `read_layout` values are normalized to `paired_end` or `single_end`.

Required reference columns:

`reference_id`, `species`, `genome_fasta`

Real-mode RNA-seq also requires `gtf` and `star_index`. Real-mode ATAC-seq also requires `bwa_index` and `chrom_sizes`.

## Workflow

```bash
nextflow run . \
  --run_stage bulk_omics \
  --omics_samplesheet assets/example_samplesheets/omics_samplesheet.csv \
  --reference_manifest assets/example_samplesheets/reference_manifest.tsv \
  --omics_stub true \
  --omics_types rnaseq,atacseq
```

The workflow prepares joined manifests, runs RNA-seq and ATAC-seq interfaces, creates a MultiQC-style report, and summarizes expected outputs.

## Outputs

Prepared inputs:

- `results/omics/input/omics_manifest_prepared.tsv`
- `results/omics/input/rnaseq_manifest.tsv`
- `results/omics/input/atacseq_manifest.tsv`
- `results/omics/input/omics_input_warnings.tsv`

RNA-seq:

- `results/rnaseq/qc/fastqc/`
- `results/rnaseq/bam/`
- `results/rnaseq/counts/gene_counts.tsv`
- `results/rnaseq/logs/`
- `results/rnaseq/summary/rnaseq_summary.tsv`

RNA count table columns are:

`feature_id`, `feature_type`, `annotation_id`, followed by sample IDs.

ATAC-seq:

- `results/atacseq/qc/fastqc/`
- `results/atacseq/bam/`
- `results/atacseq/peaks/`
- `results/atacseq/counts/re_counts.tsv`
- `results/atacseq/logs/`
- `results/atacseq/summary/atacseq_summary.tsv`

ATAC count table columns are:

`feature_id`, `feature_type`, `chrom`, `start`, `end`, followed by sample IDs.

Shared reports:

- `results/omics/qc/multiqc/`
- `results/omics/summary/omics_run_summary.tsv`
- `results/omics/summary/omics_outputs_manifest.tsv`

## Later Stages

Stage 6 and later workflows should consume the raw count matrices and prepared manifests. Stage 5 does not normalize counts, test differential abundance, or join omics counts to phenotype-response outputs.

## Common Failures

| failure | fix |
| --- | --- |
| Unsupported requested `omics_type` | Use `rnaseq`, `atacseq`, or omit unsupported modalities from `--omics_types`. |
| Unknown `reference_id` | Add the reference to `reference_manifest.tsv` or fix the sample row. |
| Paired-end sample missing `fastq_2` | Add `fastq_2` or set `read_layout` to a valid single-end value. |
| Real-mode FASTQ path missing | Provide existing FASTQ files or run with `--omics_stub true`. |
| Real-mode reference asset missing | Fill and create the required reference path for the requested assay. |
| Real-mode executable missing | Install the tool externally and make it available on `PATH`. |
