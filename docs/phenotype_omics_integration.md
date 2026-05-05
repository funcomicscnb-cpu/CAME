# Phenotype-Omics Integration

CAME connects cross-species phenotype responses with molecular responses from orthology projection and GRA analysis. It is phenotype-agnostic: phenotype names, molecular layers, and contrasts come from input tables and the study profile, not from hardcoded biology.

CAME does not perform candidate ranking, enrichment analysis, coordinate lift-over, orthology inference, or RE-to-gene link inference.

## Inputs

Required upstream outputs:

- `--phenotype_index_contrasts results/phenotype/contrasts/phenotype_index_contrasts.tsv`
- `--component_trait_contrasts results/phenotype/contrasts/component_trait_contrasts.tsv`
- `--differential_expression_orthogroups results/orthology/differential_expression_orthogroups.tsv`
- `--differential_accessibility_orthogroups results/orthology/differential_accessibility_orthogroups.tsv`
- `--differential_gra_activity results/gra/differential/differential_gra_activity.tsv`

Also required:

- `--study_profile`
- `--omics_samplesheet`
- `--species_traits`
- `--phylogeny_manifest`

The default phenotype metric is `difference`. The default molecular metric is `log2_fold_change`.

## Feature Layers

CAME normalizes molecular tables into one long response table with these layers:

- `expression`: gene orthogroup differential expression, using `orthogroup_id` as `feature_id`
- `accessibility`: regulatory-element orthogroup differential accessibility, using `orthogroup_id` as `feature_id`
- `gra_activity`: differential GRA activity, using `gra_id` as `feature_id`

Molecular rows are joined to phenotype rows by `species`, `contrast_name`, `baseline_label`, and `response_label`. Unmatched phenotype and molecular rows remain in the prepared long tables and are reported in `phenotype_omics_input_warnings.tsv`.

## Phenotype Scope

By default, association models use only the declared phenotype index response:

```bash
--phenotype_response_scope index
```

Set `--phenotype_response_scope all` to also model component-trait contrasts. Component rows are always preserved in `phenotype_response_table.tsv`.

## Clustering

Molecular response clustering runs separately by `feature_layer` and `contrast_name`.

The default deterministic method is sign-pattern clustering:

- `shared_up`
- `shared_down`
- `species_specific`
- `lineage_or_subset_specific`
- `mixed`
- `insufficient_data`

Optional hierarchical clustering can be requested with `--integration_cluster_method hierarchical`. If SciPy is unavailable, CAME falls back to sign-pattern clustering and records a compact warning in process stderr.

## Association Models

CAME fits:

```text
feature_response_value ~ phenotype_response_value
```

Models run separately by feature layer, contrast, feature, phenotype response id, phenotype metric, and molecular metric.

Supported model types:

- `lm`: baseline linear model, always available through base R
- `pgls_brownian`: Brownian PGLS, used only when `ape`, `nlme`, enough species, a readable tree, and complete species-to-tip matching are available

PGLS is optional. If it cannot run, LM output is still written and the PGLS skip reason is recorded in `phenotype_omics_association_warnings.tsv`.

CAME does not silently drop species from model groups. Missing numeric values, duplicate species rows, missing phylogeny labels, or tree-tip mismatches cause the affected model to be skipped with an explicit warning.

Small species sets limit inference. The default PGLS minimum is:

```bash
--pgls_min_species 6
```

`--integration_min_species` defaults to the same value and can be overridden for exploratory runs. LM still runs with three or more species when model data are usable. PGLS below the configured threshold is skipped with a structured warning; if the threshold is deliberately lowered to 3-5, PGLS emits an exploratory small-n warning.

## Pairwise Species Contrasts

Pairwise contrasts compare species-level phenotype and molecular responses. By default, all species pairs present in the prepared response tables are used. If `--species_pairs` points to a table with `species_a` and `species_b`, only those ordered pairs are used.

Deltas are defined as:

```text
species_b - species_a
```

The `direction_match` column is:

- `same`
- `opposite`
- `zero_or_missing`

## Outputs

Input preparation:

- `results/integration/input/phenotype_response_table.tsv`
- `results/integration/input/molecular_response_long.tsv`
- `results/integration/input/phenotype_omics_model_table.tsv`
- `results/integration/input/phenotype_omics_input_warnings.tsv`

Clustering:

- `results/integration/clustering/response_clusters_expression.tsv`
- `results/integration/clustering/response_clusters_accessibility.tsv`
- `results/integration/clustering/response_clusters_gra_activity.tsv`
- `results/integration/clustering/response_cluster_summary.tsv`

Associations:

- `results/integration/associations/phenotype_expression_associations.tsv`
- `results/integration/associations/phenotype_accessibility_associations.tsv`
- `results/integration/associations/phenotype_gra_associations.tsv`
- `results/integration/associations/phenotype_omics_association_warnings.tsv`

Pairwise:

- `results/integration/pairwise/pairwise_species_molecular_contrasts.tsv`
- `results/integration/pairwise/pairwise_species_contrast_summary.tsv`

Summary:

- `results/integration/summary/phenotype_omics_integration_summary.tsv`
- `results/integration/summary/phenotype_omics_outputs_manifest.tsv`

## Example

Run CAME, CAME, and CAME first with the same `--outdir`, or provide all upstream output paths explicitly. Then run:

```bash
nextflow run . \
  --run_stage phenotype_omics_integration \
  --study_profile profiles/generic/study_profile.yaml \
  --omics_samplesheet assets/example_samplesheets/omics_samplesheet.csv \
  --species_traits assets/example_samplesheets/species_traits.tsv \
  --phylogeny_manifest assets/example_samplesheets/phylogeny_manifest.tsv \
  --omics_stub true
```

## CAME Use

CAME candidate ranking can consume CAME association tables, response clusters, and pairwise contrasts to prioritize features that repeatedly track phenotype responses across model types, species pairs, and molecular layers.
