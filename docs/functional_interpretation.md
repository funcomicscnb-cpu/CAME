# Stage 11: Functional Interpretation

Stage 11 adds phenotype-agnostic functional interpretation for ranked CAME candidates. It consumes Stage 10 candidate rankings, Stage 7 feature coordinates, Stage 8 GRA membership, and local annotation files to produce offline enrichment results, GREAT-ready regulatory-region exports, and compact interpretation summaries.

Stage 11 does not call online APIs, infer orthology, perform coordinate lift-over, or hardcode profile-specific biology.

## Inputs

Default upstream inputs are resolved under `--outdir`:

- `candidates/ranked/candidate_genes_ranked.tsv`
- `candidates/ranked/candidate_res_ranked.tsv`
- `candidates/ranked/candidate_gras_ranked.tsv`
- `candidates/ranked/candidate_all_ranked.tsv`
- `orthology/feature_to_orthogroup_map.tsv`
- `gra/tables/gene_regulatory_architectures.tsv`
- `gra/tables/gra_re_membership.tsv`

Annotation inputs default to:

- `assets/example_samplesheets/gene_annotations.tsv`
- `assets/example_samplesheets/gene_sets.tsv`

Run:

```bash
nextflow run . \
  --run_stage functional_interpretation \
  --gene_annotations assets/example_samplesheets/gene_annotations.tsv \
  --gene_sets assets/example_samplesheets/gene_sets.tsv
```

Use `--functional_interpretation_top_n` to change the selected number of candidates per candidate type. Default is `50`. Use `--functional_interpretation_min_score` to filter candidates before applying `top_n`.

## Gene Annotations

`gene_annotations.tsv` requires:

```text
gene_orthogroup_id
gene_symbol
```

Optional columns:

```text
description
species
source_gene_id
chrom
start
end
strand
biotype
external_id
notes
```

Missing optional annotation columns generate warnings but do not stop the stage.

## Gene Sets

`gene_sets.tsv` requires:

```text
gene_set_id
gene_set_name
gene_orthogroup_id
```

Optional columns:

```text
gene_set_source
description
category
notes
```

This file is the offline source for enrichment. Missing required columns or a missing file cause a clear failure.

## Candidate-Linked Gene Sets

Stage 11 builds four candidate sets:

- `genes`: selected direct gene candidates.
- `regulatory_element_linked_genes`: genes linked to selected RE candidates.
- `gra_linked_genes`: genes linked to selected GRA candidates.
- `all_candidates_linked_genes`: selected genes plus linked genes from selected RE and GRA candidates.

Linked genes are resolved from ranked candidate table link columns first. If those columns are empty, Stage 11 falls back to `gra_re_membership.tsv` and `gene_regulatory_architectures.tsv`.

The enrichment background is the intersection of genes in `gene_annotations.tsv` and genes in `gene_sets.tsv`. Candidate genes outside that background are reported and excluded from enrichment tests.

Outputs:

- `results/interpretation/input/candidate_gene_sets.tsv`
- `results/interpretation/input/enrichment_background.tsv`
- `results/interpretation/input/enrichment_input_warnings.tsv`

## Offline Enrichment

Stage 11 runs a one-sided exact hypergeometric overrepresentation test using the Python standard library. P-values are Benjamini-Hochberg adjusted separately within each candidate set.

Output:

- `results/interpretation/enrichment/gene_set_enrichment.tsv`
- `results/interpretation/enrichment/enrichment_warnings.tsv`

`gene_set_enrichment.tsv` includes candidate-set size, background size, overlap genes, odds ratio, p-value, adjusted p-value, and status. Empty candidate sets are retained with status values rather than causing a crash.

## Regulatory BED Export

Stage 11 exports selected regulatory-element candidates and REs linked to selected GRA candidates:

- `results/interpretation/regulatory_regions/candidate_res.bed`
- `results/interpretation/regulatory_regions/gra_linked_candidate_res.bed`
- `results/interpretation/regulatory_regions/regulatory_region_export_warnings.tsv`

Coordinates are taken directly from `feature_to_orthogroup_map.tsv` rows where `feature_type=regulatory_element`. Rows with missing or invalid coordinates are skipped and reported. Coordinates are not lifted or converted.

The BED-like exports include:

```text
chrom
start
end
name
score
strand
candidate_type
candidate_id
linked_gene_orthogroup_id
support_summary
species
source_feature_id
```

## Summary Outputs

Stage 11 combines candidates, annotations, enrichment results, and regulatory exports into:

- `results/interpretation/summary/candidate_gene_interpretation.tsv`
- `results/interpretation/summary/candidate_re_interpretation.tsv`
- `results/interpretation/summary/candidate_gra_interpretation.tsv`
- `results/interpretation/summary/functional_interpretation_summary.tsv`
- `results/interpretation/summary/functional_interpretation_outputs_manifest.tsv`

These outputs are designed for later final reporting: they provide compact candidate labels, linked genes, top enrichment terms, annotation status, BED export counts, and output availability.

## Limitations

- Enrichment uses simple overrepresentation tests and does not deconvolve correlated evidence layers.
- Background definition depends on the supplied annotation and gene-set files.
- RE and GRA interpretation depends on supplied Stage 8 links.
- Coordinates are used as supplied and are assumed to already be in the intended genome coordinate system.
- Missing annotations or coordinates reduce interpretability but do not imply absence of biological support.
