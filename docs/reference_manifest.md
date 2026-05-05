# Real-Mode Reference Manifest

`reference_manifest.tsv` remains backward compatible with earlier metadata examples. Keep legacy columns such as `genome_fasta`, `gtf`, `transcript_fasta`, `star_index`, `bwa_index`, `chrom_sizes`, `annotation_version`, and `source`; add the real-mode columns alongside them.

## Required Real-Mode Columns

The validator requires one row per reference with:

`reference_id`, `species`, `species_name`, `assembly_name`, `assembly_accession`, `assembly_source`, `assembly_release`, `assembly_report`, `fasta`, `fai`, `annotation_file`, `annotation_format`, `annotation_source`, `annotation_release`, `seqname_style`, `mitochondrial_name`

`assembly_report` is required. A real-mode reference must be traceable to an assembly report or equivalent source report for reproducibility.

## Controlled Values

`assembly_source`: `NCBI`, `Ensembl`, `UCSC`, `Custom`

`annotation_format`: `gtf`, `gff3`, `bed`, `other`

`seqname_style`: `ncbi`, `ensembl`, `ucsc`, `custom`

## Legacy Compatibility Aliases

Legacy consumers read:

- `genome_fasta`: legacy alias for `fasta`;
- `gtf`: legacy RNA annotation path, usually the same file as `annotation_file` when `annotation_format=gtf`;
- `annotation_version`: legacy alias for `annotation_release`;
- `source`: legacy free-text source label;
- `bwa_index`: used as the WGS BWA-MEM2 index prefix when `bwa_index_prefix` is absent, and retained for legacy compatibility.

Do not remove these columns from shared examples until downstream tools have been migrated.

## Naming Guidance

Use stable underscore species tokens in `species`, such as `Mus_musculus`. Use the readable scientific name in `species_name`, such as `Mus musculus`.

Use reference IDs that are stable and concise, for example `mmus_ref`, `drer_ref`, or `mmus_grcm39_ensembl110`. The same `species` may appear in multiple rows only when the assembly is intentionally the same or the difference is documented through distinct reference IDs; conflicting assemblies for the same species fail CAME validation.

## Recommended Assets

The validator warns, but does not fail, when recommended assets are missing:

- `transcript_fasta`
- `star_index`
- `bwa_index`
- `bowtie2_index`
- `chrom_sizes`
- `blacklist_bed`
- `repeatmasker_bed`
- `mappability_bed`
- `busco_lineage`
- `busco_complete`

Assay declarations add targeted warnings. RNA expects `transcript_fasta` and `star_index`. ATAC expects `bowtie2_index`, `chrom_sizes`, `blacklist_bed`, and `mappability_bed`; ATAC real mode uses Bowtie2 plus MACS3. WGS expects `fasta`, `fai`, `dict`, and `bwa_index` or `bwa_index_prefix` unless the FASTA is available for BWA-MEM2 index building. WES production support is not implemented.

Paths are metadata by default. Use `--check-paths` only when the validator should require local path existence.

## Reference Quality

Reference-quality validation adds content-level checks without changing the manifest schema. It validates declared reference assets, parses assembly reports into sequence-name alias maps, and checks FASTA/FAI/annotation sequence-name concordance.

Accepted aliases:

- `annotation_gtf` or `annotation_gff3` may be used when `annotation_file` is not present.
- `bowtie2_index_prefix` is accepted as an alias for `bowtie2_index`.
- `bwa_index_prefix` is accepted as an alias for `bwa_index`.
- `busco_score` is accepted as an alias for `busco_complete`.
- `repeatmask_bed` is accepted as an alias for `repeatmasker_bed`.
- `dict` or `sequence_dict` is used by WGS/GATK checks.
- `known_sites_vcf` is optional WGS metadata for known-sites policy checks.
- `tss_bed` is optional ATAC metadata used for TSS enrichment when local BAMs and bedtools are available.

Run:

```bash
nextflow run . \
  --run_stage reference_quality \
  --reference_manifest path/to/reference_manifest.tsv \
  --outdir results \
  --check_paths false
```

`--check_paths false` allows placeholder paths and reports content checks as skipped when local files are unavailable. Use `--check_paths true` for local reference bundles that should be fully readable.
