# Real-Mode Metadata

Stage 23 real-mode metadata separates study, sample, experiment, and run concepts so future workflows can join biological design to sequencing files without guessing.

## Required Columns

`sample_id`, `study_id`, `species`, `individual_id`, `biological_replicate`, `assay`, `tissue`, `condition`, `platform`, `library_protocol`, `read_layout`, `fastq_1`, `reference_id`

`sample_id` must be unique. `reference_id` must resolve to the reference manifest when one is supplied, and the metadata `species` must match the reference row.

## Controlled Values

`assay`: `rna`, `atac`, `wgs`, `wes`, `chip_tf`, `chip_histone`, `other`

`read_layout`: `single`, `paired`

RNA `strandedness`: `forward`, `reverse`, `unstranded`, `unknown`

## Assay-Specific Requirements

Paired-end rows require `fastq_2`. Single-end rows must not provide `fastq_2`.

RNA rows require `strandedness`.

ChIP rows, both `chip_tf` and `chip_histone`, require `antibody`.

WES rows require `target_bed`.

ATAC single-end libraries are accepted with a warning because paired-end libraries are generally preferred for fragment-level QC and regulatory-region analysis.

## Study, Sample, Experiment, And Run Fields

Use `study_id` for the study or project. Use `individual_id` for the biological individual. Use `biological_replicate` for the biological replicate label within a condition.

Recommended optional fields include:

- `batch`
- `read_length`
- `library_id`
- `run_id`
- `lane`
- `timepoint`
- `antibody`
- `target_bed`
- `notes`

These fields let Stage 24 and later workflows group technical runs, inspect batch effects, and record longitudinal designs without overloading `sample_id`.

## Replicates And QC

The validator warns when a study/species/assay/tissue/condition group has fewer than two biological replicates. This is a warning because some pilot or public datasets are unreplicated, but production differential analysis should justify low replication before interpretation.

Recommended QC expectations for Stage 24 include FASTQ quality summaries, read length checks, adapter/duplication summaries, alignment rates, library complexity, RNA strandedness confirmation, ATAC fragment-size and TSS-enrichment metrics, WES target coverage, and ChIP antibody and peak-quality summaries.

Stage 23 records only the metadata contract and warnings. It does not run QC tools or production analysis.
