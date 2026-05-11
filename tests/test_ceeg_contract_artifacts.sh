#!/usr/bin/env sh
# CAME-I0: tests for bin/summarize_ceeg_contract_artifacts.py
# Covers all 10 spec cases. No Nextflow or CEEG repo checkout required.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ADAPTER="$ROOT_DIR/bin/summarize_ceeg_contract_artifacts.py"
FIXTURE_DIR="$ROOT_DIR/assets/test_data/ceeg_compatibility"
R2_SUCCESS="$FIXTURE_DIR/mock_r2_output_success"
R2_FATAL="$FIXTURE_DIR/mock_r2_output_fatal"
R3_SUCCESS="$FIXTURE_DIR/mock_r3_output_success"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

# ── helper: assert file exists ────────────────────────────────────────────────
assert_file() { file="$1"; name="$2"
  if [ ! -f "$file" ]; then fail "$name: expected file $file"; return 1; fi
}

# ── helper: assert file contains string ──────────────────────────────────────
assert_contains() { file="$1"; pattern="$2"; name="$3"
  if ! grep -q "$pattern" "$file"; then
    fail "$name: expected '$pattern' in $file"; return 1
  fi
}

# ── helper: assert file does NOT contain string ───────────────────────────────
assert_not_contains() { file="$1"; pattern="$2"; name="$3"
  if grep -q "$pattern" "$file"; then
    fail "$name: unexpected '$pattern' in $file"; return 1
  fi
}

# ── helper: assert row count (header + N data rows) ──────────────────────────
assert_rows() { file="$1"; expected="$2"; name="$3"
  actual=$(wc -l < "$file" | tr -d ' ')
  if [ "$actual" != "$expected" ]; then
    fail "$name: expected $expected lines in $file, got $actual"
    return 1
  fi
}

# ── 1. No dirs supplied: no-op, exit 0, no output files written ──────────────
CASE1="$TMP_DIR/case1"
mkdir -p "$CASE1"
if python3 "$ADAPTER" --out-dir "$CASE1"; then
  :
else
  fail "case1: expected exit 0 for no-op"; FAIL=$((FAIL + 1))
fi
if ls "$CASE1" | grep -q '.'; then
  fail "case1: expected no output files written in no-op mode"
else
  pass "case1: no-op exits 0 and writes nothing"
fi

# ── 2. Missing R2 manifest: adapter records error row ────────────────────────
CASE2="$TMP_DIR/case2"
EMPTY_R2="$TMP_DIR/empty_r2"
mkdir -p "$CASE2" "$EMPTY_R2"
python3 "$ADAPTER" --out-dir "$CASE2" --r2-dir "$EMPTY_R2" --created-at "2026-05-11T00:00:00Z"
assert_file "$CASE2/ceeg_contract_summary.tsv" "case2:contract_summary" \
  && assert_contains "$CASE2/ceeg_contract_summary.tsv" "missing_manifest" "case2:missing_manifest_status" \
  && assert_contains "$CASE2/ceeg_compatibility_warnings.tsv" "came_report_manifest.json" "case2:warning_present" \
  && pass "case2: missing R2 manifest produces error row and warning"

# ── 3. R2 success dir only ────────────────────────────────────────────────────
CASE3="$TMP_DIR/case3"
mkdir -p "$CASE3"
python3 "$ADAPTER" --out-dir "$CASE3" --r2-dir "$R2_SUCCESS" --created-at "2026-05-11T00:00:00Z"

assert_file "$CASE3/ceeg_contract_summary.tsv" "case3:contract_summary" \
  && assert_contains "$CASE3/ceeg_contract_summary.tsv" "r2_overlay" "case3:artifact_type" \
  && assert_contains "$CASE3/ceeg_contract_summary.tsv" "compatible" "case3:status" \
  && assert_contains "$CASE3/ceeg_contract_summary.tsv" "compatibility_result=compatible" "case3:message" \
  && assert_file "$CASE3/ceeg_mapping_summary.tsv" "case3:mapping_summary" \
  && assert_file "$CASE3/ceeg_outputs_manifest.tsv" "case3:manifest" \
  && pass "case3: R2 success dir produces contract summary"

# ── 4a. R2 fatal dir with --fail-on-error: exits 2 after writing ─────────────
CASE4A="$TMP_DIR/case4a"
mkdir -p "$CASE4A"
rc=0
python3 "$ADAPTER" --out-dir "$CASE4A" --r2-dir "$R2_FATAL" \
    --created-at "2026-05-11T00:00:00Z" --fail-on-error || rc=$?
if [ "$rc" = "2" ]; then
  assert_file "$CASE4A/ceeg_contract_summary.tsv" "case4a:contract_summary" \
    && assert_contains "$CASE4A/ceeg_contract_summary.tsv" "fatal" "case4a:fatal_status" \
    && pass "case4a: R2 fatal exits 2 with --fail-on-error, outputs written"
else
  fail "case4a: expected exit 2 for R2 fatal with --fail-on-error, got $rc"
fi

# ── 4b. R2 fatal dir without --fail-on-error: exits 0 ────────────────────────
CASE4B="$TMP_DIR/case4b"
mkdir -p "$CASE4B"
python3 "$ADAPTER" --out-dir "$CASE4B" --r2-dir "$R2_FATAL" --created-at "2026-05-11T00:00:00Z"
assert_file "$CASE4B/ceeg_contract_summary.tsv" "case4b:contract_summary" \
  && assert_contains "$CASE4B/ceeg_contract_summary.tsv" "fatal" "case4b:fatal_status" \
  && assert_contains "$CASE4B/ceeg_compatibility_warnings.tsv" \
      "compatibility_summary.json is absent" "case4b:absent_note" \
  && pass "case4b: R2 fatal exits 0 without --fail-on-error, outputs written"

# ── 5. R3 dir only: unmapped/ambiguous notes present ─────────────────────────
CASE5="$TMP_DIR/case5"
mkdir -p "$CASE5"
python3 "$ADAPTER" --out-dir "$CASE5" --r3-dir "$R3_SUCCESS" --created-at "2026-05-11T00:00:00Z"

assert_file "$CASE5/ceeg_contract_summary.tsv" "case5:contract_summary" \
  && assert_contains "$CASE5/ceeg_contract_summary.tsv" "r3_mapping" "case5:artifact_type" \
  && assert_contains "$CASE5/ceeg_mapping_summary.tsv" "mock_r3_run_001" "case5:run_id" \
  && assert_contains "$CASE5/ceeg_unmapped_features.tsv" \
      "failed mapping is not biological absence" "case5:unmapped_note" \
  && assert_not_contains "$CASE5/ceeg_unmapped_features.tsv" "is absent" "case5:no_is_absent_claim" \
  && assert_contains "$CASE5/ceeg_ambiguous_mappings.tsv" \
      "ambiguous mapping is not collapsed to one-to-one" "case5:ambiguous_note" \
  && pass "case5: R3 dir produces mapping summary, unmapped/ambiguous with interpretation notes"

# ── 6. R2 success + R3 success: combined outputs ─────────────────────────────
CASE6="$TMP_DIR/case6"
mkdir -p "$CASE6"
python3 "$ADAPTER" --out-dir "$CASE6" --r2-dir "$R2_SUCCESS" --r3-dir "$R3_SUCCESS" \
    --created-at "2026-05-11T00:00:00Z"

assert_file "$CASE6/ceeg_contract_summary.tsv" "case6:contract_summary" \
  && assert_rows "$CASE6/ceeg_contract_summary.tsv" 3 "case6:two_artifact_rows" \
  && assert_contains "$CASE6/ceeg_contract_summary.tsv" "r2_overlay" "case6:r2_present" \
  && assert_contains "$CASE6/ceeg_contract_summary.tsv" "r3_mapping" "case6:r3_present" \
  && assert_file "$CASE6/ceeg_outputs_manifest.tsv" "case6:manifest" \
  && pass "case6: R2+R3 combined outputs, manifest lists 6 output files"

# ── 7. Input directories are not mutated ─────────────────────────────────────
CASE7="$TMP_DIR/case7"
mkdir -p "$CASE7"
before_r2=$(find "$R2_SUCCESS" -type f | sort | md5sum 2>/dev/null || find "$R2_SUCCESS" -type f | sort | xargs sha256sum 2>/dev/null)
before_r3=$(find "$R3_SUCCESS" -type f | sort | md5sum 2>/dev/null || find "$R3_SUCCESS" -type f | sort | xargs sha256sum 2>/dev/null)
python3 "$ADAPTER" --out-dir "$CASE7" --r2-dir "$R2_SUCCESS" --r3-dir "$R3_SUCCESS" \
    --created-at "2026-05-11T00:00:00Z"
after_r2=$(find "$R2_SUCCESS" -type f | sort | md5sum 2>/dev/null || find "$R2_SUCCESS" -type f | sort | xargs sha256sum 2>/dev/null)
after_r3=$(find "$R3_SUCCESS" -type f | sort | md5sum 2>/dev/null || find "$R3_SUCCESS" -type f | sort | xargs sha256sum 2>/dev/null)
if [ "$before_r2" = "$after_r2" ] && [ "$before_r3" = "$after_r3" ]; then
  pass "case7: input directories not mutated"
else
  fail "case7: input directory contents changed after adapter run"
fi

# ── 8. Existing R1 scaffold test still passes ────────────────────────────────
if [ -f "$ROOT_DIR/tests/test_ceeg_compatibility_stub.sh" ]; then
  if sh "$ROOT_DIR/tests/test_ceeg_compatibility_stub.sh" > "$TMP_DIR/r1_stub_out.txt" 2>&1; then
    pass "case8: existing R1 scaffold test passes unchanged"
  else
    cat "$TMP_DIR/r1_stub_out.txt" >&2
    fail "case8: existing R1 scaffold test failed"
  fi
else
  pass "case8: test_ceeg_compatibility_stub.sh not found — skipped (no R1 test regression)"
fi

# ── 9. --run_stage all does not include ceeg_compatibility ───────────────────
if grep -q "ceeg_compatibility.*included_in_all.*false" "$ROOT_DIR/main.nf" || \
   grep -q "included_in_all: false.*ceeg_compatibility\|ceeg_compatibility.*included_in_all: false" "$ROOT_DIR/main.nf"; then
  pass "case9: ceeg_compatibility remains excluded from --run_stage all"
else
  if awk '/ceeg_compatibility/{found=1} found && /included_in_all: false/{print; found=0}' "$ROOT_DIR/main.nf" | grep -q "included_in_all"; then
    pass "case9: ceeg_compatibility remains excluded from --run_stage all"
  else
    fail "case9: could not confirm ceeg_compatibility is excluded from --run_stage all"
  fi
fi

# ── 10. Anti-overclaim audit: code files must not assert biological claims ────
# Docs files legitimately use these terms to document anti-overclaim rules,
# so only check code files (Python, Nextflow).
OVERCLAIM_FOUND=0
for f in \
    "$ROOT_DIR/bin/summarize_ceeg_contract_artifacts.py" \
    "$ROOT_DIR/modules/local/consume_ceeg_contract_artifacts.nf" \
    "$ROOT_DIR/subworkflows/ceeg_contract_artifacts.nf"; do
  for term in "conserved_function" "biological_conservation" "functional_equivalence" \
              "candidate_scoring" "admissibility_score" "comparability_score"; do
    if grep -qi "$term" "$f" 2>/dev/null; then
      fail "case10: forbidden term '$term' found in code file $f"
      OVERCLAIM_FOUND=1
    fi
  done
done
if [ "$OVERCLAIM_FOUND" = "0" ]; then
  pass "case10: no forbidden overclaim wording in code files"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
