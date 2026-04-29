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

VALID_OUT="$TMP_DIR/valid_assets"
"$PYTHON" "$ROOT_DIR/bin/validate_reference_assets.py" \
  --reference_manifest "$FIXTURE_DIR/reference_manifest.tsv" \
  --outdir "$VALID_OUT" \
  --check-paths true \
  --assay rna,atac \
  --strict false > "$TMP_DIR/valid_assets.out" 2>&1
assert_file "$VALID_OUT/reference_asset_validation.tsv" "valid asset validation report missing"
assert_grep '^tiny_ref	.*	OK	0	0$' "$VALID_OUT/reference_asset_summary.tsv" "valid reference should have OK asset summary"

MISSING_COLUMN="$TMP_DIR/missing_fasta.tsv"
"$PYTHON" - "$FIXTURE_DIR/reference_manifest.tsv" "$MISSING_COLUMN" <<'PY'
import csv
import sys

src, dst = sys.argv[1:3]
rows = list(csv.DictReader(open(src), delimiter="\t"))
fields = [field for field in rows[0].keys() if field != "fasta"]
with open(dst, "w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", lineterminator="\n")
    writer.writeheader()
    writer.writerows({field: row.get(field, "") for field in fields} for row in rows)
PY
if "$PYTHON" "$ROOT_DIR/bin/validate_reference_assets.py" \
  --reference_manifest "$MISSING_COLUMN" \
  --outdir "$TMP_DIR/missing_column_out" \
  --check-paths false \
  --assay rna > "$TMP_DIR/missing_column.out" 2>&1; then
  cat "$TMP_DIR/missing_column_out/reference_asset_validation.tsv" >&2
  fail "missing required FASTA column should fail"
fi
assert_grep 'Missing required FASTA column' "$TMP_DIR/missing_column_out/reference_asset_validation.tsv" "missing FASTA column diagnostic absent"

OPTIONAL_OUT="$TMP_DIR/missing_optional"
"$PYTHON" "$ROOT_DIR/bin/validate_reference_assets.py" \
  --reference_manifest "$FIXTURE_DIR/reference_manifest_missing_optional.tsv" \
  --outdir "$OPTIONAL_OUT" \
  --check-paths true \
  --assay rna,atac > "$TMP_DIR/missing_optional.out" 2>&1
assert_grep 'repeatmask_bed' "$OPTIONAL_OUT/reference_asset_warnings.tsv" "missing repeatmask warning absent"
assert_grep 'mappability_bed' "$OPTIONAL_OUT/reference_asset_warnings.tsv" "missing mappability warning absent"
assert_grep 'busco_score' "$OPTIONAL_OUT/reference_asset_warnings.tsv" "missing BUSCO warning absent"

LOW_BUSCO_OUT="$TMP_DIR/low_busco"
"$PYTHON" "$ROOT_DIR/bin/validate_reference_assets.py" \
  --reference_manifest "$FIXTURE_DIR/reference_manifest_low_busco.tsv" \
  --outdir "$LOW_BUSCO_OUT" \
  --check-paths false \
  --assay rna,atac \
  --strict false > "$TMP_DIR/low_busco.out" 2>&1
assert_grep 'below 80' "$LOW_BUSCO_OUT/reference_asset_warnings.tsv" "low BUSCO warning absent"

if "$PYTHON" "$ROOT_DIR/bin/validate_reference_assets.py" \
  --reference_manifest "$FIXTURE_DIR/reference_manifest_low_busco.tsv" \
  --outdir "$TMP_DIR/low_busco_strict" \
  --check-paths false \
  --assay rna,atac \
  --strict true > "$TMP_DIR/low_busco_strict.out" 2>&1; then
  cat "$TMP_DIR/low_busco_strict/reference_asset_validation.tsv" >&2
  fail "BUSCO below 70 should fail in strict mode"
fi
assert_grep 'below 70' "$TMP_DIR/low_busco_strict/reference_asset_validation.tsv" "strict BUSCO failure diagnostic absent"

"$PYTHON" "$ROOT_DIR/bin/validate_reference_assets.py" \
  --reference_manifest "$FIXTURE_DIR/reference_manifest_low_busco.tsv" \
  --outdir "$TMP_DIR/low_busco_allowed" \
  --check-paths false \
  --assay rna,atac \
  --strict true \
  --allow_low_quality_reference true > "$TMP_DIR/low_busco_allowed.out" 2>&1

MISSING_PATHS="$TMP_DIR/missing_paths.tsv"
"$PYTHON" - "$FIXTURE_DIR/reference_manifest.tsv" "$MISSING_PATHS" <<'PY'
import csv
import sys

src, dst = sys.argv[1:3]
rows = list(csv.DictReader(open(src), delimiter="\t"))
rows[0]["fasta"] = "missing.fa"
rows[0]["fai"] = "missing.fa.fai"
with open(dst, "w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()), delimiter="\t", lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
PY
"$PYTHON" "$ROOT_DIR/bin/validate_reference_assets.py" \
  --reference_manifest "$MISSING_PATHS" \
  --outdir "$TMP_DIR/missing_paths_out" \
  --check-paths false \
  --assay rna,atac > "$TMP_DIR/missing_paths.out" 2>&1

NF_OUT="$TMP_DIR/nf_reference_quality"
nextflow -log "$TMP_DIR/reference_quality.log" run "$ROOT_DIR" \
  -work-dir "$TMP_DIR/work" \
  --run_stage reference_quality \
  --reference_manifest "$FIXTURE_DIR/reference_manifest.tsv" \
  --outdir "$NF_OUT" \
  --check_paths true > "$TMP_DIR/reference_quality_nf.out" 2>&1
for expected in \
  reference_asset_validation.tsv \
  reference_asset_warnings.tsv \
  reference_asset_summary.tsv \
  seqname_alias_map.tsv \
  assembly_report_warnings.tsv \
  seqname_concordance.tsv \
  seqname_concordance_warnings.tsv \
  reference_quality_summary.tsv \
  reference_quality_manifest.tsv
do
  assert_file "$NF_OUT/reference_quality/$expected" "Nextflow reference_quality missing $expected"
done

echo "reference asset tests passed"
