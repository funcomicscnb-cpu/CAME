# CAME Reciprocal-Best Orthologous Regions

This document describes the **real mode** of the optional `coordinate_projection`
stage: a basic reciprocal-best lift-over pipeline that defines orthologous
regions for a starting set of regions from one or more source species, with
round-trip quality control and structural classification.

It is the detailed companion to [coordinate_projection.md](coordinate_projection.md),
which covers the stage's input contracts, validation, and deterministic stub
mode. Read that first for the shared input formats; this document focuses on the
real-mode method, the reference-preparation helpers, the output contracts, the
status/QC vocabularies, and how to run everything end to end.

This interface is optional and is **not** part of `--run_stage all`. It does not
implement a production comparative-genomics pipeline. It is study-side,
query-specific coordinate projection owned by CAME; it does not build or modify
any CEEG model bundle, and it never reinterprets a mapping failure as biological
absence.

## What It Does

Given regulatory (or other) regions in a source assembly and a pairwise
alignment to one or more target assemblies, the pipeline:

1. projects each region forward into the target assembly,
2. when a query-side callable mask is supplied, keeps only fragments that fall in
   conservative callable-orthology space (otherwise all forward fragments are
   retained permissively),
3. resolves regions that scatter across multiple target contigs to a single
   best locus,
4. projects the selected locus back to the source assembly and measures how much
   of the original region (and its active core) is recovered after the round
   trip, and
5. labels each locus with a forward-mapping status, a round-trip QC verdict, and
   a block-based structural class.

The method follows the UCSC reciprocal-best chain/net framework. CAME owns the
study-side projection and QC; constructing the reciprocal-best chains and
callable masks is a reference-preparation step (see
[Reference preparation](#reference-preparation-chains-and-callable-masks)).

## Architecture

Per the CAME execution model, Nextflow orchestrates the external lift-over tools
while all analyzable logic lives in dependency-free, unit-tested Python so the
default CI never needs genomics binaries.

| Component | Kind | Role |
| --- | --- | --- |
| `subworkflows/liftover_projection.nf` | Nextflow | Orchestrates per-pair forward/back lift-over, builds fragment BEDs, runs the engine. |
| `subworkflows/regulatory_orthology_inference.nf` | Nextflow | Runs the classifier to emit the inferred orthology table. |
| `bin/manifest_to_region_bed.py` | Python | Reshapes the prepared manifest into lift-ready per-pair region BEDs. |
| `bin/project_orthologous_regions.py` | Python | The engine: mask filtering, best-contig selection, span/block, round-trip QC, structural class. |
| `bin/classify_orthologous_regions.py` | Python | Builds `inferred_orthologous_res.tsv` from the per-region summary. |
| `bin/define_reciprocal_best_chains.py` | Python | Reference-prep helper: reciprocal-best chain-id intersection + filtering. |
| `bin/build_callable_mask.py` | Python | Reference-prep helper: callable-mask intersection from level-1 net fills. |
| `bin/orthology_intervals.py` | Python | Shared interval/BED/chain library used by the above. |

## Command

```bash
nextflow run . \
  --run_stage coordinate_projection \
  --regulatory_regions assets/example_samplesheets/regulatory_regions.tsv \
  --genome_alignment_manifest assets/example_samplesheets/genome_alignment_manifest.tsv \
  --coordinate_projection_config assets/example_samplesheets/coordinate_projection_config.tsv \
  --coordinate_projection_stub false \
  --orthology_lift_tool liftover \
  --orthology_species_callable_mask references/masks/species_callable.bed \
  --orthology_source_callable_mask references/masks/source_callable.bed \
  --orthology_source_element_union references/elements/element_union.bed
```

Real mode requires the configured lift-over tools on `PATH` (CAME does not
install them) plus the alignment asset for the chosen tool: for
`orthology_lift_tool=liftover`, the per-pair `chain_file` referenced by the
manifest; for `halliftover`, the single `--orthology_hal_file` HAL (per-pair
`chain_file`/`maf_file` are not required). If a required tool or asset is
missing, the workflow fails clearly rather than emitting synthetic results.

## Parameters

All parameters are optional and default to the values below. They are defined in
`nextflow.config`.

| parameter | default | description |
| --- | --- | --- |
| `orthology_reference_bundle_manifest` | `null` | Versioned orthology reference bundle manifest. When supplied, CAME validates it and derives the alignment/config inputs plus optional masks/HAL assets from the bundle. |
| `orthology_lift_tool` | `liftover` | `liftover` (UCSC `liftOver` + `chainSwap`) or `halliftover` (`halLiftover`). |
| `orthology_liftover_min_match` | `0.1` | `liftOver -minMatch`; deliberately permissive so fragmented regulatory mappings survive to QC. `-multiple` is always set. |
| `orthology_hal_file` | `null` | HAL alignment path; required when `orthology_lift_tool=halliftover`. |
| `orthology_species_callable_mask` | `null` | Query-side (target-coordinate) reciprocal-best callable mask, BED. |
| `orthology_source_callable_mask` | `null` | Source-side (source-coordinate) callable mask, BED. |
| `orthology_source_element_union` | `null` | Original constituent-element union, BED named `projection_id::feature_id`. |
| `orthology_min_element_recovery_bp` | `50` | Minimum recovered element bp for active-core recovery. |
| `orthology_min_element_recovery_frac` | `0.5` | Minimum recovered element fraction for active-core recovery. |
| `orthology_min_window_recovery_frac` | `0.5` | Minimum recovered window fraction for high confidence. |
| `orthology_primary_only` | `false` | If `true`, the inferred orthology table contains only high-confidence non-hyperfragmented primary loci. |

The block-based structural-class thresholds (`compact`/`hyperfragmented`
cut-offs) are fixed at the engine defaults in the Nextflow stage and are only
adjustable when invoking `project_orthologous_regions.py` directly:
`--compact-density 0.8`, `--hyperfragmented-density 0.5`,
`--hyperfragmented-pieces 8`, `--hyperfragmented-components 3`.

### Lift tool selection

- `liftover` — projects through a UCSC chain (`chain_file` per pair) and
  back-projects through its `chainSwap`-swapped chain. Requires `liftOver` and
  `chainSwap`. The manifest `method` must be `liftover_chain` or
  `precomputed_map`; `maf_projection` is rejected at input preparation because
  the `liftOver` executor cannot run MAF projection.
- `halliftover` — projects with `halLiftover --noDupes` through a single HAL
  (`--orthology_hal_file`). Per-pair `chain_file`/`maf_file` assets are not
  required; input preparation instead requires the HAL to exist. The HAL is
  staged into the preparation and projection tasks so the existence check is
  portable to remote/containerized executors and is part of the task cache key.

When `orthology_reference_bundle_manifest` is supplied, the bundle's
`orthology_lift_tool` value selects the executor and CAME ignores the loose
alignment/config inputs. Mixing the bundle manifest with loose orthology assets
or custom loose alignment/config files is rejected.

Bundle consumption is currently local-file oriented and stages assets into
Nextflow tasks. Remote URI assets are not supported for projection runs. The
adapter also supports only one distinct staged asset per optional role per run:
one source callable mask, one target callable mask, one source element union,
and one HAL file. Multi-pair chain bundles are accepted when these optional
assets are shared or absent; bundles with separate target masks per species
should be split into separate runs until per-pair optional assets are supported.

## Inputs

The three primary samplesheets (`regulatory_regions`, `genome_alignment_manifest`,
`coordinate_projection_config`) are documented in
[coordinate_projection.md](coordinate_projection.md). Real mode adds three
optional reference files.

### Callable masks (`orthology_species_callable_mask`, `orthology_source_callable_mask`)

Plain BED (`.bed` or `.bed.gz`) of conservative callable-orthology space:

- the **species/query-side** mask is in *target* coordinates and is used to
  filter forward fragments;
- the **source-side** mask is in *source* coordinates and is used to compute the
  source callable fraction (and to flag regions that fall outside callable space
  as `NOT_CALLABLE_IN_SOURCE`).

Masks are optional. Without the species-side mask, forward fragments are retained
permissively (a less conservative callable definition). A mask path that is
supplied but missing, or that contains data rows that do not all parse as valid
BED, is an **input error** — never silently treated as an empty mask.

### Constituent-element union (`orthology_source_element_union`)

Plain BED in *source* coordinates whose name (column 4) is `projection_id::feature_id`,
giving the experimentally supported active promoter/enhancer core for each
region. When supplied:

- it is lifted forward per pair to provide the element-overlap signal used in
  best-contig selection, and
- it is the denominator for active-core round-trip recovery.

High confidence requires active-core recovery, so it is only reachable **per
region**: the file must be supplied *and* contain element rows whose name matches
that region's `projection_id::feature_id`. A region with no matching element rows
is treated exactly as if no element union were supplied — a locus that recovers
its window is labelled `WINDOW_ONLY_NO_CORE` and is never promoted to the primary
set.

### Reserved identifier delimiters

Because fragment BED names encode provenance as `projection_id::feature_id` with
an optional `@@<contig>` suffix, `projection_id` and `feature_id` must not
contain `::` or `@@`. Input preparation rejects regions/config rows that do.

## Reference preparation: chains and callable masks

The reciprocal-best chains and callable masks consumed by the stage are produced
during reference preparation with external UCSC/HAL tools, then post-processed by
two standalone CAME helpers. The external steps (out of scope for this stage)
are, per species pair:

1. `halSynteny` (or pairwise aligner) → PSL of syntenic anchors,
2. `pslPosTarget` → `axtChain` (medium linear gap) → `chainSort`/`chainPreNet`/`chainNet`,
3. `chainSwap` + reciprocal nets in both orientations,
4. `netChainSubset` to extract the chains each net retains,
5. `netSyntenic` + level-1 fill extraction for the callable masks.

### `bin/define_reciprocal_best_chains.py`

Defines the reciprocal-best chain set as the **intersection of chain identifiers**
retained by the net in both orientations, then filters the raw chains to that id
set.

```bash
python3 bin/define_reciprocal_best_chains.py \
  --target-net-chains target_as_reference.netchains.chain \
  --query-net-chains  query_as_reference.netchains.chain \
  --raw-chains        raw.chain \
  --out-chains        reciprocal_best.chain \
  --out-ids           reciprocal_best_ids.txt   # optional
```

| argument | required | description |
| --- | --- | --- |
| `--target-net-chains` | yes | `netChainSubset` output, target-as-reference orientation. |
| `--query-net-chains` | yes | `netChainSubset` output, query-as-reference orientation. |
| `--raw-chains` | yes | Original raw chain file to filter. |
| `--out-chains` | yes | Reciprocal-best chain output (parent directories created as needed). |
| `--out-ids` | no | Optional list of reciprocal-best chain ids, one per line. |

Behavior and exit codes:

- All inputs are validated **before** any output is written, so a fatal error
  never leaves partial/inconsistent artifacts.
- An empty intersection is valid: it writes empty outputs, prints a warning, and
  exits `0`.
- Exit `1` (no outputs written) on: a missing input; a non-empty file with no
  chain headers; a structurally invalid chain header or body record (see
  [Chain-file validation](#chain-file-validation)); duplicate chain ids within
  any input; or a reciprocal-best id that is absent from the raw chain (an
  input-mismatch signal).
- `.chain.gz` inputs are read transparently.

### `bin/build_callable_mask.py`

Builds a conservative callable-orthology mask in reference coordinates as the
intersection of the reference-side level-1 net fills and the query-side level-1
fills already projected (via `liftOver`) into reference coordinates.

```bash
python3 bin/build_callable_mask.py \
  --reference-fills        reference_level1.bed \
  --query-fills-projected  query_level1_projected_to_reference.bed \
  --min-fragment 50 \
  --out callable_mask.bed
```

| argument | required | default | description |
| --- | --- | --- | --- |
| `--reference-fills` | yes | | Reference-side level-1 reciprocal-best net fills (BED, reference coords). |
| `--query-fills-projected` | yes | | Query-side level-1 fills projected to reference coordinates (BED). |
| `--min-fragment` | no | `50` | Drop fills shorter than this many bp before merging/intersecting. |
| `--out` | yes | | Output callable-mask BED (merged intersection). |

Sub-threshold fills are discarded, each side is merged, and the intersection is
written. A missing or malformed (data rows that do not all parse) input is an
error, not an empty mask. Retained bases are top-level reciprocal-best syntenic
space supported from both directional definitions; exclusion does **not** imply
absence of homology.

## Pipeline (real mode)

For each `(projection_id, source_feature_id, target_species)` record the engine:

1. **Forward projection.** Lifts the region (and, when the element union is
   supplied, its elements) into the target assembly with `liftOver -minMatch=<param> -multiple`
   or `halLiftover --noDupes`.
2. **Source callable check.** If a source-side mask is supplied and the region
   has zero overlap with it, the region is `NOT_CALLABLE_IN_SOURCE` (failed).
3. **Permissive mask filtering.** Forward fragments are retained if they have
   *any* overlap with the species-side callable mask (boundary-overlapping or
   fragmented mappings are not discarded prematurely). Without a mask, all
   fragments are retained.
4. **Best-contig selection.** When retained fragments land on more than one
   target contig, one contig is selected by, in order: presence of a fragment
   overlapping a lifted element; total lifted element bp; total retained region
   length; then fewer fragmented pieces. Competition is recorded as
   `MULTICONTIG_RESOLVED`.
5. **Span and block representations.** The span is the min–max target coordinate
   on the selected contig; the block representation is the merged fragments,
   preserving internal fragmentation.
6. **Round-trip recovery.** The selected fragments are back-projected to source
   coordinates (restricted to the selected contig via the `@@<contig>` name tag)
   and intersected with the original region window and the original element
   union to compute window/element recovery.
7. **Labels.** A forward-mapping status, a round-trip QC verdict, and a
   structural class are assigned (see below).

The **primary lifted regulatory set** is the loci with `roundtrip_qc =
HIGH_CONFIDENCE` and a non-hyperfragmented, non-missing structure.

### Forward-mapping status (`forward_status`)

| value | meaning |
| --- | --- |
| `NOT_CALLABLE_IN_SOURCE` | Region has no overlap with the source-side callable mask. |
| `NO_FORWARD_MAPPING` | No forward lift-over fragments were produced. |
| `RAW_ONLY_FAILED_MASK` | Fragments were produced but none passed the species-side mask filter. |
| `MULTICONTIG_RESOLVED` | Retained fragments competed across contigs; one was selected. |
| `RETAINED_WITH_ELEMENT` | Single-contig locus with a fragment overlapping a lifted element. |
| `RETAINED_CALLABLE` | Single-contig retained locus without element support. |

### Round-trip QC (`roundtrip_qc`)

| value | meaning |
| --- | --- |
| `NO_LOCUS` | No locus was selected (a failed forward status). |
| `NO_BACKLIFT` | No back-lifted fragments on the selected contig. |
| `CORE_NOT_RECOVERED` | Matching element-union rows exist for this region, but the active core was not recovered. |
| `LOW_RECOVERY` | Window recovery below `orthology_min_window_recovery_frac`. |
| `WINDOW_ONLY_NO_CORE` | Window recovered, but this region has no matching element-union rows to confirm the active core; not promoted. |
| `HIGH_CONFIDENCE` | Back-lift succeeded, window recovered, and active core recovered. |

### Structural class (`structural_class`)

Computed from the selected blocks:

| value | rule (defaults) |
| --- | --- |
| `missing` | No selected blocks. |
| `hyperfragmented` | `block_density < 0.5`, or `selected_piece_count > 8`, or `mask_components_overlapped > 3`. |
| `compact` | `block_density >= 0.8` and `mask_components_overlapped <= 1`. |
| `fragmented` | Anything else (partial discontinuity, still interpretable). |

`block_density` is `selected_block_union_len / selected_span_len`.

## Outputs

All published under `results/coordinate_projection/`.

### `projected_regions.tsv`

One row per region (the selected span). Same schema as stub mode.

`projection_id`, `source_species`, `target_species`, `source_feature_id`,
`projected_feature_id`, `source_chrom`, `source_start`, `source_end`,
`target_chrom`, `target_start`, `target_end`, `strand`, `region_type`,
`alignment_id`, `method`, `projection_status` (`OK`/`FAILED`),
`overlap_fraction` (window recovered fraction), `mapping_class`
(`one_to_one`/`ambiguous`/`failed_projection`), `notes`
(`forward_status|roundtrip_qc|structural_class`).

`strand` is the projected strand taken from the lifted fragments, or `.` when the
source strand was unknown or the fragments disagree.

### `region_orthology_summary.tsv`

The integrated per-region summary (real mode only). Columns:

| column | description |
| --- | --- |
| `projection_id`, `source_species`, `target_species`, `source_feature_id`, `region_type` | Record identity. |
| `source_chrom`, `source_start`, `source_end`, `source_window_len` | Original region window. |
| `source_element_union_len` | Total bp of the original constituent-element union for this region (blank when no element union was supplied *or* no element rows match this region's `projection_id::feature_id`). |
| `source_callable_fraction` | Fraction of the window within the source-side callable mask (blank if no mask). |
| `raw_fragment_count` | Forward fragments before mask filtering. |
| `retained_fragment_count` | Forward fragments retained after mask filtering. |
| `competing_target_contigs` | Number of target contigs with retained fragments. |
| `selected_target_contig`, `selected_piece_count` | Chosen contig and its fragment count. |
| `selected_span_len`, `selected_block_union_len` | Span length and merged block length. |
| `block_density` | `selected_block_union_len / selected_span_len`. |
| `mean_fragment_len`, `piece_redundancy` | Mean selected fragment length; overlap redundancy among pieces. |
| `species_mask_support_fraction` | Block bp overlapping the species mask / block union (blank if no mask). |
| `mask_components_overlapped` | Distinct mask components the blocks touch (blank if no mask). |
| `backlift_fragment_count` | Back-lifted fragments on the selected contig. |
| `window_recovered_bp`, `window_recovered_fraction` | Round-trip recovery of the window. |
| `element_recovered_bp`, `element_recovered_fraction` | Round-trip recovery of the element union (blank when no element union was supplied *or* no element rows match this region's `projection_id::feature_id`). |
| `core_recovered` | `true`/`false`/`na` (na when this region has no matching element-union rows). |
| `forward_status`, `roundtrip_qc`, `structural_class` | Label vocabularies above. |
| `high_confidence_primary` | `true` if `HIGH_CONFIDENCE` and non-hyperfragmented/non-missing. |

### `orthologous_region_blocks.tsv`

The block representation of each selected locus, one row per block:
`projection_id`, `source_species`, `target_species`, `source_feature_id`,
`block_index`, `target_chrom`, `target_start`, `target_end`, `length`.

### `inferred_orthologous_res.tsv`

Built by the classifier from the per-region summary, in the same schema as CAME
regulatory-orthology inputs (`orthologous_res.tsv`). Loci classified `missing`
are excluded; with `--orthology_primary_only` only high-confidence
non-hyperfragmented loci are emitted. Two rows per locus (source anchor and
projected span) sharing an `orthogroup_id` of `OG_RE_RB_<projection_id>_<feature_id>`.

Columns: `species`, `feature_id`, `orthogroup_id`, `chrom`, `start`, `end`,
`human_anchor_region`, `re_type`, `orthology_type` (`one_to_one`/`one_to_many`),
`orthology_confidence` (`high`/`medium`/`low`), `source`
(`reciprocal_best_orthology`), `notes`.

`orthology_confidence` is `high` for primary loci, `medium` when
`roundtrip_qc` is `HIGH_CONFIDENCE` or `LOW_RECOVERY`, else `low`.

### `projection_warnings.tsv`

`severity`, `projection_id`, `source_feature_id`, `target_species`, `message`.

### `summary/`

`coordinate_projection_summary.tsv` (run metrics) and
`coordinate_projection_outputs_manifest.tsv` (output inventory, including the
real-mode `region_orthology_summary` and `orthologous_region_blocks` artifacts).

## Internal fragment-name contract

The orchestration encodes provenance in BED names so the engine can key
fragments and restrict round-trip recovery to the selected contig:

- forward/element fragments: name = `projection_id::feature_id`;
- back-lift fragments: name = `projection_id::feature_id@@<origin_target_contig>`.

`bin/manifest_to_region_bed.py` emits the per-pair region BEDs (BED6, so lift
tools can flip strand) and a `chains.tsv` index; it fills empty optional fields
with a `.` sentinel so tab-delimited shell `read` does not collapse columns.

## Chain-file validation

`define_reciprocal_best_chains.py` validates inputs structurally (it does **not**
verify block-size arithmetic against the header span — that full chain
verification is out of scope for an id-filtering helper). A file is rejected if:

- a header-looking line (first token `chain`) is not a valid 13-field UCSC header
  with an integer score, non-negative integer sizes/coordinates satisfying
  `0 <= start <= end <= size` on both sides, `+`/`-` strands, and a non-empty id;
- a chain block is not a header followed by zero or more 3-field `size dt dq`
  rows and exactly one 1-field `size` final row before a blank line/EOF/next
  header (a body-less header, a missing final row, or a row after the final row
  are all rejected);
- a `track`/`browser`/comment metadata line appears inside a block (metadata is
  allowed only before the first header or between blank-separated blocks, and is
  never copied into the filtered output);
- a chain id appears more than once (ids are unique and are the reciprocal-best
  join key).

`track`/`browser` are recognized only as whole leading tokens, so content such as
`tracking ...` is treated as data, not silently skipped as metadata.

## Tools required (real mode)

| `orthology_lift_tool` | required tools |
| --- | --- |
| `liftover` | UCSC `liftOver`, `chainSwap` |
| `halliftover` | `halLiftover` |

Reference preparation additionally uses external UCSC/HAL tools (`halSynteny`,
`axtChain`, `chainNet`, `netChainSubset`, `netSyntenic`, etc.). CAME does not
install any of these.

## Testing

Default CI is independent of genomics binaries:

- `tests/test_reciprocal_best_orthology.sh` — mock-driven unit tests for all
  Python components (interval ops, reciprocal-best chains, callable masks, the
  projection engine, the classifier, and input validation), run on fixture
  BED/chain files under `tests/fixtures/orthology/`. Wired into default CI.
- `tests/test_reciprocal_best_orthology_nextflow.sh` — end-to-end real-mode
  `liftover` run using mock `liftOver`/`chainSwap` shims (identity mappers), so
  the full orchestration is exercised without UCSC Kent tools.
- `tests/test_reciprocal_best_orthology_hal.sh` — end-to-end real-mode
  `halliftover` run using a mock `halLiftover` shim, also covering a launch-dir
  relative HAL path and projected-strand preservation.

The two Nextflow mock tests require Java/Nextflow and run in the CI
end-to-end-stub job.

## Boundary and ownership

This stage is CAME-owned, query-specific coordinate projection. It must not be
confused with CEEG model building. In particular:

- a region excluded here is reported as a status/QC label, never as biological
  absence, sequence loss, or non-conservation;
- ambiguous multi-contig mappings are resolved explicitly and recorded, never
  collapsed silently;
- the inferred orthology table is an optional artifact that users explicitly
  choose to review or reuse; it does not feed candidate prioritization, GRA, or
  phenotype-omics integration automatically.

## Limitations

- This is a basic implementation, not a production-grade comparative-genomics
  pipeline; full reciprocal-best chain and net generation is not implemented
  within this stage.
- Real mode requires the configured external lift-over tools; CAME does not
  install them.
- Callable masks and the element union are optional. Without a species-side
  callable mask the callable definition is less conservative; and without
  matching `projection_id::feature_id` element-union rows for a region, high
  confidence is not reachable for that region.
- Structural-class thresholds are fixed at engine defaults in the Nextflow stage.
- Chain validation is structural only; block-size arithmetic is not verified.
- This interface is optional and is not required by `--run_stage all`.
