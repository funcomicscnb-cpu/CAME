# Reference Quality

Stage 26 adds a lightweight reference-quality validation layer for real-mode CAME runs. It checks whether declared reference assets are internally consistent before expensive RNA-seq, ATAC-seq, or optional WGS work starts.

This stage validates readiness. It does not build references, run BUSCO, run RepeatMasker, run GenMap, certify a reference for production, or run WGS variant calling.

## Why This Matters

For non-model mammals, reference quality is often the limiting factor. A high-quality assay workflow can still produce misleading counts or peaks if the FASTA, FAI, annotation, assembly report, indexes, mitochondrial naming, repeat masks, and mappability assets do not describe the same assembly and sequence naming convention.

The most common failure is a sequence-name mismatch, such as FASTA names `1` and `MT` with annotations using `chr1` and `chrM`. Stage 26 detects these cases and reports a direct alias-map or normalization fix instead of letting the mismatch surface later as empty counts or missing QC metrics.

## Running

Standalone reference-quality validation:

```bash
nextflow run . \
  --run_stage reference_quality \
  --reference_manifest assets/test_data/reference_quality/reference_manifest.tsv \
  --outdir results \
  --check_paths false
```

Strict local-path and content validation:

```bash
nextflow run . \
  --run_stage reference_quality \
  --reference_manifest path/to/reference_manifest.tsv \
  --outdir results \
  --check_paths true \
  --reference_quality_strict true
```

When `--enable_real_mode_validation true` and `--omics_mode real` are used with `--run_stage bulk_omics`, Stage 26 runs as an optional preflight after the Stage 23 metadata/reference manifest gate and before RNA/ATAC work. The same validation gate runs for `--run_stage wgs_variants --wgs_mode real`, using `--reference_quality_assay wgs`.

Stub mode does not run the reference-quality preflight.

## Required And Recommended Assets

Stage 26 keeps Stage 23 manifest semantics unchanged. It uses existing columns first and accepts common aliases:

- FASTA: `fasta`, then `genome_fasta`
- annotation: `annotation_file`, `annotation_gtf`, `annotation_gff3`, then `gtf`
- Bowtie2 index: `bowtie2_index`, then `bowtie2_index_prefix`
- BWA index: `bwa_index`, then `bwa_index_prefix`
- BUSCO score: `busco_complete`, then `busco_score`
- repeat mask: `repeatmasker_bed`, then `repeatmask_bed`

Required by assay:

- RNA: `fasta`, `fai`, and GTF/GFF3 annotation. `star_index` is optional when FASTA plus annotation are buildable.
- ATAC: `fasta` and `fai`. `bowtie2_index` is optional when FASTA is buildable.
- WGS reference checks: `fasta`, `fai`, `dict`, and either `bwa_index`/`bwa_index_prefix` or buildable FASTA. These checks support Stage 27 WGS SNP/indel calling but do not perform variant calling themselves.

Recommended assets warn but do not fail by themselves:

- `assembly_report`
- `repeatmasker_bed` or `repeatmask_bed`
- `mappability_bed`
- `busco_lineage`
- `busco_complete` or `busco_score`
- `blacklist_bed`

## Sequence-Name Concordance

Stage 26 checks:

- FASTA names against FAI names;
- FASTA names against GTF/GFF3 seqnames;
- annotation seqnames against assembly-report or alias-map names when available.

FASTA/FAI mismatches are severe because indexes and FASTA no longer describe the same sequence set. FASTA/annotation zero-overlap is severe because RNA counts or feature-level interpretation can silently collapse. Partial overlap is a warning in non-strict mode and an error in strict mode when overlap is too low.

Assembly reports can be NCBI-style reports or simple alias maps with `sequence_name` and optional `ucsc_style_name`, `genbank_accession`, and `refseq_accession` columns.

## BUSCO Policy

If BUSCO completeness metadata is declared:

- below 90: warning;
- below 80: strong warning;
- below 70: error only with `--reference_quality_strict true` and without `--allow_low_quality_reference true`.

The thresholds are guardrails for review, not a universal biological certification policy.

## Outputs

Outputs are written under `results/reference_quality/`:

- `reference_asset_validation.tsv`
- `reference_asset_warnings.tsv`
- `reference_asset_summary.tsv`
- `seqname_alias_map.tsv`
- `assembly_report_warnings.tsv`
- `seqname_concordance.tsv`
- `seqname_concordance_warnings.tsv`
- `reference_quality_summary.tsv`
- `reference_quality_manifest.tsv`

Status values are `OK`, `WARNING`, `ERROR`, `SKIPPED`, or `NOT_DECLARED`.

## Examples Of Fixes

If FASTA uses `1` but GTF uses `chr1`, provide an assembly report or alias map that declares both names, then normalize the annotation or FASTA/index set to one convention before real-mode execution.

If FAI names differ from FASTA headers, regenerate the FAI from the exact FASTA used by the manifest.

If BUSCO is low, review assembly lineage choice, assembly version, and annotation provenance before deciding whether `--allow_low_quality_reference true` is appropriate.

## Relationship To Earlier Stages

Stage 23 validates manifest and metadata schema. Stage 24/25 run baseline RNA/ATAC real-mode workflows. Stage 27 runs the optional WGS SNP/indel baseline. Stage 26 sits before those real-mode workflows when explicitly enabled: it checks reference content consistency and readiness without changing sample metadata contracts or downstream RNA/ATAC/WGS output paths.

## Stage 28 Fixtures

The Stage 28 fixture reference under `assets/test_data/real_mode_fixtures/tiny_reference/` includes a tiny FASTA, matching FAI, sequence dictionary, GTF, GFF3, assembly report, alias map, chrom sizes, and small BED helper files. It is designed so `--run_stage reference_quality --check_paths true` can validate reference contracts without downloading public data.

The fixture reference is synthetic. A passing reference-quality fixture test means the CAME validators accept the declared assets and seqname contracts; it does not certify assembly or annotation quality for production analysis.
