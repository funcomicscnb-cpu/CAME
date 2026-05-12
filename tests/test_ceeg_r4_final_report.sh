#!/usr/bin/env sh
# CAME-I3: tests for the CEEG R4 Comparability Evidence section + truth-table
# validation in render_final_report.py. Tests render_final_report.py directly —
# no Nextflow or CEEG repo checkout required.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SUMMARIZER="$ROOT_DIR/bin/summarize_ceeg_r4_comparability_artifacts.py"
RENDERER="$ROOT_DIR/bin/render_final_report.py"
FIXTURE_DIR="$ROOT_DIR/assets/test_data/ceeg_compatibility"
R4_SUCCESS="$FIXTURE_DIR/mock_r4_output_success"
R4_CONTRACT_ERROR="$FIXTURE_DIR/mock_r4_output_contract_error"
R4_FATAL="$FIXTURE_DIR/mock_r4_output_fatal"

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
    FAIL=$((FAIL + 1))
  fi
}

assert_not_grep() {
  pattern="$1"; file="$2"; message="$3"
  if grep -q "$pattern" "$file"; then
    echo "FAIL: $message (unexpected pattern: $pattern)" >&2
    FAIL=$((FAIL + 1))
  fi
}

# ── helper: minimal report fixtures ───────────────────────────────────────────
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

# ── helper: header-only R2/R3 outputs ─────────────────────────────────────────
write_ceeg_headers() {
  rd="$1"
  mkdir -p "$rd/ceeg_compatibility"
  printf 'artifact_type\tartifact_path\tstatus\texit_code\tvalidator_name\tvalidator_version\trun_id\tmessage\n' \
    > "$rd/ceeg_compatibility/ceeg_contract_summary.tsv"
  printf 'run_id\ttotal_features\tmapped_count\tambiguous_count\tfailed_count\tsource_artifact\n' \
    > "$rd/ceeg_compatibility/ceeg_mapping_summary.tsv"
  printf 'severity\tsource\tmessage\n' \
    > "$rd/ceeg_compatibility/ceeg_compatibility_warnings.tsv"
}

# ── helper: write an R2 success row ───────────────────────────────────────────
write_r2_success() {
  rd="$1"
  printf 'r2_overlay\t/mock/r2\tcompatible\t0\tmock_overlay_validator\t1.0.0\tmock_r2_run_001\tstatus=compatible; compatibility_result=compatible\n' \
    >> "$rd/ceeg_compatibility/ceeg_contract_summary.tsv"
}

# ── helper: populate R4 outputs from a fixture directory ──────────────────────
write_r4_from_fixture() {
  rd="$1"; fixture="$2"
  mkdir -p "$rd/ceeg_compatibility"
  python3 "$SUMMARIZER" \
    --out-dir "$rd/ceeg_compatibility" \
    --r4-dir "$fixture" \
    --created-at 2026-05-11T00:00:00Z >/dev/null
}

# ── helper: write header-only R4 outputs (no R4 rows present) ─────────────────
write_r4_header_only() {
  rd="$1"
  mkdir -p "$rd/ceeg_compatibility"
  python3 "$SUMMARIZER" \
    --out-dir "$rd/ceeg_compatibility" \
    --created-at 2026-05-11T00:00:00Z >/dev/null
}

# ── helper: run render_final_report.py with mode ──────────────────────────────
render() {
  rd="$1"; out="$2"; mode="$3"; expect_exit="${4:-0}"
  set +e
  python3 "$RENDERER" \
    --study_profile "$ROOT_DIR/profiles/generic/study_profile.yaml" \
    --results_dir   "$rd" \
    --manifest      "$rd/final/manifest/came_outputs_manifest.tsv" \
    --stage_summary "$rd/final/manifest/came_stage_completion_summary.tsv" \
    --missing_outputs "$rd/final/manifest/came_missing_outputs.tsv" \
    --release_checks  "$rd/final/release_checks/came_release_checks.tsv" \
    --release_summary "$rd/final/release_checks/came_release_summary.tsv" \
    --output_dir "$out" \
    --comparability_mode "$mode" 2>"$out.stderr"
  rc=$?
  set -e
  if [ "$rc" != "$expect_exit" ]; then
    echo "FAIL: render mode=$mode expected exit $expect_exit, got $rc" >&2
    cat "$out.stderr" >&2
    FAIL=$((FAIL + 1))
    return 1
  fi
  return 0
}

# ── case 1: ceeg_comparability_evidence_consumed + R4 only renders R4 section ─
CASE1="$TMP_DIR/case1"
CASE1_OUT="$TMP_DIR/case1_out"
setup_min_fixture "$CASE1"
write_ceeg_headers "$CASE1"
write_r4_from_fixture "$CASE1" "$R4_SUCCESS"
mkdir -p "$CASE1_OUT"
render "$CASE1" "$CASE1_OUT" "ceeg_comparability_evidence_consumed"
for fmt in md html; do
  f="$CASE1_OUT/came_final_report.$fmt"
  assert_grep "Comparability mode: CEEG R4 evidence-state consumed" "$f" \
    "case1/$fmt: R4 mode heading"
  assert_grep "CAME consumed CEEG R4 comparability evidence artifacts in this run" "$f" \
    "case1/$fmt: R4 mode body sentence 1"
  assert_grep "structured evidence-state status under a bound analysis context" "$f" \
    "case1/$fmt: R4 mode body sentence 2"
  assert_grep "do not validate biological comparability as a verdict" "$f" \
    "case1/$fmt: R4 mode body sentence 3"
  assert_grep "CEEG R4 Comparability Evidence" "$f" \
    "case1/$fmt: R4 section heading"
  assert_grep "Validator metadata" "$f" "case1/$fmt: Validator metadata subsection"
  assert_grep "Context" "$f" "case1/$fmt: Context subsection"
  assert_grep "Evidence state" "$f" "case1/$fmt: Evidence state subsection"
  assert_grep "Evidence counts" "$f" "case1/$fmt: Evidence counts subsection"
  assert_grep "Limitations" "$f" "case1/$fmt: Limitations subsection"
  assert_grep "mock_model_alpha" "$f" "case1/$fmt: model_id rendered"
  assert_grep "mock_context_beta" "$f" "case1/$fmt: context_id rendered"
  assert_grep "cmp_0001" "$f" "case1/$fmt: comparison_id rendered"
  assert_grep "evidence_supports_comparability" "$f" "case1/$fmt: comparability_status rendered"
  assert_grep "supporting_evidence_majority" "$f" "case1/$fmt: status_basis rendered"
  assert_grep "Supporting evidence count" "$f" "case1/$fmt: supporting count label"
done
pass "case1: ceeg_comparability_evidence_consumed + R4-only renders R4 section in MD and HTML"

# ── case 2: ceeg_comparability_evidence_consumed + R4 + R2/R3 renders both ────
CASE2="$TMP_DIR/case2"
CASE2_OUT="$TMP_DIR/case2_out"
setup_min_fixture "$CASE2"
write_ceeg_headers "$CASE2"
write_r2_success "$CASE2"
write_r4_from_fixture "$CASE2" "$R4_SUCCESS"
mkdir -p "$CASE2_OUT"
render "$CASE2" "$CASE2_OUT" "ceeg_comparability_evidence_consumed"
for fmt in md html; do
  f="$CASE2_OUT/came_final_report.$fmt"
  assert_grep "CEEG Contract Consumption" "$f" "case2/$fmt: R2/R3 section present"
  assert_grep "mock_overlay_validator" "$f" "case2/$fmt: R2 validator surfaced"
  assert_grep "CEEG R4 Comparability Evidence" "$f" "case2/$fmt: R4 section present"
  assert_grep "Comparability mode: CEEG R4 evidence-state consumed" "$f" \
    "case2/$fmt: R4 mode heading still used"
done
pass "case2: ceeg_comparability_evidence_consumed + R4 + R2/R3 renders both sections"

# ── case 3: design_assumed + R4 rows → reject (truth table) ───────────────────
CASE3="$TMP_DIR/case3"
CASE3_OUT="$TMP_DIR/case3_out"
setup_min_fixture "$CASE3"
write_ceeg_headers "$CASE3"
write_r4_from_fixture "$CASE3" "$R4_SUCCESS"
mkdir -p "$CASE3_OUT"
render "$CASE3" "$CASE3_OUT" "design_assumed" 2
assert_grep "design_assumed" "$CASE3_OUT.stderr" "case3: error names declared mode"
assert_grep "ceeg_r4_comparability_summary.tsv" "$CASE3_OUT.stderr" "case3: error names R4 path"
assert_grep "ceeg_comparability_evidence_consumed" "$CASE3_OUT.stderr" "case3: error suggests R4 mode"
pass "case3: design_assumed + R4 rows → exit 2 with R4-naming error"

# ── case 4: design_assumed + R2/R3 + R4 → reject ──────────────────────────────
CASE4="$TMP_DIR/case4"
CASE4_OUT="$TMP_DIR/case4_out"
setup_min_fixture "$CASE4"
write_ceeg_headers "$CASE4"
write_r2_success "$CASE4"
write_r4_from_fixture "$CASE4" "$R4_SUCCESS"
mkdir -p "$CASE4_OUT"
render "$CASE4" "$CASE4_OUT" "design_assumed" 2
assert_grep "design_assumed" "$CASE4_OUT.stderr" "case4: error names declared mode"
assert_grep "ceeg_contract_summary.tsv" "$CASE4_OUT.stderr" "case4: error names R2/R3 path"
assert_grep "ceeg_r4_comparability_summary.tsv" "$CASE4_OUT.stderr" "case4: error names R4 path"
pass "case4: design_assumed + R2/R3 + R4 → exit 2 with both-path error"

# ── case 5: ceeg_contract_checked + R4-only → reject ──────────────────────────
CASE5="$TMP_DIR/case5"
CASE5_OUT="$TMP_DIR/case5_out"
setup_min_fixture "$CASE5"
write_ceeg_headers "$CASE5"
write_r4_from_fixture "$CASE5" "$R4_SUCCESS"
mkdir -p "$CASE5_OUT"
render "$CASE5" "$CASE5_OUT" "ceeg_contract_checked" 2
assert_grep "ceeg_contract_checked" "$CASE5_OUT.stderr" "case5: error names declared mode"
assert_grep "ceeg_r4_comparability_summary.tsv" "$CASE5_OUT.stderr" "case5: error names R4 path"
assert_grep "ceeg_comparability_evidence_consumed" "$CASE5_OUT.stderr" "case5: error suggests R4 mode"
pass "case5: ceeg_contract_checked + R4-only → exit 2"

# ── case 6: ceeg_contract_checked + R2/R3 + R4 → reject ───────────────────────
CASE6="$TMP_DIR/case6"
CASE6_OUT="$TMP_DIR/case6_out"
setup_min_fixture "$CASE6"
write_ceeg_headers "$CASE6"
write_r2_success "$CASE6"
write_r4_from_fixture "$CASE6" "$R4_SUCCESS"
mkdir -p "$CASE6_OUT"
render "$CASE6" "$CASE6_OUT" "ceeg_contract_checked" 2
assert_grep "ceeg_contract_checked" "$CASE6_OUT.stderr" "case6: error names declared mode"
assert_grep "ceeg_r4_comparability_summary.tsv" "$CASE6_OUT.stderr" "case6: error names R4 path"
pass "case6: ceeg_contract_checked + R2/R3 + R4 → exit 2"

# ── case 7: ceeg_comparability_evidence_consumed + no rows → reject ───────────
CASE7="$TMP_DIR/case7"
CASE7_OUT="$TMP_DIR/case7_out"
setup_min_fixture "$CASE7"
write_ceeg_headers "$CASE7"
write_r4_header_only "$CASE7"
mkdir -p "$CASE7_OUT"
render "$CASE7" "$CASE7_OUT" "ceeg_comparability_evidence_consumed" 2
assert_grep "ceeg_comparability_evidence_consumed" "$CASE7_OUT.stderr" "case7: error names declared mode"
assert_grep "no CEEG R4 comparability rows" "$CASE7_OUT.stderr" "case7: error notes missing R4 rows"
pass "case7: ceeg_comparability_evidence_consumed + no R4 rows → exit 2"

# ── case 8: ceeg_comparability_evidence_consumed + R2/R3 only → reject ────────
CASE8="$TMP_DIR/case8"
CASE8_OUT="$TMP_DIR/case8_out"
setup_min_fixture "$CASE8"
write_ceeg_headers "$CASE8"
write_r2_success "$CASE8"
write_r4_header_only "$CASE8"
mkdir -p "$CASE8_OUT"
render "$CASE8" "$CASE8_OUT" "ceeg_comparability_evidence_consumed" 2
assert_grep "ceeg_comparability_evidence_consumed" "$CASE8_OUT.stderr" "case8: error names declared mode"
assert_grep "ceeg_r4_comparability_summary.tsv" "$CASE8_OUT.stderr" "case8: error names R4 path"
pass "case8: ceeg_comparability_evidence_consumed + R2/R3 only → exit 2"

# ── case 9: R4 contract_error fixture renders diagnostic row in the section ───
CASE9="$TMP_DIR/case9"
CASE9_OUT="$TMP_DIR/case9_out"
setup_min_fixture "$CASE9"
write_ceeg_headers "$CASE9"
write_r4_from_fixture "$CASE9" "$R4_CONTRACT_ERROR"
mkdir -p "$CASE9_OUT"
render "$CASE9" "$CASE9_OUT" "ceeg_comparability_evidence_consumed"
for fmt in md html; do
  f="$CASE9_OUT/came_final_report.$fmt"
  assert_grep "CEEG R4 Comparability Evidence" "$f" "case9/$fmt: section heading"
  assert_grep "contract_error" "$f" "case9/$fmt: contract_error status rendered"
  assert_grep "upstream_contract_error" "$f" "case9/$fmt: status_basis rendered"
  assert_grep "R4 contract_error reported by manifest" "$f" "case9/$fmt: diagnostic message"
done
pass "case9: R4 contract_error fixture renders diagnostic row in MD and HTML"

# ── case 10: R4 fatal exit-2 fixture renders diagnostic row ───────────────────
CASE10="$TMP_DIR/case10"
CASE10_OUT="$TMP_DIR/case10_out"
setup_min_fixture "$CASE10"
write_ceeg_headers "$CASE10"
write_r4_from_fixture "$CASE10" "$R4_FATAL"
mkdir -p "$CASE10_OUT"
render "$CASE10" "$CASE10_OUT" "ceeg_comparability_evidence_consumed"
for fmt in md html; do
  f="$CASE10_OUT/came_final_report.$fmt"
  assert_grep "contract_error" "$f" "case10/$fmt: contract_error status rendered"
  assert_grep "fatal-shape artifact" "$f" "case10/$fmt: fatal-shape diagnostic message"
done
pass "case10: R4 fatal exit-2 fixture renders diagnostic row"

# ── case 11: anti-overclaim — no forbidden verdict phrases in R4 outputs ──────
CASE11="$TMP_DIR/case11"
CASE11_OUT="$TMP_DIR/case11_out"
setup_min_fixture "$CASE11"
write_ceeg_headers "$CASE11"
write_r4_from_fixture "$CASE11" "$R4_SUCCESS"
mkdir -p "$CASE11_OUT"
render "$CASE11" "$CASE11_OUT" "ceeg_comparability_evidence_consumed"
for fmt in md html; do
  f="$CASE11_OUT/came_final_report.$fmt"
  for forbidden in 'validated comparability' 'biologically comparable' 'biologically incomparable' 'admissible candidate' 'conserved candidate' 'equivalent system' 'absent because unmappable'; do
    assert_not_grep "$forbidden" "$f" "case11/$fmt: forbidden phrase '$forbidden'"
  done
  # Allowed words (sanity check that we did not over-reject):
  assert_grep "comparability" "$f" "case11/$fmt: 'comparability' allowed and present"
  assert_grep "comparability_status" "$f" "case11/$fmt: 'comparability_status' allowed and present"
  assert_grep "evidence_supports_comparability" "$f" "case11/$fmt: controlled vocab present"
done
pass "case11: R4 outputs contain no forbidden verdict phrasing"

# ── case 12: multi-row R4 summary renders one block per comparison ────────────
# Uses a hand-written 2-row summary to confirm grouped headings use #### / h4
# when wrapped under per-comparison ### / h3 (heading-hierarchy bug fix).
CASE_MULTI="$TMP_DIR/case_multi"
CASE_MULTI_OUT="$TMP_DIR/case_multi_out"
setup_min_fixture "$CASE_MULTI"
write_ceeg_headers "$CASE_MULTI"
mkdir -p "$CASE_MULTI/ceeg_compatibility"
# Two synthetic R4 comparison rows under the canonical 28-column schema.
{
  printf 'artifact_type\tartifact_path\tvalidator_name\tvalidator_version\tvalidation_mode\tstatus\texit_code\tcreated_at\tmodel_id\tcontext_id\tcomparison_count\tcomparison_id\tleft_system_id\tright_system_id\tentity_scope\tcomparability_status\tstatus_basis\tsupporting_evidence_count\tweakening_evidence_count\tmixed_evidence_count\tunresolved_evidence_count\tambiguity_count\tunknown_count\tunknown_unmappable_count\tabsent_count\tlimitations_count\tprimary_limitation\tmessage\n'
  printf 'r4_comparability_report\t/mock/r4\tmock_validator\t1.0.0\tdevelopment\tevidence_supports_comparability\t0\t2026-05-11T00:00:00Z\tmodel_alpha\tcontext_beta\t2\tcmp_A001\tsys_L\tsys_R\tscope_X\tevidence_supports_comparability\tsupporting_evidence_majority\t3\t0\t0\t0\t0\t0\t0\t0\t0\t\tstatus=ok\n'
  printf 'r4_comparability_report\t/mock/r4\tmock_validator\t1.0.0\tdevelopment\tevidence_mixed_for_comparability\t0\t2026-05-11T00:00:00Z\tmodel_alpha\tcontext_beta\t2\tcmp_B002\tsys_L\tsys_R\tscope_X\tevidence_mixed_for_comparability\tmixed_evidence\t1\t1\t2\t0\t0\t0\t0\t0\t0\t\tstatus=mixed\n'
} > "$CASE_MULTI/ceeg_compatibility/ceeg_r4_comparability_summary.tsv"
printf 'comparison_id\tcontext_id\tlimitation_id\tlimitation_type\tseverity\taffected_scope\tdescription\trecommended_interpretation\n' \
  > "$CASE_MULTI/ceeg_compatibility/ceeg_r4_comparability_limitations.tsv"
printf 'evidence_id\tcomparison_id\tcontext_id\tevidence_type\tevidence_class\tconfidence\tnotes\tsource_artifact\tinterpretation_note\n' \
  > "$CASE_MULTI/ceeg_compatibility/ceeg_r4_comparability_evidence.tsv"
mkdir -p "$CASE_MULTI_OUT"
render "$CASE_MULTI" "$CASE_MULTI_OUT" "ceeg_comparability_evidence_consumed"
# Both comparison_ids are surfaced.
assert_grep "cmp_A001" "$CASE_MULTI_OUT/came_final_report.md" "case_multi/md: first comparison_id surfaced"
assert_grep "cmp_B002" "$CASE_MULTI_OUT/came_final_report.md" "case_multi/md: second comparison_id surfaced"
assert_grep "cmp_A001" "$CASE_MULTI_OUT/came_final_report.html" "case_multi/html: first comparison_id surfaced"
assert_grep "cmp_B002" "$CASE_MULTI_OUT/came_final_report.html" "case_multi/html: second comparison_id surfaced"
# Multi-row Markdown wraps each row under `### Comparison ...` and uses
# `#### <group>` for the group subsections.
assert_grep "^### Comparison cmp_A001" "$CASE_MULTI_OUT/came_final_report.md" \
  "case_multi/md: per-comparison h3 wrapper for cmp_A001"
assert_grep "^### Comparison cmp_B002" "$CASE_MULTI_OUT/came_final_report.md" \
  "case_multi/md: per-comparison h3 wrapper for cmp_B002"
assert_grep "^#### Validator metadata" "$CASE_MULTI_OUT/came_final_report.md" \
  "case_multi/md: group subsection at h4 when multi-row"
assert_grep "^#### Limitations" "$CASE_MULTI_OUT/came_final_report.md" \
  "case_multi/md: limitations subsection at h4 when multi-row"
# Multi-row HTML wraps each row under <h3>Comparison ...</h3> and uses <h4>
# for the group subsections.
assert_grep "<h3>Comparison cmp_A001</h3>" "$CASE_MULTI_OUT/came_final_report.html" \
  "case_multi/html: per-comparison h3 wrapper for cmp_A001"
assert_grep "<h3>Comparison cmp_B002</h3>" "$CASE_MULTI_OUT/came_final_report.html" \
  "case_multi/html: per-comparison h3 wrapper for cmp_B002"
assert_grep "<h4>Validator metadata</h4>" "$CASE_MULTI_OUT/came_final_report.html" \
  "case_multi/html: group subsection at h4 when multi-row"
assert_grep "<h4>Limitations</h4>" "$CASE_MULTI_OUT/came_final_report.html" \
  "case_multi/html: limitations subsection at h4 when multi-row"
pass "case_multi: multi-row R4 summary renders one block per comparison with correct heading hierarchy"

# ── case 13: single-row R4 summary keeps groups at ### / h3 ─────────────────
# Regression: when only one comparison row exists, group subsections use h3
# (single-level structure). This pins the single-row hierarchy.
assert_grep "^### Validator metadata" "$CASE1_OUT/came_final_report.md" \
  "case_single: group subsection at h3 when single-row"
assert_grep "<h3>Validator metadata</h3>" "$CASE1_OUT/came_final_report.html" \
  "case_single/html: group subsection at h3 when single-row"
assert_not_grep "^### Comparison" "$CASE1_OUT/came_final_report.md" \
  "case_single: no per-comparison wrapper heading when single-row"
pass "case_single: single-row R4 summary uses h3 groups and no per-comparison wrapper"

# ── case 14: R2/R3 body text reinforces R4 distinction (Track A wording) ─────
CASE14="$TMP_DIR/case14"
CASE14_OUT="$TMP_DIR/case14_out"
setup_min_fixture "$CASE14"
write_ceeg_headers "$CASE14"
write_r2_success "$CASE14"
mkdir -p "$CASE14_OUT"
render "$CASE14" "$CASE14_OUT" "ceeg_contract_checked"
for fmt in md html; do
  f="$CASE14_OUT/came_final_report.$fmt"
  assert_grep "CAME consumed CEEG R2/R3 contract artifacts in this run" "$f" \
    "case14/$fmt: existing R2/R3 body retained"
  assert_grep "R2/R3 contract artifacts do not substitute for R4 comparability-evidence reporting" "$f" \
    "case14/$fmt: R4 distinction sentence present"
done
pass "case14: ceeg_contract_checked body retains R2/R3 wording and adds R4 distinction"

# ── Results ──────────────────────────────────────────────────────────────────
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
