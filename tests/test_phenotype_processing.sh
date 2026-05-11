#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

write_phenotype() {
  file="$1"
  cat > "$file" <<'EOF'
sample_id,species,individual_id,replicate_id,condition,timepoint,assay,measurement,value,unit,batch
generic_a_base_a,Species_a,ind_a,rep1,baseline,t0,generic_profile,component_a,2,ratio,b1
generic_a_base_b,Species_a,ind_a,rep1,baseline,t0,generic_profile,component_b,0.5,ratio,b1
generic_a_base_c,Species_a,ind_a,rep1,baseline,t0,generic_profile,component_c,1,ratio,b1
generic_a_resp_a,Species_a,ind_a,rep1,response,t1,generic_profile,component_a,5,ratio,b1
generic_a_resp_b,Species_a,ind_a,rep1,response,t1,generic_profile,component_b,1,ratio,b1
generic_a_resp_c,Species_a,ind_a,rep1,response,t1,generic_profile,component_c,2,ratio,b1
generic_b_base_a,Species_b,ind_b,rep1,baseline,t0,generic_profile,component_a,1.5,ratio,b1
generic_b_base_b,Species_b,ind_b,rep1,baseline,t0,generic_profile,component_b,0.5,ratio,b1
generic_b_base_c,Species_b,ind_b,rep1,baseline,t0,generic_profile,component_c,1,ratio,b1
generic_b_resp_a,Species_b,ind_b,rep1,response,t1,generic_profile,component_a,3,ratio,b1
generic_b_resp_b,Species_b,ind_b,rep1,response,t1,generic_profile,component_b,0.5,ratio,b1
generic_b_resp_c,Species_b,ind_b,rep1,response,t1,generic_profile,component_c,1,ratio,b1
ddr_a_ctrl_v,Species_a,ind_a,rep1,control,0h,ddr_response,viability,1,ratio,b1
ddr_a_ctrl_a,Species_a,ind_a,rep1,control,0h,ddr_response,apoptosis,0.1,ratio,b1
ddr_a_ctrl_s,Species_a,ind_a,rep1,control,0h,ddr_response,senescence,0.1,ratio,b1
ddr_a_dmg_v,Species_a,ind_a,rep1,damage,24h,ddr_response,viability,0.7,ratio,b1
ddr_a_dmg_a,Species_a,ind_a,rep1,damage,24h,ddr_response,apoptosis,0.2,ratio,b1
ddr_a_dmg_s,Species_a,ind_a,rep1,damage,24h,ddr_response,senescence,0.1,ratio,b1
ddr_b_ctrl_v,Species_b,ind_b,rep1,control,0h,ddr_response,viability,0.9,ratio,b1
ddr_b_ctrl_a,Species_b,ind_b,rep1,control,0h,ddr_response,apoptosis,0.1,ratio,b1
ddr_b_ctrl_s,Species_b,ind_b,rep1,control,0h,ddr_response,senescence,0.1,ratio,b1
ddr_b_dmg_v,Species_b,ind_b,rep1,damage,24h,ddr_response,viability,0.8,ratio,b1
ddr_b_dmg_a,Species_b,ind_b,rep1,damage,24h,ddr_response,apoptosis,0.1,ratio,b1
ddr_b_dmg_s,Species_b,ind_b,rep1,damage,24h,ddr_response,senescence,0.1,ratio,b1
EOF
}

run_pipeline() {
  profile="$1"
  phenotype="$2"
  out="$3"
  mode="${4:-none}"
  mkdir -p "$out"
  python3 "$ROOT_DIR/bin/phenotype_normalize.py" \
    --input "$phenotype" \
    --normalization "$mode" \
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
}

assert_value() {
  file="$1"
  awk_expr="$2"
  message="$3"
  if ! awk "$awk_expr" "$file"; then
    cat "$file"
    echo "FAIL: $message" >&2
    exit 1
  fi
}

PHENO="$TMP_DIR/phenotype.csv"
write_phenotype "$PHENO"

GENERIC_OUT="$TMP_DIR/generic"
run_pipeline "$ROOT_DIR/profiles/generic/study_profile.yaml" "$PHENO" "$GENERIC_OUT"
assert_value "$GENERIC_OUT/index_by_group.tsv" 'BEGIN{FS="\t"; ok=0} NR==1{for(i=1;i<=NF;i++) h[$i]=i} NR>1 && $h["species"]=="Species_a" && $h["condition"]=="response" && $h["timepoint"]=="t1" && ($h["index_value"]>1.999 && $h["index_value"]<2.001){ok=1} END{exit ok?0:1}' "generic response index value"
assert_value "$GENERIC_OUT/index_contrasts.tsv" 'BEGIN{FS="\t"; ok=0} NR==1{for(i=1;i<=NF;i++) h[$i]=i} NR>1 && $h["contrast_name"]=="baseline_vs_response" && $h["species"]=="Species_a" && ($h["difference"]>0.499 && $h["difference"]<0.501){ok=1} END{exit ok?0:1}' "generic contrast difference"

DDR_OUT="$TMP_DIR/ddr"
run_pipeline "$ROOT_DIR/profiles/ddr_ror/study_profile.yaml" "$PHENO" "$DDR_OUT"
assert_value "$DDR_OUT/index_by_group.tsv" 'BEGIN{FS="\t"; ok=0} NR==1{for(i=1;i<=NF;i++) h[$i]=i} NR>1 && $h["species"]=="Species_a" && $h["condition"]=="damage" && $h["timepoint"]=="24h" && ($h["index_value"]>0.444 && $h["index_value"]<0.445){ok=1} END{exit ok?0:1}' "DDR/RoR damage index value"

MISSING="$TMP_DIR/missing_component.csv"
awk -F, 'BEGIN{OFS=","} !($8=="component_c" && $5=="response" && $6=="t1"){print}' "$PHENO" > "$MISSING"
mkdir -p "$TMP_DIR/missing"
python3 "$ROOT_DIR/bin/phenotype_normalize.py" --input "$MISSING" --output "$TMP_DIR/missing/norm.tsv" --summary "$TMP_DIR/missing/summary.tsv" > "$TMP_DIR/missing/norm.out" 2>&1
if python3 "$ROOT_DIR/bin/calc_phenotype_index.py" --input "$TMP_DIR/missing/norm.tsv" --study_profile "$ROOT_DIR/profiles/generic/study_profile.yaml" --sample_output "$TMP_DIR/missing/sample.tsv" --group_output "$TMP_DIR/missing/group.tsv" > "$TMP_DIR/missing/index.out" 2>&1; then
  cat "$TMP_DIR/missing/index.out"
  echo "FAIL: missing component expected failure" >&2
  exit 1
fi

ZERO="$TMP_DIR/div_zero.csv"
awk -F, 'BEGIN{OFS=","} $8=="component_c" && $5=="response" && $6=="t1" && $2=="Species_a"{$9=0} {print}' "$PHENO" > "$ZERO"
ZERO_OUT="$TMP_DIR/div_zero"
run_pipeline "$ROOT_DIR/profiles/generic/study_profile.yaml" "$ZERO" "$ZERO_OUT"
if ! grep -q 'Division by zero' "$ZERO_OUT/index_by_sample.tsv"; then
  cat "$ZERO_OUT/index_by_sample.tsv"
  echo "FAIL: division by zero warning missing" >&2
  exit 1
fi

BAD_PROFILE="$TMP_DIR/bad_formula.yaml"
sed 's/formula: "(component_a - component_b) \/ component_c"/formula: "component_a ** 2"/' "$ROOT_DIR/profiles/generic/study_profile.yaml" > "$BAD_PROFILE"
if python3 "$ROOT_DIR/bin/calc_phenotype_index.py" --input "$GENERIC_OUT/normalized.tsv" --study_profile "$BAD_PROFILE" --sample_output "$TMP_DIR/bad_sample.tsv" --group_output "$TMP_DIR/bad_group.tsv" > "$TMP_DIR/bad_formula.out" 2>&1; then
  cat "$TMP_DIR/bad_formula.out"
  echo "FAIL: invalid formula expected failure" >&2
  exit 1
fi

DUP="$TMP_DIR/duplicate.csv"
awk 'NR==2{print} {print}' "$PHENO" > "$DUP"
mkdir -p "$TMP_DIR/dup"
python3 "$ROOT_DIR/bin/phenotype_normalize.py" --input "$DUP" --output "$TMP_DIR/dup/norm.tsv" --summary "$TMP_DIR/dup/summary.tsv" > "$TMP_DIR/dup/norm.out" 2>&1
if ! grep -q 'exact_duplicate_rows_removed' "$TMP_DIR/dup/summary.tsv"; then
  cat "$TMP_DIR/dup/summary.tsv"
  echo "FAIL: duplicate warning missing" >&2
  exit 1
fi

BAD_CONTRAST="$TMP_DIR/bad_contrast.yaml"
sed 's/response_condition: response/response_condition: missing_condition/' "$ROOT_DIR/profiles/generic/study_profile.yaml" > "$BAD_CONTRAST"
if python3 "$ROOT_DIR/bin/phenotype_contrasts.py" --phenotype_table "$GENERIC_OUT/normalized.tsv" --study_profile "$BAD_CONTRAST" --index_by_group "$GENERIC_OUT/index_by_group.tsv" --index_output "$TMP_DIR/bad_contrast.tsv" --component_output "$TMP_DIR/bad_component.tsv" > "$TMP_DIR/bad_contrast.out" 2>&1; then
  cat "$TMP_DIR/bad_contrast.out"
  echo "FAIL: missing contrast condition expected failure" >&2
  exit 1
fi

for mode in none zscore_within_assay minmax_within_assay log10_if_positive median_center_within_assay; do
  mkdir -p "$TMP_DIR/mode_$mode"
  python3 "$ROOT_DIR/bin/phenotype_normalize.py" \
    --input "$PHENO" \
    --normalization "$mode" \
    --output "$TMP_DIR/mode_$mode/norm.tsv" \
    --summary "$TMP_DIR/mode_$mode/summary.tsv" > "$TMP_DIR/mode_$mode/out.txt" 2>&1
done

bash "$ROOT_DIR/tests/test_metadata_validation.sh"
bash "$ROOT_DIR/tests/test_study_profile_validation.sh"

echo "phenotype processing tests passed"
