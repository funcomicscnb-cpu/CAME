#!/usr/bin/env sh
# CAME-I2: mock CEEG validator for unit and integration tests.
# Simulates bin/run_came_overlay.py and bin/run_mapping_contract.py behavior.
# Never writes outside --out-dir. Never requires a CEEG checkout.
#
# Usage:
#   mock_ceeg_validator.sh --mode <mode> --run-dir <dir> --out-dir <dir>
#                          [--validation-mode <mode>] [--created-at <ts>]
#
# Modes:
#   r2_success     - writes R2 success artifacts (manifest + summary), exits 0
#   r2_invalid     - writes R2 invalid artifacts (manifest + summary), exits 1
#   r2_fatal       - writes R2 fatal artifact (manifest only), exits 2
#   r2_no_manifest - writes no manifest, exits 0
#   r2_bad_exit    - writes no manifest, exits 99
#   r3_success     - writes R3 success artifacts, exits 0
#   r3_invalid     - writes R3 invalid artifact (manifest only), exits 1
#   r3_no_manifest - writes no manifest, exits 1
set -eu

MODE=""
OUT_DIR=""
CREATED_AT="2026-05-11T00:00:00Z"

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)           MODE="$2";       shift 2 ;;
    --out-dir)        OUT_DIR="$2";    shift 2 ;;
    --run-dir)                         shift 2 ;;
    --validation-mode)                 shift 2 ;;
    --created-at)     CREATED_AT="$2"; shift 2 ;;
    *) printf 'mock_ceeg_validator: unknown argument: %s\n' "$1" >&2; shift ;;
  esac
done

if [ -z "$MODE" ]; then
  printf 'mock_ceeg_validator: --mode is required\n' >&2
  exit 1
fi
if [ -z "$OUT_DIR" ]; then
  printf 'mock_ceeg_validator: --out-dir is required\n' >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

case "$MODE" in
  r2_success)
    cat > "$OUT_DIR/came_report_manifest.json" <<EOF
{"run_id":"mock_r2_run_001","validator_name":"came_overlay_validator","validator_version":"0.1.0","validation_mode":"development","status":"compatible","exit_code":0,"ceeg_enabled":true,"overlay_mode":"report_only","output_files":["came_report_manifest.json","compatibility_summary.json"],"created_at":"${CREATED_AT}"}
EOF
    cat > "$OUT_DIR/compatibility_summary.json" <<EOF
{"validator_name":"came_overlay_validator","validator_version":"0.1.0","validation_mode":"development","strict":false,"run_id":"mock_r2_run_001","ceeg_enabled":true,"overlay_mode":"report_only","ceeg_bundle_path":"/mock/ceeg_bundle","ceeg_bundle_status":"valid","ceeg_schema_version":"0.1.0","ceeg_contract_version":"0.1.0","compatibility_result":"compatible","warnings_count":0,"exit_code":0,"created_at":"${CREATED_AT}"}
EOF
    exit 0
    ;;
  r2_invalid)
    cat > "$OUT_DIR/came_report_manifest.json" <<EOF
{"run_id":"mock_r2_invalid_001","validator_name":"came_overlay_validator","validator_version":"0.1.0","validation_mode":"development","status":"invalid","exit_code":1,"ceeg_enabled":true,"overlay_mode":"report_only","output_files":["came_report_manifest.json","compatibility_summary.json"],"created_at":"${CREATED_AT}"}
EOF
    cat > "$OUT_DIR/compatibility_summary.json" <<EOF
{"validator_name":"came_overlay_validator","validator_version":"0.1.0","validation_mode":"development","strict":false,"run_id":"mock_r2_invalid_001","ceeg_enabled":true,"overlay_mode":"report_only","ceeg_bundle_path":"/mock/ceeg_bundle","ceeg_bundle_status":"invalid","ceeg_schema_version":"0.1.0","ceeg_contract_version":"0.1.0","compatibility_result":"invalid","warnings_count":1,"exit_code":1,"created_at":"${CREATED_AT}"}
EOF
    exit 1
    ;;
  r2_fatal)
    cat > "$OUT_DIR/came_report_manifest.json" <<EOF
{"run_id":null,"validator_name":"came_overlay_validator","validator_version":"0.1.0","validation_mode":"development","status":"fatal","exit_code":2,"ceeg_enabled":null,"overlay_mode":"report_only","output_files":["came_report_manifest.json"],"created_at":"${CREATED_AT}"}
EOF
    exit 2
    ;;
  r2_no_manifest)
    printf 'mock: r2_no_manifest mode — no manifest written\n'
    exit 0
    ;;
  r2_bad_exit)
    printf 'mock: r2_bad_exit mode — simulating tooling failure\n' >&2
    exit 99
    ;;
  r3_success)
    cat > "$OUT_DIR/mapping_report_manifest.json" <<EOF
{"run_id":"mock_r3_run_001","validator_name":"mapping_contract_validator","validator_version":"0.1.0","validation_mode":"development","mapping_policy":"report_only","status":"valid","exit_code":0,"output_files":["mapping_report_manifest.json","mapping_summary.tsv","unmapped_features.tsv","ambiguous_mappings.tsv"],"created_at":"${CREATED_AT}"}
EOF
    printf 'run_id\ttotal_features\tmapped_count\tambiguous_count\tfailed_count\n' > "$OUT_DIR/mapping_summary.tsv"
    printf 'mock_r3_run_001\t10\t7\t1\t2\n' >> "$OUT_DIR/mapping_summary.tsv"
    printf 'unmapped_id\tfeature_id\tfailure_reason\tnotes\n' > "$OUT_DIR/unmapped_features.tsv"
    printf 'unmapped_001\tFEAT_A\tno_target_found\tmock unmapped feature\n' >> "$OUT_DIR/unmapped_features.tsv"
    printf 'unmapped_002\tFEAT_B\tno_target_found\tmock unmapped feature\n' >> "$OUT_DIR/unmapped_features.tsv"
    printf 'ambiguous_id\tfeature_id\tcandidate_count\tcandidate_ids\tnotes\n' > "$OUT_DIR/ambiguous_mappings.tsv"
    printf 'ambiguous_001\tFEAT_C\t2\tTARGET_X,TARGET_Y\tmock ambiguous mapping\n' >> "$OUT_DIR/ambiguous_mappings.tsv"
    exit 0
    ;;
  r3_invalid)
    cat > "$OUT_DIR/mapping_report_manifest.json" <<EOF
{"run_id":"mock_r3_invalid_001","validator_name":"mapping_contract_validator","validator_version":"0.1.0","validation_mode":"development","mapping_policy":"report_only","status":"invalid","exit_code":1,"output_files":["mapping_report_manifest.json"],"created_at":"${CREATED_AT}"}
EOF
    exit 1
    ;;
  r3_no_manifest)
    printf 'mock: r3_no_manifest mode — no manifest written\n'
    exit 1
    ;;
  *)
    printf 'mock_ceeg_validator: unknown mode: %s\n' "$MODE" >&2
    exit 1
    ;;
esac
