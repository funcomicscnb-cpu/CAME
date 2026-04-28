#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

REGIONS="$ROOT_DIR/assets/example_samplesheets/regulatory_regions.tsv"
ALIGNMENTS="$ROOT_DIR/assets/example_samplesheets/genome_alignment_manifest.tsv"
CONFIG="$ROOT_DIR/assets/example_samplesheets/coordinate_projection_config.tsv"

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
python3 "$ROOT_DIR/bin/prepare_coordinate_projection_inputs.py" \
  --regulatory_regions "$REGIONS" \
  --genome_alignment_manifest "$ALIGNMENTS" \
  --coordinate_projection_config "$CONFIG" \
  --coordinate_projection_stub true \
  --output_dir "$PREP" > "$TMP_DIR/prepare.out" 2>&1
assert_file "$PREP/coordinate_projection_manifest.tsv" "prepared coordinate projection manifest missing"
assert_file "$PREP/coordinate_projection_warnings.tsv" "coordinate projection warnings missing"
assert_grep '^proj_mouse_to_xenopus' "$PREP/coordinate_projection_manifest.tsv" "prepared xenopus projection missing"
assert_grep 'mmus_re_0001' "$PREP/coordinate_projection_manifest.tsv" "prepared regulatory region missing"

BAD_MISSING="$TMP_DIR/missing_feature_id.tsv"
awk -F'\t' 'BEGIN{OFS="\t"} {print $1,$3,$4,$5,$6,$7,$8,$9}' "$REGIONS" > "$BAD_MISSING"
if python3 "$ROOT_DIR/bin/prepare_coordinate_projection_inputs.py" \
  --regulatory_regions "$BAD_MISSING" \
  --genome_alignment_manifest "$ALIGNMENTS" \
  --coordinate_projection_config "$CONFIG" \
  --coordinate_projection_stub true \
  --output_dir "$TMP_DIR/bad_missing" > "$TMP_DIR/bad_missing.out" 2>&1; then
  cat "$TMP_DIR/bad_missing.out"
  echo "FAIL: missing required regulatory_regions column expected failure" >&2
  exit 1
fi
assert_grep 'Missing required column' "$TMP_DIR/bad_missing/coordinate_projection_warnings.tsv" "missing required column diagnostic absent"

BAD_COORD="$TMP_DIR/invalid_coordinate.tsv"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$4=900;$5=800} {print}' "$REGIONS" > "$BAD_COORD"
if python3 "$ROOT_DIR/bin/prepare_coordinate_projection_inputs.py" \
  --regulatory_regions "$BAD_COORD" \
  --genome_alignment_manifest "$ALIGNMENTS" \
  --coordinate_projection_config "$CONFIG" \
  --coordinate_projection_stub true \
  --output_dir "$TMP_DIR/bad_coord" > "$TMP_DIR/bad_coord.out" 2>&1; then
  cat "$TMP_DIR/bad_coord.out"
  echo "FAIL: invalid coordinate expected failure" >&2
  exit 1
fi
assert_grep 'start must be less than end' "$TMP_DIR/bad_coord/coordinate_projection_warnings.tsv" "invalid coordinate diagnostic absent"

if python3 "$ROOT_DIR/bin/prepare_coordinate_projection_inputs.py" \
  --regulatory_regions "$REGIONS" \
  --genome_alignment_manifest "$ALIGNMENTS" \
  --coordinate_projection_config "$CONFIG" \
  --coordinate_projection_stub false \
  --output_dir "$TMP_DIR/real_prep" > "$TMP_DIR/real_prep.out" 2>&1; then
  cat "$TMP_DIR/real_prep.out"
  echo "FAIL: real-mode coordinate input preparation expected missing alignment asset failure" >&2
  exit 1
fi
assert_grep 'Alignment asset does not exist in real mode' "$TMP_DIR/real_prep/coordinate_projection_warnings.tsv" "real-mode missing alignment diagnostic absent"

STUB_OUT="$TMP_DIR/coordinate_projection"
python3 "$ROOT_DIR/bin/make_synthetic_coordinate_projection_outputs.py" \
  --prepared_manifest "$PREP/coordinate_projection_manifest.tsv" \
  --output_dir "$STUB_OUT" > "$TMP_DIR/stub_outputs.out" 2>&1
assert_file "$STUB_OUT/projected_regions.tsv" "stub projected regions missing"
assert_file "$STUB_OUT/inferred_orthologous_res.tsv" "stub inferred orthologous_res missing"
assert_file "$STUB_OUT/projection_warnings.tsv" "stub projection warnings missing"
assert_grep 'one_to_one' "$STUB_OUT/projected_regions.tsv" "stub one-to-one mapping missing"
assert_grep 'many_to_one' "$STUB_OUT/projected_regions.tsv" "stub many-to-one mapping missing"
assert_grep 'ambiguous' "$STUB_OUT/projected_regions.tsv" "stub ambiguous mapping missing"
assert_grep 'FAILED' "$STUB_OUT/projected_regions.tsv" "stub failed projection missing"
assert_header "$STUB_OUT/inferred_orthologous_res.tsv" "species	feature_id	orthogroup_id	chrom	start	end	human_anchor_region	re_type	orthology_type	orthology_confidence	source	notes"
assert_grep 'OG_RE_COORD' "$STUB_OUT/inferred_orthologous_res.tsv" "stub inferred orthogroups missing"

SUMMARY_OUT="$TMP_DIR/summary"
python3 "$ROOT_DIR/bin/summarize_coordinate_projection.py" \
  --prepared_manifest "$PREP/coordinate_projection_manifest.tsv" \
  --projected_regions "$STUB_OUT/projected_regions.tsv" \
  --inferred_orthologous_res "$STUB_OUT/inferred_orthologous_res.tsv" \
  --projection_warnings "$STUB_OUT/projection_warnings.tsv" \
  --coordinate_projection_stub true \
  --output_dir "$SUMMARY_OUT" > "$TMP_DIR/summary.out" 2>&1
assert_file "$SUMMARY_OUT/coordinate_projection_summary.tsv" "coordinate projection summary missing"
assert_file "$SUMMARY_OUT/coordinate_projection_outputs_manifest.tsv" "coordinate projection outputs manifest missing"
assert_grep '^mode	stub$' "$SUMMARY_OUT/coordinate_projection_summary.tsv" "summary did not record stub mode"
assert_grep '^input_regions	4$' "$SUMMARY_OUT/coordinate_projection_summary.tsv" "summary input region count incorrect"
assert_grep '^failed_projections	2$' "$SUMMARY_OUT/coordinate_projection_summary.tsv" "summary failed projection count incorrect"

NF_OUT="$TMP_DIR/nf_results"
nextflow run "$ROOT_DIR" \
  --run_stage coordinate_projection \
  --regulatory_regions "$REGIONS" \
  --genome_alignment_manifest "$ALIGNMENTS" \
  --coordinate_projection_config "$CONFIG" \
  --coordinate_projection_stub true \
  --outdir "$NF_OUT" > "$TMP_DIR/nextflow_stub.out" 2>&1
assert_file "$NF_OUT/coordinate_projection/input/coordinate_projection_manifest.tsv" "Nextflow prepared coordinate manifest missing"
assert_file "$NF_OUT/coordinate_projection/projected_regions.tsv" "Nextflow projected regions missing"
assert_file "$NF_OUT/coordinate_projection/inferred_orthologous_res.tsv" "Nextflow inferred orthologous_res missing"
assert_file "$NF_OUT/coordinate_projection/summary/coordinate_projection_summary.tsv" "Nextflow coordinate summary missing"
assert_grep '^mode	stub$' "$NF_OUT/coordinate_projection/summary/coordinate_projection_summary.tsv" "Nextflow summary did not record stub mode"

if nextflow run "$ROOT_DIR" \
  --run_stage coordinate_projection \
  --regulatory_regions "$REGIONS" \
  --genome_alignment_manifest "$ALIGNMENTS" \
  --coordinate_projection_config "$CONFIG" \
  --coordinate_projection_stub false \
  --outdir "$TMP_DIR/nf_real_results" > "$TMP_DIR/nextflow_real.out" 2>&1; then
  cat "$TMP_DIR/nextflow_real.out"
  echo "FAIL: Nextflow coordinate real mode expected missing alignment asset failure" >&2
  exit 1
fi
assert_grep 'Alignment asset does not exist in real mode' "$TMP_DIR/nextflow_real.out" "Nextflow real-mode coordinate failure was not clear"
if [ -e "$TMP_DIR/nf_real_results/coordinate_projection/projected_regions.tsv" ]; then
  echo "FAIL: coordinate real mode emitted synthetic projected regions" >&2
  exit 1
fi

bash "$ROOT_DIR/tests/test_reference_preparation.sh"

echo "coordinate projection tests passed"
