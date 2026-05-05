# CAME input formats

CAME validates metadata for cross-species phenotype and multi-omics studies. It does not run biological analyses.

The core metadata model is phenotype-agnostic. Study-specific variables such as DDR state, viability, apoptosis, senescence, cancer prevalence, longevity, or body mass should be represented as generic traits, covariates, measurements, or later study profiles. They must not be hardcoded into core validation.

Study profiles are documented in [`study_profiles.md`](study_profiles.md). `study_design.yaml` remains the metadata design file; `study_profile.yaml` is an optional validation input.

## Required files

### `species_traits.tsv`

Long-format species trait and covariate table. Each row is one generic trait or covariate observation for one species.

Required columns:

| column | description |
| --- | --- |
| `species` | Species identifier shared across metadata files. |
| `phylogeny_label` | Label used for the species in phylogeny files. |
| `trait_value` | Generic trait or covariate value. |

Recommended columns:

| column | description |
| --- | --- |
| `common_name` | Optional common species name. |
| `clade` | Optional clade or taxonomic grouping. |
| `external_trait` | Generic trait group. |
| `covariate` | Generic covariate or trait name. |
| `trait_unit` | Unit for `trait_value`. |
| `trait_source` | Source for the trait value. |
| `trait_confidence` | Confidence label or score. |

Example:

```tsv
species	phylogeny_label	common_name	clade	external_trait	covariate	trait_value	trait_unit
Mus_musculus	Mus_musculus	house mouse	Mammalia	life_history	body_size	0.025	kg
```

### `phenotype_samplesheet.csv`

Long-format phenotype observations. Each row is one measurement.

Required columns:

`sample_id`, `species`, `individual_id`, `replicate_id`, `condition`, `timepoint`, `assay`, `measurement`, `value`, `unit`

Optional columns:

`perturbation`, `dose`, `dose_unit`, `recovery_time`, `batch`, `plate_id`, `well_id`, `file`, `notes`

Example:

```csv
sample_id,species,individual_id,replicate_id,condition,timepoint,assay,measurement,value,unit
pheno_mouse_1,Mus_musculus,mouse_001,rep1,control,0h,generic_growth,response_index,1.0,ratio
```

### `omics_samplesheet.csv`

Omics sample metadata. CAME validates metadata only and does not require FASTQ files to exist.

Required columns:

`sample_id`, `species`, `individual_id`, `replicate_id`, `omics_type`, `condition`, `timepoint`, `reference_id`

Optional columns:

`perturbation`, `dose`, `dose_unit`, `batch`, `fastq_1`, `fastq_2`, `strandedness`, `read_layout`, `library_strategy`, `file`, `notes`

Known `omics_type` examples are `rnaseq` and `atacseq`. Other values are allowed with a warning so additional modalities can be added without changing the core schema.

Example:

```csv
sample_id,species,individual_id,replicate_id,omics_type,condition,timepoint,reference_id,fastq_1,fastq_2,read_layout
omics_mouse_rna_1,Mus_musculus,mouse_001,rep1,rnaseq,control,0h,mmus_ref,data/mouse_R1.fastq.gz,data/mouse_R2.fastq.gz,paired-end
```

### `reference_manifest.tsv`

Reference asset metadata. CAME requires path values but does not check that referenced files exist.

Required columns:

`reference_id`, `species`, `genome_fasta`

Optional columns:

`gtf`, `transcript_fasta`, `star_index`, `bwa_index`, `bowtie2_index`, `chrom_sizes`, `tss_bed`, `blacklist_bed`, `repeatmasker_bed`, `mappability_bed`, `annotation_version`, `source`, `notes`

Example:

```tsv
reference_id	species	genome_fasta	gtf	annotation_version
mmus_ref	Mus_musculus	references/mouse/genome.fa	references/mouse/genes.gtf	example_v1
```

### `phylogeny_manifest.tsv`

Phylogeny file metadata. `species` and `phylogeny_label` are optional, but when provided they must match `species_traits.tsv`.

Required columns:

`phylogeny_id`, `phylogeny_file`

Optional columns:

`species`, `phylogeny_label`, `source`, `branch_length_type`, `notes`

Example:

```tsv
phylogeny_id	phylogeny_file	species	phylogeny_label	source
example_tree	phylogeny/example_tree.nwk	Mus_musculus	Mus_musculus	example
```

### `study_design.yaml`

Minimal study configuration with placeholders for optional configurable phenotype indexes and hypothesis models.

Required top-level sections:

`study`, `metadata`, `contrasts`

Example:

```yaml
study:
  study_id: came_stage1_example
metadata:
  phenotype_samplesheet: phenotype_samplesheet.csv
contrasts:
  - contrast_id: example_control_profile
phenotype_indexes: []
hypothesis_models: []
```

## Validation

Run with Nextflow:

```bash
nextflow run . \
  --phenotype_samplesheet assets/example_samplesheets/phenotype_samplesheet.csv \
  --omics_samplesheet assets/example_samplesheets/omics_samplesheet.csv \
  --species_traits assets/example_samplesheets/species_traits.tsv \
  --reference_manifest assets/example_samplesheets/reference_manifest.tsv \
  --phylogeny_manifest assets/example_samplesheets/phylogeny_manifest.tsv \
  --study_design assets/example_samplesheets/study_design.yaml \
  --validate_only true
```

Run the Python validator directly:

```bash
python3 bin/validate_metadata.py \
  --phenotype_samplesheet assets/example_samplesheets/phenotype_samplesheet.csv \
  --omics_samplesheet assets/example_samplesheets/omics_samplesheet.csv \
  --species_traits assets/example_samplesheets/species_traits.tsv \
  --reference_manifest assets/example_samplesheets/reference_manifest.tsv \
  --phylogeny_manifest assets/example_samplesheets/phylogeny_manifest.tsv \
  --study_design assets/example_samplesheets/study_design.yaml
```

The validator writes `results/validation/metadata_validation_report.tsv` with `severity`, `rule_id`, `source`, `field`, `row`, `message`, and `suggestion` columns.

## Common validation errors

| error | fix |
| --- | --- |
| Missing required column | Add the named column to the relevant metadata file. |
| Missing required value | Fill the empty required cell. |
| Duplicate `sample_id` | Make sample IDs unique within the phenotype or omics table. |
| Unknown `reference_id` | Add the reference to `reference_manifest.tsv` or fix the omics row. |
| Non-numeric phenotype `value` | Use a numeric value for quantitative phenotype rows. |
| Paired-end sample requires `fastq_1` and `fastq_2` | Add both FASTQ path fields or change `read_layout`. |
| Single-end sample requires `fastq_1` | Add `fastq_1` or correct `read_layout`. |
| Unknown `omics_type` warning | Confirm the value is intentional or fix spelling. |
