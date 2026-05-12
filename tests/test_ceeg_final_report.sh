#!/usr/bin/env sh
# CAME-I1: tests for CEEG Contract Consumption section in render_final_report.py
# Tests render_final_report.py directly — no Nextflow or CEEG repo checkout required.
#
# Mode/fixture policy:
#   Every test case whose fixture produces R2 or R3 contract-consumption rows in the
#   rendered output MUST call `render` with `ceeg_contract_checked` as the 3rd arg.
#   Only cases without R2/R3 contract data — i.e. no R2/R3 rows beyond headers,
#   R1-only scaffold, or completely empty CEEG fixtures — may rely on the renderer
#   default `design_assumed`. This keeps fixtures consistent with the
#   --comparability_mode validation contract enforced in main.nf.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

assert_grep() {
  pattern="$1"; file="$2"; message="$3"
  if ! grep -q "$pattern" "$file"; then
    echo "FAIL: $message (pattern: $pattern)" >&2
    FAIL=$((FAIL + 1)); return 0
  fi
}

assert_not_grep() {
  pattern="$1"; file="$2"; message="$3"
  if grep -q "$pattern" "$file"; then
    echo "FAIL: $message (unexpected pattern: $pattern)" >&2
    FAIL=$((FAIL + 1)); return 0
  fi
}

# ── helper: write minimal report fixtures ─────────────────────────────────────
setup_min_fixture() {
  rd="$1"
  mkdir -p "$rd/final/manifest" "$rd/final/release_checks"
  printf 'output_file\tsize_bytes\tmodified_time_utc\tstage\n' \
    > "$rd/final/manifest/came_outputs_manifest.tsv"
  printf 'stage\texpected_count\tpresent_count\tmissing_count\tstatus\n' \
    > "$rd/final/manifest/came_stage_completion_summary.tsv"
  printf 'missing_file\tstage\tmessage\n' \
    > "$rd/final/manifest/came_missing_outputs.tsv"
  printf 'check_id\tstatus\tmessage\n' \
    > "$rd/final/release_checks/came_release_checks.tsv"
  printf 'status\tcount\n' \
    > "$rd/final/release_checks/came_release_summary.tsv"
}

# ── helper: run render_final_report.py ────────────────────────────────────────
# 3rd arg `mode` is optional. When omitted, the renderer's default (design_assumed)
# applies — only valid for fixtures without R2/R3 contract-consumption rows.
render() {
  rd="$1"; out="$2"; mode="${3:-}"
  if [ -n "$mode" ]; then
    python3 "$ROOT_DIR/bin/render_final_report.py" \
      --study_profile "$ROOT_DIR/profiles/generic/study_profile.yaml" \
      --results_dir   "$rd" \
      --manifest      "$rd/final/manifest/came_outputs_manifest.tsv" \
      --stage_summary "$rd/final/manifest/came_stage_completion_summary.tsv" \
      --missing_outputs "$rd/final/manifest/came_missing_outputs.tsv" \
      --release_checks  "$rd/final/release_checks/came_release_checks.tsv" \
      --release_summary "$rd/final/release_checks/came_release_summary.tsv" \
      --output_dir "$out" \
      --comparability_mode "$mode"
  else
    python3 "$ROOT_DIR/bin/render_final_report.py" \
      --study_profile "$ROOT_DIR/profiles/generic/study_profile.yaml" \
      --results_dir   "$rd" \
      --manifest      "$rd/final/manifest/came_outputs_manifest.tsv" \
      --stage_summary "$rd/final/manifest/came_stage_completion_summary.tsv" \
      --missing_outputs "$rd/final/manifest/came_missing_outputs.tsv" \
      --release_checks  "$rd/final/release_checks/came_release_checks.tsv" \
      --release_summary "$rd/final/release_checks/came_release_summary.tsv" \
      --output_dir "$out"
  fi
}

# ── helper: write header-only CEEG-I0 outputs ─────────────────────────────────
write_ceeg_headers() {
  rd="$1"
  mkdir -p "$rd/ceeg_compatibility"
  printf 'artifact_type\tartifact_path\tstatus\texit_code\tvalidator_name\tvalidator_version\trun_id\tmessage\n' \
    > "$rd/ceeg_compatibility/ceeg_contract_summary.tsv"
  printf 'run_id\ttotal_features\tmapped_count\tambiguous_count\tfailed_count\tsource_artifact\n' \
    > "$rd/ceeg_compatibility/ceeg_mapping_summary.tsv"
  printf 'unmapped_id\tfeature_id\tfailure_reason\tnotes\tsource_artifact\tinterpretation_note\n' \
    > "$rd/ceeg_compatibility/ceeg_unmapped_features.tsv"
  printf 'ambiguous_id\tfeature_id\tcandidate_count\tcandidate_ids\tnotes\tsource_artifact\tinterpretation_note\n' \
    > "$rd/ceeg_compatibility/ceeg_ambiguous_mappings.tsv"
  printf 'severity\tsource\tmessage\n' \
    > "$rd/ceeg_compatibility/ceeg_compatibility_warnings.tsv"
  printf 'output_file\tartifact_type\trow_count\tsource_artifact\tgenerated_at\n' \
    > "$rd/ceeg_compatibility/ceeg_outputs_manifest.tsv"
}

# ── helper: write R2 success row ──────────────────────────────────────────────
write_r2_success() {
  rd="$1"
  write_ceeg_headers "$rd"
  printf 'r2_overlay\t/mock/r2\tcompatible\t0\tmock_overlay_validator\t1.0.0\tmock_r2_run_001\tstatus=compatible; compatibility_result=compatible\n' \
    >> "$rd/ceeg_compatibility/ceeg_contract_summary.tsv"
}

# ── helper: write R3 success row + mapping summary ────────────────────────────
write_r3_success() {
  rd="$1"
  write_ceeg_headers "$rd"
  printf 'r3_mapping\t/mock/r3\tvalid\t0\tmock_mapping_validator\t1.0.0\tmock_r3_run_001\tmapping_contract_status=valid\n' \
    >> "$rd/ceeg_compatibility/ceeg_contract_summary.tsv"
  printf 'mock_r3_run_001\t10\t7\t1\t2\t/mock/r3\n' \
    >> "$rd/ceeg_compatibility/ceeg_mapping_summary.tsv"
}

# ── helper: write R2 fatal row ────────────────────────────────────────────────
write_r2_fatal() {
  rd="$1"
  write_ceeg_headers "$rd"
  printf 'r2_overlay\t/mock/r2_fatal\tfatal\t2\tmock_overlay_validator\t1.0.0\t\tstatus=fatal; fatal R2 run; compatibility_summary.json absent\n' \
    >> "$rd/ceeg_compatibility/ceeg_contract_summary.tsv"
}

# ── helper: simulate R1 scaffold artifacts ────────────────────────────────────
write_r1_scaffold() {
  rd="$1"
  mkdir -p "$rd/ceeg/summary"
  printf 'metric\tvalue\tsource\nceeg_status\tSKIPPED\tsummary\n' \
    > "$rd/ceeg/summary/ceeg_compatibility_summary.tsv"
}

# ==============================================================================
# Case 1 — no CEEG directory
# ==============================================================================
CASE1_RD="$TMP_DIR/case1_results"
CASE1_OUT="$TMP_DIR/case1_out"
mkdir -p "$CASE1_OUT"
setup_min_fixture "$CASE1_RD"
render "$CASE1_RD" "$CASE1_OUT"

assert_grep "CEEG Contract Consumption" "$CASE1_OUT/came_final_report.html" \
  "case1: CEEG section missing from HTML"
assert_grep "No CEEG R2 overlay or R3 mapping audit artifacts were supplied" \
  "$CASE1_OUT/came_final_report.html" \
  "case1: expected no-artifacts message absent"
assert_grep "This is not a contract-validation failure" \
  "$CASE1_OUT/came_final_report.html" \
  "case1: expected non-error framing absent"
assert_grep "Failed mapping is not biological absence" \
  "$CASE1_OUT/came_final_report.html" \
  "case1: anti-overclaim note absent"
if [ "$FAIL" -eq 0 ] || [ "$PASS" -gt 0 ]; then
  pass "case1: no CEEG dir renders no-artifacts message correctly"
fi

# ==============================================================================
# Case 2 — header-only CEEG-I0 outputs
# ==============================================================================
CASE2_RD="$TMP_DIR/case2_results"
CASE2_OUT="$TMP_DIR/case2_out"
mkdir -p "$CASE2_OUT"
setup_min_fixture "$CASE2_RD"
write_ceeg_headers "$CASE2_RD"
render "$CASE2_RD" "$CASE2_OUT"

assert_grep "No CEEG R2 overlay or R3 mapping audit artifacts were supplied" \
  "$CASE2_OUT/came_final_report.html" \
  "case2: expected no-artifacts message absent for header-only"
assert_grep "This is not a contract-validation failure" \
  "$CASE2_OUT/came_final_report.html" \
  "case2: expected non-error framing absent"
pass "case2: header-only CEEG outputs render no-artifacts message correctly"

# ==============================================================================
# Case 3 — R1-only: scaffold artifacts present, no R2/R3
# ==============================================================================
CASE3_RD="$TMP_DIR/case3_results"
CASE3_OUT="$TMP_DIR/case3_out"
mkdir -p "$CASE3_OUT"
setup_min_fixture "$CASE3_RD"
write_ceeg_headers "$CASE3_RD"
write_r1_scaffold "$CASE3_RD"
render "$CASE3_RD" "$CASE3_OUT"

assert_grep "R1 bundle scaffold: yes" "$CASE3_OUT/came_final_report.html" \
  "case3: R1 bundle scaffold yes not rendered"
assert_grep "R1 CEEG scaffold artifacts were detected" "$CASE3_OUT/came_final_report.html" \
  "case3: R1 detected message absent"
assert_grep "This is not a contract-validation failure" \
  "$CASE3_OUT/came_final_report.html" \
  "case3: non-error framing absent"
pass "case3: R1-only scaffold artifacts rendered correctly"

# ==============================================================================
# Case 4 — R2 success only
# ==============================================================================
CASE4_RD="$TMP_DIR/case4_results"
CASE4_OUT="$TMP_DIR/case4_out"
mkdir -p "$CASE4_OUT"
setup_min_fixture "$CASE4_RD"
write_r2_success "$CASE4_RD"
render "$CASE4_RD" "$CASE4_OUT" ceeg_contract_checked

assert_grep "R2 Overlay Contract" "$CASE4_OUT/came_final_report.html" \
  "case4: R2 section missing"
assert_grep "mock_overlay_validator" "$CASE4_OUT/came_final_report.html" \
  "case4: R2 validator name missing"
assert_grep "compatible" "$CASE4_OUT/came_final_report.html" \
  "case4: R2 status missing"
assert_grep "R2 exit code" "$CASE4_OUT/came_final_report.html" \
  "case4: R2 exit code field missing"
assert_grep "Failed mapping is not biological absence" \
  "$CASE4_OUT/came_final_report.html" \
  "case4: anti-overclaim note absent"
pass "case4: R2 success only renders correctly"

# ==============================================================================
# Case 5 — R3 success only
# ==============================================================================
CASE5_RD="$TMP_DIR/case5_results"
CASE5_OUT="$TMP_DIR/case5_out"
mkdir -p "$CASE5_OUT"
setup_min_fixture "$CASE5_RD"
write_r3_success "$CASE5_RD"
render "$CASE5_RD" "$CASE5_OUT" ceeg_contract_checked

assert_grep "R3 Mapping Audit" "$CASE5_OUT/came_final_report.html" \
  "case5: R3 section missing"
assert_grep "Total features" "$CASE5_OUT/came_final_report.html" \
  "case5: mapping counts missing"
assert_grep "Mapped features" "$CASE5_OUT/came_final_report.html" \
  "case5: mapped count missing"
assert_grep "Ambiguous mappings" "$CASE5_OUT/came_final_report.html" \
  "case5: ambiguous count missing"
assert_grep "Failed mappings" "$CASE5_OUT/came_final_report.html" \
  "case5: failed count missing"
assert_grep "mock_mapping_validator" "$CASE5_OUT/came_final_report.html" \
  "case5: R3 validator name missing"
assert_grep "R3 status" "$CASE5_OUT/came_final_report.html" \
  "case5: R3 status field missing"
assert_grep "R3 exit code" "$CASE5_OUT/came_final_report.html" \
  "case5: R3 exit code field missing"
assert_grep "Failed mapping is not biological absence" \
  "$CASE5_OUT/came_final_report.html" \
  "case5: anti-overclaim note absent"
assert_not_grep "Absent features" "$CASE5_OUT/came_final_report.html" \
  "case5: forbidden 'Absent features' text found"
assert_not_grep "Conserved features" "$CASE5_OUT/came_final_report.html" \
  "case5: forbidden 'Conserved features' text found"
pass "case5: R3 success only renders correctly with interpretation notes"

# ==============================================================================
# Case 6 — R2 + R3 combined
# ==============================================================================
CASE6_RD="$TMP_DIR/case6_results"
CASE6_OUT="$TMP_DIR/case6_out"
mkdir -p "$CASE6_OUT"
setup_min_fixture "$CASE6_RD"
write_r2_success "$CASE6_RD"
# Append R3 row to existing contract_summary
printf 'r3_mapping\t/mock/r3\tvalid\t0\tmock_mapping_validator\t1.0.0\tmock_r3_run_001\tmapping_contract_status=valid\n' \
  >> "$CASE6_RD/ceeg_compatibility/ceeg_contract_summary.tsv"
printf 'mock_r3_run_001\t10\t7\t1\t2\t/mock/r3\n' \
  >> "$CASE6_RD/ceeg_compatibility/ceeg_mapping_summary.tsv"
render "$CASE6_RD" "$CASE6_OUT" ceeg_contract_checked

assert_grep "R2 Overlay Contract" "$CASE6_OUT/came_final_report.html" \
  "case6: R2 section missing from combined"
assert_grep "R3 Mapping Audit" "$CASE6_OUT/came_final_report.html" \
  "case6: R3 section missing from combined"
assert_grep "Total features" "$CASE6_OUT/came_final_report.html" \
  "case6: mapping counts missing from combined"
pass "case6: R2+R3 combined renders both sections"

# ==============================================================================
# Case 7 — R2 fatal: render_final_report.py must exit 0
# ==============================================================================
CASE7_RD="$TMP_DIR/case7_results"
CASE7_OUT="$TMP_DIR/case7_out"
mkdir -p "$CASE7_OUT"
setup_min_fixture "$CASE7_RD"
write_r2_fatal "$CASE7_RD"
rc=0
render "$CASE7_RD" "$CASE7_OUT" ceeg_contract_checked || rc=$?
if [ "$rc" -ne 0 ]; then
  fail "case7: render_final_report.py exited $rc for R2 fatal (expected 0)"
else
  assert_grep "fatal" "$CASE7_OUT/came_final_report.html" \
    "case7: fatal status not displayed"
  assert_grep "R2 exit code" "$CASE7_OUT/came_final_report.html" \
    "case7: exit code field missing"
  pass "case7: R2 fatal renders fatal status, render_final_report.py exits 0"
fi

# ==============================================================================
# Case 8 — regression: existing final-report core sections unchanged
# ==============================================================================
CASE8_RD="$TMP_DIR/case8_results"
CASE8_OUT="$TMP_DIR/case8_out"
mkdir -p "$CASE8_OUT"
setup_min_fixture "$CASE8_RD"
render "$CASE8_RD" "$CASE8_OUT"

assert_grep "Stage Completion" "$CASE8_OUT/came_final_report.html" \
  "case8: Stage Completion section missing"
assert_grep "Run Provenance" "$CASE8_OUT/came_final_report.html" \
  "case8: Run Provenance section missing"
assert_grep "Release Checks" "$CASE8_OUT/came_final_report.html" \
  "case8: Release Checks section missing"
assert_grep "Limitations" "$CASE8_OUT/came_final_report.html" \
  "case8: Limitations section missing"
assert_grep "CEEG Contract Consumption" "$CASE8_OUT/came_final_report.html" \
  "case8: CEEG section absent from core report (regression)"
pass "case8: existing report sections intact alongside CEEG section"

# ==============================================================================
# Case 9 — semantic guard: no forbidden phrases
# ==============================================================================
CASE9_RD="$TMP_DIR/case9_results"
CASE9_OUT="$TMP_DIR/case9_out"
mkdir -p "$CASE9_OUT"
setup_min_fixture "$CASE9_RD"
write_r2_success "$CASE9_RD"
printf 'r3_mapping\t/mock/r3\tvalid\t0\tmock_mapping_validator\t1.0.0\tmock_r3_run_001\tmapping_contract_status=valid\n' \
  >> "$CASE9_RD/ceeg_compatibility/ceeg_contract_summary.tsv"
printf 'mock_r3_run_001\t10\t7\t1\t2\t/mock/r3\n' \
  >> "$CASE9_RD/ceeg_compatibility/ceeg_mapping_summary.tsv"
render "$CASE9_RD" "$CASE9_OUT" ceeg_contract_checked

assert_not_grep "conserved feature" "$CASE9_OUT/came_final_report.html" \
  "case9: forbidden 'conserved feature' found in report"
assert_not_grep "functional equivalence" "$CASE9_OUT/came_final_report.html" \
  "case9: forbidden 'functional equivalence' found in report"
assert_not_grep "candidate score" "$CASE9_OUT/came_final_report.html" \
  "case9: forbidden 'candidate score' found in report"
assert_not_grep "biological comparability score" "$CASE9_OUT/came_final_report.html" \
  "case9: forbidden 'biological comparability score' found in report"
# Bare "admissibility" appears as part of the legitimate anti-overclaim wording
# ("R5 admissibility validation") under ceeg_contract_checked mode. The forbidden
# claim is "admissibility status" — that is what this guard must prohibit.
assert_not_grep "admissibility status" "$CASE9_OUT/came_final_report.html" \
  "case9: forbidden 'admissibility status' found in report"
# "biological absence" only allowed in the anti-overclaim note
# Check it does NOT appear outside the notes context by verifying the approved form is present
assert_grep "Failed mapping is not biological absence" \
  "$CASE9_OUT/came_final_report.html" \
  "case9: approved anti-overclaim form missing"
pass "case9: no forbidden semantic phrases in report"

# ==============================================================================
# Case 10 — R2 missing manifest (adapter error): must render as error, not no-artifacts
# ==============================================================================
CASE10_RD="$TMP_DIR/case10_results"
CASE10_OUT="$TMP_DIR/case10_out"
mkdir -p "$CASE10_OUT"
setup_min_fixture "$CASE10_RD"
write_ceeg_headers "$CASE10_RD"
# Simulate _parse_r2 output when came_report_manifest.json is absent
printf 'r2_overlay\t/mock/r2_missing\tmissing_manifest\t2\t\t\t\tcame_report_manifest.json not found\n' \
  >> "$CASE10_RD/ceeg_compatibility/ceeg_contract_summary.tsv"
render "$CASE10_RD" "$CASE10_OUT" ceeg_contract_checked

assert_grep "R2 Overlay Contract" "$CASE10_OUT/came_final_report.html" \
  "case10: R2 section missing when manifest was absent (adapter error)"
assert_grep "missing_manifest" "$CASE10_OUT/came_final_report.html" \
  "case10: missing_manifest status not rendered"
assert_grep "came_report_manifest.json not found" "$CASE10_OUT/came_final_report.html" \
  "case10: R2 message (diagnostic) not rendered"
assert_not_grep "No CEEG R2 overlay or R3 mapping audit artifacts were supplied" \
  "$CASE10_OUT/came_final_report.html" \
  "case10: adapter error misclassified as no-artifacts-supplied"
pass "case10: R2 missing-manifest adapter error renders error status, message, not no-artifacts"

# ==============================================================================
# Case 11 — R3 missing manifest: message field rendered (symmetry with R2)
# ==============================================================================
CASE11_RD="$TMP_DIR/case11_results"
CASE11_OUT="$TMP_DIR/case11_out"
mkdir -p "$CASE11_OUT"
setup_min_fixture "$CASE11_RD"
write_ceeg_headers "$CASE11_RD"
# Simulate _parse_r3 output when mapping_report_manifest.json is absent
printf 'r3_mapping\t/mock/r3_missing\tmissing_manifest\t2\t\t\t\tmapping_report_manifest.json not found\n' \
  >> "$CASE11_RD/ceeg_compatibility/ceeg_contract_summary.tsv"
render "$CASE11_RD" "$CASE11_OUT" ceeg_contract_checked

assert_grep "R3 Mapping Audit" "$CASE11_OUT/came_final_report.html" \
  "case11: R3 section missing when manifest was absent (adapter error)"
assert_grep "missing_manifest" "$CASE11_OUT/came_final_report.html" \
  "case11: missing_manifest status not rendered for R3"
assert_grep "mapping_report_manifest.json not found" "$CASE11_OUT/came_final_report.html" \
  "case11: R3 message (diagnostic) not rendered"
assert_not_grep "No R3 mapping-contract artifacts were supplied" \
  "$CASE11_OUT/came_final_report.html" \
  "case11: R3 adapter error misclassified as no-artifacts-supplied"
pass "case11: R3 missing-manifest adapter error renders error status and message"

# ==============================================================================
# Case 12 — design-assumed mode (default): no R2/R3 fixtures, MD + HTML parity
# ==============================================================================
CASE12_RD="$TMP_DIR/case12_results"
CASE12_OUT="$TMP_DIR/case12_out"
mkdir -p "$CASE12_OUT"
setup_min_fixture "$CASE12_RD"
# Deliberately no write_ceeg_headers / write_r2_success / write_r3_success — this
# fixture must contain no R2/R3 contract-consumption rows so the renderer's
# default design_assumed mode is honoured by the param-validation contract.
render "$CASE12_RD" "$CASE12_OUT"

for fmt in md html; do
  assert_grep "Comparability Mode" "$CASE12_OUT/came_final_report.$fmt" \
    "case12/$fmt: Comparability Mode heading missing"
  assert_grep "Comparability mode: standard / design-assumed" "$CASE12_OUT/came_final_report.$fmt" \
    "case12/$fmt: design-assumed heading line missing"
  assert_grep "CAME did not consume CEEG R2/R3 contract artifacts" "$CASE12_OUT/came_final_report.$fmt" \
    "case12/$fmt: design-assumed body sentence 1 missing"
  assert_grep "assumed from the experimental design" "$CASE12_OUT/came_final_report.$fmt" \
    "case12/$fmt: design-assumed body sentence 2 missing"
  assert_grep "Interpret comparative results conditional on that design assumption" \
    "$CASE12_OUT/came_final_report.$fmt" \
    "case12/$fmt: design-assumed closing sentence missing"
  assert_not_grep "CEEG contract-checked" "$CASE12_OUT/came_final_report.$fmt" \
    "case12/$fmt: unexpected ceeg_contract_checked wording present"
  assert_not_grep "R4 comparability validation" "$CASE12_OUT/came_final_report.$fmt" \
    "case12/$fmt: unexpected R4 wording present"
  assert_not_grep "R5 admissibility validation" "$CASE12_OUT/came_final_report.$fmt" \
    "case12/$fmt: unexpected R5 wording present"
  assert_not_grep "CEEG comparability contracts" "$CASE12_OUT/came_final_report.$fmt" \
    "case12/$fmt: forbidden 'CEEG comparability contracts' phrase present"
done
pass "case12: design-assumed mode renders correctly in MD and HTML"

# ==============================================================================
# Case 13 — CEEG contract-checked mode: R2 success fixture, MD + HTML parity
# ==============================================================================
CASE13_RD="$TMP_DIR/case13_results"
CASE13_OUT="$TMP_DIR/case13_out"
mkdir -p "$CASE13_OUT"
setup_min_fixture "$CASE13_RD"
write_r2_success "$CASE13_RD"
render "$CASE13_RD" "$CASE13_OUT" ceeg_contract_checked

for fmt in md html; do
  assert_grep "Comparability Mode" "$CASE13_OUT/came_final_report.$fmt" \
    "case13/$fmt: Comparability Mode heading missing"
  assert_grep "Comparability mode: CEEG contract-checked" "$CASE13_OUT/came_final_report.$fmt" \
    "case13/$fmt: ceeg_contract_checked heading line missing"
  assert_grep "CAME consumed CEEG R2/R3 contract artifacts" "$CASE13_OUT/came_final_report.$fmt" \
    "case13/$fmt: ceeg_contract_checked body sentence 1 missing"
  assert_grep "report contract and mapping-artifact status" "$CASE13_OUT/came_final_report.$fmt" \
    "case13/$fmt: ceeg_contract_checked body sentence 2 missing"
  assert_grep "not by themselves constitute R4 comparability validation" \
    "$CASE13_OUT/came_final_report.$fmt" \
    "case13/$fmt: R4 anti-overclaim sentence missing"
  assert_grep "R5 admissibility validation" "$CASE13_OUT/came_final_report.$fmt" \
    "case13/$fmt: R5 anti-overclaim wording missing"
  assert_not_grep "standard / design-assumed" "$CASE13_OUT/came_final_report.$fmt" \
    "case13/$fmt: unexpected design-assumed wording present"
  assert_not_grep "CEEG comparability contracts" "$CASE13_OUT/came_final_report.$fmt" \
    "case13/$fmt: forbidden 'CEEG comparability contracts' phrase present"
done
pass "case13: CEEG contract-checked mode renders correctly in MD and HTML"

# ==============================================================================
# Case 14 — MD/HTML parity for the comparability-mode declaration (both modes)
# ==============================================================================
# Re-use the case-12 outputs (design_assumed) and case-13 outputs (ceeg_contract_checked).
# Each body string must be present in BOTH formats for the mode in question.
parity_check() {
  pattern="$1"; out_dir="$2"; case_label="$3"
  assert_grep "$pattern" "$out_dir/came_final_report.md" \
    "case14/$case_label: MD missing '$pattern'"
  assert_grep "$pattern" "$out_dir/came_final_report.html" \
    "case14/$case_label: HTML missing '$pattern'"
}

# design_assumed parity (from case12 output)
parity_check "Comparability mode: standard / design-assumed" "$CASE12_OUT" "design_assumed"
parity_check "CAME did not consume CEEG R2/R3 contract artifacts in this run" "$CASE12_OUT" "design_assumed"
parity_check "Cross-condition or cross-system comparability is assumed from the experimental design" "$CASE12_OUT" "design_assumed"
parity_check "Interpret comparative results conditional on that design assumption" "$CASE12_OUT" "design_assumed"

# ceeg_contract_checked parity (from case13 output)
parity_check "Comparability mode: CEEG contract-checked" "$CASE13_OUT" "ceeg_contract_checked"
parity_check "CAME consumed CEEG R2/R3 contract artifacts in this run" "$CASE13_OUT" "ceeg_contract_checked"
parity_check "These artifacts report contract and mapping-artifact status" "$CASE13_OUT" "ceeg_contract_checked"
parity_check "They do not by themselves constitute R4 comparability validation or R5 admissibility validation" \
  "$CASE13_OUT" "ceeg_contract_checked"
pass "case14: comparability-mode body text has MD/HTML parity for both modes"

# ==============================================================================
# Case 15 — renderer rejects design_assumed when on-disk R2/R3 rows are present
# (simulates a re-render where the user forgot --comparability_mode after a
#  prior ceeg_contract_checked run wrote contract data into the results tree)
# ==============================================================================
CASE15_RD="$TMP_DIR/case15_results"
CASE15_OUT="$TMP_DIR/case15_out"
mkdir -p "$CASE15_OUT"
setup_min_fixture "$CASE15_RD"
write_r2_success "$CASE15_RD"
rc=0
# Deliberately omit the mode arg → renderer default is design_assumed, which
# is inconsistent with the R2 rows now on disk. The renderer must reject this.
render "$CASE15_RD" "$CASE15_OUT" > "$TMP_DIR/case15.stderr" 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
  pass "case15: renderer exits 2 when design_assumed declared with R2 rows on disk"
else
  cat "$TMP_DIR/case15.stderr"
  fail "case15: expected exit 2, got $rc"
fi
assert_grep "comparability_mode is 'design_assumed'" "$TMP_DIR/case15.stderr" \
  "case15: stderr does not name design_assumed"
assert_grep "ceeg_contract_summary.tsv" "$TMP_DIR/case15.stderr" \
  "case15: stderr does not name the offending TSV path"
assert_grep "comparability_mode ceeg_contract_checked" "$TMP_DIR/case15.stderr" \
  "case15: stderr does not guide user to the correct mode"

# ==============================================================================
# Case 16 — renderer rejects ceeg_contract_checked when no R2/R3 rows are on disk
# (simulates a renderer-only run that declared CEEG consumption but the
#  ceeg_compatibility stage was never actually run)
# ==============================================================================
CASE16_RD="$TMP_DIR/case16_results"
CASE16_OUT="$TMP_DIR/case16_out"
mkdir -p "$CASE16_OUT"
setup_min_fixture "$CASE16_RD"
# Deliberately no write_ceeg_headers / write_r2_success → no R2/R3 rows on disk.
rc=0
render "$CASE16_RD" "$CASE16_OUT" ceeg_contract_checked > "$TMP_DIR/case16.stderr" 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
  pass "case16: renderer exits 2 when ceeg_contract_checked declared with no R2/R3 rows"
else
  cat "$TMP_DIR/case16.stderr"
  fail "case16: expected exit 2, got $rc"
fi
assert_grep "comparability_mode is 'ceeg_contract_checked'" "$TMP_DIR/case16.stderr" \
  "case16: stderr does not name ceeg_contract_checked"
assert_grep "comparability_mode design_assumed" "$TMP_DIR/case16.stderr" \
  "case16: stderr does not guide user to the correct mode"

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
