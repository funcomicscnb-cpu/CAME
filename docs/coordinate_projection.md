# CAME Optional Coordinate Projection

This optional scaffold interface defines input contracts, validation, deterministic stub outputs, and summary manifests for coordinate projection across species.

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

## Orthology Reference Bundle Manifest

Real mode can consume a versioned orthology reference bundle manifest instead of
loose alignment/config files:

```bash
nextflow run . \
  --run_stage coordinate_projection \
  --regulatory_regions regions.tsv \
  --orthology_reference_bundle_manifest orthology_reference_bundle.tsv \
  --coordinate_projection_stub false
```

When `--orthology_reference_bundle_manifest` is supplied, CAME validates the
bundle with `bin/validate_orthology_reference_bundle.py`, generates
`genome_alignment_manifest.from_bundle.tsv` and
`coordinate_projection_config.from_bundle.tsv`, and stages bundle-declared masks,
element-union files, and HAL assets into the projection tasks. The bundle's
`orthology_lift_tool` controls whether the run uses `liftover` or `halliftover`.

Do not mix the bundle interface with loose alignment/config inputs or loose
orthology asset parameters (`orthology_hal_file`,
`orthology_species_callable_mask`, `orthology_source_callable_mask`,
`orthology_source_element_union`). CAME fails clearly on that conflict.

Current bundle consumption is local-file oriented: bundle assets are validated
with local path checks and staged into Nextflow tasks, so remote URI assets are
not supported for projection runs. It also supports only one distinct staged
asset per optional role per run (`source_callable_mask`, `target_callable_mask`,
`source_element_union`, and `hal_alignment`). Multi-pair chain bundles are
accepted, but a multi-target bundle with separate target callable masks must be
split into separate runs until per-pair optional assets are implemented.

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

## Real Mode — Reciprocal-Best Orthologous Regions

`--coordinate_projection_stub false` runs a basic reciprocal-best orthology
pipeline that defines orthologous regions for a starting set of regions from one
or more source species. It is a study-side, query-specific coordinate-projection
analysis owned by CAME; it does not build or modify any CEEG model bundle, and it
never reinterprets a mapping failure as biological absence.

> Full real-mode reference: [reciprocal_best_orthology.md](reciprocal_best_orthology.md)
> documents the method, the reference-preparation helpers
> (`define_reciprocal_best_chains.py`, `build_callable_mask.py`), the complete
> output schemas, the status/QC/structural label vocabularies, the chain-file
> validation contract, and how to run everything end to end. The sections below
> are a summary.

CAME orchestrates the external lift-over tools (Nextflow), while the analyzable
logic — fragment filtering, best-contig selection, round-trip recovery, and
structural classification — lives in dependency-free, unit-tested Python scripts.
If the requested lift-over tool or a required alignment asset is missing, the
workflow fails clearly rather than emitting synthetic results.

### Pipeline

For every region the workflow:

1. forward-projects the region — and, when `orthology_source_element_union` is
   supplied, its constituent elements — into each target species with `liftOver`
   (using the supplied, ideally reciprocal-best, chain; `-multiple` and a
   permissive `-minMatch`) or `halLiftover --noDupes`;
2. filters forward fragments permissively by the query-side callable mask
   (any-overlap retention) when a mask is supplied;
3. when fragments land on more than one target contig, selects one best contig
   by, in order: presence of a fragment overlapping a lifted constituent
   element, total lifted element bp, total retained region length, then fewer
   fragmented pieces;
4. builds a span representation (min–max target coordinate) and a block
   representation (preserving internal fragmentation);
5. back-projects the selected fragments and measures round-trip recovery of the
   original region window and, when `orthology_source_element_union` is
   supplied, the original constituent-element union;
6. assigns a forward-mapping status label, a round-trip QC label, and block-based
   structural metrics, then classifies the locus as `compact`, `fragmented`,
   `hyperfragmented`, or `missing`.

High confidence requires recovering the constituent active core, so it is only
reachable per region when `orthology_source_element_union` is supplied *and* has
element rows matching that region's `projection_id::feature_id`; otherwise a
locus that recovers its window is labelled `WINDOW_ONLY_NO_CORE` and is not
promoted.
The primary lifted regulatory set is defined as loci with high-confidence
round-trip recovery and a non-hyperfragmented structure.

Robustness notes: chain files may be gzipped (`.chain.gz`); a callable-mask or
element-union path that is supplied but missing is treated as an input error,
never as an empty mask or biological absence; round-trip recovery is scored only
against the selected target contig; and the projected strand is taken from the
lifted fragments (reported as `.` when the source strand was unknown).

### Reciprocal-best chain and callable-mask preparation

Two standalone helpers implement the UCSC reciprocal-best preparation steps so
that masks and chains can be produced during reference preparation and supplied
to the projection stage:

- `bin/define_reciprocal_best_chains.py` — intersects the chain identifiers
  retained by the net in both orientations (target-as-reference and
  query-as-reference) and filters the raw chains to that reciprocal-best id set.
- `bin/build_callable_mask.py` — drops sub-threshold fills, merges, and
  intersects the reference-side and projected query-side level-1 net fills to
  produce a conservative callable-orthology mask in reference coordinates.

Generating chains and nets themselves (`halSynteny`, `pslPosTarget`, `axtChain`,
`chainSort`/`chainPreNet`/`chainNet`, `chainSwap`, `netChainSubset`,
`netSyntenic`) is performed with external UCSC/HAL tools and is outside this
optional stage.

### Parameters

| parameter | default | description |
| --- | --- | --- |
| `orthology_lift_tool` | `liftover` | `liftover` (UCSC `liftOver` + `chainSwap`) or `halliftover`. |
| `orthology_liftover_min_match` | `0.1` | `liftOver -minMatch`; permissive so fragmented regulatory mappings survive to QC (`-multiple` is always set). |
| `orthology_hal_file` | `null` | HAL alignment, required for `orthology_lift_tool=halliftover`. |
| `orthology_species_callable_mask` | `null` | Query-side reciprocal-best callable mask (BED, target coordinates). |
| `orthology_source_callable_mask` | `null` | Source-side callable mask (BED, source coordinates). |
| `orthology_source_element_union` | `null` | Original constituent-element union (BED, `projection_id::feature_id` names). |
| `orthology_min_element_recovery_bp` | `50` | Minimum recovered element bp for core recovery. |
| `orthology_min_element_recovery_frac` | `0.5` | Minimum recovered element fraction for core recovery. |
| `orthology_min_window_recovery_frac` | `0.5` | Minimum recovered window fraction for high confidence. |
| `orthology_primary_only` | `false` | Emit only high-confidence non-hyperfragmented loci in the inferred orthology table. |

Required tools: `liftOver` and `chainSwap` for `orthology_lift_tool=liftover`, or
`halLiftover` for `orthology_lift_tool=halliftover`.

For `orthology_lift_tool=halliftover`, the single HAL alignment replaces per-pair
chain/MAF assets: input preparation does not require `chain_file`/`maf_file` and
instead requires `--orthology_hal_file` to exist. Optional masks, the element
union, and the HAL are staged as workflow inputs (via `NO_FILE.*` placeholders
when unset) so content changes invalidate caches and remote executors/containers
can see them.

### Outputs

In addition to the stub-mode outputs, real mode writes:

- `results/coordinate_projection/region_orthology_summary.tsv` — the integrated
  per-region summary (window/element lengths, callable fractions, raw/retained
  fragment counts, competing contigs, span/block metrics, round-trip recovery,
  forward status, round-trip QC, and structural class);
- `results/coordinate_projection/orthologous_region_blocks.tsv` — the block
  representation of each selected locus.

`projected_regions.tsv` and `inferred_orthologous_res.tsv` keep the same schemas
as stub mode.

## Ambiguity Handling

Stub outputs use `mapping_class` in `projected_regions.tsv` and `orthology_type` in `inferred_orthologous_res.tsv` to distinguish:

- `one_to_one`
- `many_to_one`
- `one_to_many` ambiguous mappings
- `failed_projection`

Production logic should preserve ambiguous mappings with explicit confidence and notes rather than collapsing them silently.

## Limitations

- This is a basic implementation, not a production-grade comparative-genomics
  pipeline; full reciprocal-best chain and net generation is not implemented
  within this stage, and stub mode remains a scaffold for contract fixtures.
- Real mode requires the configured external lift-over tools to be installed;
  CAME does not install them.
- Reciprocal-best chain and net construction (`halSynteny`, `axtChain`,
  `chainNet`, `netChainSubset`, `netSyntenic`) is performed outside this stage;
  the stage consumes the resulting chains and optional callable masks.
- Callable masks are optional inputs; without them, forward fragments are
  retained permissively and a less conservative callable definition is used.
- Region exclusion is reported as a status/QC label, never as biological
  absence, and ambiguous multi-contig mappings are resolved explicitly rather
  than collapsed silently.
- Stub coordinates are deterministic placeholders.
- Input coordinates are validated as zero-based, half-open intervals.
- This interface is optional and is not required by `--run_stage all`.
