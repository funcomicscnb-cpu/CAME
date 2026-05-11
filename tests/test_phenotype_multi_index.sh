#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PHENO="$TMP_DIR/phenotype.csv"
cat > "$PHENO" <<'EOF'
sample_id,species,individual_id,replicate_id,condition,timepoint,assay,measurement,value,unit,batch
mouse_base_a,Mus_musculus,mouse_1,rep1,baseline,t0,generic_profile,component_a,2,ratio,b1
mouse_base_b,Mus_musculus,mouse_1,rep1,baseline,t0,generic_profile,component_b,0.5,ratio,b1
mouse_base_c,Mus_musculus,mouse_1,rep1,baseline,t0,generic_profile,component_c,1,ratio,b1
mouse_resp_a,Mus_musculus,mouse_1,rep1,response,t1,generic_profile,component_a,5,ratio,b1
mouse_resp_b,Mus_musculus,mouse_1,rep1,response,t1,generic_profile,component_b,1,ratio,b1
mouse_resp_c,Mus_musculus,mouse_1,rep1,response,t1,generic_profile,component_c,2,ratio,b1
fish_base_a,Danio_rerio,fish_1,rep1,baseline,t0,generic_profile,component_a,1.5,ratio,b1
fish_base_b,Danio_rerio,fish_1,rep1,baseline,t0,generic_profile,component_b,0.5,ratio,b1
fish_base_c,Danio_rerio,fish_1,rep1,baseline,t0,generic_profile,component_c,1,ratio,b1
fish_resp_a,Danio_rerio,fish_1,rep1,response,t1,generic_profile,component_a,3,ratio,b1
fish_resp_b,Danio_rerio,fish_1,rep1,response,t1,generic_profile,component_b,0.5,ratio,b1
fish_resp_c,Danio_rerio,fish_1,rep1,response,t1,generic_profile,component_c,1,ratio,b1
EOF

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

run_pipeline() {
  profile="$1"
  out="$2"
  mkdir -p "$out"
  python3 "$ROOT_DIR/bin/phenotype_normalize.py" \
    --input "$PHENO" \
    --output "$out/normalized.tsv" \
    --summary "$out/normalization_summary.tsv" > "$out/normalize.out" 2>&1
  python3 "$ROOT_DIR/bin/phenotype_qc.py" \
    --input "$out/normalized.tsv" \
    --study_profile "$profile" \
    --metrics "$out/qc_metrics.tsv" \
    --outliers "$out/outliers.tsv" \
    --group_counts "$out/group_counts.tsv" > "$out/qc.out" 2>&1
  python3 "$ROOT_DIR/bin/calc_phenotype_index.py" \
    --input "$out/normalized.tsv" \
    --study_profile "$profile" \
    --sample_output "$out/index_by_sample.tsv" \
    --group_output "$out/index_by_group.tsv" \
    --indexes_sample_output "$out/indexes_by_sample.tsv" \
    --indexes_group_output "$out/indexes_by_group.tsv" \
    --manifest_output "$out/manifest.tsv" > "$out/index.out" 2>&1
  python3 "$ROOT_DIR/bin/phenotype_contrasts.py" \
    --phenotype_table "$out/normalized.tsv" \
    --study_profile "$profile" \
    --index_by_group "$out/index_by_group.tsv" \
    --indexes_by_group "$out/indexes_by_group.tsv" \
    --index_output "$out/index_contrasts.tsv" \
    --component_output "$out/component_contrasts.tsv" \
    --index_long_output "$out/index_contrasts_long.tsv" > "$out/contrasts.out" 2>&1
}

validate_profile() {
  profile="$1"
  out="$2"
  python3 "$ROOT_DIR/bin/validate_study_profile.py" \
    --study_profile "$profile" \
    --phenotype_samplesheet "$PHENO" \
    --species_traits "$ROOT_DIR/assets/example_samplesheets/species_traits.tsv" \
    --output "$out" > "$out.stdout" 2>&1
}

LEGACY_OUT="$TMP_DIR/legacy"
run_pipeline "$ROOT_DIR/profiles/generic/study_profile.yaml" "$LEGACY_OUT"
test -s "$LEGACY_OUT/indexes_by_sample.tsv"
test -s "$LEGACY_OUT/indexes_by_group.tsv"
test -s "$LEGACY_OUT/index_contrasts_long.tsv"
assert_grep 'composite_response_index' "$LEGACY_OUT/indexes_by_group.tsv" "legacy long group output missing primary index"

MULTI_PROFILE="$ROOT_DIR/profiles/multi_index_test/study_profile.yaml"
MULTI_OUT="$TMP_DIR/multi"
run_pipeline "$MULTI_PROFILE" "$MULTI_OUT"
assert_grep 'secondary_sum_index' "$MULTI_OUT/indexes_by_group.tsv" "multi-index group output missing secondary index"
assert_grep 'primary_response_index' "$MULTI_OUT/indexes_by_group.tsv" "multi-index group output missing primary index"
assert_grep 'secondary_sum_index' "$MULTI_OUT/index_contrasts_long.tsv" "long contrast output missing secondary index"
if grep -q 'secondary_sum_index' "$MULTI_OUT/index_by_group.tsv"; then
  cat "$MULTI_OUT/index_by_group.tsv"
  echo "FAIL: legacy group output should contain only primary index" >&2
  exit 1
fi
assert_grep 'primary_response_index' "$MULTI_OUT/index_by_group.tsv" "legacy group output missing marked primary index"
assert_grep 'true' "$MULTI_OUT/manifest.tsv" "manifest missing primary flag"

VALID_REPORT="$TMP_DIR/valid_multi.tsv"
validate_profile "$MULTI_PROFILE" "$VALID_REPORT"
if grep -q '^ERROR' "$VALID_REPORT"; then
  cat "$VALID_REPORT"
  echo "FAIL: valid multi-index profile should pass validation" >&2
  exit 1
fi

BAD_SECONDARY="$TMP_DIR/bad_secondary.yaml"
awk 'BEGIN{in_secondary=0; replaced_component=0} /^  - name: secondary_sum_index/{in_secondary=1} /^  - name:/ && !/secondary_sum_index/{in_secondary=0} in_secondary && /^    formula:/{print "    formula: \"component_a + component_d\""; next} in_secondary && !replaced_component && /^      - component_b/{print "      - component_d"; replaced_component=1; next} {print}' "$MULTI_PROFILE" > "$BAD_SECONDARY"
BAD_OUT="$TMP_DIR/bad_secondary"
mkdir -p "$BAD_OUT"
python3 "$ROOT_DIR/bin/phenotype_normalize.py" --input "$PHENO" --output "$BAD_OUT/normalized.tsv" --summary "$BAD_OUT/summary.tsv" > "$BAD_OUT/normalize.out" 2>&1
if python3 "$ROOT_DIR/bin/calc_phenotype_index.py" --input "$BAD_OUT/normalized.tsv" --study_profile "$BAD_SECONDARY" --sample_output "$BAD_OUT/sample.tsv" --group_output "$BAD_OUT/group.tsv" > "$BAD_OUT/index.out" 2>&1; then
  cat "$BAD_OUT/index.out"
  echo "FAIL: missing secondary-index component should fail index calculation" >&2
  exit 1
fi

QC_MISSING="$TMP_DIR/qc_missing.yaml"
sed 's/fail_on_missing_components: false/fail_on_missing_components: true/' "$BAD_SECONDARY" > "$QC_MISSING"
if python3 "$ROOT_DIR/bin/phenotype_qc.py" --input "$BAD_OUT/normalized.tsv" --study_profile "$QC_MISSING" --metrics "$TMP_DIR/qc_missing.tsv" --outliers "$TMP_DIR/qc_missing_outliers.tsv" --group_counts "$TMP_DIR/qc_missing_counts.tsv" > "$TMP_DIR/qc_missing.out" 2>&1; then
  cat "$TMP_DIR/qc_missing.tsv"
  echo "FAIL: fail_on_missing_components should make QC fail" >&2
  exit 1
fi
assert_grep 'missing_profile_component' "$TMP_DIR/qc_missing.tsv" "missing component QC error absent"

QC_SPARSE="$TMP_DIR/qc_sparse.yaml"
sed 's/fail_on_sparse_groups: false/fail_on_sparse_groups: true/' "$MULTI_PROFILE" > "$QC_SPARSE"
if python3 "$ROOT_DIR/bin/phenotype_qc.py" --input "$MULTI_OUT/normalized.tsv" --study_profile "$QC_SPARSE" --metrics "$TMP_DIR/qc_sparse.tsv" --outliers "$TMP_DIR/qc_sparse_outliers.tsv" --group_counts "$TMP_DIR/qc_sparse_counts.tsv" > "$TMP_DIR/qc_sparse.out" 2>&1; then
  cat "$TMP_DIR/qc_sparse.tsv"
  echo "FAIL: fail_on_sparse_groups should make QC fail" >&2
  exit 1
fi
assert_grep 'sparse_group' "$TMP_DIR/qc_sparse.tsv" "sparse group QC error absent"

UNIT_PHENO="$TMP_DIR/unit_phenotype.csv"
awk -F, 'BEGIN{OFS=","} NR==3{$10="percent"} {print}' "$PHENO" > "$UNIT_PHENO"
UNIT_OUT="$TMP_DIR/unit"
mkdir -p "$UNIT_OUT"
python3 "$ROOT_DIR/bin/phenotype_normalize.py" --input "$UNIT_PHENO" --output "$UNIT_OUT/normalized.tsv" --summary "$UNIT_OUT/summary.tsv" > "$UNIT_OUT/normalize.out" 2>&1
QC_UNIT="$TMP_DIR/qc_unit.yaml"
sed 's/fail_on_unit_inconsistency: false/fail_on_unit_inconsistency: true/' "$MULTI_PROFILE" > "$QC_UNIT"
if python3 "$ROOT_DIR/bin/phenotype_qc.py" --input "$UNIT_OUT/normalized.tsv" --study_profile "$QC_UNIT" --metrics "$TMP_DIR/qc_unit.tsv" --outliers "$TMP_DIR/qc_unit_outliers.tsv" --group_counts "$TMP_DIR/qc_unit_counts.tsv" > "$TMP_DIR/qc_unit.out" 2>&1; then
  cat "$TMP_DIR/qc_unit.tsv"
  echo "FAIL: fail_on_unit_inconsistency should make QC fail" >&2
  exit 1
fi
assert_grep 'unit_inconsistency' "$TMP_DIR/qc_unit.tsv" "unit inconsistency QC error absent"

DUP_PROFILE="$TMP_DIR/duplicate_index.yaml"
awk 'BEGIN{done=0} /name: secondary_sum_index/ && !done{sub("secondary_sum_index", "primary_response_index"); done=1} {print}' "$MULTI_PROFILE" > "$DUP_PROFILE"
if validate_profile "$DUP_PROFILE" "$TMP_DIR/duplicate_report.tsv"; then
  cat "$TMP_DIR/duplicate_report.tsv"
  echo "FAIL: duplicate index names should fail validation" >&2
  exit 1
fi
assert_grep 'PROFILE_DUPLICATE_INDEX_NAME' "$TMP_DIR/duplicate_report.tsv" "duplicate index rule missing"

MULTI_PRIMARY="$TMP_DIR/multiple_primary.yaml"
awk '/name: secondary_sum_index/ && !done{print; print "    primary: true"; done=1; next} {print}' "$MULTI_PROFILE" > "$MULTI_PRIMARY"
if validate_profile "$MULTI_PRIMARY" "$TMP_DIR/multiple_primary_report.tsv"; then
  cat "$TMP_DIR/multiple_primary_report.tsv"
  echo "FAIL: multiple primary indexes should fail validation" >&2
  exit 1
fi
assert_grep 'PROFILE_MULTIPLE_PRIMARY' "$TMP_DIR/multiple_primary_report.tsv" "multiple primary rule missing"

EMPTY_PROFILE="$TMP_DIR/empty_indexes.yaml"
awk '/^phenotype_indexes:/{print "phenotype_indexes: []"; skip=1; next} skip && /^phenotype_qc:/{skip=0} !skip{print}' "$MULTI_PROFILE" > "$EMPTY_PROFILE"
if validate_profile "$EMPTY_PROFILE" "$TMP_DIR/empty_report.tsv"; then
  cat "$TMP_DIR/empty_report.tsv"
  echo "FAIL: empty phenotype_indexes should fail validation" >&2
  exit 1
fi
assert_grep 'PROFILE_INDEXES_EMPTY' "$TMP_DIR/empty_report.tsv" "empty indexes rule missing"

MISMATCH_PROFILE="$TMP_DIR/mismatch.yaml"
awk 'BEGIN{done=0} /name: primary_response_index/ && !done{sub("primary_response_index", "mismatched_primary"); done=1} {print}' "$MULTI_PROFILE" > "$MISMATCH_PROFILE"
if validate_profile "$MISMATCH_PROFILE" "$TMP_DIR/mismatch_report.tsv"; then
  cat "$TMP_DIR/mismatch_report.tsv"
  echo "FAIL: top-level primary mismatch should fail validation" >&2
  exit 1
fi
assert_grep 'PROFILE_PRIMARY_INDEX_MISMATCH' "$TMP_DIR/mismatch_report.tsv" "primary mismatch rule missing"

FORMULA_MISMATCH="$TMP_DIR/formula_mismatch.yaml"
awk 'BEGIN{done=0} /formula:/ && !done{print "  formula: \"component_a + component_b\""; done=1; next} {print}' "$MULTI_PROFILE" > "$FORMULA_MISMATCH"
if validate_profile "$FORMULA_MISMATCH" "$TMP_DIR/formula_mismatch_report.tsv"; then
  cat "$TMP_DIR/formula_mismatch_report.tsv"
  echo "FAIL: top-level primary definition mismatch should fail validation" >&2
  exit 1
fi
assert_grep 'PROFILE_PRIMARY_INDEX_MISMATCH' "$TMP_DIR/formula_mismatch_report.tsv" "primary definition mismatch rule missing"

echo "phenotype multi-index tests passed"
