#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT_DIR/bin/validate_study_profile.py"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

run_validator() {
  profile="$1"
  phenotype="$2"
  traits="$3"
  output="$4"
  shift 4
  python3 "$VALIDATOR" \
    --study_profile "$profile" \
    --phenotype_samplesheet "$phenotype" \
    --species_traits "$traits" \
    --output "$output" \
    "$@" > "$output.stdout" 2>&1
}

write_metadata() {
  dir="$1"
  cat > "$dir/phenotype_samplesheet.csv" <<'EOF'
sample_id,species,individual_id,replicate_id,condition,timepoint,assay,measurement,value,unit
p1,Species_a,i1,r1,baseline,t0,generic_profile,component_a,1,ratio
p2,Species_a,i1,r1,baseline,t0,generic_profile,component_b,0.2,ratio
p3,Species_a,i1,r1,baseline,t0,generic_profile,component_c,1,ratio
p3a,Species_a,i1,r1,response,t1,generic_profile,component_a,1.5,ratio
p3b,Species_a,i1,r1,response,t1,generic_profile,component_b,0.3,ratio
p3c,Species_a,i1,r1,response,t1,generic_profile,component_c,1,ratio
p4,Species_a,i1,r1,control,0h,ddr_response,viability,0.8,ratio
p5,Species_a,i1,r1,damage,24h,ddr_response,apoptosis,0.1,ratio
p6,Species_a,i1,r1,damage,24h,ddr_response,senescence,0.1,ratio
EOF
  cat > "$dir/species_traits.tsv" <<'EOF'
species	phylogeny_label	external_trait	covariate	trait_value
Species_a	Species_a	generic_external	external_trait_alpha	1
Species_a	Species_a	generic_covariate	covariate_alpha	1
Species_a	Species_a	life_history	max_longevity	1
Species_a	Species_a	disease_trait	cancer_prevalence	1
Species_a	Species_a	life_history	body_mass	1
EOF
}

write_valid_profile() {
  dir="$1"
  cat > "$dir/study_profile.yaml" <<'EOF'
study:
  profile_id: test
  name: Test profile
  description: Test profile.
  version: "1.0"
phenotype_index:
  name: test_index
  formula: "(component_a - component_b) / component_c"
  components:
    - component_a
    - component_b
    - component_c
  aggregation: mean
  contrasts:
    - name: c1
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

expect_pass() {
  name="$1"
  dir="$TMP_DIR/$name"
  mkdir -p "$dir"
  write_metadata "$dir"
  write_valid_profile "$dir"
  if ! run_validator "$dir/study_profile.yaml" "$dir/phenotype_samplesheet.csv" "$dir/species_traits.tsv" "$dir/report.tsv"; then
    cat "$dir/report.tsv.stdout"
    echo "FAIL: $name expected pass" >&2
    exit 1
  fi
}

expect_fail() {
  name="$1"
  mutate="$2"
  expected="$3"
  dir="$TMP_DIR/$name"
  mkdir -p "$dir"
  write_metadata "$dir"
  write_valid_profile "$dir"
  sh -c "$mutate" sh "$dir"
  if run_validator "$dir/study_profile.yaml" "$dir/phenotype_samplesheet.csv" "$dir/species_traits.tsv" "$dir/report.tsv"; then
    cat "$dir/report.tsv"
    echo "FAIL: $name expected failure" >&2
    exit 1
  fi
  if ! grep -q "$expected" "$dir/report.tsv"; then
    cat "$dir/report.tsv"
    echo "FAIL: $name missing expected report text: $expected" >&2
    exit 1
  fi
}

expect_strict_fail() {
  name="$1"
  mutate="$2"
  expected="$3"
  dir="$TMP_DIR/$name"
  mkdir -p "$dir"
  write_metadata "$dir"
  write_valid_profile "$dir"
  sh -c "$mutate" sh "$dir"
  if run_validator "$dir/study_profile.yaml" "$dir/phenotype_samplesheet.csv" "$dir/species_traits.tsv" "$dir/report.tsv" --validation_strict; then
    cat "$dir/report.tsv"
    echo "FAIL: $name expected strict failure" >&2
    exit 1
  fi
  if ! grep -q "$expected" "$dir/report.tsv"; then
    cat "$dir/report.tsv"
    echo "FAIL: $name missing expected strict report text: $expected" >&2
    exit 1
  fi
}

dir="$TMP_DIR/generic_profile"
mkdir -p "$dir"
if ! run_validator "$ROOT_DIR/profiles/generic/study_profile.yaml" "$ROOT_DIR/assets/example_samplesheets/phenotype_samplesheet.csv" "$ROOT_DIR/assets/example_samplesheets/species_traits.tsv" "$dir/report.tsv"; then
  cat "$dir/report.tsv.stdout"
  echo "FAIL: generic profile expected pass" >&2
  exit 1
fi

dir="$TMP_DIR/ddr_profile"
mkdir -p "$dir"
if ! run_validator "$ROOT_DIR/profiles/ddr_ror/study_profile.yaml" "$ROOT_DIR/assets/example_samplesheets/phenotype_samplesheet.csv" "$ROOT_DIR/assets/example_samplesheets/species_traits.tsv" "$dir/report.tsv"; then
  cat "$dir/report.tsv.stdout"
  echo "FAIL: DDR/RoR profile expected pass" >&2
  exit 1
fi

for profile in immune_response metabolic_response stress_tolerance; do
  dir="$TMP_DIR/${profile}_profile"
  mkdir -p "$dir"
  if ! run_validator "$ROOT_DIR/profiles/$profile/study_profile.yaml" "$ROOT_DIR/assets/example_samplesheets/profile_examples/phenotype_samplesheet.csv" "$ROOT_DIR/assets/example_samplesheets/profile_examples/species_traits.tsv" "$dir/report.tsv"; then
    cat "$dir/report.tsv.stdout"
    echo "FAIL: $profile profile expected pass" >&2
    exit 1
  fi
done

expect_pass valid_profile

expect_fail missing_phenotype_index \
  'awk "BEGIN{skip=0} /^phenotype_index:/{skip=1; next} /^derived_variables:/{skip=0} !skip{print}" "$1/study_profile.yaml" > "$1/tmp" && mv "$1/tmp" "$1/study_profile.yaml"' \
  'Missing required top-level section'

expect_fail formula_unlisted_variable \
  'awk "/formula:/{sub(\"component_c\", \"component_z\")} {print}" "$1/study_profile.yaml" > "$1/tmp" && mv "$1/tmp" "$1/study_profile.yaml"' \
  'Formula variable is not listed in components'

expect_fail invalid_profile_schema \
  'printf "\nunexpected_top_level: true\n" >> "$1/study_profile.yaml"' \
  'PROFILE_SCHEMA_VIOLATION'

expect_fail absent_component \
  'awk -F, "BEGIN{OFS=\",\"} NR==4{\$8=\"missing_component\"} {print}" "$1/phenotype_samplesheet.csv" > "$1/tmp" && mv "$1/tmp" "$1/phenotype_samplesheet.csv"' \
  'PROFILE_CONTRAST_COMPONENT_MISSING'

expect_fail unsafe_formula \
  'awk "/formula:/{print \"  formula: '\''component_a + __import__(\\\"os\\\")'\''\"; next} {print}" "$1/study_profile.yaml" > "$1/tmp" && mv "$1/tmp" "$1/study_profile.yaml"' \
  'Unsafe or unsupported formula element'

expect_fail formula_exponentiation \
  'awk "/formula:/{print \"  formula: '\''component_a ** 2'\''\"; next} {print}" "$1/study_profile.yaml" > "$1/tmp" && mv "$1/tmp" "$1/study_profile.yaml"' \
  'Unsafe or unsupported formula element'

expect_fail missing_contrast_value \
  'sed "s/response_condition: response/response_condition: missing_condition/" "$1/study_profile.yaml" > "$1/tmp" && mv "$1/tmp" "$1/study_profile.yaml"' \
  'Contrast condition not found'

expect_fail incomplete_contrast \
  'awk "/response_condition:/{next} /response_timepoint:/{next} {print}" "$1/study_profile.yaml" > "$1/tmp" && mv "$1/tmp" "$1/study_profile.yaml"' \
  'PROFILE_CONTRAST_INCOMPLETE'

expect_fail contrast_not_executable \
  'sed "s/baseline_condition: baseline/baseline_condition: missing_baseline/" "$1/study_profile.yaml" > "$1/tmp" && mv "$1/tmp" "$1/study_profile.yaml"' \
  'PROFILE_CONTRAST_NOT_EXECUTABLE'

expect_fail malformed_hypothesis \
  'awk "BEGIN{skip=0} /^    predictors:/{skip=1; next} /^    covariates:/{skip=0} !skip{print}" "$1/study_profile.yaml" > "$1/tmp" && mv "$1/tmp" "$1/study_profile.yaml"' \
  'Missing required field'

expect_pass declared_derived_variable

expect_fail undeclared_derived_variable \
  'awk "BEGIN{derived=0} /^derived_variables:/{derived=1} /^external_traits:/{derived=0} derived && /phenotype_index_response/{next} {print}" "$1/study_profile.yaml" > "$1/tmp" && mv "$1/tmp" "$1/study_profile.yaml"' \
  'Variable is not resolvable or declared as derived'

expect_strict_fail strict_low_replicates \
  ':' \
  'PROFILE_CONTRAST_LOW_REPLICATES'

dir="$TMP_DIR/json_summary"
mkdir -p "$dir"
write_metadata "$dir"
write_valid_profile "$dir"
if ! run_validator "$dir/study_profile.yaml" "$dir/phenotype_samplesheet.csv" "$dir/species_traits.tsv" "$dir/report.tsv" --json_summary "$dir/summary.json"; then
  cat "$dir/report.tsv.stdout"
  echo "FAIL: json summary run expected pass" >&2
  exit 1
fi
if ! grep -q '"WARNING"' "$dir/summary.json"; then
  cat "$dir/summary.json"
  echo "FAIL: json summary missing WARNING count" >&2
  exit 1
fi

dir="$TMP_DIR/multi_index_profile"
mkdir -p "$dir"
write_metadata "$dir"
cp "$ROOT_DIR/profiles/multi_index_test/study_profile.yaml" "$dir/study_profile.yaml"
if ! run_validator "$dir/study_profile.yaml" "$dir/phenotype_samplesheet.csv" "$dir/species_traits.tsv" "$dir/report.tsv"; then
  cat "$dir/report.tsv.stdout"
  cat "$dir/report.tsv"
  echo "FAIL: valid multi-index profile expected pass" >&2
  exit 1
fi

awk 'BEGIN{done=0} /formula: "component_a \+ component_b"/ && !done{sub("component_b", "component_z"); done=1} {print}' "$ROOT_DIR/profiles/multi_index_test/study_profile.yaml" > "$dir/bad_formula.yaml"
if run_validator "$dir/bad_formula.yaml" "$dir/phenotype_samplesheet.csv" "$dir/species_traits.tsv" "$dir/bad_formula_report.tsv"; then
  cat "$dir/bad_formula_report.tsv"
  echo "FAIL: invalid secondary index formula expected failure" >&2
  exit 1
fi
if ! grep -q 'Formula variable is not listed in components' "$dir/bad_formula_report.tsv"; then
  cat "$dir/bad_formula_report.tsv"
  echo "FAIL: secondary index formula diagnostic missing" >&2
  exit 1
fi

echo "study profile validation tests passed"
