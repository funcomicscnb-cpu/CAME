# Gene Regulatory Architecture Analysis

CAME builds phenotype-agnostic gene regulatory architectures (GRAs) from orthologous regulatory elements (REs) and orthologous genes. It consumes orthology projection outputs, links RE orthogroups to gene orthogroups, aggregates ATAC-seq accessibility into GRA-level activity, and runs differential GRA activity tests when executable contrasts are available.

CAME does not run phenotype-omics association, candidate ranking, orthology inference, or coordinate lift-over.

## Inputs

Required upstream outputs:

- `--gene_orthogroup_counts results/orthology/gene_orthogroup_counts.tsv`
- `--re_orthogroup_counts results/orthology/re_orthogroup_counts.tsv`
- `--feature_to_orthogroup_map results/orthology/feature_to_orthogroup_map.tsv`
- `--differential_expression_orthogroups results/orthology/differential_expression_orthogroups.tsv`
- `--differential_accessibility_orthogroups results/orthology/differential_accessibility_orthogroups.tsv`

Required input:

- `--re_to_gene_links assets/example_samplesheets/re_to_gene_links.tsv`

Also required:

- `--omics_samplesheet`

Optional:

- `--study_profile`, or complete CLI contrast override using `--baseline_condition`, `--response_condition`, `--baseline_timepoint`, and `--response_timepoint`
- `--gra_activity_aggregation mean|sum|median|max|weighted_mean`

## RE-To-Gene Link Format

Required columns:

- `species`
- `re_feature_id`
- `gene_feature_id`
- `link_type`

Optional columns:

- `re_orthogroup_id`
- `gene_orthogroup_id`
- `distance_to_tss`
- `contact_score`
- `link_confidence`
- `source`
- `notes`

Supported `link_type` examples are `promoter`, `proximal`, `distal_contact`, `nearest_gene`, and `curated`. Unsupported values are retained with warnings.

Resolution priority:

1. Use supplied `gene_orthogroup_id` and `re_orthogroup_id` when present, after checking that they exist in CAME outputs.
2. Otherwise resolve `(species, feature_id)` through `feature_to_orthogroup_map.tsv`.
3. Retain unresolved links in validation output, but exclude them from constructed GRAs.

## GRA IDs

GRAs are gene-centered. The stable ID format is:

```text
GRA_<gene_orthogroup_id>
```

An RE linked to multiple genes is duplicated into each gene-centered GRA and flagged as ambiguous. Genes with multiple linked REs keep all resolved RE memberships.

## Aggregation

GRA activity is aggregated from `re_orthogroup_counts.tsv`.

Modes:

- `mean` default
- `sum`
- `median`
- `max`
- `weighted_mean`

`weighted_mean` uses numeric `contact_score` first, then numeric `link_confidence`. If no usable weights exist for a GRA, CAME falls back to `mean` and records a warning.

Missing RE values are not converted to zero. A GRA/sample value is `NA` when all member REs are absent for that sample.

## Differential GRA Activity

Differential GRA testing uses the CAME contrast direction convention:

```text
log2_fold_change = response - baseline
```

DESeq2 is used only when all of the following are true:

- aggregation mode is `sum`
- selected activity values are non-negative integers with no missing values
- DESeq2 is installed
- `--differential_force_fallback false`

Otherwise CAME uses deterministic fallback tests. If no executable contrasts are available, it writes empty differential output with headers and a warning.

## Outputs

Validation:

- `results/gra/validation/re_to_gene_link_validation_report.tsv`

Tables:

- `results/gra/tables/gene_regulatory_architectures.tsv`
- `results/gra/tables/gra_re_membership.tsv`
- `results/gra/tables/gra_link_warnings.tsv`

Activity:

- `results/gra/activity/gra_activity_matrix.tsv`
- `results/gra/activity/gra_activity_long.tsv`
- `results/gra/activity/gra_activity_contributing_res.tsv`
- `results/gra/activity/gra_activity_warnings.tsv`

Differential:

- `results/gra/differential/differential_gra_activity.tsv`
- `results/gra/differential/normalized_gra_activity.tsv`
- `results/gra/differential/differential_gra_activity_warnings.tsv`

`differential_gra_activity.tsv` includes the species for each species-stratified GRA contrast so downstream phenotype-omics integration can join GRA responses to phenotype responses. It also reports `correction_method`, with `BH` for adjusted p-values and `NA` for untested rows.

Summary:

- `results/gra/summary/gra_analysis_summary.tsv`
- `results/gra/summary/gra_outputs_manifest.tsv`

## Example

```bash
nextflow run . \
  --run_stage gra_analysis \
  --omics_samplesheet assets/example_samplesheets/omics_samplesheet.csv \
  --re_to_gene_links assets/example_samplesheets/re_to_gene_links.tsv \
  --study_profile profiles/generic/study_profile.yaml \
  --omics_stub true
```

Run the upstream workflows first with the same `--outdir`, or provide all paths explicitly.

## Limitations

- Link evidence is consumed as supplied; CAME does not infer RE-to-gene links.
- Orthogroup-level links are preferred when cross-species feature-level links cannot be resolved.
- Differential testing on mean/median/max aggregated activity uses fallback statistics by design.
- No phenotype-omics association or candidate ranking is performed. Downstream workflows can use `gra_activity_matrix.tsv`, `differential_gra_activity.tsv`, and GRA membership tables to relate GRA activity to phenotype responses.
