#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PYTHON=${PYTHON:-python3}
FIXTURE_DIR="$ROOT_DIR/assets/test_data/reference_quality"

fail() {
  echo "FAIL: $1" >&2
  exit 1
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

assert_file() {
  [ -s "$1" ] || fail "$2"
}

ALIAS_OUT="$TMP_DIR/assembly"
"$PYTHON" "$ROOT_DIR/bin/parse_assembly_report.py" \
  --reference_manifest "$FIXTURE_DIR/reference_manifest.tsv" \
  --outdir "$ALIAS_OUT" \
  --check-paths true \
  --strict true > "$TMP_DIR/assembly.out" 2>&1
assert_grep 'tiny_ref	1	assembled-molecule	1	CM000001.1	NC_000001.1	chr1' "$ALIAS_OUT/seqname_alias_map.tsv" "assembly alias row absent"

SEQ_OUT="$TMP_DIR/seq_valid"
"$PYTHON" "$ROOT_DIR/bin/check_seqname_concordance.py" \
  --reference_manifest "$FIXTURE_DIR/reference_manifest.tsv" \
  --alias_map "$ALIAS_OUT/seqname_alias_map.tsv" \
  --outdir "$SEQ_OUT" \
  --check-paths true \
  --strict false > "$TMP_DIR/seq_valid.out" 2>&1
assert_file "$SEQ_OUT/seqname_concordance.tsv" "valid seqname concordance report missing"
assert_grep 'fasta_vs_fai	OK' "$SEQ_OUT/seqname_concordance.tsv" "FASTA/FAI exact match not accepted"
assert_grep 'fasta_vs_annotation	OK' "$SEQ_OUT/seqname_concordance.tsv" "GTF comments should be ignored and seqnames should match"

if "$PYTHON" "$ROOT_DIR/bin/check_seqname_concordance.py" \
  --reference_manifest "$FIXTURE_DIR/reference_manifest_fai_mismatch.tsv" \
  --outdir "$TMP_DIR/fai_mismatch" \
  --check-paths true \
  --strict false > "$TMP_DIR/fai_mismatch.out" 2>&1; then
  cat "$TMP_DIR/fai_mismatch/seqname_concordance.tsv" >&2
  fail "FASTA/FAI mismatch should fail"
fi
assert_grep 'FASTA and FAI sequence names differ' "$TMP_DIR/fai_mismatch/seqname_concordance.tsv" "FASTA/FAI mismatch diagnostic absent"

if "$PYTHON" "$ROOT_DIR/bin/check_seqname_concordance.py" \
  --reference_manifest "$FIXTURE_DIR/reference_manifest_chr_mismatch.tsv" \
  --outdir "$TMP_DIR/chr_mismatch" \
  --check-paths true \
  --strict false > "$TMP_DIR/chr_mismatch.out" 2>&1; then
  cat "$TMP_DIR/chr_mismatch/seqname_concordance.tsv" >&2
  fail "chr-prefix FASTA/GTF mismatch should fail"
fi
assert_grep 'chr-prefix mismatch.*alias map|alias map.*chr-prefix mismatch' "$TMP_DIR/chr_mismatch/seqname_concordance.tsv" "chr-prefix mismatch fix guidance absent"

SIMPLE_ALIAS_MANIFEST="$TMP_DIR/simple_alias_manifest.tsv"
"$PYTHON" - "$FIXTURE_DIR/reference_manifest_chr_mismatch.tsv" "$SIMPLE_ALIAS_MANIFEST" "$FIXTURE_DIR" "$FIXTURE_DIR/simple_alias_map.tsv" <<'PY'
import csv
import sys

src, dst, fixture_dir, alias_map = sys.argv[1:5]
rows = list(csv.DictReader(open(src), delimiter="\t"))
rows[0]["assembly_report"] = alias_map
rows[0]["fasta"] = fixture_dir + "/valid.fa"
rows[0]["fai"] = fixture_dir + "/valid.fa.fai"
rows[0]["annotation_file"] = fixture_dir + "/chr_annotation.gtf"
with open(dst, "w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()), delimiter="\t", lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
PY
"$PYTHON" "$ROOT_DIR/bin/parse_assembly_report.py" \
  --reference_manifest "$SIMPLE_ALIAS_MANIFEST" \
  --outdir "$TMP_DIR/simple_alias" \
  --check-paths true \
  --strict true > "$TMP_DIR/simple_alias.out" 2>&1
if "$PYTHON" "$ROOT_DIR/bin/check_seqname_concordance.py" \
  --reference_manifest "$SIMPLE_ALIAS_MANIFEST" \
  --alias_map "$TMP_DIR/simple_alias/seqname_alias_map.tsv" \
  --outdir "$TMP_DIR/chr_mismatch_with_alias" \
  --check-paths true \
  --strict false > "$TMP_DIR/chr_mismatch_with_alias.out" 2>&1; then
  fail "direct FASTA/GTF mismatch should still fail even when alias map is available"
fi
assert_grep 'annotation_vs_alias_map	OK' "$TMP_DIR/chr_mismatch_with_alias/seqname_concordance.tsv" "alias map did not resolve annotation synonyms"

if "$PYTHON" "$ROOT_DIR/bin/parse_assembly_report.py" \
  --reference_manifest "$FIXTURE_DIR/reference_manifest_bad_assembly.tsv" \
  --outdir "$TMP_DIR/bad_assembly" \
  --check-paths true \
  --strict true > "$TMP_DIR/bad_assembly.out" 2>&1; then
  cat "$TMP_DIR/bad_assembly/assembly_report_warnings.tsv" >&2
  fail "malformed assembly report should fail in strict mode"
fi
assert_grep 'Malformed assembly report row|did not contain any parseable sequence rows' "$TMP_DIR/bad_assembly/assembly_report_warnings.tsv" "malformed assembly report diagnostic absent"

echo "seqname concordance tests passed"
