# ATAC Real Mode

CAME ATAC real mode runs a per-sample ATAC-seq baseline while preserving the downstream regulatory-element count contract.

Implemented backend and peak caller:

- `--atac_backend bowtie2`
- `--peak_caller macs3`

## Execution Graph

ATAC real mode is decomposed into:

1. `ATAC_SPLIT_MANIFEST`
2. `ATAC_BOWTIE2_INDEX`, one per reference
3. `ATAC_FASTQC_SAMPLE`, one per sample
4. `ATAC_BOWTIE2_ALIGN_SAMPLE`, one per sample
5. `ATAC_SAMTOOLS_FILTER_SAMPLE`, one per sample
6. `ATAC_MACS3_PEAKS_SAMPLE`, one per sample
7. `ATAC_CONSENSUS_PEAKS`
8. `ATAC_PEAK_COUNTS`
9. `ATAC_REAL_AGGREGATE`

Internal files use safe `sample_key` names. Final count matrix columns use original `sample_id` values.

## Inputs

Use real-mode metadata rows with `assay=atac`. Required fields include:

`sample_id`, `species`, `individual_id`, `biological_replicate`, `assay`, `condition`, `read_layout`, `fastq_1`, and `reference_id`.

Paired-end ATAC is strongly preferred. Single-end ATAC is allowed by default with an explicit warning; set `--real_require_paired_atac true` to make single-end ATAC fail during input preparation.

Reference rows must provide FASTA through `fasta` or `genome_fasta`. `bowtie2_index` is reused when present; otherwise an index is built under `--reference_cache_dir`. `chrom_sizes` helps MACS3 genome-size selection. `mitochondrial_name` enables mitochondrial read and fraction metrics; if it is absent or not found in idxstats, mitochondrial metrics are marked unavailable with a warning. Optional `tss_bed` enables TSS coverage enrichment in `atac_qc.tsv`.

Input preparation fails if normalized filesystem keys for samples or references collide.

## Outputs

The downstream count contract remains:

```text
feature_id	feature_type	chrom	start	end	<sample_id>...
```

Primary outputs are:

- `results/atacseq/counts/re_counts.tsv`
- `results/atacseq/counts/peak_counts.tsv`
- `results/atacseq/counts/peak_consensus.bed`
- `results/atacseq/counts/bedtools/`
- `results/atacseq/peaks/*_peaks.narrowPeak`
- `results/atacseq/bam/*.bam`
- `results/atacseq/bam/*.bam.bai`
- `results/atacseq/logs/bowtie2/`
- `results/atacseq/logs/samtools/`
- `results/atacseq/logs/macs3/`
- `results/atacseq/qc/atac_qc.tsv`
- `results/atacseq/qc/library_complexity.tsv`
- `results/atacseq/qc/atac_qc_warnings.tsv`
- `results/atacseq/summary/atacseq_summary.tsv`
- `results/atacseq/validation/atac_real_validation.tsv`

## QC Metrics

`atac_qc.tsv` includes per-sample metadata plus:

- BAM and BAI existence checks;
- total reads and mapped reads;
- mapping rate;
- mitochondrial reads and fraction when `mitochondrial_name` can be matched;
- usable reads from filtered BAM metrics;
- duplicate proxy metrics when samtools stats exposes them;
- peak count;
- reads in peaks from bedtools count output;
- FRiP when usable reads and reads-in-peaks are both available;
- `tss_reads` and `tss_enrichment` when `tss_bed` is supplied;
- read layout and single-end warning;
- paired-end fragment mean and standard deviation when samtools stats exposes them;
- status and warning text.

`library_complexity.tsv` is written when duplicate proxy or complexity-related metrics exist. `nrf`, `pbc1`, and `pbc2` are derived from filtered BAM position-level duplicate complexity output; `pbc2` remains blank when no two-read duplicate positions exist, because the metric denominator is zero.

`atac_qc_warnings.tsv` records single-end libraries, missing mitochondrial contig metadata, unavailable metrics, low usable reads, high mitochondrial fraction, missing `tss_bed`, replicate-concordance status, and bedtools-merge consensus peak limitations.

`--atac_replicate_concordance none|idr` defaults to `none`. `idr` records an explicit replicate-concordance request and checks whether any species/condition/timepoint/reference group has at least two biological replicates, but CAME v0.1 still treats consensus peaks as exploratory unless external IDR results are supplied outside this workflow.

Blank numeric fields mean unavailable, not zero.

## Resource Tuning

ATAC uses these labels:

- `process_bowtie2_align`
- `process_peak_calling`
- `process_counting`
- `process_medium`
- `process_low`

Tune these labels for mammalian genomes, read depth, peak density, executor type, and local scratch behavior.

## Troubleshooting

Missing Bowtie2, bowtie2-build, MACS3, samtools, FastQC, or bedtools fails with an actionable message. Validation fails if all MACS3 peak files are empty, consensus peaks are malformed or empty, BAMs are empty, BAM indexes are missing, or counts are non-integer.

High mitochondrial fraction, low usable reads, unavailable mitochondrial contig metrics, missing TSS BED, and single-end ATAC are warnings. Fragment periodicity modeling, TOBIAS, production HMMRATAC, and internal IDR execution are not implemented in CAME.

## CAME Fixtures

Tiny paired ATAC FASTQs and a matching synthetic reference are available under `assets/test_data/real_mode_fixtures/`. Use `bash tests/test_real_mode_fixtures.sh --soft` to validate fixture contracts and, when Bowtie2, MACS3, samtools, bedtools, FastQC, and MultiQC are installed, run the tiny ATAC real-mode path.

These outputs test contract behavior only. They are not ATAC-seq peak-quality or regulatory-biology benchmarks. Optional ENCODE-derived validation should be curated manually and kept out of default CI.
