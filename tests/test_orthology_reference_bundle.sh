#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PYTHON=${PYTHON:-python3}
FIXTURE_DIR="$ROOT_DIR/assets/test_data/orthology_reference_bundle"
VALIDATOR="$ROOT_DIR/bin/validate_orthology_reference_bundle.py"
ADAPTER="$ROOT_DIR/bin/prepare_coordinate_projection_bundle_inputs.py"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_file() {
  [ -s "$1" ] || fail "$2"
}

assert_grep() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if ! grep -Eq "$pattern" "$file"; then
    cat "$file" >&2
    fail "$message"
  fi
}

assert_no_grep() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if grep -Eq "$pattern" "$file"; then
    cat "$file" >&2
    fail "$message"
  fi
}

mutate_manifest() {
  "$PYTHON" - "$1" "$2" "$3" <<'PY'
import csv
import sys

src, dst, op = sys.argv[1:4]
rows = list(csv.DictReader(open(src), delimiter="\t"))
fields = list(rows[0].keys())
if op == "came_missing_provenance":
    rows[0]["params_hash"] = ""
elif op == "missing_asset":
    rows[0]["asset_path"] = "alignments/missing.chain"
elif op == "bad_version":
    rows[0]["schema_version"] = "orthology_reference_bundle.v0"
elif op == "bad_role":
    rows[0]["asset_role"] = "not_a_role"
elif op == "bad_format":
    rows[0]["asset_format"] = "bam"
elif op == "duplicate_conflict":
    duplicate = dict(rows[0])
    duplicate["asset_path"] = "masks/mmus.callable.bed"
    rows.append(duplicate)
elif op == "no_hal":
    rows = [row for row in rows if row["asset_role"] != "hal_alignment"]
elif op == "no_chain":
    rows = [row for row in rows if row["asset_role"] != "reciprocal_best_chain"]
elif op == "header_only":
    rows = []
else:
    raise SystemExit(f"unknown op: {op}")
with open(dst, "w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
PY
}

run_valid() {
  local manifest="$1"
  local outdir="$2"
  "$PYTHON" "$VALIDATOR" \
    --manifest "$manifest" \
    --outdir "$outdir" \
    --check-paths true > "$outdir.log" 2>&1
  assert_file "$outdir/orthology_reference_bundle_validation.tsv" "validation table missing for $manifest"
  assert_file "$outdir/orthology_reference_bundle_warnings.tsv" "warnings table missing for $manifest"
  assert_no_grep '^ERROR	' "$outdir/orthology_reference_bundle_validation.tsv" "valid bundle emitted ERROR rows"
}

run_invalid() {
  local manifest="$1"
  local outdir="$2"
  local pattern="$3"
  local message="$4"
  if "$PYTHON" "$VALIDATOR" \
    --manifest "$manifest" \
    --outdir "$outdir" \
    --check-paths true > "$outdir.log" 2>&1; then
    cat "$outdir/orthology_reference_bundle_validation.tsv" >&2
    fail "$message"
  fi
  assert_file "$outdir/orthology_reference_bundle_validation.tsv" "negative case did not write validation table"
  assert_grep "$pattern" "$outdir/orthology_reference_bundle_validation.tsv" "$message"
  assert_no_grep 'Traceback' "$outdir.log" "negative case produced traceback"
}

EXT="$FIXTURE_DIR/manifest_external_liftover.tsv"
CAME="$FIXTURE_DIR/manifest_came_generated_liftover.tsv"
HAL="$FIXTURE_DIR/manifest_external_halliftover.tsv"

run_valid "$EXT" "$TMP_DIR/external_liftover"
assert_grep 'WARNING	.*provenance	OPTIONAL_MISSING' "$TMP_DIR/external_liftover/orthology_reference_bundle_warnings.tsv" "external provenance omission warning absent"

SEQ_OUT="$TMP_DIR/external_with_seqname"
"$PYTHON" "$VALIDATOR" \
  --manifest "$EXT" \
  --outdir "$SEQ_OUT" \
  --check-paths true \
  --seqname-reference-manifest "$ROOT_DIR/assets/test_data/reference_quality/reference_manifest.tsv" > "$TMP_DIR/external_with_seqname.log" 2>&1
assert_file "$SEQ_OUT/seqname_concordance/seqname_concordance.tsv" "seqname concordance report missing when reference manifest supplied"
assert_no_grep '^ERROR	' "$SEQ_OUT/orthology_reference_bundle_validation.tsv" "valid bundle with seqname check emitted ERROR rows"

run_valid "$CAME" "$TMP_DIR/came_liftover"
assert_no_grep 'provenance' "$TMP_DIR/came_liftover/orthology_reference_bundle_validation.tsv" "CAME-generated fixture should provide required provenance"

run_valid "$HAL" "$TMP_DIR/external_hal"
assert_grep 'hal_alignment	asset_path	OK' "$TMP_DIR/external_hal/orthology_reference_bundle_validation.tsv" "valid HAL asset row absent"

"$PYTHON" "$ADAPTER" \
  --bundle-manifest "$EXT" \
  --output-dir "$TMP_DIR/liftover_adapter" > "$TMP_DIR/liftover_adapter.log" 2>&1
assert_grep 'reciprocal_best_chain' "$TMP_DIR/liftover_adapter/genome_alignment_manifest.from_bundle.tsv" "adapter did not emit reciprocal-best chain alignment"
assert_grep 'liftover_chain' "$TMP_DIR/liftover_adapter/coordinate_projection_config.from_bundle.tsv" "adapter did not emit liftover_chain config"
assert_grep '^liftover$' "$TMP_DIR/liftover_adapter/effective_orthology_lift_tool.txt" "adapter did not record liftover effective tool"
assert_grep '^source_mask	true	' "$TMP_DIR/liftover_adapter/orthology_reference_bundle_asset_selectors.tsv" "adapter did not select source mask"
assert_file "$TMP_DIR/liftover_adapter/opt_source_mask/mmus.callable.bed" "adapter did not stage source mask"

"$PYTHON" "$ADAPTER" \
  --bundle-manifest "$HAL" \
  --output-dir "$TMP_DIR/hal_adapter" > "$TMP_DIR/hal_adapter.log" 2>&1
assert_grep 'hal_alignment' "$TMP_DIR/hal_adapter/genome_alignment_manifest.from_bundle.tsv" "adapter did not emit HAL alignment metadata"
assert_grep 'precomputed_map' "$TMP_DIR/hal_adapter/coordinate_projection_config.from_bundle.tsv" "adapter did not emit HAL-compatible config"
assert_grep '^halliftover$' "$TMP_DIR/hal_adapter/effective_orthology_lift_tool.txt" "adapter did not record halliftover effective tool"
assert_file "$TMP_DIR/hal_adapter/opt_hal/mmus_drer.hal" "adapter did not stage HAL asset"

mutate_manifest "$CAME" "$TMP_DIR/came_missing_provenance.tsv" came_missing_provenance
run_invalid "$TMP_DIR/came_missing_provenance.tsv" "$TMP_DIR/came_missing_provenance" 'CAME-generated bundle requires provenance field: params_hash' "CAME-generated missing provenance should fail"

mutate_manifest "$EXT" "$TMP_DIR/missing_asset.tsv" missing_asset
run_invalid "$TMP_DIR/missing_asset.tsv" "$TMP_DIR/missing_asset" 'Declared asset_path does not exist' "missing asset should fail when check-paths=true"

mutate_manifest "$EXT" "$TMP_DIR/bad_version.tsv" bad_version
run_invalid "$TMP_DIR/bad_version.tsv" "$TMP_DIR/bad_version" 'Unsupported schema_version' "unsupported schema_version should fail"

mutate_manifest "$EXT" "$TMP_DIR/bad_role.tsv" bad_role
run_invalid "$TMP_DIR/bad_role.tsv" "$TMP_DIR/bad_role" 'Unsupported asset_role' "unsupported asset_role should fail"

mutate_manifest "$EXT" "$TMP_DIR/bad_format.tsv" bad_format
run_invalid "$TMP_DIR/bad_format.tsv" "$TMP_DIR/bad_format" 'Unsupported asset_format' "unsupported asset_format should fail"

mutate_manifest "$EXT" "$TMP_DIR/duplicate_conflict.tsv" duplicate_conflict
run_invalid "$TMP_DIR/duplicate_conflict.tsv" "$TMP_DIR/duplicate_conflict" 'Conflicting duplicate rows' "conflicting duplicate role should fail"

mutate_manifest "$HAL" "$TMP_DIR/no_hal.tsv" no_hal
run_invalid "$TMP_DIR/no_hal.tsv" "$TMP_DIR/no_hal" 'halliftover requires exactly one hal_alignment' "halliftover bundle without HAL should fail"

mutate_manifest "$EXT" "$TMP_DIR/no_chain.tsv" no_chain
run_invalid "$TMP_DIR/no_chain.tsv" "$TMP_DIR/no_chain" 'liftover requires a reciprocal_best_chain' "liftover bundle without chain should fail"

mutate_manifest "$EXT" "$TMP_DIR/header_only.tsv" header_only
run_invalid "$TMP_DIR/header_only.tsv" "$TMP_DIR/header_only" 'Manifest has no asset rows' "header-only manifest should fail"

echo "orthology reference bundle tests passed"
