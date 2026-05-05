# CAME Real-Mode Requirements

CAME defines the metadata, reference, validation, and provenance expectations required for real-mode workflows. This document focuses on contracts and validation behavior, not on additional biological analysis methods.

## Purpose

The contract layer answers one question before expensive analysis starts: are the declared samples and references complete enough to run real biological data reproducibly?

The real-mode contract covers:

- real-mode reference manifest documentation and schema;
- real-mode sample metadata documentation and schema;
- command-line validators that emit deterministic TSV reports;
- optional Nextflow validation when explicitly enabled;
- placeholder example files that do not require referenced paths to exist.

Existing metadata contracts remain valid. The legacy `reference_manifest.tsv` columns such as `genome_fasta`, `gtf`, `bwa_index`, and `source` are preserved for compatibility.

## Enablement

Standalone validation:

```bash
python3 bin/validate_reference_manifest.py \
  --manifest assets/example_samplesheets/reference_manifest.tsv \
  --assays rna,atac \
  --report results/validation/reference_manifest_real_mode_validation_report.tsv

python3 bin/validate_real_mode_metadata.py \
  --metadata assets/example_samplesheets/real_mode_metadata_example.tsv \
  --reference_manifest assets/example_samplesheets/reference_manifest.tsv \
  --report results/validation/real_mode_metadata_validation_report.tsv
```

Optional Nextflow validation-only run:

```bash
nextflow run . \
  --run_stage validation \
  --enable_real_mode_validation true \
  --reference_manifest assets/example_samplesheets/reference_manifest.tsv \
  --real_mode_metadata assets/example_samplesheets/real_mode_metadata_example.tsv \
  --outdir results
```

When `--enable_real_mode_validation false`, the workflow uses the standard metadata checks. When `true` with `--run_stage validation`, `--reference_manifest` and `--real_mode_metadata` are required and both reports are published under `results/validation/`.

Reference-quality validation can also be run directly:

```bash
nextflow run . \
  --run_stage reference_quality \
  --reference_manifest assets/test_data/reference_quality/reference_manifest.tsv \
  --outdir results \
  --check_paths false
```

For real-mode `bulk_omics`, `--enable_real_mode_validation true` runs metadata/reference validation and then the reference-quality preflight before RNA/ATAC work. Stub mode is not gated by reference-quality validation.

## Failure Semantics

Validator reports use:

```tsv
severity	source	field	row	message
```

`ERROR` records fail the command. `WARNING` records document risks but do not fail validation. Placeholder paths are accepted by default; reference path existence is checked only when `bin/validate_reference_manifest.py --check-paths` is provided.

Reference manifest errors include missing required real-mode columns or values, duplicate `reference_id`, conflicting assemblies for the same species, and invalid enum values. Reference warnings include missing recommended assets, missing BUSCO metadata, missing ATAC `tss_bed`, and missing assay-relevant indexes for declared RNA, ATAC, WGS, or WES use.

Metadata errors include duplicate `sample_id`, unknown assay, read-layout/FASTQ contradictions, missing RNA `strandedness`, missing ChIP `antibody`, missing WES `target_bed`, unresolved `reference_id`, and species/reference mismatches. Metadata warnings include low replicate counts, ATAC single-end libraries, missing `batch`, unknown `platform`, missing `read_length`, mixed seqname styles, and species naming inconsistencies.

## Tool Defaults

This page documents expected defaults; it does not run these tools.

Current compatibility interfaces still reference STAR plus featureCounts for RNA-seq and BWA plus HMMRATAC-related ATAC paths where those interfaces already exist.

The ATAC production default is Bowtie2 for alignment and MACS3 for peak calling. WGS/WES production defaults are expected to use BWA-MEM2 or a documented equivalent aligner with variant-calling tools such as GATK. Salmon and tximport interfaces are not implemented in this release.

## Provenance Expectations

Real-mode provenance should preserve at least:

- exact reference IDs and assembly accessions;
- assembly report paths and annotation releases;
- aligner, quantifier, peak caller, and variant caller versions;
- command-line parameters and container or environment identity;
- checksum or content-addressed identifiers for FASTQ and reference assets;
- sample, library, run, and batch identifiers.

The existing final-report provenance already captures partial workflow context such as CAME version, git status when available, selected tool versions, output directory, and parameter snapshots.

## Scope

The contract layer is limited to examples, validators, schemas, and fast checks. It does not by itself implement Bowtie2, MACS3, Salmon, tximport, BWA-MEM2, GATK, BUSCO, RepeatMasker, GenMap, production orthology, coordinate projection, or production regulatory-element-to-gene workflows.

Real-mode execution paths consume these manifests without changing their required fields.

## Implementation Status

CAME implements a production-oriented real-mode core workflow for baseline bulk RNA-seq and ATAC-seq:

- RNA uses STAR plus featureCounts.
- ATAC uses Bowtie2 plus MACS3.
- STAR and Bowtie2 indexes are reused when present or built under `--reference_cache_dir` when feasible.
- Existing downstream count contracts are preserved through `results/rnaseq/counts/gene_counts.tsv` and `results/atacseq/counts/re_counts.tsv`.

WGS production, CNV/SV, TOBIAS, HMMRATAC production, ChIP production, HAL liftOver, contact RE linking, and OU models remain out of scope.

## Reference Quality Status

Reference-quality validation checks readiness for real-mode runs:

- declared assay assets for RNA, ATAC, and optional WGS reference checks;
- FASTA and FAI sequence-name consistency;
- FASTA and GTF/GFF3 sequence-name overlap;
- assembly-report or alias-map parsing;
- BUSCO completeness metadata thresholds;
- missing recommended repeat-mask, mappability, blacklist, ATAC TSS BED, and BUSCO metadata.

CAME does not run BUSCO, RepeatMasker, GenMap, WGS production, CNV/SV, ChIP, TOBIAS, HMMRATAC production, HAL liftOver, or OU models. It is a preflight validation layer, not a production reference-preparation pipeline.
