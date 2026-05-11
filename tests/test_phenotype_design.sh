#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PHENO="$TMP_DIR/phenotype.csv"
TRAITS="$TMP_DIR/species_traits.tsv"

cat > "$PHENO" <<'EOF'
sample_id,species,individual_id,replicate_id,condition,timepoint,assay,measurement,value,unit,batch
a_base_a_b1,Species_a,ind_a,rep1,baseline,t0,generic_profile,component_a,2,ratio,b1
a_base_b_b1,Species_a,ind_a,rep1,baseline,t0,generic_profile,component_b,0.5,ratio,b1
a_base_c_b1,Species_a,ind_a,rep1,baseline,t0,generic_profile,component_c,1,ratio,b1
a_base_a_b2,Species_a,ind_a,rep1,baseline,t0,generic_profile,component_a,4,ratio,b2
a_base_b_b2,Species_a,ind_a,rep1,baseline,t0,generic_profile,component_b,1,ratio,b2
a_base_c_b2,Species_a,ind_a,rep1,baseline,t0,generic_profile,component_c,2,ratio,b2
a_resp_a,Species_a,ind_a,rep1,response,t1,generic_profile,component_a,5,ratio,b1
a_resp_b,Species_a,ind_a,rep1,response,t1,generic_profile,component_b,1,ratio,b1
a_resp_c,Species_a,ind_a,rep1,response,t1,generic_profile,component_c,2,ratio,b1
b_base_a,Species_b,ind_b,rep1,baseline,t0,generic_profile,component_a,1.5,ratio,b1
b_base_b,Species_b,ind_b,rep1,baseline,t0,generic_profile,component_b,0.5,ratio,b1
b_base_c,Species_b,ind_b,rep1,baseline,t0,generic_profile,component_c,1,ratio,b1
b_resp_a,Species_b,ind_b,rep1,response,t1,generic_profile,component_a,3,ratio,b1
b_resp_b,Species_b,ind_b,rep1,response,t1,generic_profile,component_b,0.5,ratio,b1
b_resp_c,Species_b,ind_b,rep1,response,t1,generic_profile,component_c,1,ratio,b1
EOF

cat > "$TRAITS" <<'EOF'
species	phylogeny_label	external_trait	covariate	trait_value
Species_a	Species_a	generic_external	external_trait_alpha	1
Species_a	Species_a	generic_covariate	covariate_alpha	1
Species_b	Species_b	generic_external	external_trait_alpha	2
Species_b	Species_b	generic_covariate	covariate_alpha	2
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

assert_awk() {
  file="$1"
  script="$2"
  message="$3"
  if ! awk "$script" "$file"; then
    cat "$file"
    echo "FAIL: $message" >&2
    exit 1
  fi
}

write_profile() {
  dir="$1"
  extra="$2"
  cat > "$dir/profile.yaml" <<EOF
study:
  profile_id: test
  name: Test profile
  description: Test profile.
  version: "1.0"
$extra
phenotype_index:
  name: test_index
  formula: "(component_a - component_b) / component_c"
  components:
    - component_a
    - component_b
    - component_c
  aggregation: mean
  contrasts:
    - name: baseline_vs_response
      type: baseline_vs_response
      baseline_condition: baseline
      response_condition: response
      baseline_timepoint: t0
      response_timepoint: t1
derived_variables:
  - phenotype_index_response
external_traits:
  - external_trait_alpha
covariates:
  - covariate_alpha
hypotheses:
  - name: h1
    description: Test.
    model_type: regression
    response: external_trait_alpha
    predictors:
      - phenotype_index_response
    covariates:
      - covariate_alpha
    phylogenetic: false
    stratify_by: []
reporting:
  phenotype_label: Test index
  condition_label: Condition
  response_label: Response
  external_trait_label: External trait
  candidate_mechanism_label: Mechanism
EOF
}

run_pipeline() {
  profile="$1"
  out="$2"
  mode="${3:-none}"
  mkdir -p "$out"
  python3 "$ROOT_DIR/bin/phenotype_normalize.py" \
    --input "$PHENO" \
    --study_profile "$profile" \
    --normalization "$mode" \
    --output "$out/normalized.tsv" \
    --summary "$out/normalization_summary.tsv" \
    --design_summary "$out/phenotype_design_summary.tsv" > "$out/normalize.out" 2>&1
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
    --manifest_output "$out/manifest.tsv" > "$out/index.out" 2>&1
}

validate_profile() {
  profile="$1"
  out="$2"
  python3 "$ROOT_DIR/bin/validate_study_profile.py" \
    --study_profile "$profile" \
    --phenotype_samplesheet "$PHENO" \
    --species_traits "$TRAITS" \
    --output "$out" > "$out.stdout" 2>&1
}

DEFAULT_DIR="$TMP_DIR/default"
mkdir -p "$DEFAULT_DIR"
write_profile "$DEFAULT_DIR" ""
run_pipeline "$DEFAULT_DIR/profile.yaml" "$DEFAULT_DIR/out"
assert_grep '^replicate_key	species|individual_id|replicate_id|condition|timepoint$' "$DEFAULT_DIR/out/phenotype_design_summary.tsv" "default replicate key not recorded"
assert_awk "$DEFAULT_DIR/out/index_by_group.tsv" 'BEGIN{FS="\t"; ok=0} NR==1{for(i=1;i<=NF;i++) h[$i]=i} NR>1 && $h["species"]=="Species_a" && $h["condition"]=="baseline" && $h["timepoint"]=="t0" && ($h["index_value"]>1.499 && $h["index_value"]<1.501){ok=1} END{exit ok?0:1}' "default index value changed"

NO_PROFILE_OUT="$TMP_DIR/no_profile"
mkdir -p "$NO_PROFILE_OUT"
python3 "$ROOT_DIR/bin/phenotype_normalize.py" \
  --input "$PHENO" \
  --output "$NO_PROFILE_OUT/normalized.tsv" \
  --summary "$NO_PROFILE_OUT/normalization_summary.tsv" \
  --design_summary "$NO_PROFILE_OUT/phenotype_design_summary.tsv" > "$NO_PROFILE_OUT/normalize.out" 2>&1
assert_grep '^normalization_scope	assay|measurement$' "$NO_PROFILE_OUT/phenotype_design_summary.tsv" "normalization without profile did not write default design"

BATCH_DIR="$TMP_DIR/batch"
mkdir -p "$BATCH_DIR"
write_profile "$BATCH_DIR" "phenotype_design:
  replicate_key:
    - species
    - individual_id
    - replicate_id
    - condition
    - timepoint
    - batch
"
run_pipeline "$BATCH_DIR/profile.yaml" "$BATCH_DIR/out"
assert_awk "$BATCH_DIR/out/group_counts.tsv" 'BEGIN{FS="\t"; ok=0} NR>1 && $1=="Species_a" && $2=="baseline" && $4=="t0" && $7==2{ok=1} END{exit ok?0:1}' "batch replicate count was not split"
assert_grep 'Species_a|ind_a|rep1|baseline|t0|b1' "$BATCH_DIR/out/index_by_sample.tsv" "batch b1 sample id absent"
assert_grep 'Species_a|ind_a|rep1|baseline|t0|b2' "$BATCH_DIR/out/index_by_sample.tsv" "batch b2 sample id absent"
assert_grep 'design_replicate_key' "$BATCH_DIR/out/manifest.tsv" "manifest design columns absent"

SCOPE_DIR="$TMP_DIR/scope"
mkdir -p "$SCOPE_DIR"
write_profile "$SCOPE_DIR" "phenotype_design:
  normalization_scope:
    - assay
"
DEFAULT_ZSCORE="$TMP_DIR/default_zscore"
run_pipeline "$DEFAULT_DIR/profile.yaml" "$DEFAULT_ZSCORE" "zscore_within_assay"
run_pipeline "$SCOPE_DIR/profile.yaml" "$SCOPE_DIR/out" "zscore_within_assay"
assert_grep '^normalization_scope	assay$' "$SCOPE_DIR/out/phenotype_design_summary.tsv" "custom normalization scope not recorded"
assert_grep '	assay	' "$SCOPE_DIR/out/normalization_summary.tsv" "normalization summary scope not updated"
if cmp -s "$DEFAULT_ZSCORE/normalized.tsv" "$SCOPE_DIR/out/normalized.tsv"; then
  echo "FAIL: assay-scoped normalization should differ from default assay-measurement scope" >&2
  exit 1
fi

check_invalid_design() {
  name="$1"
  extra="$2"
  rule="$3"
  dir="$TMP_DIR/$name"
  mkdir -p "$dir"
  write_profile "$dir" "$extra"
  if validate_profile "$dir/profile.yaml" "$dir/report.tsv"; then
    cat "$dir/report.tsv"
    echo "FAIL: $name should fail validation" >&2
    exit 1
  fi
  assert_grep "$rule" "$dir/report.tsv" "$name missing $rule"
}

check_invalid_design unknown_replicate "phenotype_design:
  replicate_key: [species, nonexistent_col, condition, timepoint]
" PROFILE_DESIGN_UNKNOWN_FIELD
check_invalid_design unknown_scope "phenotype_design:
  normalization_scope: [assay, bad_col]
" PROFILE_DESIGN_UNKNOWN_FIELD
check_invalid_design empty_key "phenotype_design:
  replicate_key: []
" PROFILE_DESIGN_EMPTY_KEY
check_invalid_design blank_key "phenotype_design:
  normalization_scope: [assay, \"\"]
" PROFILE_DESIGN_EMPTY_KEY
check_invalid_design duplicate_key "phenotype_design:
  normalization_scope: [assay, assay]
" PROFILE_DESIGN_DUPLICATE_FIELD
check_invalid_design invalid_section "phenotype_design: invalid
" PROFILE_DESIGN_INVALID_SECTION
check_invalid_design unknown_key "phenotype_design:
  technical_replicate_key: [batch]
" PROFILE_DESIGN_UNKNOWN_KEY
check_invalid_design missing_group_field "phenotype_design:
  replicate_key: [species, individual_id, replicate_id, condition, batch]
" PROFILE_DESIGN_MISSING_GROUP_FIELD

RUNTIME_BAD="$TMP_DIR/runtime_bad"
mkdir -p "$RUNTIME_BAD"
write_profile "$RUNTIME_BAD" "phenotype_design:
  normalization_scope: [assay, runtime_missing_col]
"
if python3 "$ROOT_DIR/bin/phenotype_normalize.py" \
  --input "$PHENO" \
  --study_profile "$RUNTIME_BAD/profile.yaml" \
  --output "$RUNTIME_BAD/normalized.tsv" \
  --summary "$RUNTIME_BAD/normalization_summary.tsv" \
  --design_summary "$RUNTIME_BAD/phenotype_design_summary.tsv" > "$RUNTIME_BAD/normalize.out" 2>&1; then
  cat "$RUNTIME_BAD/normalize.out"
  echo "FAIL: runtime normalization should fail on missing design field" >&2
  exit 1
fi
assert_grep 'phenotype_design field(s) absent from phenotype table' "$RUNTIME_BAD/normalize.out" "runtime missing design field error absent"

echo "phenotype design tests passed"
