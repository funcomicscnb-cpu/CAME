# Stage 23 Real-Mode Requirements

Stage 23 adds a real-mode contract layer for CAME. It defines the metadata, reference, validation, and provenance expectations that production real-mode workflows must satisfy later. It does not add production RNA-seq, ATAC-seq, WGS, WES, ChIP-seq, orthology, coordinate-projection, or regulatory-element-to-gene workflows.

## Purpose

The contract layer answers one question before expensive analysis starts: are the declared samples and references complete enough to run real biological data reproducibly?

Stage 23 covers:

- real-mode reference manifest documentation and schema;
- real-mode sample metadata documentation and schema;
- command-line validators that emit deterministic TSV reports;
- optional Nextflow validation when explicitly enabled;
- placeholder example files that do not require referenced paths to exist.

Existing Stage 1-22 metadata contracts remain valid. The legacy `reference_manifest.tsv` columns such as `genome_fasta`, `gtf`, `bwa_index`, and `source` are preserved for compatibility.

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

When `--enable_real_mode_validation false`, the workflow keeps the Stage 1-22 behavior. When `true` with `--run_stage validation`, `--reference_manifest` and `--real_mode_metadata` are required and both reports are published under `results/validation/`.

Stage 26 adds a separate reference-quality stage:

```bash
nextflow run . \
  --run_stage reference_quality \
  --reference_manifest assets/test_data/reference_quality/reference_manifest.tsv \
  --outdir results \
  --check_paths false
```

For real-mode `bulk_omics`, `--enable_real_mode_validation true` runs Stage 23 metadata/reference validation and then the Stage 26 reference-quality preflight before RNA/ATAC work. Stub mode is not gated by Stage 26.

## Failure Semantics

Validator reports use:

```tsv
severity	source	field	row	message
```

`ERROR` records fail the command. `WARNING` records document risks but do not fail validation. Placeholder paths are accepted by default; reference path existence is checked only when `bin/validate_reference_manifest.py --check-paths` is provided.

Reference manifest errors include missing required real-mode columns or values, duplicate `reference_id`, conflicting assemblies for the same species, and invalid enum values. Reference warnings include missing recommended assets, missing BUSCO metadata, and missing assay-relevant indexes for declared RNA, ATAC, WGS, or WES use.

Metadata errors include duplicate `sample_id`, unknown assay, read-layout/FASTQ contradictions, missing RNA `strandedness`, missing ChIP `antibody`, missing WES `target_bed`, unresolved `reference_id`, and species/reference mismatches. Metadata warnings include low replicate counts, ATAC single-end libraries, missing `batch`, unknown `platform`, missing `read_length`, mixed seqname styles, and species naming inconsistencies.

## Tool Defaults

Stage 23 documents expected defaults; it does not run these tools.

Current scaffolds still reference STAR plus featureCounts for RNA-seq and BWA plus HMMRATAC-related ATAC scaffolding where those interfaces already exist.

The Stage 24 ATAC production default is Bowtie2 for alignment and MACS3 for peak calling. Future WGS/WES production defaults are expected to use BWA-MEM2 or a documented equivalent aligner with variant-calling tools such as GATK. Future RNA production work may add Salmon and tximport interfaces, but those are not implemented in Stage 23.

## Provenance Expectations

Stage 23 provenance is documentation-only. Future real-mode runs should preserve at least:

- exact reference IDs and assembly accessions;
- assembly report paths and annotation releases;
- aligner, quantifier, peak caller, and variant caller versions;
- command-line parameters and container or environment identity;
- checksum or content-addressed identifiers for FASTQ and reference assets;
- sample, library, run, and batch identifiers.

The existing final-report provenance already captures partial workflow context such as CAME version, git status when available, selected tool versions, output directory, and parameter snapshots.

## Stage 24 Boundary

Stage 23 is complete when contracts, examples, validators, schemas, and fast tests pass. It intentionally does not implement Bowtie2, MACS3, Salmon, tximport, BWA-MEM2, GATK, BUSCO, RepeatMasker, GenMap, production orthology, coordinate projection, or production regulatory-element-to-gene workflows.

The recommended Stage 24 is production implementation behind these contracts, starting with real-mode execution paths that consume the Stage 23 manifests without changing their required fields.

## Stage 24 Implementation Status

Stage 24 now implements the first production-oriented real-mode core workflow for baseline bulk RNA-seq and ATAC-seq:

- RNA uses STAR plus featureCounts.
- ATAC uses Bowtie2 plus MACS3.
- STAR and Bowtie2 indexes are reused when present or built under `--reference_cache_dir` when feasible.
- Existing downstream count contracts are preserved through `results/rnaseq/counts/gene_counts.tsv` and `results/atacseq/counts/re_counts.tsv`.

This does not change the Stage 23 contract boundary above. WGS production, CNV/SV, TOBIAS, HMMRATAC production, ChIP production, HAL liftOver, contact RE linking, and OU models remain out of scope.

## Stage 26 Reference Quality Status

Stage 26 validates reference readiness for real-mode runs:

- declared assay assets for RNA, ATAC, and optional WGS reference checks;
- FASTA and FAI sequence-name consistency;
- FASTA and GTF/GFF3 sequence-name overlap;
- assembly-report or alias-map parsing;
- BUSCO completeness metadata thresholds;
- missing recommended repeat-mask, mappability, blacklist, and BUSCO metadata.

Stage 26 does not run BUSCO, RepeatMasker, GenMap, WGS production, CNV/SV, ChIP, TOBIAS, HMMRATAC production, HAL liftOver, or OU models. It is a preflight validation layer, not a production reference-preparation pipeline.
