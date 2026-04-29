#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PYTHON=${PYTHON:-python3}

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

CONTRACT="$TMP_DIR/contract"
mkdir -p "$CONTRACT/bam" "$CONTRACT/variants" "$CONTRACT/qc" "$CONTRACT/reports"

cat > "$CONTRACT/wgs_manifest.tsv" <<'EOF'
sample_id	sample_key	species	reference_id	assay	omics_type
wgs_contract_1	wgs_contract_1	Tiny_mammal	tiny_ref	wgs	wgs
EOF

cat > "$CONTRACT/qc/variant_qc.tsv" <<'EOF'
sample_id	species	reference_id	mapped_reads	duplicate_rate	mean_coverage	breadth_10x	insert_size_median	n_variants	n_snps	n_indels	bqsr_applied	calling_mode	joint_genotyping	mode
wgs_contract_1	Tiny_mammal	tiny_ref	NA	NA	NA	NA	NA	0	0	0	false	per_sample	false	stub
EOF

printf 'CAME_WGS_STUB stub contract BAM; not biological output.\n' > "$CONTRACT/bam/wgs_contract_1.bam"
printf 'CAME_WGS_STUB stub contract BAI; not biological output.\n' > "$CONTRACT/bam/wgs_contract_1.bam.bai"

write_valid_vcf() {
  "$PYTHON" - "$CONTRACT/variants/wgs_contract_1.vcf.gz" <<'PY'
import gzip
import sys

with gzip.open(sys.argv[1], "wt") as handle:
    handle.write("##fileformat=VCFv4.2\n")
    handle.write("##source=CAME_WGS_STUB contract fixture; not biological output\n")
    handle.write("#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\twgs_contract_1\n")
PY
  printf 'CAME_WGS_STUB stub contract VCF index; not biological output.\n' > "$CONTRACT/variants/wgs_contract_1.vcf.gz.tbi"
}

write_valid_vcf

"$PYTHON" "$ROOT_DIR/bin/validate_wgs_outputs.py" \
  --manifest "$CONTRACT/wgs_manifest.tsv" \
  --bam_dir "$CONTRACT/bam" \
  --variants_dir "$CONTRACT/variants" \
  --variant_qc "$CONTRACT/qc/variant_qc.tsv" \
  --report "$CONTRACT/reports/valid_stub.tsv" \
  --mode stub > "$TMP_DIR/valid_stub.out" 2>&1
assert_file "$CONTRACT/reports/valid_stub.tsv" "valid stub validation report missing"
assert_grep 'Validated WGS outputs for 1 sample' "$CONTRACT/reports/valid_stub.tsv" "valid stub contract did not validate"

"$PYTHON" - "$CONTRACT/variants/wgs_contract_1.vcf.gz" <<'PY'
import gzip
import sys

with gzip.open(sys.argv[1], "wt") as handle:
    handle.write("#not_a_vcf_fileformat_header\n")
    handle.write("#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\twgs_contract_1\n")
PY
if "$PYTHON" "$ROOT_DIR/bin/validate_wgs_outputs.py" \
  --manifest "$CONTRACT/wgs_manifest.tsv" \
  --bam_dir "$CONTRACT/bam" \
  --variants_dir "$CONTRACT/variants" \
  --variant_qc "$CONTRACT/qc/variant_qc.tsv" \
  --report "$CONTRACT/reports/malformed_vcf.tsv" \
  --mode stub > "$TMP_DIR/malformed_vcf.out" 2>&1; then
  cat "$CONTRACT/reports/malformed_vcf.tsv" >&2
  fail "malformed VCF should fail WGS output validation"
fi
assert_grep 'VCF header does not begin with ##fileformat' "$CONTRACT/reports/malformed_vcf.tsv" "malformed VCF diagnostic absent"

write_valid_vcf
mv "$CONTRACT/bam/wgs_contract_1.bam.bai" "$CONTRACT/bam/wgs_contract_1.bam.bai.missing"
if "$PYTHON" "$ROOT_DIR/bin/validate_wgs_outputs.py" \
  --manifest "$CONTRACT/wgs_manifest.tsv" \
  --bam_dir "$CONTRACT/bam" \
  --variants_dir "$CONTRACT/variants" \
  --variant_qc "$CONTRACT/qc/variant_qc.tsv" \
  --report "$CONTRACT/reports/missing_bai.tsv" \
  --mode stub > "$TMP_DIR/missing_bai.out" 2>&1; then
  cat "$CONTRACT/reports/missing_bai.tsv" >&2
  fail "missing BAM index should fail WGS output validation"
fi
assert_grep 'Missing BAM index' "$CONTRACT/reports/missing_bai.tsv" "missing BAM index diagnostic absent"
mv "$CONTRACT/bam/wgs_contract_1.bam.bai.missing" "$CONTRACT/bam/wgs_contract_1.bam.bai"

if "$PYTHON" "$ROOT_DIR/bin/validate_wgs_outputs.py" \
  --manifest "$CONTRACT/wgs_manifest.tsv" \
  --bam_dir "$CONTRACT/bam" \
  --variants_dir "$CONTRACT/variants" \
  --variant_qc "$CONTRACT/qc/variant_qc.tsv" \
  --report "$CONTRACT/reports/real_rejects_stub.tsv" \
  --mode real > "$TMP_DIR/real_rejects_stub.out" 2>&1; then
  cat "$CONTRACT/reports/real_rejects_stub.tsv" >&2
  fail "real-mode validation should reject synthetic WGS outputs"
fi
assert_grep 'Synthetic/stub .* real mode|mode=stub during real-mode validation' "$CONTRACT/reports/real_rejects_stub.tsv" "real-mode synthetic-output diagnostic absent"

cat > "$CONTRACT/qc/variant_qc_missing_mode.tsv" <<'EOF'
sample_id	species	reference_id	mapped_reads	duplicate_rate	mean_coverage	breadth_10x	insert_size_median	n_variants	n_snps	n_indels	bqsr_applied	calling_mode	joint_genotyping
wgs_contract_1	Tiny_mammal	tiny_ref	NA	NA	NA	NA	NA	0	0	0	false	per_sample	false
EOF
if "$PYTHON" "$ROOT_DIR/bin/validate_wgs_outputs.py" \
  --manifest "$CONTRACT/wgs_manifest.tsv" \
  --bam_dir "$CONTRACT/bam" \
  --variants_dir "$CONTRACT/variants" \
  --variant_qc "$CONTRACT/qc/variant_qc_missing_mode.tsv" \
  --report "$CONTRACT/reports/missing_qc_column.tsv" \
  --mode stub > "$TMP_DIR/missing_qc_column.out" 2>&1; then
  cat "$CONTRACT/reports/missing_qc_column.tsv" >&2
  fail "missing variant_qc column should fail WGS output validation"
fi
assert_grep 'Missing required column\(s\): mode' "$CONTRACT/reports/missing_qc_column.tsv" "missing variant_qc column diagnostic absent"

echo "WGS output contract tests passed"
