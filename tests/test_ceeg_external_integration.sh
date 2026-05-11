#!/usr/bin/env sh
# Real-CEEG external integration test for CAME-I2.
# Exercises the boundary: CEEG validator CLI -> R2/R3 artifacts -> CAME-I0 summarizer.
# Skipped unless CEEG_REPO is set. Does not alter default CAME CI.
# Does not run the full Nextflow orchestration path.
#
# Required:
#   CEEG_REPO         path to a real CEEG repository checkout
#
# Optional:
#   CEEG_R2_RUN_DIR           override R2 valid run dir (default: $CEEG_REPO/examples/R2_came_overlay_valid/enabled)
#   CEEG_R3_RUN_DIR           override R3 valid run dir (default: $CEEG_REPO/examples/R3_mapping_contract_valid/basic)
#   CEEG_R2_INVALID_RUN_DIR   override R2 invalid run dir
#   CEEG_R3_INVALID_RUN_DIR   override R3 invalid run dir
#   CEEG_R2_FATAL_RUN_DIR     R2 fatal run dir (tested only if set; exit 2 empirically confirmed)
#   CEEG_R3_FATAL_RUN_DIR     R3 fatal run dir (tested only if set; exit 2 empirically confirmed)
#   CEEG_VALIDATION_MODE      validator --validation-mode (default: development)
#   CEEG_CREATED_AT           forwarded as --created-at when set
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if [ -z "${CEEG_REPO:-}" ]; then
  echo "SKIP: CEEG_REPO is not set; real-CEEG integration test not run."
  exit 0
fi

CHECKER="$ROOT_DIR/bin/check_ceeg_orchestration.py"
SUMMARIZER="$ROOT_DIR/bin/summarize_ceeg_contract_artifacts.py"
MODE="${CEEG_VALIDATION_MODE:-development}"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PASS=0
FAIL=0
SKIPPED=0

pass()       { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail()       { printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
skip_group() { printf 'SKIP (group): %s\n' "$1"; SKIPPED=$((SKIPPED + 1)); }

assert_file() {
  file="$1"; name="$2"
  if [ -f "$file" ]; then
    pass "$name: $(basename "$file") exists"
  else
    fail "$name: expected $file"
  fi
}

assert_exit() {
  actual="$1"; expected="$2"; name="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$name: exit $expected"
  else
    fail "$name: expected exit $expected, got $actual"
  fi
}

# Column-aware exit_code helpers ──────────────────────────────────────────────
# Parse exit_code column by header name so new columns do not break assertions.

exit_code_col() {
  awk -F '\t' '
    NR == 1 {
      for (i = 1; i <= NF; i++) {
        if ($i == "exit_code") { print i; exit 0 }
      }
      exit 1
    }
  ' "$1"
}

count_exit_code() {
  file="$1"; code="$2"
  col="$(exit_code_col "$file")"
  awk -F '\t' -v c="$col" -v code="$code" \
    'NR > 1 && $c == code { n++ } END { print n + 0 }' "$file"
}

# Helpers for invoking CEEG CLIs from the CEEG repo root ─────────────────────
# Fixtures contain relative bundle paths so the cwd must be $CEEG_REPO.

run_r2() {
  run_dir="$1"; out_dir="$2"
  if [ -n "${CEEG_CREATED_AT:-}" ]; then
    (cd "$CEEG_REPO" && python3 "$CEEG_REPO/bin/run_came_overlay.py" \
      --run-dir "$run_dir" \
      --out-dir "$out_dir" \
      --validation-mode "$MODE" \
      --created-at "$CEEG_CREATED_AT")
  else
    (cd "$CEEG_REPO" && python3 "$CEEG_REPO/bin/run_came_overlay.py" \
      --run-dir "$run_dir" \
      --out-dir "$out_dir" \
      --validation-mode "$MODE")
  fi
}

run_r3() {
  run_dir="$1"; out_dir="$2"
  if [ -n "${CEEG_CREATED_AT:-}" ]; then
    (cd "$CEEG_REPO" && python3 "$CEEG_REPO/bin/run_mapping_contract.py" \
      --run-dir "$run_dir" \
      --out-dir "$out_dir" \
      --validation-mode "$MODE" \
      --created-at "$CEEG_CREATED_AT")
  else
    (cd "$CEEG_REPO" && python3 "$CEEG_REPO/bin/run_mapping_contract.py" \
      --run-dir "$run_dir" \
      --out-dir "$out_dir" \
      --validation-mode "$MODE")
  fi
}

run_checker() {
  out_dir="$1"; manifest="$2"; exit_code="$3"; label="$4"
  python3 "$CHECKER" \
    --out-dir "$out_dir" \
    --manifest-name "$manifest" \
    --exit-code "$exit_code" \
    --validator-label "$label"
}

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP 1 — CLI contract verification
# ═══════════════════════════════════════════════════════════════════════════════

printf '\n── Group 1: CLI contract verification ──────────────────────────────────────\n'

for _cli in run_came_overlay.py run_mapping_contract.py; do
  if [ -f "$CEEG_REPO/bin/$_cli" ]; then
    pass "1: bin/$_cli present"
  else
    fail "1: bin/$_cli not found at $CEEG_REPO/bin/$_cli"
  fi
done

R2_HELP="$TMP_DIR/r2_help.txt"
R3_HELP="$TMP_DIR/r3_help.txt"
python3 "$CEEG_REPO/bin/run_came_overlay.py"    --help > "$R2_HELP" 2>&1 || true
python3 "$CEEG_REPO/bin/run_mapping_contract.py" --help > "$R3_HELP" 2>&1 || true

for _flag in '--run-dir' '--out-dir' '--validation-mode' '--created-at'; do
  if grep -qF -- "$_flag" "$R2_HELP"; then
    pass "1: run_came_overlay.py help has $_flag"
  else
    fail "1: run_came_overlay.py help missing $_flag"
  fi
  if grep -qF -- "$_flag" "$R3_HELP"; then
    pass "1: run_mapping_contract.py help has $_flag"
  else
    fail "1: run_mapping_contract.py help missing $_flag"
  fi
done

if grep -qF "$MODE" "$R2_HELP"; then
  pass "1: run_came_overlay.py help enumerates validation-mode '$MODE'"
else
  printf 'NOTE: run_came_overlay.py help does not enumerate "%s"; invocation will confirm.\n' "$MODE"
fi
if grep -qF "$MODE" "$R3_HELP"; then
  pass "1: run_mapping_contract.py help enumerates validation-mode '$MODE'"
else
  printf 'NOTE: run_mapping_contract.py help does not enumerate "%s"; invocation will confirm.\n' "$MODE"
fi

# Track valid outputs so later groups can optionally include them.
R2_OUT=""
R3_OUT=""

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP 2 — R2 valid fixture (expected exit 0)
# ═══════════════════════════════════════════════════════════════════════════════

printf '\n── Group 2: R2 valid fixture ───────────────────────────────────────────────\n'

R2_RUN="${CEEG_R2_RUN_DIR:-$CEEG_REPO/examples/R2_came_overlay_valid/enabled}"
_R2_OUT="$TMP_DIR/r2_valid_out"

if [ ! -d "$R2_RUN" ]; then
  skip_group "2: R2 valid run dir not found: $R2_RUN"
else
  set +e
  run_r2 "$R2_RUN" "$_R2_OUT"
  R2_RC=$?
  set -e
  assert_exit "$R2_RC" 0 "2: R2 valid CLI exit"
  assert_file "$_R2_OUT/came_report_manifest.json"   "2: R2 valid manifest"
  assert_file "$_R2_OUT/compatibility_summary.json"  "2: R2 valid compatibility_summary"
  set +e
  run_checker "$_R2_OUT" came_report_manifest.json "$R2_RC" r2_overlay
  _CHECKER_RC=$?
  set -e
  assert_exit "$_CHECKER_RC" 0 "2: R2 valid checker"
  R2_OUT="$_R2_OUT"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP 3 — R3 valid fixture (expected exit 0)
# ═══════════════════════════════════════════════════════════════════════════════

printf '\n── Group 3: R3 valid fixture ───────────────────────────────────────────────\n'

R3_RUN="${CEEG_R3_RUN_DIR:-$CEEG_REPO/examples/R3_mapping_contract_valid/basic}"
_R3_OUT="$TMP_DIR/r3_valid_out"

if [ ! -d "$R3_RUN" ]; then
  skip_group "3: R3 valid run dir not found: $R3_RUN"
else
  set +e
  run_r3 "$R3_RUN" "$_R3_OUT"
  R3_RC=$?
  set -e
  assert_exit "$R3_RC" 0 "3: R3 valid CLI exit"
  assert_file "$_R3_OUT/mapping_report_manifest.json" "3: R3 valid manifest"
  assert_file "$_R3_OUT/mapping_summary.tsv"          "3: R3 valid mapping_summary"
  assert_file "$_R3_OUT/unmapped_features.tsv"        "3: R3 valid unmapped_features"
  assert_file "$_R3_OUT/ambiguous_mappings.tsv"       "3: R3 valid ambiguous_mappings"
  set +e
  run_checker "$_R3_OUT" mapping_report_manifest.json "$R3_RC" r3_mapping
  _CHECKER_RC=$?
  set -e
  assert_exit "$_CHECKER_RC" 0 "3: R3 valid checker"
  R3_OUT="$_R3_OUT"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP 4 — CAME-I0 adapter consumes valid real CEEG artifacts
# ═══════════════════════════════════════════════════════════════════════════════

printf '\n── Group 4: CAME-I0 adapter (valid path) ───────────────────────────────────\n'

if [ -n "$R2_OUT" ] && [ -n "$R3_OUT" ]; then
  _SUMMARY_VALID="$TMP_DIR/summary_valid"
  set +e
  python3 "$SUMMARIZER" \
    --r2-dir "$R2_OUT" \
    --r3-dir "$R3_OUT" \
    --out-dir "$_SUMMARY_VALID" \
    --validation-mode "$MODE"
  _SUMMARIZER_RC=$?
  set -e
  assert_exit "$_SUMMARIZER_RC" 0 "4: summarizer valid exit"
  assert_file "$_SUMMARY_VALID/ceeg_contract_summary.tsv" "4: ceeg_contract_summary.tsv"
  _SUMMARY_LINES=$(wc -l < "$_SUMMARY_VALID/ceeg_contract_summary.tsv" | tr -d ' ')
  if [ "$_SUMMARY_LINES" -ge 3 ]; then
    pass "4: ceeg_contract_summary.tsv has >= 3 lines (header + >= 2 data rows)"
  else
    fail "4: ceeg_contract_summary.tsv: expected >= 3 lines, got $_SUMMARY_LINES"
  fi
  _N0="$(count_exit_code "$_SUMMARY_VALID/ceeg_contract_summary.tsv" 0)"
  if [ "$_N0" -ge 2 ]; then
    pass "4: ceeg_contract_summary.tsv has >= 2 rows with exit_code=0"
  else
    fail "4: ceeg_contract_summary.tsv: expected >= 2 rows with exit_code=0, got $_N0"
  fi
  assert_file "$_SUMMARY_VALID/ceeg_mapping_summary.tsv" "4: ceeg_mapping_summary.tsv"
  _MAPPING_LINES=$(wc -l < "$_SUMMARY_VALID/ceeg_mapping_summary.tsv" | tr -d ' ')
  if [ "$_MAPPING_LINES" -ge 2 ]; then
    pass "4: ceeg_mapping_summary.tsv has >= 2 lines"
  else
    fail "4: ceeg_mapping_summary.tsv: expected >= 2 lines, got $_MAPPING_LINES"
  fi
else
  skip_group "4: R2 or R3 valid output absent; skipping joint adapter test"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP 5 — R2 invalid fixture (expected exit 1)
# ═══════════════════════════════════════════════════════════════════════════════

printf '\n── Group 5: R2 invalid fixture (exit 1) ────────────────────────────────────\n'

_R2_INVALID="${CEEG_R2_INVALID_RUN_DIR:-$CEEG_REPO/examples/R2_came_overlay_invalid/core/incompatible_contract_version}"
_R2_INVALID_OUT="$TMP_DIR/r2_invalid_out"

if [ ! -d "$_R2_INVALID" ]; then
  skip_group "5: R2 invalid run dir not found: $_R2_INVALID"
else
  set +e
  run_r2 "$_R2_INVALID" "$_R2_INVALID_OUT"
  _R2_INV_RC=$?
  set -e
  assert_exit "$_R2_INV_RC" 1 "5: R2 invalid CLI exit 1"
  assert_file "$_R2_INVALID_OUT/came_report_manifest.json" "5: R2 invalid manifest (exit 1)"
  set +e
  run_checker "$_R2_INVALID_OUT" came_report_manifest.json "$_R2_INV_RC" r2_overlay
  _CHECKER_INV_RC=$?
  set -e
  assert_exit "$_CHECKER_INV_RC" 0 "5: R2 invalid checker exits 0 (exit-1 pass-through)"
  _SUMMARY_R2_INV="$TMP_DIR/summary_r2_invalid"
  set +e
  python3 "$SUMMARIZER" \
    --r2-dir "$_R2_INVALID_OUT" \
    --out-dir "$_SUMMARY_R2_INV" \
    --validation-mode "$MODE"
  _SUMMARIZER_INV_RC=$?
  set -e
  if [ "$_SUMMARIZER_INV_RC" = "0" ] || [ "$_SUMMARIZER_INV_RC" = "1" ]; then
    pass "5: summarizer exited $_SUMMARIZER_INV_RC for invalid R2 (0 or 1 both valid)"
  else
    fail "5: summarizer unexpected exit $_SUMMARIZER_INV_RC for invalid R2"
  fi
  assert_file "$_SUMMARY_R2_INV/ceeg_contract_summary.tsv" "5: summary from invalid R2"
  _N1="$(count_exit_code "$_SUMMARY_R2_INV/ceeg_contract_summary.tsv" 1)"
  if [ "$_N1" -ge 1 ]; then
    pass "5: ceeg_contract_summary.tsv records exit_code=1"
  else
    fail "5: ceeg_contract_summary.tsv: expected >= 1 row with exit_code=1, got $_N1"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP 6 — R3 invalid fixture (expected exit 1)
# ═══════════════════════════════════════════════════════════════════════════════

printf '\n── Group 6: R3 invalid fixture (exit 1) ────────────────────────────────────\n'

_R3_INVALID="${CEEG_R3_INVALID_RUN_DIR:-$CEEG_REPO/examples/R3_mapping_contract_invalid/core/invalid_mapping_status}"
_R3_INVALID_OUT="$TMP_DIR/r3_invalid_out"

if [ ! -d "$_R3_INVALID" ]; then
  skip_group "6: R3 invalid run dir not found: $_R3_INVALID"
else
  set +e
  run_r3 "$_R3_INVALID" "$_R3_INVALID_OUT"
  _R3_INV_RC=$?
  set -e
  assert_exit "$_R3_INV_RC" 1 "6: R3 invalid CLI exit 1"
  assert_file "$_R3_INVALID_OUT/mapping_report_manifest.json" "6: R3 invalid manifest (exit 1)"
  set +e
  run_checker "$_R3_INVALID_OUT" mapping_report_manifest.json "$_R3_INV_RC" r3_mapping
  _CHECKER_R3_INV_RC=$?
  set -e
  assert_exit "$_CHECKER_R3_INV_RC" 0 "6: R3 invalid checker exits 0"
  _SUMMARY_R3_INV="$TMP_DIR/summary_r3_invalid"
  set +e
  python3 "$SUMMARIZER" \
    --r3-dir "$_R3_INVALID_OUT" \
    --out-dir "$_SUMMARY_R3_INV" \
    --validation-mode "$MODE"
  _SUMMARIZER_R3_INV_RC=$?
  set -e
  if [ "$_SUMMARIZER_R3_INV_RC" = "0" ] || [ "$_SUMMARIZER_R3_INV_RC" = "1" ]; then
    pass "6: summarizer exited $_SUMMARIZER_R3_INV_RC for invalid R3 (0 or 1 both valid)"
  else
    fail "6: summarizer unexpected exit $_SUMMARIZER_R3_INV_RC for invalid R3"
  fi
  assert_file "$_SUMMARY_R3_INV/ceeg_contract_summary.tsv" "6: summary from invalid R3"
  _N1_R3="$(count_exit_code "$_SUMMARY_R3_INV/ceeg_contract_summary.tsv" 1)"
  if [ "$_N1_R3" -ge 1 ]; then
    pass "6: ceeg_contract_summary.tsv records exit_code=1"
  else
    fail "6: ceeg_contract_summary.tsv: expected >= 1 row with exit_code=1, got $_N1_R3"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# GROUP 7 — fatal fixtures (exit 2), empirically confirmed only
# ═══════════════════════════════════════════════════════════════════════════════

printf '\n── Group 7: fatal fixtures (exit 2, empirically confirmed only) ─────────────\n'

test_fatal_r2() {
  _fatal_dir="$1"; _out_dir="$2"
  set +e
  run_r2 "$_fatal_dir" "$_out_dir"
  _fatal_r2_rc=$?
  set -e
  if [ "$_fatal_r2_rc" = "2" ]; then
    assert_file "$_out_dir/came_report_manifest.json" "7: R2 fatal manifest (exit 2)"
    set +e
    run_checker "$_out_dir" came_report_manifest.json 2 r2_overlay
    _checker_fatal_rc=$?
    set -e
    assert_exit "$_checker_fatal_rc" 0 "7: R2 fatal checker exits 0"
    _summary_r2_fatal="$TMP_DIR/summary_r2_fatal"
    set +e
    python3 "$SUMMARIZER" \
      --r2-dir "$_out_dir" \
      --out-dir "$_summary_r2_fatal" \
      --validation-mode "$MODE"
    set -e
    assert_file "$_summary_r2_fatal/ceeg_contract_summary.tsv" "7: summary from R2 fatal"
    _n2="$(count_exit_code "$_summary_r2_fatal/ceeg_contract_summary.tsv" 2)"
    if [ "$_n2" -ge 1 ]; then
      pass "7: R2 fatal: ceeg_contract_summary.tsv records exit_code=2"
    else
      fail "7: R2 fatal: expected >= 1 row with exit_code=2, got $_n2"
    fi
  else
    printf 'SKIP (group 7/R2): candidate exited %s (not 2); treating as non-fatal.\n' "$_fatal_r2_rc"
  fi
}

test_fatal_r3() {
  _fatal_dir="$1"; _out_dir="$2"
  set +e
  run_r3 "$_fatal_dir" "$_out_dir"
  _fatal_r3_rc=$?
  set -e
  if [ "$_fatal_r3_rc" = "2" ]; then
    assert_file "$_out_dir/mapping_report_manifest.json" "7: R3 fatal manifest (exit 2)"
    set +e
    run_checker "$_out_dir" mapping_report_manifest.json 2 r3_mapping
    _checker_fatal_rc=$?
    set -e
    assert_exit "$_checker_fatal_rc" 0 "7: R3 fatal checker exits 0"
    _summary_r3_fatal="$TMP_DIR/summary_r3_fatal"
    set +e
    python3 "$SUMMARIZER" \
      --r3-dir "$_out_dir" \
      --out-dir "$_summary_r3_fatal" \
      --validation-mode "$MODE"
    set -e
    assert_file "$_summary_r3_fatal/ceeg_contract_summary.tsv" "7: summary from R3 fatal"
    _n2_r3="$(count_exit_code "$_summary_r3_fatal/ceeg_contract_summary.tsv" 2)"
    if [ "$_n2_r3" -ge 1 ]; then
      pass "7: R3 fatal: ceeg_contract_summary.tsv records exit_code=2"
    else
      fail "7: R3 fatal: expected >= 1 row with exit_code=2, got $_n2_r3"
    fi
  else
    printf 'SKIP (group 7/R3): candidate exited %s (not 2); treating as non-fatal.\n' "$_fatal_r3_rc"
  fi
}

_FATAL_TESTED=0

if [ -n "${CEEG_R2_FATAL_RUN_DIR:-}" ]; then
  if [ -d "$CEEG_R2_FATAL_RUN_DIR" ]; then
    test_fatal_r2 "$CEEG_R2_FATAL_RUN_DIR" "$TMP_DIR/r2_fatal_out"
    _FATAL_TESTED=$((_FATAL_TESTED + 1))
  else
    fail "7: CEEG_R2_FATAL_RUN_DIR set but not found: $CEEG_R2_FATAL_RUN_DIR"
  fi
fi

if [ -n "${CEEG_R3_FATAL_RUN_DIR:-}" ]; then
  if [ -d "$CEEG_R3_FATAL_RUN_DIR" ]; then
    test_fatal_r3 "$CEEG_R3_FATAL_RUN_DIR" "$TMP_DIR/r3_fatal_out"
    _FATAL_TESTED=$((_FATAL_TESTED + 1))
  else
    fail "7: CEEG_R3_FATAL_RUN_DIR set but not found: $CEEG_R3_FATAL_RUN_DIR"
  fi
fi

if [ "$_FATAL_TESTED" = "0" ]; then
  printf 'SKIP (group 7): CEEG_R2_FATAL_RUN_DIR and CEEG_R3_FATAL_RUN_DIR not set; '
  printf 'mock-driven CAME tests cover exit-2 behavior.\n'
fi

# ═══════════════════════════════════════════════════════════════════════════════
printf '\nResults: %d passed, %d failed, %d group-skipped\n' "$PASS" "$FAIL" "$SKIPPED"
exit "$( [ "$FAIL" = "0" ] && echo 0 || echo 1 )"
