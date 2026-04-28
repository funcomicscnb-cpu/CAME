# Stage 10: Candidate Mechanism Prioritization

Stage 10 ranks candidate genes, regulatory elements, and gene regulatory architectures (GRAs) using outputs from previous CAME stages. It is phenotype-agnostic: candidate IDs, contrasts, and evidence layers come from input tables, not from hardcoded biology.

Stage 10 does not run enrichment analysis, coordinate lift-over, orthology inference, or RE-to-gene inference.

## Inputs

Default inputs are resolved under `--outdir`:

- `phenotype/contrasts/phenotype_index_contrasts.tsv`
- `hypotheses/hypothesis_model_results.tsv` optional
- `orthology/differential_expression_orthogroups.tsv`
- `orthology/differential_accessibility_orthogroups.tsv`
- `orthology/feature_to_orthogroup_map.tsv`
- `gra/tables/gene_regulatory_architectures.tsv`
- `gra/tables/gra_re_membership.tsv`
- `gra/differential/differential_gra_activity.tsv`
- `integration/associations/phenotype_expression_associations.tsv`
- `integration/associations/phenotype_accessibility_associations.tsv`
- `integration/associations/phenotype_gra_associations.tsv`
- `integration/clustering/response_clusters_expression.tsv`
- `integration/clustering/response_clusters_accessibility.tsv`
- `integration/clustering/response_clusters_gra_activity.tsv`
- `integration/pairwise/pairwise_species_molecular_contrasts.tsv`

Stage 10 also accepts explicit path overrides. For differential orthogroup tables, `--differential_expression_orthogroups` and `--differential_accessibility_orthogroups` are preferred. The older `--differential_expression` and `--differential_accessibility` parameters remain valid aliases only for this stage.

Optional evidence layers may be absent. Missing optional layers are reported in `candidate_evidence_warnings.tsv`. The stage fails only when no major scoring evidence is available.

## Candidate Types

Candidate IDs are normalized as:

- `gene`: gene `orthogroup_id`
- `regulatory_element`: regulatory element `orthogroup_id`
- `gra`: `gra_id`

`gra_re_membership.tsv` is the authoritative link graph for gene-RE-GRA relationships. Direct evidence is scored at full strength. Evidence propagated across a membership link is scored with `--candidate_linked_evidence_weight`, default `0.5`.

## Evidence Layers

Supported evidence types:

- `differential_expression`
- `differential_accessibility`
- `differential_gra_activity`
- `phenotype_expression_association`
- `phenotype_accessibility_association`
- `phenotype_gra_association`
- `response_cluster`
- `pairwise_species_contrast`
- `hypothesis_support`
- `gra_membership`

Current Stage 4 hypothesis results are usually global. They are warning-only unless rows contain candidate identifiers such as `candidate_id`, `gene_orthogroup_id`, `re_orthogroup_id`, `gra_id`, or a candidate-specific `feature_id` with `feature_layer`.

## Scoring

Default weights are provided in:

```text
assets/example_samplesheets/candidate_scoring_config.tsv
```

The config columns are:

```text
evidence_type    weight    enabled    notes
```

Rules:

- Association evidence: `weight * -log10(p_value)`, capped by `--candidate_score_cap` default `50`. A p-value of `0` uses the cap.
- Missing association p-values use a small effect-size fallback and generate a warning.
- Differential evidence: `weight * abs(log2_fold_change) * significance_factor`.
- `significance_factor` is `2` for `padj <= 0.05`, `1.5` for `p_value <= 0.05`, otherwise `1`.
- Cluster evidence scores `shared_up` and `shared_down` highest, `species_specific` and `lineage_or_subset_specific` modestly, `mixed` weakly, and `insufficient_data` as zero.
- Pairwise evidence scores `same` highest, `opposite` weakly, and `zero_or_missing` as zero.
- GRA membership is low-weight structural support.

Duplicate evidence rows are not double-counted. The scored audit table records counted and ignored duplicate rows.

## Outputs

Evidence:

- `results/candidates/evidence/candidate_evidence_long.tsv`
- `results/candidates/evidence/candidate_evidence_scored.tsv`
- `results/candidates/evidence/candidate_evidence_warnings.tsv`

Ranked candidates:

- `results/candidates/ranked/candidate_genes_ranked.tsv`
- `results/candidates/ranked/candidate_res_ranked.tsv`
- `results/candidates/ranked/candidate_gras_ranked.tsv`
- `results/candidates/ranked/candidate_all_ranked.tsv`
- `results/candidates/ranked/candidate_scoring_warnings.tsv`

Summary:

- `results/candidates/summary/candidate_prioritization_summary.tsv`
- `results/candidates/summary/candidate_outputs_manifest.tsv`

Ranked tables include total score, number of evidence types, number of contrasts and species, top evidence type, top contrast, mean effect size, combined direction, support summary, and linked gene/RE/GRA IDs.

## Example

Run upstream stages first with the same `--outdir`, then:

```bash
nextflow run . \
  --run_stage candidate_prioritization \
  --study_profile profiles/generic/study_profile.yaml
```

To override weights:

```bash
nextflow run . \
  --run_stage candidate_prioritization \
  --study_profile profiles/generic/study_profile.yaml \
  --candidate_scoring_config assets/example_samplesheets/candidate_scoring_config.tsv
```

## Stage 11 Use

Stage 11 enrichment and reporting can consume the ranked candidate tables as transparent, auditable inputs. Enrichment should operate on candidate sets selected from these rankings, not on hidden score internals.

## Limitations

- Scores are deterministic prioritization scores, not calibrated probabilities.
- Linked evidence is intentionally down-weighted to reduce double-counting across connected gene, RE, and GRA candidates.
- Correlated evidence layers are not statistically deconvolved.
- Hypothesis results without candidate IDs are not assigned to candidates.
- Missing optional layers reduce available support but do not imply lack of biological evidence.
