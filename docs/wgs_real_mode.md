# WGS Real Mode

CAME provides an optional short-read WGS small-variant path. It is a production-oriented baseline for per-sample germline SNP/indel discovery, not a complete production WGS platform.

Implemented scope:

- BWA-MEM2 alignment for short-read DNA libraries;
- samtools duplicate marking where feasible, sorting, indexing, flagstat, stats, and coverage summaries;
- GATK HaplotypeCaller per-sample SNP/indel calling;
- optional GATK hard filtering through `--wgs_filtering_mode hard_filter`;
- deterministic stub contracts for routing and output validation.

Out of scope:

- CNV and structural-variant discovery;
- DeepVariant;
- WES capture production support;
- BQSR execution;
- cohort joint genotyping or truth-set benchmarking.

## Running

Stub mode is the default:

```bash
nextflow run . \
  --run_stage wgs_variants \
  --wgs_samplesheet assets/example_samplesheets/wgs_samplesheet.csv \
  --reference_manifest assets/example_samplesheets/reference_manifest.tsv \
  --wgs_mode stub \
  --outdir results
```

Real mode:

```bash
nextflow run . \
  --run_stage wgs_variants \
  --wgs_samplesheet path/to/wgs_samplesheet.csv \
  --reference_manifest path/to/reference_manifest.tsv \
  --wgs_mode real \
  --outdir results
```

`wgs_variants` is not part of `--run_stage all`.

`--wgs_calling_mode` is fixed to `per_sample` in v0.1. Values such as `joint` or `cohort` fail at workflow start because GenomicsDBImport/GenotypeGVCFs joint genotyping is not implemented.

## Inputs

The WGS samplesheet uses the real-mode metadata model and requires WGS rows with `assay=wgs`. Required fields for WGS input preparation are:

`sample_id`, `study_id`, `species`, `individual_id`, `biological_replicate`, `assay`, `read_layout`, `fastq_1`, `reference_id`, `platform`, and `library_protocol`.

Paired-end rows require `fastq_2`. WES rows fail with a clear unsupported-scope error.

Real WGS references require:

- `fasta`
- `fai`
- `dict`
- `bwa_index` or `bwa_index_prefix`, unless FASTA is available for index building

Recommended WGS reference fields:

- `known_sites_vcf`
- `repeatmask_bed` or `repeatmasker_bed`
- `mappability_bed`

## Known-Sites And BQSR Policy

CAME does not run BQSR, even when `known_sites_vcf` is present. If known sites are absent and `--require_known_sites false`, input preparation emits:

```text
WARNING: known_sites_vcf absent; BQSR skipped and hard-filtering/no-BQSR fallback used.
```

If `--require_known_sites true`, missing known sites fail input preparation. If `--allow_no_bqsr false`, real WGS fails because CAME has no BQSR execution path.

## Outputs

Primary outputs are written under `results/wgs/`:

- `bam/*.bam`
- `bam/*.bam.bai`
- `variants/*.vcf.gz`
- `variants/*.vcf.gz.tbi`
- `qc/wgs_alignment_qc.tsv`
- `qc/variant_qc.tsv`
- `summary/wgs_variant_summary.tsv`
- `summary/wgs_outputs_manifest.tsv`
- `validation/wgs_outputs_validation.tsv`

Required QC fields include:

`sample_id`, `species`, `reference_id`, `mapped_reads`, `duplicate_rate`, `mean_coverage`, `breadth_10x`, `insert_size_median`, `n_variants`, `n_snps`, `n_indels`, `bqsr_applied`, `calling_mode`, `joint_genotyping`, and `mode`.

Unavailable metrics are recorded as `NA` and paired with warnings. CAME records `bqsr_applied=false`, `calling_mode=per_sample`, and `joint_genotyping=false` in `variant_qc.tsv` and `wgs_variant_summary.tsv`. Stub outputs are marked `mode=stub` and are contract fixtures only.

## Non-Model Mammal Limits

For non-model mammals, reference quality is often the limiting factor. Use reference-quality validation with `--reference_quality_assay wgs` or `--enable_real_mode_validation true` before real WGS when local reference assets are available. Missing masks and mappability tracks warn because they affect interpretability, but CAME does not generate species-specific blacklists or empirical problematic-site masks.

## CAME Fixtures

Tiny paired WGS FASTQs and a matching synthetic reference are available under `assets/test_data/real_mode_fixtures/`. Use `bash tests/test_real_mode_fixtures.sh --soft` to validate fixture contracts and, when BWA-MEM2, samtools, GATK, and FastQC are installed, run the tiny WGS real-mode path.

These outputs test the WGS SNP/indel contract only. They are not variant-calling accuracy benchmarks, do not validate BQSR, and do not add WGS to `--run_stage all`. Public WGS fixtures need accession-level manual vetting before use.
