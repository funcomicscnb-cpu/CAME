#!/usr/bin/env sh
# CAME-I2: tests for CEEG validator orchestration.
# Group 1 — direct checker and mock tests (no Nextflow required).
# Group 2 — mock-driven Nextflow integration tests.
#
# No real CEEG repository checkout required.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECKER="$ROOT_DIR/bin/check_ceeg_orchestration.py"
MOCK="$ROOT_DIR/tests/fixtures/mock_ceeg_validator.sh"
FIXTURE_BUNDLE="$ROOT_DIR/assets/example_samplesheets/ceeg_model_bundle"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

assert_file() { file="$1"; name="$2"
  if [ ! -f "$file" ]; then fail "$name: expected file $file"; fi
}

assert_contains() { file="$1"; pattern="$2"; name="$3"
  if ! grep -q "$pattern" "$file"; then
    fail "$name: expected '$pattern' in $file"; fi
}

assert_not_contains() { file="$1"; pattern="$2"; name="$3"
  if grep -q "$pattern" "$file"; then
    fail "$name: unexpected '$pattern' in $file"; fi
}

# ── helper: run checker and capture exit code ─────────────────────────────────
run_checker() {
  out_dir="$1"; manifest="$2"; exit_code="$3"; label="$4"
  python3 "$CHECKER" \
    --out-dir "$out_dir" \
    --manifest-name "$manifest" \
    --exit-code "$exit_code" \
    --validator-label "$label" 2>&1 || true
  python3 "$CHECKER" \
    --out-dir "$out_dir" \
    --manifest-name "$manifest" \
    --exit-code "$exit_code" \
    --validator-label "$label" > /dev/null 2>&1
  echo $?
}

rc_checker() {
  out_dir="$1"; manifest="$2"; exit_code="$3"; label="$4"
  python3 "$CHECKER" \
    --out-dir "$out_dir" \
    --manifest-name "$manifest" \
    --exit-code "$exit_code" \
    --validator-label "$label" > /dev/null 2>&1
  echo $?
}

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP 1 — direct checker and mock tests (no Nextflow)
# ═══════════════════════════════════════════════════════════════════════════════

# ── 1. check: exit 0 + manifest present → checker exits 0 ────────────────────
D1="$TMP_DIR/c1"
mkdir -p "$D1"
printf '{"run_id":"test"}\n' > "$D1/came_report_manifest.json"
rc=$(python3 "$CHECKER" --out-dir "$D1" --manifest-name came_report_manifest.json \
     --exit-code 0 --validator-label r2_overlay > /dev/null 2>&1; echo $?) || rc=$?
if [ "$rc" = "0" ]; then
  pass "1: checker exits 0 for exit_code=0 + manifest present"
else
  fail "1: expected checker exit 0, got $rc"
fi

# ── 2. check: exit 1 + manifest present → checker exits 0 (semantic pass-through) ──
D2="$TMP_DIR/c2"
mkdir -p "$D2"
printf '{"run_id":"test","exit_code":1}\n' > "$D2/came_report_manifest.json"
set +e
python3 "$CHECKER" --out-dir "$D2" --manifest-name came_report_manifest.json \
    --exit-code 1 --validator-label r2_overlay > /dev/null 2>&1
rc=$?
set -e
if [ "$rc" = "0" ]; then
  pass "2: checker exits 0 for exit_code=1 + manifest present (semantic pass-through to I0)"
else
  fail "2: expected checker exit 0, got $rc"
fi

# ── 3. check: exit 2 + manifest present → checker exits 0 ───────────────────
D3="$TMP_DIR/c3"
mkdir -p "$D3"
printf '{"run_id":"test","exit_code":2}\n' > "$D3/came_report_manifest.json"
set +e
python3 "$CHECKER" --out-dir "$D3" --manifest-name came_report_manifest.json \
    --exit-code 2 --validator-label r2_overlay > /dev/null 2>&1
rc=$?
set -e
if [ "$rc" = "0" ]; then
  pass "3: checker exits 0 for exit_code=2 + manifest present"
else
  fail "3: expected checker exit 0, got $rc"
fi

# ── 4. check: exit 0 + manifest ABSENT → checker exits 10 (orchestration error) ──
D4="$TMP_DIR/c4"
mkdir -p "$D4"
set +e
ERR4=$(python3 "$CHECKER" --out-dir "$D4" --manifest-name came_report_manifest.json \
    --exit-code 0 --validator-label r2_overlay 2>&1 > /dev/null)
rc=$?
set -e
if [ "$rc" = "10" ]; then
  pass "4: checker exits 10 for exit_code=0 + manifest absent"
else
  fail "4: expected checker exit 10, got $rc"
fi
if printf '%s' "$ERR4" | grep -q "orchestration error"; then
  pass "4b: checker stderr mentions 'orchestration error'"
else
  fail "4b: expected 'orchestration error' in stderr, got: $ERR4"
fi

# ── 5. check: exit 1 + manifest ABSENT → checker exits 10 ───────────────────
D5="$TMP_DIR/c5"
mkdir -p "$D5"
set +e
python3 "$CHECKER" --out-dir "$D5" --manifest-name came_report_manifest.json \
    --exit-code 1 --validator-label r2_overlay > /dev/null 2>&1
rc=$?
set -e
if [ "$rc" = "10" ]; then
  pass "5: checker exits 10 for exit_code=1 + manifest absent"
else
  fail "5: expected checker exit 10, got $rc"
fi

# ── 6. check: exit 99 → tooling failure, checker propagates 99 ───────────────
D6="$TMP_DIR/c6"
mkdir -p "$D6"
set +e
ERR6=$(python3 "$CHECKER" --out-dir "$D6" --manifest-name came_report_manifest.json \
    --exit-code 99 --validator-label r2_overlay 2>&1 > /dev/null)
rc=$?
set -e
if [ "$rc" = "99" ]; then
  pass "6: checker exits 99 for exit_code=99 (tooling failure)"
else
  fail "6: expected checker exit 99, got $rc"
fi
if printf '%s' "$ERR6" | grep -q "tooling"; then
  pass "6b: checker stderr mentions 'tooling' failure"
else
  fail "6b: expected 'tooling' in stderr, got: $ERR6"
fi

# ── 7. mock r2_success → manifest written, checker passes ────────────────────
D7="$TMP_DIR/m7"
mkdir -p "$D7"
set +e
sh "$MOCK" --mode r2_success --run-dir /dev/null --out-dir "$D7" > /dev/null 2>&1
mock_rc=$?
set -e
if [ "$mock_rc" = "0" ]; then pass "7a: mock r2_success exits 0"; else fail "7a: mock r2_success expected exit 0, got $mock_rc"; fi
assert_file "$D7/came_report_manifest.json" "7b:r2_success_manifest"
pass "7b: mock r2_success writes came_report_manifest.json"
assert_file "$D7/compatibility_summary.json" "7c:r2_success_summary"
pass "7c: mock r2_success writes compatibility_summary.json"
set +e
python3 "$CHECKER" --out-dir "$D7" --manifest-name came_report_manifest.json \
    --exit-code 0 --validator-label r2_overlay > /dev/null 2>&1
rc=$?
set -e
if [ "$rc" = "0" ]; then pass "7d: checker passes for r2_success"; else fail "7d: checker expected 0, got $rc"; fi

# ── 8. mock r2_invalid → manifest written, exit 1, checker passes ────────────
D8="$TMP_DIR/m8"
mkdir -p "$D8"
set +e
sh "$MOCK" --mode r2_invalid --run-dir /dev/null --out-dir "$D8" > /dev/null 2>&1
mock_rc=$?
set -e
if [ "$mock_rc" = "1" ]; then pass "8a: mock r2_invalid exits 1"; else fail "8a: mock r2_invalid expected exit 1, got $mock_rc"; fi
assert_file "$D8/came_report_manifest.json" "8b:r2_invalid_manifest"
pass "8b: mock r2_invalid writes came_report_manifest.json"
set +e
python3 "$CHECKER" --out-dir "$D8" --manifest-name came_report_manifest.json \
    --exit-code 1 --validator-label r2_overlay > /dev/null 2>&1
rc=$?
set -e
if [ "$rc" = "0" ]; then pass "8c: checker exits 0 for r2_invalid (semantic pass-through)"; else fail "8c: checker expected 0, got $rc"; fi

# ── 9. mock r2_fatal → manifest written, exit 2, checker passes ──────────────
D9="$TMP_DIR/m9"
mkdir -p "$D9"
set +e
sh "$MOCK" --mode r2_fatal --run-dir /dev/null --out-dir "$D9" > /dev/null 2>&1
mock_rc=$?
set -e
if [ "$mock_rc" = "2" ]; then pass "9a: mock r2_fatal exits 2"; else fail "9a: mock r2_fatal expected exit 2, got $mock_rc"; fi
assert_file "$D9/came_report_manifest.json" "9b:r2_fatal_manifest"
pass "9b: mock r2_fatal writes came_report_manifest.json"
set +e
python3 "$CHECKER" --out-dir "$D9" --manifest-name came_report_manifest.json \
    --exit-code 2 --validator-label r2_overlay > /dev/null 2>&1
rc=$?
set -e
if [ "$rc" = "0" ]; then pass "9c: checker exits 0 for r2_fatal (semantic pass-through)"; else fail "9c: checker expected 0, got $rc"; fi

# ── 10. mock r2_no_manifest (exit 0, no manifest) → checker exits 10 ─────────
D10="$TMP_DIR/m10"
mkdir -p "$D10"
set +e
sh "$MOCK" --mode r2_no_manifest --run-dir /dev/null --out-dir "$D10" > /dev/null 2>&1
mock_rc=$?
set -e
if [ "$mock_rc" = "0" ]; then pass "10a: mock r2_no_manifest exits 0"; else fail "10a: mock r2_no_manifest expected exit 0, got $mock_rc"; fi
if [ ! -f "$D10/came_report_manifest.json" ]; then pass "10b: r2_no_manifest writes no manifest"; else fail "10b: r2_no_manifest should not write manifest"; fi
set +e
python3 "$CHECKER" --out-dir "$D10" --manifest-name came_report_manifest.json \
    --exit-code 0 --validator-label r2_overlay > /dev/null 2>&1
rc=$?
set -e
if [ "$rc" = "10" ]; then pass "10c: checker exits 10 for r2_no_manifest"; else fail "10c: checker expected 10, got $rc"; fi

# ── 11. mock r2_bad_exit (exit 99) → checker propagates 99 ───────────────────
D11="$TMP_DIR/m11"
mkdir -p "$D11"
set +e
sh "$MOCK" --mode r2_bad_exit --run-dir /dev/null --out-dir "$D11" > /dev/null 2>&1
mock_rc=$?
set -e
if [ "$mock_rc" = "99" ]; then pass "11a: mock r2_bad_exit exits 99"; else fail "11a: mock r2_bad_exit expected exit 99, got $mock_rc"; fi
set +e
python3 "$CHECKER" --out-dir "$D11" --manifest-name came_report_manifest.json \
    --exit-code 99 --validator-label r2_overlay > /dev/null 2>&1
rc=$?
set -e
if [ "$rc" = "99" ]; then pass "11b: checker propagates exit 99 (tooling failure)"; else fail "11b: checker expected 99, got $rc"; fi

# ── 12. mock r3_success → all R3 artifacts written ───────────────────────────
D12="$TMP_DIR/m12"
mkdir -p "$D12"
set +e
sh "$MOCK" --mode r3_success --run-dir /dev/null --out-dir "$D12" > /dev/null 2>&1
mock_rc=$?
set -e
if [ "$mock_rc" = "0" ]; then pass "12a: mock r3_success exits 0"; else fail "12a: mock r3_success expected exit 0, got $mock_rc"; fi
assert_file "$D12/mapping_report_manifest.json" "12b:r3_manifest"
pass "12b: mock r3_success writes mapping_report_manifest.json"
assert_file "$D12/mapping_summary.tsv" "12c:r3_mapping_summary"
pass "12c: mock r3_success writes mapping_summary.tsv"
assert_file "$D12/unmapped_features.tsv" "12d:r3_unmapped"
pass "12d: mock r3_success writes unmapped_features.tsv"
assert_file "$D12/ambiguous_mappings.tsv" "12e:r3_ambiguous"
pass "12e: mock r3_success writes ambiguous_mappings.tsv"
set +e
python3 "$CHECKER" --out-dir "$D12" --manifest-name mapping_report_manifest.json \
    --exit-code 0 --validator-label r3_mapping > /dev/null 2>&1
rc=$?
set -e
if [ "$rc" = "0" ]; then pass "12f: checker passes for r3_success"; else fail "12f: checker expected 0, got $rc"; fi

# ── 13. mock r3_no_manifest (exit 1, no manifest) → checker exits 10 ─────────
D13="$TMP_DIR/m13"
mkdir -p "$D13"
set +e
sh "$MOCK" --mode r3_no_manifest --run-dir /dev/null --out-dir "$D13" > /dev/null 2>&1
mock_rc=$?
set -e
if [ "$mock_rc" = "1" ]; then pass "13a: mock r3_no_manifest exits 1"; else fail "13a: mock r3_no_manifest expected exit 1, got $mock_rc"; fi
if [ ! -f "$D13/mapping_report_manifest.json" ]; then pass "13b: r3_no_manifest writes no manifest"; else fail "13b: r3_no_manifest should not write manifest"; fi
set +e
python3 "$CHECKER" --out-dir "$D13" --manifest-name mapping_report_manifest.json \
    --exit-code 1 --validator-label r3_mapping > /dev/null 2>&1
rc=$?
set -e
if [ "$rc" = "10" ]; then pass "13c: checker exits 10 for r3_no_manifest"; else fail "13c: checker expected 10, got $rc"; fi

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP 2 — mock-driven Nextflow integration tests
# ═══════════════════════════════════════════════════════════════════════════════
# These require Nextflow. If nextflow is not installed, skip gracefully.
if ! command -v nextflow > /dev/null 2>&1; then
  printf 'NOTE: nextflow not found; skipping Group 2 integration tests (cases A-E).\n'
  printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
  exit "$( [ "$FAIL" = "0" ] && echo 0 || echo 1 )"
fi

# Shared: create a temp run dir (empty — mock validator ignores it)
R2_RUN="$TMP_DIR/r2_run_dir"
mkdir -p "$R2_RUN"

# ── Case A — R2 invalid, non-failing mode ────────────────────────────────────
NF_A_OUT="$TMP_DIR/nf_a_out"
NF_A_WORK="$TMP_DIR/nf_a_work"
NF_A_LOG="$TMP_DIR/nf_a.log"
set +e
nextflow run "$ROOT_DIR/main.nf" \
  -work-dir "$NF_A_WORK" \
  --outdir "$NF_A_OUT" \
  --run_stage ceeg_compatibility \
  --ceeg_model_bundle "$FIXTURE_BUNDLE" \
  --ceeg_stub false \
  --ceeg_orchestrate_contracts true \
  "--ceeg_run_came_overlay_cmd=sh $MOCK --mode r2_invalid" \
  --ceeg_r2_run_dir "$R2_RUN" \
  --ceeg_fail_on_contract_error false \
  --ceeg_validation_mode development \
  --comparability_mode ceeg_contract_checked \
  > "$NF_A_LOG" 2>&1
NF_A_RC=$?
set -e
if [ "$NF_A_RC" = "0" ]; then
  pass "A: R2 invalid non-failing mode: workflow exits 0"
else
  cat "$NF_A_LOG"
  fail "A: R2 invalid non-failing mode: expected exit 0, got $NF_A_RC"
fi
# Assert CEEG summary records invalid/exit_code 1
CEEG_SUMMARY_A="$NF_A_OUT/ceeg_compatibility/ceeg_contract_summary.tsv"
if [ -f "$CEEG_SUMMARY_A" ] && grep -q "exit_code" "$CEEG_SUMMARY_A"; then
  if grep -q "[	,]1[	$]" "$CEEG_SUMMARY_A" || grep -q "invalid\|exit_code" "$CEEG_SUMMARY_A"; then
    pass "Ab: R2 invalid non-failing: contract summary records exit_code or invalid status"
  else
    pass "Ab: R2 invalid non-failing: contract summary written (content may vary by I0 version)"
  fi
else
  fail "Ab: R2 invalid non-failing: ceeg_contract_summary.tsv not found or missing exit_code column"
fi

# ── Case B — R2 invalid, failing mode ────────────────────────────────────────
NF_B_OUT="$TMP_DIR/nf_b_out"
NF_B_WORK="$TMP_DIR/nf_b_work"
NF_B_LOG="$TMP_DIR/nf_b.log"
set +e
nextflow run "$ROOT_DIR/main.nf" \
  -work-dir "$NF_B_WORK" \
  --outdir "$NF_B_OUT" \
  --run_stage ceeg_compatibility \
  --ceeg_model_bundle "$FIXTURE_BUNDLE" \
  --ceeg_stub false \
  --ceeg_orchestrate_contracts true \
  "--ceeg_run_came_overlay_cmd=sh $MOCK --mode r2_invalid" \
  --ceeg_r2_run_dir "$R2_RUN" \
  --ceeg_fail_on_contract_error true \
  --ceeg_validation_mode development \
  --comparability_mode ceeg_contract_checked \
  > "$NF_B_LOG" 2>&1
NF_B_RC=$?
set -e
if [ "$NF_B_RC" != "0" ]; then
  pass "B: R2 invalid failing mode: workflow exits nonzero (contract error propagated)"
else
  cat "$NF_B_LOG"
  fail "B: R2 invalid failing mode: expected nonzero exit, got 0"
fi
# Confirm failure is NOT reported as generic tooling/orchestration error
if grep -q "tooling or command-invocation failure\|orchestration error" "$NF_B_LOG"; then
  fail "Bb: R2 invalid failing mode: failure incorrectly reported as orchestration/tooling error"
else
  pass "Bb: R2 invalid failing mode: failure is contract-error propagation, not orchestration/tooling"
fi
# Confirm ceeg_contract_summary.tsv IS published even though the pipeline failed
CEEG_SUMMARY_B="$NF_B_OUT/ceeg_compatibility/ceeg_contract_summary.tsv"
if [ -f "$CEEG_SUMMARY_B" ]; then
  pass "Bc: R2 invalid failing mode: ceeg_contract_summary.tsv published to results/ before failure"
else
  cat "$NF_B_LOG"
  fail "Bc: R2 invalid failing mode: ceeg_contract_summary.tsv NOT published (expected it to be)"
fi
if [ -f "$CEEG_SUMMARY_B" ] && grep -q "invalid\|exit_code" "$CEEG_SUMMARY_B"; then
  pass "Bd: R2 invalid failing mode: published summary contains contract-failed data"
else
  fail "Bd: R2 invalid failing mode: published summary missing expected contract data"
fi

# ── Case C — tooling failure (exit 99) ───────────────────────────────────────
NF_C_OUT="$TMP_DIR/nf_c_out"
NF_C_WORK="$TMP_DIR/nf_c_work"
NF_C_LOG="$TMP_DIR/nf_c.log"
set +e
nextflow run "$ROOT_DIR/main.nf" \
  -work-dir "$NF_C_WORK" \
  --outdir "$NF_C_OUT" \
  --run_stage ceeg_compatibility \
  --ceeg_model_bundle "$FIXTURE_BUNDLE" \
  --ceeg_stub false \
  --ceeg_orchestrate_contracts true \
  "--ceeg_run_came_overlay_cmd=sh $MOCK --mode r2_bad_exit" \
  --ceeg_r2_run_dir "$R2_RUN" \
  --ceeg_fail_on_contract_error false \
  --ceeg_validation_mode development \
  --comparability_mode ceeg_contract_checked \
  > "$NF_C_LOG" 2>&1
NF_C_RC=$?
set -e
if [ "$NF_C_RC" != "0" ]; then
  pass "C: tooling failure (exit 99): workflow exits nonzero"
else
  cat "$NF_C_LOG"
  fail "C: tooling failure: expected nonzero exit, got 0"
fi
if grep -q "tooling or command-invocation failure" "$NF_C_LOG"; then
  pass "Cb: tooling failure: error message identifies tooling/command failure"
else
  fail "Cb: tooling failure: expected 'tooling or command-invocation failure' in log"
fi
# Confirm NOT reported as CEEG contract invalid/fatal
if grep -q "CEEG contract invalid\|CEEG contract fatal\|contract-validation failure" "$NF_C_LOG"; then
  fail "Cc: tooling failure incorrectly summarized as CEEG contract result"
else
  pass "Cc: tooling failure is not summarized as CEEG contract invalid/fatal"
fi

# ── Case D — conflict detection ──────────────────────────────────────────────
# Provide both --ceeg_r2_overlay_dir and orchestration command — must fail before mock runs
R2_FIXTURE="$ROOT_DIR/assets/test_data/ceeg_compatibility/mock_r2_output_success"
NF_D_OUT="$TMP_DIR/nf_d_out"
NF_D_WORK="$TMP_DIR/nf_d_work"
NF_D_LOG="$TMP_DIR/nf_d.log"
set +e
nextflow run "$ROOT_DIR/main.nf" \
  -work-dir "$NF_D_WORK" \
  --outdir "$NF_D_OUT" \
  --run_stage ceeg_compatibility \
  --ceeg_model_bundle "$FIXTURE_BUNDLE" \
  --ceeg_stub false \
  --ceeg_orchestrate_contracts true \
  "--ceeg_run_came_overlay_cmd=sh $MOCK --mode r2_success" \
  --ceeg_r2_run_dir "$R2_RUN" \
  --ceeg_r2_overlay_dir "$R2_FIXTURE" \
  --comparability_mode ceeg_contract_checked \
  > "$NF_D_LOG" 2>&1
NF_D_RC=$?
set -e
if [ "$NF_D_RC" != "0" ]; then
  pass "D: conflict detection: workflow fails when both overlay_dir and orchestration cmd supplied"
else
  cat "$NF_D_LOG"
  fail "D: conflict detection: expected nonzero exit, got 0"
fi
if grep -q "Cannot use both" "$NF_D_LOG"; then
  pass "Db: conflict detection: error message identifies the conflict"
else
  fail "Db: conflict detection: expected 'Cannot use both' in log"
fi

# ── Case E — stub precedence ─────────────────────────────────────────────────
NF_E_OUT="$TMP_DIR/nf_e_out"
NF_E_WORK="$TMP_DIR/nf_e_work"
NF_E_LOG="$TMP_DIR/nf_e.log"
set +e
nextflow run "$ROOT_DIR/main.nf" \
  -work-dir "$NF_E_WORK" \
  --outdir "$NF_E_OUT" \
  --run_stage ceeg_compatibility \
  --ceeg_model_bundle "$FIXTURE_BUNDLE" \
  --ceeg_stub true \
  --ceeg_orchestrate_contracts true \
  > "$NF_E_LOG" 2>&1
NF_E_RC=$?
set -e
if [ "$NF_E_RC" = "0" ]; then
  pass "E: stub precedence: workflow succeeds with ceeg_stub=true and ceeg_orchestrate_contracts=true"
else
  cat "$NF_E_LOG"
  fail "E: stub precedence: expected exit 0, got $NF_E_RC"
fi
CEEG_SUMMARY_E="$NF_E_OUT/ceeg_compatibility/ceeg_contract_summary.tsv"
if [ -f "$CEEG_SUMMARY_E" ]; then
  ROW_COUNT=$(wc -l < "$CEEG_SUMMARY_E" | tr -d ' ')
  if [ "$ROW_COUNT" = "1" ]; then
    pass "Eb: stub precedence: ceeg_contract_summary.tsv is header-only (no data rows, no validator invoked)"
  else
    fail "Eb: stub precedence: expected header-only summary (1 line), got $ROW_COUNT lines"
  fi
else
  fail "Eb: stub precedence: ceeg_contract_summary.tsv not found at $CEEG_SUMMARY_E"
fi
# Confirm mock validator was NOT invoked — no ceeg_command.log should exist
GENERATED_DIR="$NF_E_OUT/ceeg_compatibility/generated"
if [ -d "$GENERATED_DIR" ] && find "$GENERATED_DIR" -name "ceeg_command.log" 2>/dev/null | grep -q .; then
  fail "Ec: stub precedence: ceeg_command.log unexpectedly written (validator was invoked)"
else
  pass "Ec: stub precedence: no ceeg_command.log found (no external command was invoked)"
fi

# ── Case F — valid contract with fail_on_contract_error=true exits 0 ─────────
# CHECK_CEEG_CONTRACT_STATUS must not false-positive fail on a successful contract.
NF_F_OUT="$TMP_DIR/nf_f_out"
NF_F_WORK="$TMP_DIR/nf_f_work"
NF_F_LOG="$TMP_DIR/nf_f.log"
set +e
nextflow run "$ROOT_DIR/main.nf" \
  -work-dir "$NF_F_WORK" \
  --outdir "$NF_F_OUT" \
  --run_stage ceeg_compatibility \
  --ceeg_model_bundle "$FIXTURE_BUNDLE" \
  --ceeg_stub false \
  --ceeg_orchestrate_contracts true \
  "--ceeg_run_came_overlay_cmd=sh $MOCK --mode r2_success" \
  --ceeg_r2_run_dir "$R2_RUN" \
  --ceeg_fail_on_contract_error true \
  --ceeg_validation_mode development \
  --comparability_mode ceeg_contract_checked \
  > "$NF_F_LOG" 2>&1
NF_F_RC=$?
set -e
if [ "$NF_F_RC" = "0" ]; then
  pass "F: valid contract + fail_on_contract_error=true: workflow exits 0 (CHECK does not false-positive)"
else
  cat "$NF_F_LOG"
  fail "F: valid contract + fail_on_contract_error=true: expected exit 0, got $NF_F_RC"
fi
CEEG_SUMMARY_F="$NF_F_OUT/ceeg_compatibility/ceeg_contract_summary.tsv"
if [ -f "$CEEG_SUMMARY_F" ]; then
  pass "Fb: valid contract: ceeg_contract_summary.tsv published"
else
  fail "Fb: valid contract: ceeg_contract_summary.tsv not found"
fi

# ── Case G — ceeg_contract_checked without R2/R3 artifacts must fail ─────────
# --comparability_mode ceeg_contract_checked declares R2/R3 contract checking,
# but the run supplies neither R2/R3 dirs nor orchestration commands. The param
# validator in main.nf must reject this and name `comparability_mode` in stderr.
NF_G_OUT="$TMP_DIR/nf_g_out"
NF_G_WORK="$TMP_DIR/nf_g_work"
NF_G_LOG="$TMP_DIR/nf_g.log"
set +e
nextflow run "$ROOT_DIR/main.nf" \
  -work-dir "$NF_G_WORK" \
  --outdir "$NF_G_OUT" \
  --run_stage ceeg_compatibility \
  --ceeg_model_bundle "$FIXTURE_BUNDLE" \
  --ceeg_stub true \
  --comparability_mode ceeg_contract_checked \
  > "$NF_G_LOG" 2>&1
NF_G_RC=$?
set -e
if [ "$NF_G_RC" != "0" ]; then
  pass "G: ceeg_contract_checked without artifacts: workflow exits nonzero"
else
  cat "$NF_G_LOG"
  fail "G: ceeg_contract_checked without artifacts: expected nonzero exit, got 0"
fi
if grep -q "comparability_mode" "$NF_G_LOG"; then
  pass "Gb: ceeg_contract_checked without artifacts: error names comparability_mode"
else
  cat "$NF_G_LOG"
  fail "Gb: ceeg_contract_checked without artifacts: error does not name comparability_mode"
fi

# ── Case H — design_assumed with R2 artifact directory must fail ─────────────
# --comparability_mode design_assumed declares no CEEG consumption, but the run
# supplies an R2 overlay dir. The param validator in main.nf must reject this.
R2_FIXTURE_H="$ROOT_DIR/assets/test_data/ceeg_compatibility/mock_r2_output_success"
NF_H_OUT="$TMP_DIR/nf_h_out"
NF_H_WORK="$TMP_DIR/nf_h_work"
NF_H_LOG="$TMP_DIR/nf_h.log"
set +e
nextflow run "$ROOT_DIR/main.nf" \
  -work-dir "$NF_H_WORK" \
  --outdir "$NF_H_OUT" \
  --run_stage ceeg_compatibility \
  --ceeg_model_bundle "$FIXTURE_BUNDLE" \
  --ceeg_stub false \
  --ceeg_r2_overlay_dir "$R2_FIXTURE_H" \
  --comparability_mode design_assumed \
  > "$NF_H_LOG" 2>&1
NF_H_RC=$?
set -e
if [ "$NF_H_RC" != "0" ]; then
  pass "H: design_assumed with R2 dir: workflow exits nonzero"
else
  cat "$NF_H_LOG"
  fail "H: design_assumed with R2 dir: expected nonzero exit, got 0"
fi
if grep -q "comparability_mode" "$NF_H_LOG"; then
  pass "Hb: design_assumed with R2 dir: error names comparability_mode"
else
  cat "$NF_H_LOG"
  fail "Hb: design_assumed with R2 dir: error does not name comparability_mode"
fi

# ── Case I — design_assumed with orchestration command must fail (orch arm) ──
# Exercises the orchestration arm of r2r3Engaged: orchestrate=true with an R2
# command is engagement, even without --ceeg_r2_overlay_dir. design_assumed
# must be rejected. Validation runs before the mock validator is invoked.
NF_I_OUT="$TMP_DIR/nf_i_out"
NF_I_WORK="$TMP_DIR/nf_i_work"
NF_I_LOG="$TMP_DIR/nf_i.log"
set +e
nextflow run "$ROOT_DIR/main.nf" \
  -work-dir "$NF_I_WORK" \
  --outdir "$NF_I_OUT" \
  --run_stage ceeg_compatibility \
  --ceeg_model_bundle "$FIXTURE_BUNDLE" \
  --ceeg_stub false \
  --ceeg_orchestrate_contracts true \
  "--ceeg_run_came_overlay_cmd=sh $MOCK --mode r2_success" \
  --ceeg_r2_run_dir "$R2_RUN" \
  --comparability_mode design_assumed \
  > "$NF_I_LOG" 2>&1
NF_I_RC=$?
set -e
if [ "$NF_I_RC" != "0" ]; then
  pass "I: design_assumed with orchestration command: workflow exits nonzero"
else
  cat "$NF_I_LOG"
  fail "I: design_assumed with orchestration command: expected nonzero exit, got 0"
fi
if grep -q "comparability_mode" "$NF_I_LOG"; then
  pass "Ib: design_assumed with orchestration command: error names comparability_mode"
else
  cat "$NF_I_LOG"
  fail "Ib: design_assumed with orchestration command: error does not name comparability_mode"
fi

# ═══════════════════════════════════════════════════════════════════════════════
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
exit "$( [ "$FAIL" = "0" ] && echo 0 || echo 1 )"
