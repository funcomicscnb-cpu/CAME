# Stage 25 Real-Mode Workflows

Stage 25 hardens the RNA-seq and ATAC-seq real-mode baseline that was introduced in Stage 24. It is a scale-out and QC hardening stage, not a fully production-certified non-model mammal multi-omics platform.

Stage 26 adds an optional reference-quality preflight for real-mode references. It validates declared assets and sequence-name concordance before expensive RNA/ATAC work when explicitly enabled.

Stage 27 adds an optional WGS SNP/indel baseline through `--run_stage wgs_variants`. It is outside `--run_stage all` and does not change RNA/ATAC behavior.

Supported production-oriented real-mode scope:

- bulk RNA-seq using STAR, samtools, and featureCounts;
- ATAC-seq using Bowtie2, samtools, MACS3, and bedtools;
- per-sample process decomposition for expensive work;
- deterministic downstream contracts for RNA and ATAC count matrices;
- richer QC tables, warnings tables, and output validation.
- optional short-read WGS SNP/indel calling with BWA-MEM2, samtools, and GATK HaplotypeCaller.

Out of scope: CNV/SV, DeepVariant, WES production support, ChIP production, TOBIAS, HMMRATAC production, HAL liftOver, OU models, contact-based regulatory-element linking, and replicate-aware peak policies.

## Running Real Mode

Use Stage 23 real-mode metadata when possible:

```bash
nextflow run . \
  --run_stage bulk_omics \
  --omics_mode real \
  --omics_types rnaseq,atacseq \
  --real_mode_metadata path/to/real_mode_metadata.tsv \
  --reference_manifest path/to/reference_manifest.tsv \
  --outdir results
```

Legacy `--omics_samplesheet` remains accepted as a compatibility fallback, but `--real_mode_metadata` is preferred because it carries assay, library, run, and reference contracts more explicitly.

`--omics_stub true` remains the default. `--omics_stub false` also selects real mode unless `--omics_mode stub` is explicitly supplied.

Optional real-mode preflight:

```bash
nextflow run . \
  --run_stage bulk_omics \
  --omics_mode real \
  --enable_real_mode_validation true \
  --real_mode_metadata path/to/real_mode_metadata.tsv \
  --reference_manifest path/to/reference_manifest.tsv \
  --check_paths false \
  --outdir results
```

This runs Stage 23 metadata/reference checks and Stage 26 reference-quality checks before RNA/ATAC work. It is not run for stub mode.

Optional WGS run:

```bash
nextflow run . \
  --run_stage wgs_variants \
  --wgs_samplesheet path/to/wgs_samplesheet.csv \
  --reference_manifest path/to/reference_manifest.tsv \
  --wgs_mode stub \
  --outdir results
```

Set `--wgs_mode real` only when BWA-MEM2, samtools, GATK, FastQC, FASTQ files, FASTA, FAI, and sequence dictionary assets are available.

## Per-Sample Decomposition

RNA real mode runs these units:

1. prepare and split the real-mode manifest;
2. build or reuse one STAR index per reference;
3. run one FastQC process per sample;
4. run one STAR alignment process per sample;
5. run one samtools sort, index, and QC process per sample;
6. run one featureCounts process per sample;
7. merge per-sample counts into `gene_counts.tsv`;
8. collect QC, summary, warnings, and validation outputs.

ATAC real mode runs these units:

1. prepare and split the real-mode manifest;
2. build or reuse one Bowtie2 index per reference;
3. run one FastQC process per sample;
4. run one Bowtie2 alignment process per sample;
5. run one samtools filter, sort, index, and QC process per sample;
6. run one MACS3 peak-calling process per sample;
7. build a consensus peak BED from per-sample peaks;
8. count reads over consensus peaks;
9. collect QC, summary, warnings, and validation outputs.

WGS real mode runs these units:

1. prepare and split the WGS manifest;
2. build or reuse one BWA-MEM2 index per reference;
3. run one FastQC process per sample;
4. run one BWA-MEM2 alignment process per sample;
5. run one samtools duplicate-mark/sort/index/QC process per sample;
6. run one GATK HaplotypeCaller process per sample;
7. run GATK hard filtering when requested;
8. collect QC, summary, warnings, and validation outputs.

Internal filenames use filesystem-safe `sample_key` and `reference_key` values. The original `sample_id` values remain in final count matrix headers. Input preparation fails if sanitized keys collide.

## Output Contracts

RNA downstream contract:

- `results/rnaseq/counts/gene_counts.tsv`
- header: `feature_id`, `feature_type`, `annotation_id`, then original sample IDs.

ATAC downstream contract:

- `results/atacseq/counts/re_counts.tsv`
- header: `feature_id`, `feature_type`, `chrom`, `start`, `end`, then original sample IDs.

Primary QC outputs:

- `results/rnaseq/qc/alignment_qc.tsv`
- `results/rnaseq/qc/featurecounts_summary.tsv`
- `results/rnaseq/qc/rna_qc_warnings.tsv`
- `results/atacseq/qc/atac_qc.tsv`
- `results/atacseq/qc/library_complexity.tsv`
- `results/atacseq/qc/atac_qc_warnings.tsv`

The real-mode branch still writes empty contract files for an unrequested assay so downstream orchestration can keep stable path expectations.

WGS output contract:

- `results/wgs/bam/*.bam`
- `results/wgs/bam/*.bam.bai`
- `results/wgs/variants/*.vcf.gz`
- `results/wgs/variants/*.vcf.gz.tbi`
- `results/wgs/qc/wgs_alignment_qc.tsv`
- `results/wgs/qc/variant_qc.tsv`
- `results/wgs/summary/wgs_variant_summary.tsv`
- `results/wgs/summary/wgs_outputs_manifest.tsv`

Stub WGS outputs are marked `mode=stub` and are not biological output.

## Resource Labels

`nextflow.config` defines these labels with conservative local defaults:

| Label | Default intent |
| --- | --- |
| `process_low` | lightweight manifest, FastQC, and helper steps |
| `process_medium` | samtools and aggregate steps |
| `process_high` | reserved for heavier generic steps |
| `process_star_index` | STAR genome index build or reuse |
| `process_star_align` | per-sample STAR alignment |
| `process_bowtie2_align` | per-sample Bowtie2 alignment |
| `process_bwa_mem2_index` | BWA-MEM2 index build or reuse |
| `process_bwa_mem2_align` | per-sample BWA-MEM2 alignment |
| `process_variant_calling` | GATK HaplotypeCaller and filtering |
| `process_peak_calling` | MACS3 peak calling and consensus peaks |
| `process_counting` | featureCounts and bedtools count steps |

These defaults are not universal mammalian-genome recommendations. Tune CPUs, memory, time, scratch, and executor settings for the reference assembly, annotation size, read depth, and local scheduler.

## Conda And Container Hooks

Profiles are available as clean hooks:

```bash
nextflow run . -profile conda ...
nextflow run . -profile docker ...
nextflow run . -profile apptainer ...
nextflow run . -profile singularity ...
```

Containers are not required by default for local stub-mode work. Docker, Apptainer, and Singularity profiles default to the CAME image `ghcr.io/funcomicscnb-cpu/came:<VERSION>`. Use `--container_image` to point at a locally approved image or Apptainer/Singularity artifact.

## Backend Status

RNA production support is `--rna_backend star`.

`--rna_backend salmon` is declared only as a future architecture hook. It fails clearly in this release:

```text
ERROR: Salmon backend is declared but not implemented in this release.
```

ATAC production support is `--atac_backend bowtie2` and `--peak_caller macs3`.

WGS production-oriented support is `--wgs_variant_mode haplotypecaller`. BQSR is not executed in Stage 27. Missing `known_sites_vcf` emits a no-BQSR warning unless `--require_known_sites true`. WGS QC and summary tables record `bqsr_applied=false`, `calling_mode=per_sample`, and `joint_genotyping=false`.

## QC Semantics

RNA QC includes total reads, uniquely mapped reads and fraction when STAR logs are available, multi-mapped reads and fraction, assigned reads from featureCounts summaries, assigned fraction, strandedness, mapping rate, status, and warning text. Missing STAR logs and low assignment are warnings, not crashes, when count contracts remain valid.

ATAC QC includes total and mapped reads, mapping rate, mitochondrial reads and fraction when a mitochondrial contig is known, duplicate proxy metrics when samtools stats exposes them, usable reads, peak count, reads in peaks, FRiP, read layout, single-end warnings, and paired-end fragment mean and standard deviation when available. Missing mitochondrial contig metadata produces an explicit warning and unavailable mitochondrial fields instead of a crash.

Warnings tables use explicit records for missing or unavailable metrics. Blank numeric cells mean the metric was unavailable, not zero.

## Reference Quality Preflight

Stage 26 writes reference-quality outputs under `results/reference_quality/`:

- `reference_asset_validation.tsv`
- `reference_asset_warnings.tsv`
- `reference_asset_summary.tsv`
- `seqname_alias_map.tsv`
- `assembly_report_warnings.tsv`
- `seqname_concordance.tsv`
- `seqname_concordance_warnings.tsv`
- `reference_quality_summary.tsv`
- `reference_quality_manifest.tsv`

Use `--run_stage reference_quality` to run it directly. Use `--check_paths true` only when the manifest paths should resolve locally; leave it false for placeholder manifests or documentation examples.

## Fixture Strategy

Stage 28 adds committed tiny fixtures under `assets/test_data/real_mode_fixtures/` plus generator and validator scripts. These fixtures are for contract testing only: they verify that manifests, tiny reference assets, paired FASTQs, optional real-mode execution paths, and output contracts fit together. They are not biological benchmarks and do not replace curated production validation.

Recommended local fixtures:

- tiny synthetic FASTA, GTF, FASTQ, metadata, and reference manifests generated locally;
- fake-tool fixtures for Nextflow routing, missing-tool behavior, stable output names, and contract validation;
- tiny real-tool fixtures only in environments where STAR, Bowtie2, MACS3, BWA-MEM2, GATK, samtools, bedtools, FastQC, featureCounts, and MultiQC are installed.

Optional external fixture paths:

- a small manually curated ENCODE ATAC subset for toolchain and peak-count behavior;
- a manually curated non-model mammal subset such as pig `GSE143288 / PRJNA597497`, with explicit provenance and no automatic large downloads.

WGS regular tests use deterministic stub fixtures, Stage 28 local fixtures, and contract validators. Real WGS fixtures should remain tiny, manually curated, and local; do not automatically download large public datasets in CI.

See [real_mode_fixture_strategy.md](real_mode_fixture_strategy.md) for external fixture curation policy.

## Failure Behavior

Real mode fails for missing required tools, unresolved references, missing FASTQ or reference paths, sanitized key collisions, empty BAMs, missing BAM indexes, empty RNA count matrices, non-integer counts, malformed BED intervals, and ATAC runs where all MACS3 peak files are empty.

Warnings are used for lower-confidence or missing quality signals such as single-end ATAC, missing STAR logs, missing mitochondrial contig metadata, low mapping rate, high mitochondrial fraction, and low usable or assigned reads.

## Current Limitations

Stage 25 improves routing, validation, and QC visibility, while Stage 27 adds only a narrow WGS SNP/indel baseline. These stages do not add advanced biological QC such as full TSS enrichment, fragment periodicity modeling, TOBIAS bias correction, HMMRATAC production, replicate-aware consensus peak policies, cohort genotyping, CNV/SV discovery, or DeepVariant.
