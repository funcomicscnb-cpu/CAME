#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

assert_nonempty() {
  file="$1"
  message="$2"
  test -s "$file" || {
    echo "FAIL: $message" >&2
    exit 1
  }
}

assert_header_field() {
  file="$1"
  field="$2"
  message="$3"
  head -n 1 "$file" | tr ',' '\t' | tr '\t' '\n' | grep -qx "$field" || {
    head -n 1 "$file"
    echo "FAIL: $message" >&2
    exit 1
  }
}

DATA_DIR="$TMP_DIR/data"
python3 "$ROOT_DIR/bin/make_real_mode_smoke_data.py" --outdir "$DATA_DIR" > "$TMP_DIR/make_data.out" 2>&1

assert_nonempty "$DATA_DIR/omics_samplesheet.csv" "make_real_mode_smoke_data did not write omics_samplesheet.csv"
assert_nonempty "$DATA_DIR/reference_manifest.tsv" "make_real_mode_smoke_data did not write reference_manifest.tsv"
assert_nonempty "$DATA_DIR/rnaseq/smoke_rna_R1.fastq" "make_real_mode_smoke_data did not write rnaseq FASTQ"
assert_nonempty "$DATA_DIR/atacseq/smoke_atac_R1.fastq" "make_real_mode_smoke_data did not write atacseq FASTQ"
assert_nonempty "$DATA_DIR/reference/smoke.fa" "make_real_mode_smoke_data did not write reference FASTA"
assert_nonempty "$DATA_DIR/reference/smoke.gtf" "make_real_mode_smoke_data did not write reference GTF"

assert_header_field "$DATA_DIR/omics_samplesheet.csv" "sample_id" "omics_samplesheet.csv missing sample_id column"
assert_header_field "$DATA_DIR/omics_samplesheet.csv" "omics_type" "omics_samplesheet.csv missing omics_type column"
assert_header_field "$DATA_DIR/reference_manifest.tsv" "reference_id" "reference_manifest.tsv missing reference_id column"
assert_header_field "$DATA_DIR/reference_manifest.tsv" "species" "reference_manifest.tsv missing species column"
assert_header_field "$DATA_DIR/reference_manifest.tsv" "genome_fasta" "reference_manifest.tsv missing genome_fasta column"

TOOL_DIR="$TMP_DIR/tools"
python3 "$ROOT_DIR/bin/check_real_mode_tools.py" \
  --outdir "$TOOL_DIR" \
  --mode soft \
  --omics-types rnaseq,atacseq \
  --project-dir "$ROOT_DIR" > "$TMP_DIR/tool_check.out" 2>&1

assert_nonempty "$TOOL_DIR/tool_check.tsv" "check_real_mode_tools did not write tool_check.tsv"

for field in tool scope status severity path version message; do
  assert_header_field "$TOOL_DIR/tool_check.tsv" "$field" "tool_check.tsv missing column: $field"
done

echo "real-mode unit tests passed"
