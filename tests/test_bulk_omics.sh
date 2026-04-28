#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

OMICS="$ROOT_DIR/assets/example_samplesheets/omics_samplesheet.csv"
REFS="$ROOT_DIR/assets/example_samplesheets/reference_manifest.tsv"

assert_grep() {
  pattern="$1"
  file="$2"
  message="$3"
  if ! grep -q "$pattern" "$file"; then
    cat "$file"
    echo "FAIL: $message" >&2
    exit 1
  fi
}

assert_header() {
  file="$1"
  expected="$2"
  actual=$(head -n 1 "$file")
  if [ "$actual" != "$expected" ]; then
    cat "$file"
    echo "FAIL: unexpected header in $file" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
}

PREP="$TMP_DIR/prepared"
python3 "$ROOT_DIR/bin/prepare_omics_inputs.py" \
  --omics_samplesheet "$OMICS" \
  --reference_manifest "$REFS" \
  --omics_types rnaseq,atacseq \
  --omics_stub true \
  --output_dir "$PREP" > "$TMP_DIR/prepare.out" 2>&1
test -s "$PREP/omics_manifest_prepared.tsv"
test -s "$PREP/rnaseq_manifest.tsv"
test -s "$PREP/atacseq_manifest.tsv"
assert_grep 'omics_mouse_rna_1' "$PREP/rnaseq_manifest.tsv" "prepared RNA-seq sample missing"
assert_grep 'omics_fish_atac_1' "$PREP/atacseq_manifest.tsv" "prepared ATAC-seq sample missing"

if python3 "$ROOT_DIR/bin/prepare_omics_inputs.py" \
  --omics_samplesheet "$OMICS" \
  --reference_manifest "$REFS" \
  --omics_types proteomics \
  --omics_stub true \
  --output_dir "$TMP_DIR/bad_type" > "$TMP_DIR/bad_type.out" 2>&1; then
  cat "$TMP_DIR/bad_type.out"
  echo "FAIL: unsupported requested omics_type expected failure" >&2
  exit 1
fi
assert_grep 'Unsupported requested omics_type' "$TMP_DIR/bad_type/omics_input_warnings.tsv" "unsupported omics type diagnostic missing"

BAD_REF="$TMP_DIR/unknown_reference.csv"
awk -F, 'BEGIN{OFS=","} NR==2{$8="missing_ref"} {print}' "$OMICS" > "$BAD_REF"
if python3 "$ROOT_DIR/bin/prepare_omics_inputs.py" \
  --omics_samplesheet "$BAD_REF" \
  --reference_manifest "$REFS" \
  --omics_types rnaseq,atacseq \
  --omics_stub true \
  --output_dir "$TMP_DIR/bad_ref" > "$TMP_DIR/bad_ref.out" 2>&1; then
  cat "$TMP_DIR/bad_ref.out"
  echo "FAIL: unknown reference_id expected failure" >&2
  exit 1
fi
assert_grep 'Unknown reference_id' "$TMP_DIR/bad_ref/omics_input_warnings.tsv" "unknown reference diagnostic missing"

BAD_FASTQ="$TMP_DIR/missing_fastq2.csv"
awk -F, 'BEGIN{OFS=","} NR==2{$14=""} {print}' "$OMICS" > "$BAD_FASTQ"
if python3 "$ROOT_DIR/bin/prepare_omics_inputs.py" \
  --omics_samplesheet "$BAD_FASTQ" \
  --reference_manifest "$REFS" \
  --omics_types rnaseq \
  --omics_stub true \
  --output_dir "$TMP_DIR/bad_fastq" > "$TMP_DIR/bad_fastq.out" 2>&1; then
  cat "$TMP_DIR/bad_fastq.out"
  echo "FAIL: paired-end missing fastq_2 expected failure" >&2
  exit 1
fi
assert_grep 'Paired-end sample requires fastq_1 and fastq_2' "$TMP_DIR/bad_fastq/omics_input_warnings.tsv" "missing fastq_2 diagnostic missing"

python3 "$ROOT_DIR/bin/make_synthetic_counts.py" \
  --manifest "$PREP/rnaseq_manifest.tsv" \
  --omics_type rnaseq \
  --output "$TMP_DIR/gene_counts.tsv" \
  --summary "$TMP_DIR/rnaseq_summary.tsv" > "$TMP_DIR/rnaseq_counts.out" 2>&1
assert_header "$TMP_DIR/gene_counts.tsv" "feature_id	feature_type	annotation_id	omics_mouse_rna_1	omics_chicken_rna_1"

python3 "$ROOT_DIR/bin/make_synthetic_counts.py" \
  --manifest "$PREP/atacseq_manifest.tsv" \
  --omics_type atacseq \
  --output "$TMP_DIR/re_counts.tsv" \
  --summary "$TMP_DIR/atacseq_summary.tsv" > "$TMP_DIR/atac_counts.out" 2>&1
assert_header "$TMP_DIR/re_counts.tsv" "feature_id	feature_type	chrom	start	end	omics_fish_atac_1	omics_xenopus_atac_1"

if python3 "$ROOT_DIR/bin/summarize_omics_outputs.py" \
  --prepared_manifest "$PREP/omics_manifest_prepared.tsv" \
  --rnaseq_counts "$TMP_DIR/missing_gene_counts.tsv" \
  --rnaseq_summary "$TMP_DIR/rnaseq_summary.tsv" \
  --atacseq_counts "$TMP_DIR/re_counts.tsv" \
  --atacseq_summary "$TMP_DIR/atacseq_summary.tsv" \
  --warnings "$PREP/omics_input_warnings.tsv" \
  --output_dir "$TMP_DIR/missing_summary" > "$TMP_DIR/missing_summary.out" 2>&1; then
  cat "$TMP_DIR/missing_summary.out"
  echo "FAIL: missing summary output expected failure" >&2
  exit 1
fi
assert_grep 'Missing expected count matrix' "$TMP_DIR/missing_summary/omics_run_summary.tsv" "missing output diagnostic absent"

python3 "$ROOT_DIR/bin/summarize_omics_outputs.py" \
  --prepared_manifest "$PREP/omics_manifest_prepared.tsv" \
  --rnaseq_counts "$TMP_DIR/gene_counts.tsv" \
  --rnaseq_summary "$TMP_DIR/rnaseq_summary.tsv" \
  --atacseq_counts "$TMP_DIR/re_counts.tsv" \
  --atacseq_summary "$TMP_DIR/atacseq_summary.tsv" \
  --warnings "$PREP/omics_input_warnings.tsv" \
  --output_dir "$TMP_DIR/summary" > "$TMP_DIR/summary.out" 2>&1
assert_grep 'omics_mouse_rna_1' "$TMP_DIR/summary/omics_run_summary.tsv" "omics summary RNA sample missing"
assert_grep 'omics_fish_atac_1' "$TMP_DIR/summary/omics_run_summary.tsv" "omics summary ATAC sample missing"

NF_OUT="$TMP_DIR/nf_results"
nextflow run "$ROOT_DIR" \
  --run_stage bulk_omics \
  --omics_samplesheet "$OMICS" \
  --reference_manifest "$REFS" \
  --omics_stub true \
  --omics_types rnaseq,atacseq \
  --outdir "$NF_OUT" > "$TMP_DIR/nextflow.out" 2>&1
test -s "$NF_OUT/rnaseq/counts/gene_counts.tsv"
test -s "$NF_OUT/atacseq/counts/re_counts.tsv"
test -s "$NF_OUT/omics/summary/omics_run_summary.tsv"
assert_grep 'omics_mouse_rna_1' "$NF_OUT/rnaseq/counts/gene_counts.tsv" "Nextflow RNA count sample missing"
assert_grep 'omics_fish_atac_1' "$NF_OUT/atacseq/counts/re_counts.tsv" "Nextflow ATAC count sample missing"
assert_grep 'omics_xenopus_atac_1' "$NF_OUT/omics/summary/omics_run_summary.tsv" "Nextflow summary sample missing"

echo "bulk omics tests passed"
