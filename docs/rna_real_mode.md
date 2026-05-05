# RNA Real Mode

CAME RNA real mode runs a per-sample bulk RNA-seq baseline while preserving the downstream count contract.

Implemented backend:

- `--rna_backend star`

Declared but not implemented:

- `--rna_backend salmon`

Requesting Salmon fails with:

```text
ERROR: Salmon backend is declared but not implemented in this release.
```

## Execution Graph

RNA real mode is decomposed into:

1. `RNA_SPLIT_MANIFEST`
2. `RNA_STAR_INDEX`, one per reference
3. `RNA_FASTQC_SAMPLE`, one per sample
4. `RNA_STAR_ALIGN_SAMPLE`, one per sample
5. `RNA_SAMTOOLS_QC_SAMPLE`, one per sample
6. `RNA_FEATURECOUNTS_SAMPLE`, one per sample
7. `RNA_REAL_AGGREGATE`, one aggregate merge, QC, summary, and validation step

The aggregate step merges per-sample featureCounts outputs into `gene_counts.tsv`. Internal files use safe `sample_key` names, but final matrix columns use original `sample_id` values.

## Inputs

Use real-mode metadata rows with `assay=rna`. Required fields include:

`sample_id`, `species`, `individual_id`, `biological_replicate`, `assay`, `condition`, `read_layout`, `fastq_1`, `reference_id`, and `strandedness`.

`read_layout` may be single-end or paired-end. Paired-end rows require `fastq_2`.

Reference rows must provide FASTA and annotation fields `fasta` and `annotation_file`, or the legacy aliases `genome_fasta` and `gtf`. `star_index` is reused when present; otherwise an index is built under `--reference_cache_dir`.

Input preparation fails if normalized filesystem keys for samples or references collide.

## Strandedness

`strandedness` is passed to featureCounts:

- `unstranded` or `unknown`: `-s 0`
- `forward`: `-s 1`
- `reverse`: `-s 2`

The selected strandedness is propagated into RNA QC output.

## Outputs

The downstream count contract is:

```text
feature_id	feature_type	annotation_id	<sample_id>...
```

Primary outputs are:

- `results/rnaseq/counts/gene_counts.tsv`
- `results/rnaseq/bam/*.bam`
- `results/rnaseq/bam/*.bam.bai`
- `results/rnaseq/logs/star/`
- `results/rnaseq/logs/samtools/`
- `results/rnaseq/logs/featurecounts/`
- `results/rnaseq/qc/alignment_qc.tsv`
- `results/rnaseq/qc/featurecounts_summary.tsv`
- `results/rnaseq/qc/rna_qc_warnings.tsv`
- `results/rnaseq/summary/rnaseq_summary.tsv`
- `results/rnaseq/validation/rna_real_validation.tsv`

## QC Metrics

`alignment_qc.tsv` includes per-sample metadata plus:

- BAM and BAI existence checks;
- total reads from STAR or samtools metrics when available;
- uniquely mapped reads and fraction from STAR `Log.final.out` when available;
- multi-mapped reads and fraction from STAR `Log.final.out` when available;
- mapping rate;
- assigned reads from featureCounts summaries;
- assigned fraction;
- strandedness;
- status and warning text.

`featurecounts_summary.tsv` is written when featureCounts summary records are available. `rna_qc_warnings.tsv` records missing STAR logs, low assignment, unavailable metrics, and validation-adjacent warnings explicitly.

Blank numeric fields mean unavailable, not zero.

## Resource Tuning

RNA uses these labels:

- `process_star_index`
- `process_star_align`
- `process_counting`
- `process_medium`
- `process_low`

Tune these labels for mammalian genomes. STAR indexing and alignment are usually the limiting RNA steps, especially with large assemblies and dense annotations.

## Troubleshooting

Missing STAR, featureCounts, samtools, or FastQC fails with an actionable message. Empty BAMs, missing BAM indexes, empty count matrices, and non-integer counts fail validation. Missing STAR logs and low assigned counts are warnings when the required count and BAM contracts are otherwise valid.

## CAME Fixtures

Tiny paired RNA FASTQs and a matching synthetic reference are available under `assets/test_data/real_mode_fixtures/`. Use `bash tests/test_real_mode_fixtures.sh --soft` to validate fixture contracts and, when STAR, featureCounts, samtools, FastQC, and MultiQC are installed, run the tiny RNA real-mode path.

These outputs test file contracts only. They are not RNA-seq biological benchmarks, and production RNA validation still requires curated real datasets, appropriate references, and an installed toolchain.
