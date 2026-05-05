# CAME Phenotype Processing

CAME turns validated long-format phenotype measurements into reusable phenotype-response tables. It remains phenotype-agnostic: study-specific names such as DDRstate live in profiles and examples, not in core code.

## Workflow

Run CAME with the metadata files plus a study profile:

```bash
nextflow run . \
  --run_stage phenotype_response \
  --study_profile profiles/ddr_ror/study_profile.yaml \
  --phenotype_samplesheet assets/example_samplesheets/phenotype_samplesheet.csv \
  --omics_samplesheet assets/example_samplesheets/omics_samplesheet.csv \
  --species_traits assets/example_samplesheets/species_traits.tsv \
  --reference_manifest assets/example_samplesheets/reference_manifest.tsv \
  --phylogeny_manifest assets/example_samplesheets/phylogeny_manifest.tsv \
  --study_design assets/example_samplesheets/study_design.yaml
```

Process order is metadata validation, study profile validation, phenotype normalization, phenotype QC, phenotype index calculation, and phenotype contrasts. `--validate_only true` stops after validation.

## Normalization

`bin/phenotype_normalize.py` reads CSV or TSV, trims cells, normalizes species labels by replacing whitespace with underscores, validates numeric values, standardizes missing values, and removes exact duplicate rows with a warning.

Supported `--normalization` modes:

| mode | behavior |
| --- | --- |
| `none` | Preserve numeric values. |
| `zscore_within_assay` | Z-score within each `assay` plus `measurement`. Constant groups become 0. |
| `minmax_within_assay` | Scale within each `assay` plus `measurement` to 0-1. Constant groups become 0. |
| `log10_if_positive` | Apply log10 to positive values; non-positive values become `NA` with a warning. |
| `median_center_within_assay` | Subtract the within-assay/measurement median. |

Outputs:

- `results/phenotype/tables/phenotype_long_normalized.tsv`
- `results/phenotype/qc/normalization_summary.tsv`

## Phenotype Indexes

Profiles define one `phenotype_index` with `name`, `formula`, `components`, `aggregation`, and `contrasts`.

Formula syntax supports component names, numeric literals, parentheses, unary signs, `+`, `-`, `*`, `/`, and safe `abs`, `min`, and `max` calls. Exponentiation, attribute access, imports, strings, and raw Python evaluation are not allowed.

Component values are gathered by replicate unit:

`species + individual_id + replicate_id + condition + timepoint`

The calculator resolves components from `measurement` first, with `assay` as a compatibility fallback. Missing required components fail the run. Division by zero writes `NA` and a warning instead of crashing. Group-level index values aggregate replicate index values by `species + condition + timepoint`.

Aggregation values are `mean`, `median`, `sum`, and `first`. Existing names such as `mean_by_species_condition_timepoint` map to `mean`.

Outputs:

- `results/phenotype/index/phenotype_index_by_sample.tsv`
- `results/phenotype/index/phenotype_index_by_group.tsv`

## QC

`bin/phenotype_qc.py` writes:

- `results/phenotype/qc/phenotype_qc_metrics.tsv`
- `results/phenotype/qc/outliers.tsv`
- `results/phenotype/qc/group_counts.tsv`

QC includes row counts, missingness, replicate counts, duplicate `sample_id` warnings, expected profile component checks, unit inconsistency warnings, sparse group warnings, and IQR outliers.

## Contrasts

Profile contrasts support:

- `baseline_vs_response`
- `condition_contrast`
- `timepoint_contrast`
- `treated_vs_control` as a compatibility alias for `condition_contrast`

The direction is always `response - baseline`. Fold change is `response / baseline` when the baseline is nonzero. `log2_fold_change` is emitted only when baseline and response are positive.

Outputs:

- `results/phenotype/contrasts/phenotype_index_contrasts.tsv`
- `results/phenotype/contrasts/component_trait_contrasts.tsv`

## Examples

The generic profile computes:

```yaml
phenotype_index:
  name: composite_response_index
  formula: "(component_a - component_b) / component_c"
```

The DDR/RoR example profile computes:

```yaml
phenotype_index:
  name: DDRstate
  formula: "(viability - apoptosis - senescence) / (viability + apoptosis)"
```

Both examples use the same generic code path.

## Common Failures

| failure | fix |
| --- | --- |
| Missing component | Add rows for every profile component in each replicate unit or correct component names. |
| Invalid formula | Use only supported arithmetic and declared components. |
| Division by zero | Check component values; output is `NA` for the affected unit. |
| Missing contrast label | Align profile contrast conditions/timepoints with phenotype metadata. |
| Non-numeric value | Use numeric phenotype values or mark missing values consistently. |
| PyYAML missing | Install PyYAML in the runtime environment. |

## CAME Inputs

Downstream workflows should consume the normalized phenotype table, group-level index table, and contrast tables as stable phenotype-response inputs for omics integration and model fitting.
