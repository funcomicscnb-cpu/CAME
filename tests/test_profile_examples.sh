#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT_DIR/bin/validate_study_profile.py"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
cd "$ROOT_DIR"

MAIN_PHENO="$ROOT_DIR/assets/example_samplesheets/phenotype_samplesheet.csv"
MAIN_TRAITS="$ROOT_DIR/assets/example_samplesheets/species_traits.tsv"
EXAMPLE_PHENO="$ROOT_DIR/assets/example_samplesheets/profile_examples/phenotype_samplesheet.csv"
EXAMPLE_TRAITS="$ROOT_DIR/assets/example_samplesheets/profile_examples/species_traits.tsv"

run_validator() {
  profile="$1"
  phenotype="$2"
  traits="$3"
  output="$4"
  python3 "$VALIDATOR" \
    --study_profile "$profile" \
    --phenotype_samplesheet "$phenotype" \
    --species_traits "$traits" \
    --output "$output" > "$output.stdout" 2>&1
}

assert_validator_pass() {
  name="$1"
  profile="$2"
  phenotype="$3"
  traits="$4"
  out="$TMP_DIR/${name}_validation.tsv"
  if ! run_validator "$profile" "$phenotype" "$traits" "$out"; then
    cat "$out.stdout"
    [ ! -f "$out" ] || cat "$out"
    echo "FAIL: $name profile expected validation pass" >&2
    exit 1
  fi
}

assert_validator_fail() {
  name="$1"
  profile="$2"
  phenotype="$3"
  traits="$4"
  expected="$5"
  out="$TMP_DIR/${name}_validation.tsv"
  if run_validator "$profile" "$phenotype" "$traits" "$out"; then
    cat "$out"
    echo "FAIL: $name profile expected validation failure" >&2
    exit 1
  fi
  if ! grep -q "$expected" "$out"; then
    cat "$out"
    echo "FAIL: $name validation report missing expected text: $expected" >&2
    exit 1
  fi
}

run_profile_smoke() {
  name="$1"
  profile="$2"
  contrast="$3"
  out="$TMP_DIR/$name"
  mkdir -p "$out"
  python3 "$ROOT_DIR/bin/phenotype_normalize.py" \
    --input "$EXAMPLE_PHENO" \
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
    --group_output "$out/index_by_group.tsv" > "$out/index.out" 2>&1
  python3 "$ROOT_DIR/bin/phenotype_contrasts.py" \
    --phenotype_table "$out/normalized.tsv" \
    --study_profile "$profile" \
    --index_by_group "$out/index_by_group.tsv" \
    --index_output "$out/index_contrasts.tsv" \
    --component_output "$out/component_contrasts.tsv" > "$out/contrasts.out" 2>&1

  if ! awk -v name="$contrast" 'BEGIN{FS="\t"; ok=0} NR==1{for(i=1;i<=NF;i++) h[$i]=i} NR>1 && $h["contrast_name"]==name && $h["status"]=="OK"{ok++} END{exit ok>=4?0:1}' "$out/index_contrasts.tsv"; then
    cat "$out/index_contrasts.tsv"
    echo "FAIL: $name index contrast smoke check failed" >&2
    exit 1
  fi
  if ! awk -v name="$contrast" 'BEGIN{FS="\t"; ok=0} NR==1{for(i=1;i<=NF;i++) h[$i]=i} NR>1 && $h["contrast_name"]==name && $h["status"]=="OK"{ok++} END{exit ok>=16?0:1}' "$out/component_contrasts.tsv"; then
    cat "$out/component_contrasts.tsv"
    echo "FAIL: $name component contrast smoke check failed" >&2
    exit 1
  fi
}

assert_no_core_terms() {
  core_paths="main.nf nextflow.config lib bin workflows subworkflows modules"
  for term in \
    immune_response metabolic_response stress_tolerance \
    pathogen_clearance cytokine_signal tissue_damage inflammation_baseline \
    glucose_clearance lipid_mobilization oxygen_efficiency heat_output \
    survival_fraction recovery_rate damage_marker stress_intensity \
    infection_resistance metabolic_flexibility stress_resilience
  do
    if rg --fixed-strings "$term" $core_paths >/dev/null 2>&1; then
      rg --fixed-strings "$term" $core_paths
      echo "FAIL: profile-specific example term leaked into core logic: $term" >&2
      exit 1
    fi
  done
}

assert_validator_pass generic "$ROOT_DIR/profiles/generic/study_profile.yaml" "$MAIN_PHENO" "$MAIN_TRAITS"
assert_validator_pass ddr_ror "$ROOT_DIR/profiles/ddr_ror/study_profile.yaml" "$MAIN_PHENO" "$MAIN_TRAITS"
assert_validator_pass immune_response "$ROOT_DIR/profiles/immune_response/study_profile.yaml" "$EXAMPLE_PHENO" "$EXAMPLE_TRAITS"
assert_validator_pass metabolic_response "$ROOT_DIR/profiles/metabolic_response/study_profile.yaml" "$EXAMPLE_PHENO" "$EXAMPLE_TRAITS"
assert_validator_pass stress_tolerance "$ROOT_DIR/profiles/stress_tolerance/study_profile.yaml" "$EXAMPLE_PHENO" "$EXAMPLE_TRAITS"

run_profile_smoke immune_response "$ROOT_DIR/profiles/immune_response/study_profile.yaml" immune_challenge_response
run_profile_smoke metabolic_response "$ROOT_DIR/profiles/metabolic_response/study_profile.yaml" fasting_response
run_profile_smoke stress_tolerance "$ROOT_DIR/profiles/stress_tolerance/study_profile.yaml" acute_stress_response

MISSING_COMPONENT="$TMP_DIR/immune_missing_component.yaml"
awk '$0=="    - tissue_damage"{next} {print}' "$ROOT_DIR/profiles/immune_response/study_profile.yaml" > "$MISSING_COMPONENT"
assert_validator_fail missing_component "$MISSING_COMPONENT" "$EXAMPLE_PHENO" "$EXAMPLE_TRAITS" "Formula variable is not listed in components"

UNSAFE_FORMULA="$TMP_DIR/immune_unsafe_formula.yaml"
awk '/formula:/{print "  formula: \"pathogen_clearance + __import__(\\\"os\\\")\""; next} {print}' "$ROOT_DIR/profiles/immune_response/study_profile.yaml" > "$UNSAFE_FORMULA"
assert_validator_fail unsafe_formula "$UNSAFE_FORMULA" "$EXAMPLE_PHENO" "$EXAMPLE_TRAITS" "Unsafe or unsupported formula element"

python3 -c 'from pathlib import Path; import sys; sys.path.insert(0, "bin"); import render_final_report; profile = render_final_report.load_profile("profiles/immune_response/study_profile.yaml", Path("results")); assert profile["profile_id"] == "immune_response"; assert profile["name"] == "Immune response template profile"'

assert_no_core_terms

echo "profile example tests passed"
