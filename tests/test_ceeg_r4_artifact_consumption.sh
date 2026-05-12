#!/usr/bin/env sh
# CAME-I3: tests for bin/summarize_ceeg_r4_comparability_artifacts.py
# Direct unit tests; no Nextflow or CEEG repo checkout required.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ADAPTER="$ROOT_DIR/bin/summarize_ceeg_r4_comparability_artifacts.py"
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

assert_file() { file="$1"; name="$2"
  if [ ! -f "$file" ]; then fail "$name: expected file $file"; return 1; fi
}

assert_contains() { file="$1"; pattern="$2"; name="$3"
  if ! grep -q "$pattern" "$file"; then
    fail "$name: expected '$pattern' in $file"; return 1
  fi
}

assert_not_contains() { file="$1"; pattern="$2"; name="$3"
  if grep -q "$pattern" "$file"; then
    fail "$name: unexpected '$pattern' in $file"; return 1
  fi
}

assert_rows() { file="$1"; expected="$2"; name="$3"
  actual=$(wc -l < "$file" | tr -d ' ')
  if [ "$actual" != "$expected" ]; then
    fail "$name: expected $expected lines in $file, got $actual"
    return 1
  fi
}

# ── helper: assert column value equals expected in first data row ─────────────
assert_column_eq() { file="$1"; column="$2"; expected="$3"; name="$4"
  actual=$(awk -F'\t' -v col="$column" '
    NR == 1 {
      for (i = 1; i <= NF; i++) if ($i == col) idx = i
      next
    }
    idx > 0 && NR == 2 { print $idx; exit }
  ' "$file")
  if [ "$actual" != "$expected" ]; then
    fail "$name: expected column '$column' = '$expected' in $file, got '$actual'"
    return 1
  fi
}

# ── 1. --r4-dir absent → header-only outputs, exit 0 ─────────────────────────
CASE1="$TMP_DIR/case1"
mkdir -p "$CASE1"
python3 "$ADAPTER" --out-dir "$CASE1" --created-at 2026-05-11T00:00:00Z
assert_file "$CASE1/ceeg_r4_comparability_summary.tsv" "case1: summary file" \
  && assert_rows "$CASE1/ceeg_r4_comparability_summary.tsv" 1 "case1: summary header-only" \
  && assert_rows "$CASE1/ceeg_r4_comparability_limitations.tsv" 1 "case1: limitations header-only" \
  && assert_rows "$CASE1/ceeg_r4_comparability_evidence.tsv" 1 "case1: evidence header-only" \
  && pass "case1: no R4 dir → header-only outputs"

# ── 2. R4 success fixture → one comparison row, exit 0 ────────────────────────
CASE2="$TMP_DIR/case2"
mkdir -p "$CASE2"
python3 "$ADAPTER" --out-dir "$CASE2" --r4-dir "$R4_SUCCESS" --created-at 2026-05-11T00:00:00Z
assert_file "$CASE2/ceeg_r4_comparability_summary.tsv" "case2: summary file" \
  && assert_rows "$CASE2/ceeg_r4_comparability_summary.tsv" 2 "case2: summary has 1 row + header" \
  && assert_column_eq "$CASE2/ceeg_r4_comparability_summary.tsv" "comparability_status" "evidence_supports_comparability" "case2: comparability_status" \
  && assert_column_eq "$CASE2/ceeg_r4_comparability_summary.tsv" "exit_code" "0" "case2: exit_code" \
  && assert_column_eq "$CASE2/ceeg_r4_comparability_summary.tsv" "supporting_evidence_count" "5" "case2: supporting_evidence_count" \
  && assert_column_eq "$CASE2/ceeg_r4_comparability_summary.tsv" "comparison_id" "cmp_0001" "case2: comparison_id" \
  && assert_column_eq "$CASE2/ceeg_r4_comparability_summary.tsv" "model_id" "mock_model_alpha" "case2: model_id" \
  && assert_rows "$CASE2/ceeg_r4_comparability_evidence.tsv" 2 "case2: evidence has 1 row + header" \
  && assert_contains "$CASE2/ceeg_r4_comparability_evidence.tsv" "R4 evidence state is not biological comparability validation" "case2: evidence interpretation_note" \
  && pass "case2: R4 success fixture consumed"

# ── 3. R4 contract_error exit 1 → CAME diagnostic row (Refinement 2) ──────────
CASE3="$TMP_DIR/case3"
mkdir -p "$CASE3"
python3 "$ADAPTER" --out-dir "$CASE3" --r4-dir "$R4_CONTRACT_ERROR" --created-at 2026-05-11T00:00:00Z
assert_rows "$CASE3/ceeg_r4_comparability_summary.tsv" 2 "case3: summary has 1 diagnostic row + header" \
  && assert_column_eq "$CASE3/ceeg_r4_comparability_summary.tsv" "exit_code" "1" "case3: diagnostic exit_code=1" \
  && assert_column_eq "$CASE3/ceeg_r4_comparability_summary.tsv" "status" "contract_error" "case3: diagnostic status" \
  && assert_column_eq "$CASE3/ceeg_r4_comparability_summary.tsv" "comparability_status" "contract_error" "case3: comparability_status" \
  && assert_column_eq "$CASE3/ceeg_r4_comparability_summary.tsv" "status_basis" "upstream_contract_error" "case3: status_basis" \
  && assert_column_eq "$CASE3/ceeg_r4_comparability_summary.tsv" "primary_limitation" "upstream_contract_error" "case3: primary_limitation" \
  && assert_contains "$CASE3/ceeg_r4_comparability_summary.tsv" "R4 contract_error reported by manifest" "case3: diagnostic message" \
  && assert_rows "$CASE3/ceeg_r4_comparability_limitations.tsv" 2 "case3: limitations has 1 row + header" \
  && pass "case3: R4 contract_error → CAME diagnostic row"

# ── 4. R4 fatal exit 2 (manifest + limitations only) → diagnostic row ─────────
CASE4="$TMP_DIR/case4"
mkdir -p "$CASE4"
python3 "$ADAPTER" --out-dir "$CASE4" --r4-dir "$R4_FATAL" --created-at 2026-05-11T00:00:00Z
assert_rows "$CASE4/ceeg_r4_comparability_summary.tsv" 2 "case4: summary has 1 diagnostic row + header" \
  && assert_column_eq "$CASE4/ceeg_r4_comparability_summary.tsv" "exit_code" "2" "case4: diagnostic exit_code=2" \
  && assert_column_eq "$CASE4/ceeg_r4_comparability_summary.tsv" "status" "contract_error" "case4: diagnostic status" \
  && assert_column_eq "$CASE4/ceeg_r4_comparability_summary.tsv" "status_basis" "upstream_contract_error" "case4: status_basis" \
  && assert_contains "$CASE4/ceeg_r4_comparability_summary.tsv" "absent in fatal-shape artifact" "case4: fatal-shape message" \
  && assert_rows "$CASE4/ceeg_r4_comparability_limitations.tsv" 2 "case4: limitations has 1 row + header" \
  && assert_rows "$CASE4/ceeg_r4_comparability_evidence.tsv" 1 "case4: evidence header-only (fatal shape)" \
  && pass "case4: R4 fatal exit 2 → diagnostic row + limitations preserved"

# ── 5. --fail-on-error semantics ──────────────────────────────────────────────
CASE5="$TMP_DIR/case5"
mkdir -p "$CASE5"
# exit 1 fixture + --fail-on-error → exit 1
set +e
python3 "$ADAPTER" --out-dir "$CASE5" --r4-dir "$R4_CONTRACT_ERROR" --fail-on-error >/dev/null 2>&1
rc1=$?
set -e
if [ "$rc1" -eq 1 ]; then
  pass "case5a: --fail-on-error with exit_code=1 fixture → exit 1"
else
  fail "case5a: --fail-on-error with exit_code=1 fixture → expected exit 1, got $rc1"
fi
# exit 2 fixture + --fail-on-error → exit 2
set +e
python3 "$ADAPTER" --out-dir "$CASE5" --r4-dir "$R4_FATAL" --fail-on-error >/dev/null 2>&1
rc2=$?
set -e
if [ "$rc2" -eq 2 ]; then
  pass "case5b: --fail-on-error with exit_code=2 fixture → exit 2"
else
  fail "case5b: --fail-on-error with exit_code=2 fixture → expected exit 2, got $rc2"
fi
# success fixture without --fail-on-error → exit 0
set +e
python3 "$ADAPTER" --out-dir "$CASE5" --r4-dir "$R4_SUCCESS" >/dev/null 2>&1
rc3=$?
set -e
if [ "$rc3" -eq 0 ]; then
  pass "case5c: success fixture without --fail-on-error → exit 0"
else
  fail "case5c: success fixture → expected exit 0, got $rc3"
fi

# ── 6. Missing manifest → exit 2 diagnostic row ───────────────────────────────
CASE6="$TMP_DIR/case6"
CASE6_INPUT="$TMP_DIR/case6_input"
mkdir -p "$CASE6" "$CASE6_INPUT"
# no manifest in input dir
python3 "$ADAPTER" --out-dir "$CASE6" --r4-dir "$CASE6_INPUT"
assert_column_eq "$CASE6/ceeg_r4_comparability_summary.tsv" "status" "missing_manifest" "case6: missing_manifest status" \
  && assert_column_eq "$CASE6/ceeg_r4_comparability_summary.tsv" "exit_code" "2" "case6: missing_manifest exit_code=2" \
  && pass "case6: missing R4 manifest → diagnostic row with exit_code=2"

# ── 7. Anti-overclaim: forbidden verdict strings must NOT appear in outputs ────
CASE7="$TMP_DIR/case7"
mkdir -p "$CASE7"
python3 "$ADAPTER" --out-dir "$CASE7" --r4-dir "$R4_SUCCESS" >/dev/null
for forbidden in 'validated comparability' 'biologically comparable' 'biologically incomparable' 'admissible candidate' 'conserved candidate' 'equivalent system' 'absent because unmappable'; do
  for f in "$CASE7/ceeg_r4_comparability_summary.tsv" \
           "$CASE7/ceeg_r4_comparability_limitations.tsv" \
           "$CASE7/ceeg_r4_comparability_evidence.tsv" \
           "$CASE7/ceeg_r4_outputs_manifest.tsv"; do
    if grep -qi "$forbidden" "$f"; then
      fail "case7: forbidden phrase '$forbidden' in $f"
    fi
  done
done
pass "case7: no forbidden verdict phrasing in R4 outputs"

# ── 8. Input immutability: hash R4 fixture before/after consumption ───────────
hash_dir() {
  find "$1" -type f -exec shasum -a 256 {} \; 2>/dev/null | LC_ALL=C sort
}
BEFORE=$(hash_dir "$R4_SUCCESS")
CASE8="$TMP_DIR/case8"
mkdir -p "$CASE8"
python3 "$ADAPTER" --out-dir "$CASE8" --r4-dir "$R4_SUCCESS" >/dev/null
AFTER=$(hash_dir "$R4_SUCCESS")
if [ "$BEFORE" = "$AFTER" ]; then
  pass "case8: R4 fixture directory unchanged after consumption"
else
  fail "case8: R4 fixture directory was modified during consumption"
fi

# ── Results ──────────────────────────────────────────────────────────────────
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
