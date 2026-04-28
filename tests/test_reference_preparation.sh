#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

WGS="$ROOT_DIR/assets/example_samplesheets/wgs_samplesheet.csv"
REFS="$ROOT_DIR/assets/example_samplesheets/reference_manifest.tsv"
CONFIG="$ROOT_DIR/assets/example_samplesheets/reference_prepare_config.tsv"

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

assert_file() {
  file="$1"
  message="$2"
  if [ ! -s "$file" ]; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

PREP="$TMP_DIR/prepared"
python3 "$ROOT_DIR/bin/prepare_reference_inputs.py" \
  --wgs_samplesheet "$WGS" \
  --reference_manifest "$REFS" \
  --reference_prepare_config "$CONFIG" \
  --reference_stub true \
  --output_dir "$PREP" > "$TMP_DIR/prepare.out" 2>&1
assert_file "$PREP/reference_prepare_manifest.tsv" "prepared reference manifest missing"
assert_file "$PREP/reference_prepare_warnings.tsv" "reference preparation warnings missing"
assert_grep '^wgs_mouse_1' "$PREP/reference_prepare_manifest.tsv" "prepared WGS mouse sample missing"
assert_grep 'mmus_ref' "$PREP/reference_prepare_manifest.tsv" "prepared reference_id missing"

BAD_MISSING="$TMP_DIR/missing_wgs_column.csv"
awk -F, 'BEGIN{OFS=","} {print $1,$2,$3,$5,$6,$7,$8,$9,$10,$11,$12}' "$WGS" > "$BAD_MISSING"
if python3 "$ROOT_DIR/bin/prepare_reference_inputs.py" \
  --wgs_samplesheet "$BAD_MISSING" \
  --reference_manifest "$REFS" \
  --reference_prepare_config "$CONFIG" \
  --reference_stub true \
  --output_dir "$TMP_DIR/bad_missing" > "$TMP_DIR/bad_missing.out" 2>&1; then
  cat "$TMP_DIR/bad_missing.out"
  echo "FAIL: missing required WGS column expected failure" >&2
  exit 1
fi
assert_grep 'Missing required column' "$TMP_DIR/bad_missing/reference_prepare_warnings.tsv" "missing required WGS column diagnostic absent"

BAD_REF="$TMP_DIR/unknown_reference.csv"
awk -F, 'BEGIN{OFS=","} NR==2{$4="missing_ref"} {print}' "$WGS" > "$BAD_REF"
if python3 "$ROOT_DIR/bin/prepare_reference_inputs.py" \
  --wgs_samplesheet "$BAD_REF" \
  --reference_manifest "$REFS" \
  --reference_prepare_config "$CONFIG" \
  --reference_stub true \
  --output_dir "$TMP_DIR/bad_ref" > "$TMP_DIR/bad_ref.out" 2>&1; then
  cat "$TMP_DIR/bad_ref.out"
  echo "FAIL: unknown reference_id expected failure" >&2
  exit 1
fi
assert_grep 'Unknown reference_id' "$TMP_DIR/bad_ref/reference_prepare_warnings.tsv" "unknown reference diagnostic absent"

STUB_OUT="$TMP_DIR/reference"
python3 "$ROOT_DIR/bin/make_synthetic_reference_outputs.py" \
  --prepared_manifest "$PREP/reference_prepare_manifest.tsv" \
  --output_dir "$STUB_OUT" > "$TMP_DIR/stub_outputs.out" 2>&1
assert_file "$STUB_OUT/genomes/Mus_musculus.mmus_ref.corrected.fa" "stub corrected FASTA missing"
assert_file "$STUB_OUT/variants/Mus_musculus.mmus_ref.reliable_variants.vcf" "stub reliable VCF missing"
assert_file "$STUB_OUT/masks/Mus_musculus.mmus_ref.problematic_sites.bed" "stub problematic-sites BED missing"
assert_file "$STUB_OUT/masks/Mus_musculus.mmus_ref.nanoseq_exclusion_mask.bed" "stub exclusion BED missing"
assert_file "$STUB_OUT/cnv/Mus_musculus.mmus_ref.confirmed_cnvs.bed" "stub CNV BED missing"
assert_file "$STUB_OUT/summary/reference_prepare_outputs.tsv" "stub output contract table missing"

SUMMARY_OUT="$TMP_DIR/reference_summary"
python3 "$ROOT_DIR/bin/summarize_reference_prepare.py" \
  --prepared_manifest "$PREP/reference_prepare_manifest.tsv" \
  --warnings "$PREP/reference_prepare_warnings.tsv" \
  --outputs_table "$STUB_OUT/summary/reference_prepare_outputs.tsv" \
  --outputs_root "$STUB_OUT" \
  --reference_stub true \
  --output_dir "$SUMMARY_OUT" > "$TMP_DIR/summary.out" 2>&1
assert_file "$SUMMARY_OUT/reference_prepare_summary.tsv" "reference preparation summary missing"
assert_file "$SUMMARY_OUT/reference_outputs_manifest.tsv" "reference outputs manifest missing"
assert_grep '^wgs_samples	2$' "$SUMMARY_OUT/reference_prepare_summary.tsv" "summary WGS sample count incorrect"
assert_grep '^references	2$' "$SUMMARY_OUT/reference_prepare_summary.tsv" "summary reference count incorrect"
assert_grep 'corrected_reference_fasta' "$SUMMARY_OUT/reference_outputs_manifest.tsv" "summary output manifest missing corrected FASTA"

if python3 "$ROOT_DIR/bin/prepare_reference_inputs.py" \
  --wgs_samplesheet "$WGS" \
  --reference_manifest "$REFS" \
  --reference_prepare_config "$CONFIG" \
  --reference_stub false \
  --output_dir "$TMP_DIR/real_prep" > "$TMP_DIR/real_prep.out" 2>&1; then
  cat "$TMP_DIR/real_prep.out"
  echo "FAIL: real-mode input preparation expected missing asset failure" >&2
  exit 1
fi
assert_grep 'does not exist in real mode' "$TMP_DIR/real_prep/reference_prepare_warnings.tsv" "real-mode missing asset diagnostic absent"

NF_OUT="$TMP_DIR/nf_results"
nextflow run "$ROOT_DIR" \
  --run_stage reference_prepare \
  --wgs_samplesheet "$WGS" \
  --reference_manifest "$REFS" \
  --reference_prepare_config "$CONFIG" \
  --reference_stub true \
  --outdir "$NF_OUT" > "$TMP_DIR/nextflow_stub.out" 2>&1
assert_file "$NF_OUT/reference/input/reference_prepare_manifest.tsv" "Nextflow prepared manifest missing"
assert_file "$NF_OUT/reference/genomes/Mus_musculus.mmus_ref.corrected.fa" "Nextflow corrected FASTA missing"
assert_file "$NF_OUT/reference/summary/reference_prepare_summary.tsv" "Nextflow summary missing"
assert_file "$NF_OUT/reference/summary/reference_outputs_manifest.tsv" "Nextflow output manifest missing"
assert_grep '^mode	stub$' "$NF_OUT/reference/summary/reference_prepare_summary.tsv" "Nextflow summary did not record stub mode"

if nextflow run "$ROOT_DIR" \
  --run_stage reference_prepare \
  --wgs_samplesheet "$WGS" \
  --reference_manifest "$REFS" \
  --reference_prepare_config "$CONFIG" \
  --reference_stub false \
  --outdir "$TMP_DIR/nf_real_results" > "$TMP_DIR/nextflow_real.out" 2>&1; then
  cat "$TMP_DIR/nextflow_real.out"
  echo "FAIL: Nextflow real mode expected missing tool/asset failure" >&2
  exit 1
fi
assert_grep 'does not exist in real mode' "$TMP_DIR/nextflow_real.out" "Nextflow real-mode failure was not clear"
if [ -e "$TMP_DIR/nf_real_results/reference/genomes/Mus_musculus.mmus_ref.corrected.fa" ]; then
  echo "FAIL: real mode emitted synthetic corrected FASTA" >&2
  exit 1
fi

CAME_STAGE13_SKIP_REGRESSION=true bash "$ROOT_DIR/tests/test_end_to_end_orchestration.sh"
bash "$ROOT_DIR/tests/test_release_packaging.sh"

echo "reference preparation tests passed"
