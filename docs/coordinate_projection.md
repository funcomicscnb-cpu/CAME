# CAME Optional Coordinate Projection

This optional interface defines input contracts, validation, deterministic stub outputs, and summary manifests for coordinate projection across species.

This interface is optional. It is not part of the default v0.1 `--run_stage all` path, and it does not implement production lift-over. Core CAME remains phenotype-agnostic; projection behavior is driven by metadata tables and not by example study-profile biology.

## Relationship To Orthology Projection

`orthology_projection` remains the v0.1 workflow for projecting omics features through precomputed `orthologous_genes.tsv` and `orthologous_res.tsv` inputs.

Coordinate projection does not replace that behavior. It can write an optional `inferred_orthologous_res.tsv` table with the same core columns as regulatory orthology inputs, but users must explicitly choose whether to review or reuse that file in later experiments.

## Command

```bash
nextflow run . \
  --run_stage coordinate_projection \
  --regulatory_regions assets/example_samplesheets/regulatory_regions.tsv \
  --genome_alignment_manifest assets/example_samplesheets/genome_alignment_manifest.tsv \
  --coordinate_projection_config assets/example_samplesheets/coordinate_projection_config.tsv \
  --coordinate_projection_stub true
```

`--coordinate_projection_stub true` is the default.

## Regulatory Regions

Default example: `assets/example_samplesheets/regulatory_regions.tsv`

Required columns:

| column | description |
| --- | --- |
| `species` | Source species identifier. |
| `feature_id` | Regulatory-region identifier unique within species. |
| `chrom` | Source chromosome or contig. |
| `start` | Zero-based, inclusive start coordinate. |
| `end` | Zero-based, exclusive end coordinate. Must be greater than `start`. |

Optional columns:

`strand`, `region_type`, `source`, `notes`

## Genome Alignment Manifest

Default example: `assets/example_samplesheets/genome_alignment_manifest.tsv`

Required columns:

| column | description |
| --- | --- |
| `source_species` | Species containing source regulatory regions. |
| `target_species` | Species to project coordinates into. |
| `alignment_id` | Alignment record identifier for the species pair. |

Optional columns:

`chain_file`, `maf_file`, `net_file`, `alignment_type`, `source`, `notes`

Stub mode records these assets as metadata only. Real mode checks that assets required by the configured method exist.

## Projection Config

Default example: `assets/example_samplesheets/coordinate_projection_config.tsv`

Required columns:

| column | description |
| --- | --- |
| `projection_id` | Projection run identifier. |
| `source_species` | Source species with regulatory regions. |
| `target_species` | Target species from the alignment manifest. |
| `method` | Projection method label. |

Allowed method labels:

- `stub`
- `liftover_chain`
- `maf_projection`
- `precomputed_map`

Optional columns:

`min_overlap_fraction`, `reciprocal_required`, `notes`

## Input Preparation

`bin/prepare_coordinate_projection_inputs.py` reads regulatory regions, alignment metadata, and projection config. It validates required columns, BED-style coordinates, duplicate source regions, source species coverage, source-target alignment metadata, and real-mode chain/MAF asset existence.

Outputs:

- `results/coordinate_projection/input/coordinate_projection_manifest.tsv`
- `results/coordinate_projection/input/coordinate_projection_warnings.tsv`

## Stub Mode

Stub mode creates deterministic projected regions and inferred regulatory orthology records without external tools.

Outputs:

- `results/coordinate_projection/projected_regions.tsv`
- `results/coordinate_projection/inferred_orthologous_res.tsv`
- `results/coordinate_projection/projection_warnings.tsv`
- `results/coordinate_projection/summary/coordinate_projection_summary.tsv`
- `results/coordinate_projection/summary/coordinate_projection_outputs_manifest.tsv`

The inferred regulatory orthology table includes one-to-one, many-to-one, ambiguous one-to-many, and failed-projection examples. These records are contract fixtures only and should not be interpreted biologically.

## Real Mode

`--coordinate_projection_stub false` is intentionally conservative. The workflow validates required alignment assets and then fails clearly at placeholder execution unless a production implementation is available.

Potential implementation tools include:

- UCSC `liftOver`
- CrossMap
- HAL tools
- custom MAF projection

The current interface does not install tools, does not run production lift-over, and does not silently emit synthetic real-mode results.

## Ambiguity Handling

Stub outputs use `mapping_class` in `projected_regions.tsv` and `orthology_type` in `inferred_orthologous_res.tsv` to distinguish:

- `one_to_one`
- `many_to_one`
- `one_to_many` ambiguous mappings
- `failed_projection`

Production logic should preserve ambiguous mappings with explicit confidence and notes rather than collapsing them silently.

## Limitations

- Production coordinate projection is not implemented.
- Stub coordinates are deterministic placeholders.
- Input coordinates are validated as zero-based, half-open intervals.
- This interface is optional and is not required by `--run_stage all`.
