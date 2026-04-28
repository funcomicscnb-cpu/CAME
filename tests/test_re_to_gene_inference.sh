#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

REGIONS="$ROOT_DIR/assets/example_samplesheets/regulatory_regions.tsv"
GENES="$ROOT_DIR/assets/example_samplesheets/gene_coordinates.tsv"
CONTACTS="$ROOT_DIR/assets/example_samplesheets/chromatin_contacts.tsv"
CONFIG="$ROOT_DIR/assets/example_samplesheets/re_to_gene_inference_config.tsv"

assert_file() {
  file="$1"
  message="$2"
  if [ ! -s "$file" ]; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

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

assert_not_exists() {
  file="$1"
  message="$2"
  if [ -e "$file" ]; then
    ls -l "$file"
    echo "FAIL: $message" >&2
    exit 1
  fi
}

PREP="$TMP_DIR/prepared"
python3 "$ROOT_DIR/bin/prepare_re_to_gene_inference_inputs.py" \
  --regulatory_regions "$REGIONS" \
  --gene_coordinates "$GENES" \
  --chromatin_contacts "$CONTACTS" \
  --re_to_gene_inference_config "$CONFIG" \
  --re_to_gene_inference_stub true \
  --output_dir "$PREP" > "$TMP_DIR/prepare.out" 2>&1
assert_file "$PREP/re_to_gene_inference_manifest.tsv" "prepared RE-to-gene manifest missing"
assert_file "$PREP/re_to_gene_inference_warnings.tsv" "prepared RE-to-gene warnings missing"
assert_grep '^stub_contract' "$PREP/re_to_gene_inference_manifest.tsv" "stub inference config missing from manifest"
assert_grep 'chromatin_contact' "$PREP/re_to_gene_inference_manifest.tsv" "contact inference config missing from manifest"

BAD_MISSING="$TMP_DIR/missing_gene_feature_id.tsv"
cut -f 1,3- "$GENES" > "$BAD_MISSING"
if python3 "$ROOT_DIR/bin/prepare_re_to_gene_inference_inputs.py" \
  --regulatory_regions "$REGIONS" \
  --gene_coordinates "$BAD_MISSING" \
  --chromatin_contacts "$CONTACTS" \
  --re_to_gene_inference_config "$CONFIG" \
  --re_to_gene_inference_stub true \
  --output_dir "$TMP_DIR/bad_missing" > "$TMP_DIR/bad_missing.out" 2>&1; then
  cat "$TMP_DIR/bad_missing.out"
  echo "FAIL: missing gene_coordinates column expected failure" >&2
  exit 1
fi
assert_grep 'Missing required column' "$TMP_DIR/bad_missing/re_to_gene_inference_warnings.tsv" "missing required column diagnostic absent"

BAD_COORD="$TMP_DIR/invalid_gene_coordinate.tsv"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$4=300;$5=100} {print}' "$GENES" > "$BAD_COORD"
if python3 "$ROOT_DIR/bin/prepare_re_to_gene_inference_inputs.py" \
  --regulatory_regions "$REGIONS" \
  --gene_coordinates "$BAD_COORD" \
  --chromatin_contacts "$CONTACTS" \
  --re_to_gene_inference_config "$CONFIG" \
  --re_to_gene_inference_stub true \
  --output_dir "$TMP_DIR/bad_coord" > "$TMP_DIR/bad_coord.out" 2>&1; then
  cat "$TMP_DIR/bad_coord.out"
  echo "FAIL: invalid coordinate expected failure" >&2
  exit 1
fi
assert_grep 'start must be less than end' "$TMP_DIR/bad_coord/re_to_gene_inference_warnings.tsv" "invalid coordinate diagnostic absent"

BAD_METHOD="$TMP_DIR/invalid_method.tsv"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$3="made_up_method"} {print}' "$CONFIG" > "$BAD_METHOD"
if python3 "$ROOT_DIR/bin/prepare_re_to_gene_inference_inputs.py" \
  --regulatory_regions "$REGIONS" \
  --gene_coordinates "$GENES" \
  --chromatin_contacts "$CONTACTS" \
  --re_to_gene_inference_config "$BAD_METHOD" \
  --re_to_gene_inference_stub true \
  --output_dir "$TMP_DIR/bad_method" > "$TMP_DIR/bad_method.out" 2>&1; then
  cat "$TMP_DIR/bad_method.out"
  echo "FAIL: invalid method expected failure" >&2
  exit 1
fi
assert_grep 'Unsupported method' "$TMP_DIR/bad_method/re_to_gene_inference_warnings.tsv" "invalid method diagnostic absent"

if python3 "$ROOT_DIR/bin/prepare_re_to_gene_inference_inputs.py" \
  --regulatory_regions "$REGIONS" \
  --gene_coordinates "$GENES" \
  --chromatin_contacts "$CONTACTS" \
  --re_to_gene_inference_config "$CONFIG" \
  --re_to_gene_inference_stub false \
  --output_dir "$TMP_DIR/real_prep_stub" > "$TMP_DIR/real_prep_stub.out" 2>&1; then
  cat "$TMP_DIR/real_prep_stub.out"
  echo "FAIL: real mode with method=stub expected failure" >&2
  exit 1
fi
assert_grep 'method=stub is not valid' "$TMP_DIR/real_prep_stub/re_to_gene_inference_warnings.tsv" "real-mode stub method diagnostic absent"

REAL_CONFIG="$TMP_DIR/real_config.tsv"
awk -F'\t' 'BEGIN{OFS="\t"} NR==1 || $3!="stub" {print}' "$CONFIG" > "$REAL_CONFIG"
python3 "$ROOT_DIR/bin/prepare_re_to_gene_inference_inputs.py" \
  --regulatory_regions "$REGIONS" \
  --gene_coordinates "$GENES" \
  --chromatin_contacts "$CONTACTS" \
  --re_to_gene_inference_config "$REAL_CONFIG" \
  --re_to_gene_inference_stub false \
  --output_dir "$TMP_DIR/real_prep" > "$TMP_DIR/real_prep.out" 2>&1
assert_grep 'scaffold-only' "$TMP_DIR/real_prep/re_to_gene_inference_warnings.tsv" "real-mode scaffold warning absent"

STUB_OUT="$TMP_DIR/re_to_gene_inference"
python3 "$ROOT_DIR/bin/make_synthetic_re_to_gene_links.py" \
  --prepared_manifest "$PREP/re_to_gene_inference_manifest.tsv" \
  --re_to_gene_inference_stub true \
  --output_dir "$STUB_OUT" > "$TMP_DIR/stub_links.out" 2>&1
assert_file "$STUB_OUT/re_to_gene_links.tsv" "stub RE-to-gene links missing"
assert_file "$STUB_OUT/re_to_gene_inference_warnings.tsv" "stub RE-to-gene warnings missing"
assert_grep '	promoter	' "$STUB_OUT/re_to_gene_links.tsv" "promoter stub link missing"
assert_grep '	proximal	' "$STUB_OUT/re_to_gene_links.tsv" "proximal stub link missing"
assert_grep '	distal_contact	' "$STUB_OUT/re_to_gene_links.tsv" "distal-contact stub link missing"
assert_grep '	nearest_gene	' "$STUB_OUT/re_to_gene_links.tsv" "nearest-gene stub link missing"
awk 'BEGIN{FS="\t"; n=0} NR>1 && $2=="mmus_re_0003"{n++} END{exit n>=2?0:1}' "$STUB_OUT/re_to_gene_links.tsv" || {
  cat "$STUB_OUT/re_to_gene_links.tsv"
  echo "FAIL: one RE linked to multiple genes missing" >&2
  exit 1
}
awk 'BEGIN{FS="\t"; n=0} NR>1 && $3=="gene_0001"{n++} END{exit n>=2?0:1}' "$STUB_OUT/re_to_gene_links.tsv" || {
  cat "$STUB_OUT/re_to_gene_links.tsv"
  echo "FAIL: one gene linked to multiple REs missing" >&2
  exit 1
}

if python3 "$ROOT_DIR/bin/make_synthetic_re_to_gene_links.py" \
  --prepared_manifest "$PREP/re_to_gene_inference_manifest.tsv" \
  --re_to_gene_inference_stub false \
  --output_dir "$TMP_DIR/real_guard" > "$TMP_DIR/real_guard.out" 2>&1; then
  cat "$TMP_DIR/real_guard.out"
  echo "FAIL: synthetic link generator should fail in real mode" >&2
  exit 1
fi
assert_not_exists "$TMP_DIR/real_guard/re_to_gene_links.tsv" "real-mode synthetic link guard emitted links"

GENE_COUNTS="$TMP_DIR/gene_orthogroup_counts.tsv"
RE_COUNTS="$TMP_DIR/re_orthogroup_counts.tsv"
{
  printf 'orthogroup_id\n'
  printf 'OG_GENE_0001\nOG_GENE_0002\nOG_GENE_0003\nOG_GENE_0004\n'
} > "$GENE_COUNTS"
{
  printf 'orthogroup_id\n'
  printf 'OG_RE_0001\nOG_RE_0002\nOG_RE_0003\nOG_RE_0004\n'
} > "$RE_COUNTS"
VALIDATION="$TMP_DIR/re_to_gene_link_validation_report.tsv"
python3 "$ROOT_DIR/bin/validate_re_to_gene_links.py" \
  --re_to_gene_links "$STUB_OUT/re_to_gene_links.tsv" \
  --gene_orthogroup_counts "$GENE_COUNTS" \
  --re_orthogroup_counts "$RE_COUNTS" \
  --output "$VALIDATION" > "$TMP_DIR/link_validation.out" 2>&1
assert_file "$VALIDATION" "Stage 8 link validation report missing"
assert_grep 'resolved' "$VALIDATION" "stub links were not accepted by Stage 8 validator"

SUMMARY_OUT="$TMP_DIR/summary"
python3 "$ROOT_DIR/bin/summarize_re_to_gene_inference.py" \
  --prepared_manifest "$PREP/re_to_gene_inference_manifest.tsv" \
  --re_to_gene_links "$STUB_OUT/re_to_gene_links.tsv" \
  --inference_warnings "$STUB_OUT/re_to_gene_inference_warnings.tsv" \
  --re_to_gene_inference_stub true \
  --output_dir "$SUMMARY_OUT" > "$TMP_DIR/summary.out" 2>&1
assert_file "$SUMMARY_OUT/re_to_gene_inference_summary.tsv" "RE-to-gene inference summary missing"
assert_file "$SUMMARY_OUT/re_to_gene_inference_outputs_manifest.tsv" "RE-to-gene inference outputs manifest missing"
assert_grep '^mode	stub$' "$SUMMARY_OUT/re_to_gene_inference_summary.tsv" "summary did not record stub mode"
assert_grep '^links_produced	6$' "$SUMMARY_OUT/re_to_gene_inference_summary.tsv" "summary link count incorrect"
assert_grep '^ambiguous_links	2$' "$SUMMARY_OUT/re_to_gene_inference_summary.tsv" "summary ambiguity count incorrect"

NF_OUT="$TMP_DIR/nf_results"
nextflow run "$ROOT_DIR" \
  --run_stage re_to_gene_inference \
  --regulatory_regions "$REGIONS" \
  --gene_coordinates "$GENES" \
  --chromatin_contacts "$CONTACTS" \
  --re_to_gene_inference_config "$CONFIG" \
  --re_to_gene_inference_stub true \
  --outdir "$NF_OUT" > "$TMP_DIR/nextflow_stub.out" 2>&1
assert_file "$NF_OUT/re_to_gene_inference/input/re_to_gene_inference_manifest.tsv" "Nextflow prepared RE-to-gene manifest missing"
assert_file "$NF_OUT/re_to_gene_inference/re_to_gene_links.tsv" "Nextflow RE-to-gene links missing"
assert_file "$NF_OUT/re_to_gene_inference/summary/re_to_gene_inference_summary.tsv" "Nextflow RE-to-gene summary missing"
assert_grep '^mode	stub$' "$NF_OUT/re_to_gene_inference/summary/re_to_gene_inference_summary.tsv" "Nextflow summary did not record stub mode"

if nextflow run "$ROOT_DIR" \
  --run_stage re_to_gene_inference \
  --regulatory_regions "$REGIONS" \
  --gene_coordinates "$GENES" \
  --chromatin_contacts "$CONTACTS" \
  --re_to_gene_inference_config "$REAL_CONFIG" \
  --re_to_gene_inference_stub false \
  --outdir "$TMP_DIR/nf_real_results" > "$TMP_DIR/nextflow_real.out" 2>&1; then
  cat "$TMP_DIR/nextflow_real.out"
  echo "FAIL: Nextflow real-mode RE-to-gene inference expected scaffold failure" >&2
  exit 1
fi
assert_grep 'scaffold-only' "$TMP_DIR/nextflow_real.out" "Nextflow real-mode failure was not clear"
assert_not_exists "$TMP_DIR/nf_real_results/re_to_gene_inference/re_to_gene_links.tsv" "Nextflow real mode emitted synthetic RE-to-gene links"

if rg 're_to_gene_inference' "$ROOT_DIR/workflows/all.nf" "$ROOT_DIR/bin/check_stage_outputs.py" >/dev/null 2>&1; then
  echo "FAIL: re_to_gene_inference was wired into all-run or stage status checks" >&2
  exit 1
fi

if rg 're_to_gene_inference' \
  "$ROOT_DIR/bin/validate_re_to_gene_links.py" \
  "$ROOT_DIR/bin/build_gra_table.py" \
  "$ROOT_DIR/workflows/gra_analysis.nf" \
  "$ROOT_DIR/subworkflows/gra_building.nf" >/dev/null 2>&1; then
  echo "FAIL: Stage 8 core behavior references Stage 20" >&2
  exit 1
fi

if rg 'DDR|RoR' \
  "$ROOT_DIR/bin/prepare_re_to_gene_inference_inputs.py" \
  "$ROOT_DIR/bin/make_synthetic_re_to_gene_links.py" \
  "$ROOT_DIR/bin/summarize_re_to_gene_inference.py" \
  "$ROOT_DIR/workflows/re_to_gene_inference.nf" \
  "$ROOT_DIR/subworkflows/promoter_linking.nf" \
  "$ROOT_DIR/subworkflows/proximity_linking.nf" \
  "$ROOT_DIR/subworkflows/contact_linking.nf" \
  "$ROOT_DIR/docs/re_to_gene_inference.md" >/dev/null 2>&1; then
  echo "FAIL: Stage 20 files contain profile-specific terms" >&2
  exit 1
fi

if rg '/Users/|/home/|C:\\' \
  "$ROOT_DIR/docs/re_to_gene_inference.md" \
  "$ROOT_DIR/assets/example_samplesheets/gene_coordinates.tsv" \
  "$ROOT_DIR/assets/example_samplesheets/chromatin_contacts.tsv" \
  "$ROOT_DIR/assets/example_samplesheets/re_to_gene_inference_config.tsv" >/dev/null 2>&1; then
  echo "FAIL: Stage 20 docs/assets contain local absolute paths" >&2
  exit 1
fi

if rg 'production .* is implemented|runs production|production .* supported' "$ROOT_DIR/docs/re_to_gene_inference.md" >/dev/null 2>&1; then
  echo "FAIL: Stage 20 docs overstate production inference support" >&2
  exit 1
fi

bash "$ROOT_DIR/tests/test_gra_analysis.sh"
bash "$ROOT_DIR/tests/test_coordinate_projection.sh"
CAME_STAGE13_SKIP_REGRESSION=true bash "$ROOT_DIR/tests/test_end_to_end_orchestration.sh"

echo "RE-to-gene inference tests passed"
