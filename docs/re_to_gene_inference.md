# CAME Optional RE-To-Gene Inference

Stage 20 adds optional scaffolding for future regulatory-element-to-gene inference. It defines metadata contracts, validation, deterministic stub links, and summary outputs for links inferred from promoter overlap, proximity, chromatin contacts, nearest genes, or future precomputed maps.

This stage is future-facing. It is not part of the v0.1 `--run_stage all` path, and it does not replace the Stage 8 `--re_to_gene_links` input. Core CAME remains phenotype-agnostic; link behavior is driven by metadata tables, not by example study-profile biology.

## Relationship To Stage 8

Stage 8 GRA analysis consumes a supplied `re_to_gene_links.tsv` table. Stage 20 can write a compatible scaffold table at:

- `results/re_to_gene_inference/re_to_gene_links.tsv`

Users must explicitly inspect and pass any Stage 20 output to Stage 8. CAME does not automatically swap inferred links into `--run_stage gra_analysis` or `--run_stage all`.

## Command

```bash
nextflow run . \
  --run_stage re_to_gene_inference \
  --regulatory_regions assets/example_samplesheets/regulatory_regions.tsv \
  --gene_coordinates assets/example_samplesheets/gene_coordinates.tsv \
  --chromatin_contacts assets/example_samplesheets/chromatin_contacts.tsv \
  --re_to_gene_inference_config assets/example_samplesheets/re_to_gene_inference_config.tsv \
  --re_to_gene_inference_stub true
```

`--re_to_gene_inference_stub true` is the default.

## Regulatory Regions

Default example: `assets/example_samplesheets/regulatory_regions.tsv`

Required columns:

| column | description |
| --- | --- |
| `species` | Species identifier. |
| `feature_id` | Regulatory-region identifier unique within species. |
| `chrom` | Chromosome or contig. |
| `start` | Zero-based, inclusive start coordinate. |
| `end` | Zero-based, exclusive end coordinate. Must be greater than `start`. |

Optional columns include `strand`, `region_type`, `source`, and `notes`.

## Gene Coordinates

Default example: `assets/example_samplesheets/gene_coordinates.tsv`

Required columns:

| column | description |
| --- | --- |
| `species` | Species identifier. |
| `gene_feature_id` | Gene feature identifier unique within species. |
| `chrom` | Chromosome or contig. |
| `start` | Zero-based, inclusive gene start. |
| `end` | Zero-based, exclusive gene end. Must be greater than `start`. |

Optional columns: `strand`, `gene_symbol`, `orthogroup_id`, `tss`, `source`, `notes`.

## Chromatin Contacts

Default example: `assets/example_samplesheets/chromatin_contacts.tsv`

Required columns when supplied:

| column | description |
| --- | --- |
| `species` | Species identifier. |
| `region_a_chrom`, `region_b_chrom` | Contact anchors. |
| `region_a_start`, `region_a_end` | First anchor interval. |
| `region_b_start`, `region_b_end` | Second anchor interval. |
| `contact_score` | Numeric contact score. |

Optional columns: `cell_type`, `assay`, `source`, `notes`.

## Inference Config

Default example: `assets/example_samplesheets/re_to_gene_inference_config.tsv`

Required columns:

| column | description |
| --- | --- |
| `inference_id` | Inference record identifier. |
| `species` | Species to process. |
| `method` | Method label. |

Allowed scaffold method labels:

- `stub`
- `promoter_overlap`
- `nearest_gene`
- `distance_window`
- `chromatin_contact`
- `precomputed`

Optional columns: `max_distance`, `promoter_upstream`, `promoter_downstream`, `min_contact_score`, `notes`.

## Input Preparation

`bin/prepare_re_to_gene_inference_inputs.py` reads regulatory regions, gene coordinates, optional contacts, and inference config. It validates required columns, integer coordinates, `start < end`, duplicate IDs, numeric thresholds, method labels, species coverage, and real-mode restrictions.

Outputs:

- `results/re_to_gene_inference/input/re_to_gene_inference_manifest.tsv`
- `results/re_to_gene_inference/input/re_to_gene_inference_warnings.tsv`

## Stub Mode

Stub mode creates deterministic RE-to-gene links without external tools.

Outputs:

- `results/re_to_gene_inference/re_to_gene_links.tsv`
- `results/re_to_gene_inference/re_to_gene_inference_warnings.tsv`
- `results/re_to_gene_inference/summary/re_to_gene_inference_summary.tsv`
- `results/re_to_gene_inference/summary/re_to_gene_inference_outputs_manifest.tsv`

The stub table includes promoter, proximal, distal-contact, nearest-gene, and ambiguous examples. Ambiguity is represented as multiple rows with explanatory notes so Stage 8 can retain or flag links using its existing validator and GRA construction behavior.

## Stage 8-Compatible Output

Required columns:

`species`, `re_feature_id`, `gene_feature_id`, `link_type`

Optional columns used by the scaffold:

`re_orthogroup_id`, `gene_orthogroup_id`, `distance_to_tss`, `contact_score`, `link_confidence`, `source`, `notes`

Supported `link_type` values should stay compatible with Stage 8: `promoter`, `proximal`, `distal_contact`, `nearest_gene`, and `curated`. Do not use `ambiguous` as a link type; represent ambiguous mappings with multiple rows and notes.

## Real Mode

`--re_to_gene_inference_stub false` is intentionally conservative. Input preparation rejects `method=stub`, validates requested metadata, and checks that chromatin-contact methods have contact metadata. Placeholder real-mode subworkflows then fail clearly because production inference is not implemented in Stage 20.

The scaffold does not install tools, does not execute production promoter/proximity/contact algorithms, and does not silently emit synthetic real-mode results.

## Future Strategies

Future implementations may add:

- promoter/TSS overlap using configurable strand-aware windows
- nearest-gene or distance-window linking with explicit tie handling
- chromatin-contact linking with assay/cell-type filters and score thresholds
- curated or precomputed map ingestion
- confidence calibration and provenance for combined evidence

## Limitations

- Production RE-to-gene inference is not implemented.
- Stub links are deterministic contract fixtures, not biological claims.
- Stage 20 is optional and is not required by `--run_stage all`.
- Stage 8 continues to use the link table supplied through `--re_to_gene_links`.
