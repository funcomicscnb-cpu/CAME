# CAME Orthology Projection

CAME maps species-specific molecular features to cross-species orthology groups for later comparative analysis. It is phenotype-agnostic and does not build gene-regulatory architecture, test phenotype-omics associations, rank candidates, or hardcode DDR/RoR concepts.

## Inputs

Required:

- `--run_stage orthology_projection`
- `--omics_samplesheet`
- `--orthologous_genes`
- `--orthologous_res`

Count matrices are required for requested assays and resolve from explicit paths first:

- `--rnaseq_counts`
- `--atacseq_counts`

Otherwise CAME looks under `--outdir`:

- `results/rnaseq/counts/gene_counts.tsv`
- `results/atacseq/counts/re_counts.tsv`

Differential tables are optional by default and are projected when present:

- `--differential_expression`
- `--differential_accessibility`
- `results/differential_omics/rnaseq/differential_results.tsv`
- `results/differential_omics/atacseq/differential_results.tsv`

If an explicit differential path is supplied, it must exist. If the default differential path is absent, CAME writes empty orthogroup differential outputs and records a warning.

## Orthology Tables

`orthologous_genes.tsv` requires:

`species`, `feature_id`, `orthogroup_id`

Optional gene columns:

`gene_symbol`, `human_anchor_id`, `transcript_id`, `orthology_type`, `orthology_confidence`, `source`, `notes`

`orthologous_res.tsv` requires:

`species`, `feature_id`, `orthogroup_id`

Optional regulatory element columns:

`chrom`, `start`, `end`, `human_anchor_region`, `re_type`, `orthology_type`, `orthology_confidence`, `source`, `notes`

Both CSV and TSV delimiters are accepted.

## Mapping Semantics

Count matrices do not carry a feature-level species column. CAME uses `omics_samplesheet` to map each sample column to its species, then applies `species + feature_id` orthology mappings for that sample.

- One-to-one mappings are projected directly.
- Many-to-one mappings are summed for counts and aggregated for differential rows.
- One-to-many mappings are duplicated into each mapped orthogroup and flagged with `is_ambiguous=true`.

Ambiguous mappings are retained by default so downstream workflows can filter them explicitly.

## Aggregation Rules

Counts:

- Sum mapped features within each orthogroup per sample.
- Emit `NA` when a sample's species has no mapped source feature for an orthogroup.
- Preserve sample column ordering from the input count matrix.

Differential results:

- Keep species-stratified groups; do not aggregate effects across species.
- Mean `base_mean`, `baseline_mean`, `response_mean`, `log2_fold_change`, and `statistic`.
- Minimum `p_value` and `padj`, with a warning that this is a pragmatic feature summary, not meta-analysis.
- Retain comma-separated source feature membership.

## Outputs

Outputs are written under `results/orthology/` by default:

- `validation/orthology_validation_report.tsv`
- `gene_orthogroup_counts.tsv`
- `re_orthogroup_counts.tsv`
- `differential_expression_orthogroups.tsv`
- `differential_accessibility_orthogroups.tsv`
- `feature_to_orthogroup_map.tsv`
- `orthology_projection_warnings.tsv`
- `summary/orthology_projection_summary.tsv`
- `summary/orthology_outputs_manifest.tsv`

Projected orthogroup tables include:

`orthogroup_id`, `feature_type`, `mapping_status`, `n_source_features`, `n_species`, `is_ambiguous`, `ambiguity_reason`, `species_members`, `source_feature_ids`

Differential orthogroup tables also include the projected species and differential result columns.

## Example

```bash
nextflow run . \
  --run_stage orthology_projection \
  --omics_samplesheet assets/example_samplesheets/omics_samplesheet.csv \
  --orthologous_genes assets/example_samplesheets/orthologous_genes.tsv \
  --orthologous_res assets/example_samplesheets/orthologous_res.tsv \
  --omics_stub true
```

Orthology projection consumes existing bulk omics and differential omics outputs only. Run `bulk_omics` first, and run `differential_omics` first if differential projection is needed.

## GRA Use

GRA construction should use the orthogroup count tables and feature map to compare expression and accessibility across species while preserving feature membership and ambiguity flags. Downstream analyses should filter or model `is_ambiguous` mappings deliberately rather than assuming they were removed.

## Limitations

The projected differential p-values are summaries of mapped feature-level p-values, not orthogroup-level tests or meta-analysis.

Differential orthogroup rows are not orthogroup-level DESeq2 fits. Within each orthogroup, species and contrast, `base_mean`, `baseline_mean`, `response_mean`, `log2_fold_change` and `statistic` are arithmetic means of the non-missing mapped-feature values, and `p_value`/`padj` are minima. These summaries do not separate rows by `method` or `status`; those columns are reported as joined label sets. When an orthogroup contains both a feature with a successful DESeq2 fit and a feature removed by the low-count filter, its `log2_fold_change` averages a fitted DESeq2 effect with a descriptive pseudocount effect (`log2((response_mean + 1) / (baseline_mean + 1))`), and its `base_mean` likewise mixes the two definitions. Fallback and fitted rows from different contrasts are not combined, because contrasts are grouped separately.

Successful DESeq2 rows report unshrunk `log2FoldChange` estimates; CAME does not apply `lfcShrink`. Sparse features that pass the low-count filter can therefore carry large effect magnitudes. `collect_candidate_evidence.py` uses `log2_fold_change` from these orthogroup tables, and directly from `differential_gra_activity.tsv`, as differential `effect_size`, and candidate scoring uses its absolute value without an effect-size cap. Large or mixed effects can therefore propagate into candidate evidence. Filter on `status`/`method` or inspect feature-level results before interpreting orthogroup effects.

The strict DESeq2 test fixture is adversarial: it was constructed so that fitted and descriptive effects disagree in sign for multiple features. It demonstrates that such disagreement, and hence mixed-estimator orthogroup summaries, can occur; it does not estimate how often it occurs in real studies. CAME does not infer orthology, lift coordinates, resolve paralog confidence, build regulatory architecture, or connect molecular features to phenotype responses.
