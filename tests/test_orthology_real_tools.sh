#!/usr/bin/env sh
# Opt-in real-tool integration test for the reciprocal-best orthology stack.
#
# Unlike tests/test_reciprocal_best_orthology_nextflow.sh (identity mock shims),
# this test exercises the orchestration + Python engines against the REAL UCSC
# Kent (liftOver, chainSwap) binaries on tiny committed fixtures, so the round-trip
# QC, callable-mask filtering, best-contig selection, and adoption are validated
# against actual coordinate mapping.
#
# Stage A (Python helpers) always runs. Stage B (real lift-over) is gated on the
# binaries: with --strict a missing tool fails; otherwise Stage B is skipped.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FIX="$ROOT_DIR/assets/test_data/orthology_real"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

STRICT=false
[ "${1:-}" = "--strict" ] && STRICT=true
PYTHON=${PYTHON:-python3}

fail() { echo "FAIL: $1" >&2; exit 1; }
assert_file() { [ -s "$1" ] || fail "$2"; }
assert_grep() { grep -q "$1" "$2" || { cat "$2" >&2; fail "$3"; }; }
assert_field() {
  # FILE KEYCOL KEYVAL TARGETCOL EXPECTED MESSAGE
  actual=$(awk -F'\t' -v kc="$2" -v kv="$3" -v tc="$4" 'NR>1 && $kc==kv {print $tc; exit}' "$1")
  [ "$actual" = "$5" ] || { cat "$1" >&2; fail "$6 (expected '$5' got '$actual')"; }
}

# --- Stage A: Python reference-prep helpers (no external tools) -------------
RECIP="$TMP_DIR/recip_best.chain"
"$PYTHON" "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$FIX/recip_target_net.chain" \
  --query-net-chains "$FIX/recip_query_net.chain" \
  --raw-chains "$FIX/recip_raw.chain" \
  --out-chains "$RECIP" > "$TMP_DIR/define.out" 2>&1
assert_file "$RECIP" "reciprocal-best chain not produced"
assert_grep 'src1 1000 + 0 1000 tgt1' "$RECIP" "reciprocal-best chain content unexpected"

SRC_MASK="$TMP_DIR/source_callable.bed"
TGT_MASK="$TMP_DIR/target_callable.bed"
"$PYTHON" "$ROOT_DIR/bin/build_callable_mask.py" \
  --reference-fills "$FIX/src_reference_fills.bed" \
  --query-fills-projected "$FIX/src_query_fills_projected.bed" \
  --out "$SRC_MASK" > "$TMP_DIR/mask_src.out" 2>&1
"$PYTHON" "$ROOT_DIR/bin/build_callable_mask.py" \
  --reference-fills "$FIX/tgt_reference_fills.bed" \
  --query-fills-projected "$FIX/tgt_query_fills_projected.bed" \
  --out "$TGT_MASK" > "$TMP_DIR/mask_tgt.out" 2>&1
assert_grep '^src1	0	1000$' "$SRC_MASK" "source callable mask content unexpected"
assert_grep '^tgt1	0	1000$' "$TGT_MASK" "target callable mask content unexpected"
echo "stage A (python helpers) ok"

# --- Tool gate -------------------------------------------------------------
if ! "$PYTHON" "$ROOT_DIR/bin/check_orthology_tools.py" --lift-tool liftover --mode soft > "$TMP_DIR/tools.out" 2>&1; then
  :
fi
if ! command -v liftOver >/dev/null 2>&1 || ! command -v chainSwap >/dev/null 2>&1; then
  if [ "$STRICT" = true ]; then
    cat "$TMP_DIR/tools.out" >&2
    fail "real-tool mode (--strict) requires liftOver and chainSwap on PATH"
  fi
  echo "SKIP: liftOver/chainSwap not on PATH; Stage B (real lift-over) skipped"
  echo "orthology real-tool tests passed (stage A only; stage B skipped)"
  exit 0
fi

# --- Stage B: real coordinate_projection (loose inputs) --------------------
ALIGN="$TMP_DIR/genome_alignment_manifest.tsv"
printf 'source_species\ttarget_species\talignment_id\tchain_file\talignment_type\n' > "$ALIGN"
printf 'Src_species\tTgt_species\tsrc_to_tgt\t%s\tliftover_chain\n' "$RECIP" >> "$ALIGN"

OUT="$TMP_DIR/results_loose"
nextflow run "$ROOT_DIR" \
  --run_stage coordinate_projection \
  --regulatory_regions "$FIX/regulatory_regions.tsv" \
  --genome_alignment_manifest "$ALIGN" \
  --coordinate_projection_config "$FIX/coordinate_projection_config.tsv" \
  --coordinate_projection_stub false \
  --orthology_lift_tool liftover \
  --orthology_species_callable_mask "$TGT_MASK" \
  --orthology_source_callable_mask "$SRC_MASK" \
  --orthology_source_element_union "$FIX/element_union.bed" \
  --outdir "$OUT" > "$TMP_DIR/nf_loose.out" 2>&1 \
  || { cat "$TMP_DIR/nf_loose.out"; fail "real-tool loose coordinate projection errored"; }

SUMM="$OUT/coordinate_projection/region_orthology_summary.tsv"
PROJ="$OUT/coordinate_projection/projected_regions.tsv"
assert_file "$SUMM" "region summary missing"
# Real liftOver must produce a high-confidence, fully-recovered, element-cored locus.
assert_field "$SUMM" 4 re_0001 30 RETAINED_WITH_ELEMENT "forward status not element-supported under real liftOver"
assert_field "$SUMM" 4 re_0001 31 HIGH_CONFIDENCE "round-trip not HIGH_CONFIDENCE under real liftOver"
assert_field "$SUMM" 4 re_0001 26 1.0000 "window recovery not full under real liftOver"
assert_field "$SUMM" 4 re_0001 33 true "locus not high-confidence primary under real liftOver"
assert_grep 'tgt1' "$PROJ" "projected target contig (tgt1) absent — real liftOver did not map"
echo "stage B (real liftover loose) ok"

# --- Stage B: real bundle path + determinism + resume ----------------------
BDIR="$TMP_DIR/bundle_assets"
mkdir -p "$BDIR"
cp "$RECIP" "$BDIR/recip_best.chain"
cp "$SRC_MASK" "$BDIR/source_callable.bed"
cp "$TGT_MASK" "$BDIR/target_callable.bed"
cp "$FIX/element_union.bed" "$BDIR/element_union.bed"
BUNDLE="$BDIR/orthology_reference_bundle.tsv"
H='schema_version\tbundle_id\tbundle_source\tsource_species\ttarget_species\tsource_assembly\ttarget_assembly\tasset_role\tasset_path\tasset_format\torthology_lift_tool\tvalidation_status\tprojection_id\n'
printf "$H" > "$BUNDLE"
R='orthology_reference_bundle.v1\trb\texternal\tSrc_species\tTgt_species\tsrcA\ttgtA\t%s\t%s\t%s\tliftover\tvalid\tproj1\n'
printf "$R" reciprocal_best_chain recip_best.chain chain >> "$BUNDLE"
printf "$R" source_callable_mask source_callable.bed bed >> "$BUNDLE"
printf "$R" target_callable_mask target_callable.bed bed >> "$BUNDLE"
printf "$R" source_element_union element_union.bed bed >> "$BUNDLE"

B_OUT="$TMP_DIR/results_bundle"
B_WORK="$TMP_DIR/work_bundle"
run_bundle() {
  nextflow run "$ROOT_DIR" "$@" -work-dir "$2" \
    --run_stage coordinate_projection \
    --regulatory_regions "$FIX/regulatory_regions.tsv" \
    --orthology_reference_bundle_manifest "$BUNDLE" \
    --coordinate_projection_stub false \
    --outdir "$1"
}
run_bundle "$B_OUT" "$B_WORK" > "$TMP_DIR/nf_bundle.out" 2>&1 \
  || { cat "$TMP_DIR/nf_bundle.out"; fail "real-tool bundle coordinate projection errored"; }
assert_grep 'HIGH_CONFIDENCE' "$B_OUT/coordinate_projection/region_orthology_summary.tsv" "bundle real run not high-confidence"

B_OUT2="$TMP_DIR/results_bundle_resume"
run_bundle "$B_OUT2" "$B_WORK" -resume > "$TMP_DIR/nf_bundle_resume.out" 2>&1 \
  || { cat "$TMP_DIR/nf_bundle_resume.out"; fail "resumed real-tool bundle run errored"; }
for rel in projected_regions.tsv region_orthology_summary.tsv orthologous_region_blocks.tsv inferred_orthologous_res.tsv; do
  cmp "$B_OUT/coordinate_projection/$rel" "$B_OUT2/coordinate_projection/$rel" \
    || fail "resumed real-tool bundle output differs for $rel"
done
echo "stage B (real bundle + resume determinism) ok"

# --- Stage B: adoption handoff accepted downstream -------------------------
PROMO="$TMP_DIR/promoted"
"$PYTHON" "$ROOT_DIR/bin/promote_orthologous_res.py" \
  --region-summary "$SUMM" \
  --projected-regions "$PROJ" \
  --orthologous-genes "$ROOT_DIR/assets/example_samplesheets/orthologous_genes.tsv" \
  --output-dir "$PROMO" > "$TMP_DIR/promote.out" 2>&1 \
  || { cat "$TMP_DIR/promote.out"; fail "real-tool adoption errored"; }
assert_grep 'OG_RE_RB_Src_species_re_0001' "$PROMO/orthologous_res.adopted.tsv" "adopted stable orthogroup id missing"
assert_grep 'validate_orthology_tables.*accepted' "$PROMO/orthologous_res_promotion_report.tsv" "adopted table not accepted downstream"
echo "stage B (adoption) ok"

echo "orthology real-tool tests passed"
