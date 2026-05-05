# CAME Optional Reference Preparation

This optional scaffold interface defines metadata contracts, validation, stub-mode output files, and summary manifests that downstream comparative genomics workflows can consume.

This interface is optional. It is not part of the default v0.1 `--run_stage all` path, and it does not implement production BWA/GATK/CNV processing. Core CAME remains phenotype-agnostic; reference preparation is driven by samplesheets and manifests, not study-profile biology.

## Purpose

Reference preparation gives downstream analyses a stable place to represent:

- corrected or patched reference FASTA files
- high-confidence variant callsets
- problematic-site masks
- ultra-accurate sequencing exclusion masks
- confirmed CNV intervals
- warning and output manifests

The current implementation is intended to validate interfaces and produce deterministic stub outputs for testing.

## Command

```bash
nextflow run . \
  --run_stage reference_prepare \
  --wgs_samplesheet assets/example_samplesheets/wgs_samplesheet.csv \
  --reference_manifest assets/example_samplesheets/reference_manifest.tsv \
  --reference_prepare_config assets/example_samplesheets/reference_prepare_config.tsv \
  --reference_stub true
```

`--reference_stub true` is the default. `--run_stage all` does not require or run reference preparation.

## WGS Samplesheet

Default example: `assets/example_samplesheets/wgs_samplesheet.csv`

Required columns:

| column | description |
| --- | --- |
| `sample_id` | Unique WGS sample identifier. |
| `species` | Species identifier shared with the reference manifest. |
| `individual_id` | Individual or donor identifier. |
| `reference_id` | Reference identifier to resolve in `reference_manifest.tsv` and `reference_prepare_config.tsv`. |
| `fastq_1` | First FASTQ path or URI. In stub mode the path does not need to exist. |
| `read_layout` | `paired-end`, `paired_end`, `paired`, `pe`, `single-end`, `single_end`, `single`, or `se`. |

Optional columns:

`fastq_2`, `batch`, `platform`, `library_id`, `coverage_estimate`, `notes`

Paired-end records require both `fastq_1` and `fastq_2`. Single-end records require `fastq_1`; `fastq_2` is ignored with a warning.

## Reference Preparation Config

Default example: `assets/example_samplesheets/reference_prepare_config.tsv`

Required columns:

| column | description |
| --- | --- |
| `reference_id` | Reference identifier also present in `reference_manifest.tsv`. |
| `species` | Species identifier matching the reference manifest. |
| `masking_strategy` | Intended mask-handling strategy. |

Optional columns:

`known_repeats_bed`, `mappability_bed`, `problematic_sites_bed`, `cnv_regions_bed`, `retain_coverage_deviation_labels`, `notes`

Supported `masking_strategy` values are:

- `label_only`
- `mask_problematic`
- `exclude_for_mutation_calling`

## Input Preparation

`bin/prepare_reference_inputs.py` reads the WGS samplesheet, reference manifest, and reference preparation config. It validates required columns, `reference_id` resolution, species consistency, read layout, FASTQ field presence, and real-mode file existence when `--reference_stub false`.

Outputs:

- `results/reference/input/reference_prepare_manifest.tsv`
- `results/reference/input/reference_prepare_warnings.tsv`

## Stub Mode

Stub mode creates deterministic tiny files and does not call external bioinformatics tools. Outputs are generated per unique `species` and `reference_id` where practical:

- `results/reference/genomes/<species>.<reference_id>.corrected.fa`
- `results/reference/variants/<species>.<reference_id>.reliable_variants.vcf`
- `results/reference/masks/<species>.<reference_id>.problematic_sites.bed`
- `results/reference/masks/<species>.<reference_id>.nanoseq_exclusion_mask.bed`
- `results/reference/cnv/<species>.<reference_id>.confirmed_cnvs.bed`
- `results/reference/summary/reference_prepare_outputs.tsv`

These files are synthetic contract fixtures only. They are suitable for testing downstream wiring, not biological interpretation.

## Real Mode

`--reference_stub false` is intentionally conservative. The workflow validates that required files exist and includes placeholders for BWA mapping, GATK-style variant calling, problematic-site labeling, CNV integration, and corrected-reference output. If required tools or assets are absent, the workflow fails clearly.

The current interface does not silently emit fake real-mode outputs and does not install tools.

## Summary Outputs

`bin/summarize_reference_prepare.py` writes:

- `results/reference/summary/reference_prepare_summary.tsv`
- `results/reference/summary/reference_outputs_manifest.tsv`

The summary reports WGS sample count, reference count, species count, generated outputs, warnings, errors, and stub versus real mode.

## Downstream Use

WGS, mutation-rate, mask-aware variant, or ultra-accurate sequencing workflows should consume `reference_outputs_manifest.tsv` rather than hardcoding file names. Downstream workflows can select by `reference_id`, `species`, and `output_type` to find corrected FASTA, reliable VCF, mask BED, exclusion BED, and CNV BED outputs.

## Known Limitations

- Production BWA/GATK/CNV execution is not implemented in this workflow.
- Stub FASTA, VCF, BED, and CNV files are deterministic placeholders.
- Masking strategies define metadata intent only; they do not perform real sequence masking in stub mode.
- Real mode requires caller-provided tools and assets and will fail rather than fabricate outputs.
