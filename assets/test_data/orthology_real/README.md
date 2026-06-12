# Orthology real-tool fixtures

Tiny, format-valid fixtures for `tests/test_orthology_real_tools.sh`, the opt-in
integration test that exercises the reciprocal-best orthology stack against the
**real** UCSC Kent binaries (`liftOver`, `chainSwap`) rather than identity mock
shims. They are intentionally minimal and committed.

The toy "genomes" are a single source contig `src1` and target contig `tgt1`,
each 1000 bp, related by one ungapped block (`src1:0–1000 → tgt1:0–1000`).

| File | Role |
| --- | --- |
| `recip_raw.chain` | Raw chain set (id `1`, `src1`→`tgt1`). |
| `recip_target_net.chain`, `recip_query_net.chain` | Net-derived subsets in both orientations; both retain id `1`, so `define_reciprocal_best_chains.py` yields reciprocal-best `{1}`. |
| `src_reference_fills.bed`, `src_query_fills_projected.bed` | Source-side level-1 fills → `build_callable_mask.py` produces the source callable mask. |
| `tgt_reference_fills.bed`, `tgt_query_fills_projected.bed` | Target-side level-1 fills → target callable mask. |
| `regulatory_regions.tsv` | Source-coordinate regions inside the mapped span. |
| `element_union.bed` | Constituent-element union (source coords, `projection_id::feature_id` names). |
| `coordinate_projection_config.tsv` | Loose-mode projection config (`proj1`, `liftover_chain`). |

The test builds the reciprocal-best chain and callable masks from these with the
Python helpers (Stage A, always runs), then drives `coordinate_projection` real
mode through real `liftOver`/`chainSwap` (Stage B, skipped when the binaries are
absent unless `--strict`). These are toy coordinates for contract/round-trip
validation, not biological data.
