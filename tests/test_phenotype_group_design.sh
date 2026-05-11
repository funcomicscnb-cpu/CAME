#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PHENO="$TMP_DIR/phenotype.csv"
TRAITS="$TMP_DIR/species_traits.tsv"

cat > "$PHENO" <<'EOF'
sample_id,species,individual_id,replicate_id,condition,timepoint,tissue,assay,measurement,value,unit,batch
liver_base_a,Species_a,ind_liver,rep1,baseline,t0,liver,generic_profile,component_a,2,ratio,b1
liver_base_b,Species_a,ind_liver,rep1,baseline,t0,liver,generic_profile,component_b,0.5,ratio,b1
liver_base_c,Species_a,ind_liver,rep1,baseline,t0,liver,generic_profile,component_c,1,ratio,b1
liver_resp_a,Species_a,ind_liver,rep1,response,t1,liver,generic_profile,component_a,5,ratio,b1
liver_resp_b,Species_a,ind_liver,rep1,response,t1,liver,generic_profile,component_b,1,ratio,b1
liver_resp_c,Species_a,ind_liver,rep1,response,t1,liver,generic_profile,component_c,2,ratio,b1
brain_base_a,Species_a,ind_brain,rep1,baseline,t0,brain,generic_profile,component_a,3,ratio,b1
brain_base_b,Species_a,ind_brain,rep1,baseline,t0,brain,generic_profile,component_b,1,ratio,b1
brain_base_c,Species_a,ind_brain,rep1,baseline,t0,brain,generic_profile,component_c,1,ratio,b1
brain_resp_a,Species_a,ind_brain,rep1,response,t1,brain,generic_profile,component_a,6,ratio,b1
brain_resp_b,Species_a,ind_brain,rep1,response,t1,brain,generic_profile,component_b,1,ratio,b1
brain_resp_c,Species_a,ind_brain,rep1,response,t1,brain,generic_profile,component_c,1,ratio,b1
heart_base_a,Species_a,ind_heart,rep1,baseline,t0,heart,generic_profile,component_a,4,ratio,b1
heart_base_b,Species_a,ind_heart,rep1,baseline,t0,heart,generic_profile,component_b,1,ratio,b1
heart_base_c,Species_a,ind_heart,rep1,baseline,t0,heart,generic_profile,component_c,1,ratio,b1
EOF

cat > "$TRAITS" <<'EOF'
species	phylogeny_label	external_trait	covariate	trait_value
Species_a	Species_a	generic_external	external_trait_alpha	1
Species_a	Species_a	generic_covariate	covariate_alpha	1
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
  profile_id: tissue_test
  name: Tissue test profile
  description: Test profile.
  version: "1.0"
$extra
phenotype_index:
  name: tissue_index
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
  phenotype_label: Tissue index
  condition_label: Condition
  response_label: Response
  external_trait_label: External trait
  candidate_mechanism_label: Mechanism
EOF
}

run_pipeline() {
  profile="$1"
  out="$2"
  mkdir -p "$out"
  python3 "$ROOT_DIR/bin/phenotype_normalize.py" \
    --input "$PHENO" \
    --study_profile "$profile" \
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
    --index_long_output "$out/index_contrasts_long.tsv" \
    --contrast_audit "$out/phenotype_contrast_pairs.tsv" > "$out/contrasts.out" 2>&1
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
assert_awk "$DEFAULT_DIR/out/index_by_group.tsv" 'BEGIN{FS="\t"; ok=0} NR==1{for(i=1;i<=NF;i++) h[$i]=i} NR>1 && $h["species"]=="Species_a" && $h["condition"]=="baseline" && $h["timepoint"]=="t0" && ($h["index_value"]>2.16 && $h["index_value"]<2.17){ok=1} END{exit ok?0:1}' "default grouping did not aggregate tissues"
assert_grep 'Species_a|baseline|t0_vs_response|t1' "$DEFAULT_DIR/out/index_contrasts.tsv" "default contrast group_id changed"

TISSUE_DIR="$TMP_DIR/tissue"
mkdir -p "$TISSUE_DIR"
write_profile "$TISSUE_DIR" "phenotype_design:
  replicate_key: [species, individual_id, replicate_id, condition, timepoint, tissue]
  group_key: [species, condition, timepoint, tissue]
"
run_pipeline "$TISSUE_DIR/profile.yaml" "$TISSUE_DIR/out"
assert_grep '^group_key	species|condition|timepoint|tissue$' "$TISSUE_DIR/out/phenotype_design_summary.tsv" "group key not recorded"
assert_awk "$TISSUE_DIR/out/indexes_by_group.tsv" 'BEGIN{FS="\t"; ok=0} NR==1{for(i=1;i<=NF;i++) h[$i]=i} NR>1 && $h["phenotype_group_id"]=="Species_a|baseline|t0|liver"{ok++} NR>1 && $h["phenotype_group_id"]=="Species_a|baseline|t0|brain"{ok++} END{exit ok==2?0:1}' "tissue groups absent"
assert_grep 'Species_a|liver|baseline|t0_vs_response|t1' "$TISSUE_DIR/out/index_contrasts.tsv" "liver contrast absent"
assert_grep 'Species_a|brain|baseline|t0_vs_response|t1' "$TISSUE_DIR/out/index_contrasts.tsv" "brain contrast absent"
assert_awk "$TISSUE_DIR/out/index_contrasts_long.tsv" 'BEGIN{FS="\t"; ok=0} NR==1{for(i=1;i<=NF;i++) h[$i]=i} NR>1 && $h["group_strata_values"]=="liver" && $h["status"]=="OK" && ($h["difference"]>0.499 && $h["difference"]<0.501){ok++} NR>1 && $h["group_strata_values"]=="brain" && $h["status"]=="OK" && ($h["difference"]>2.999 && $h["difference"]<3.001){ok++} END{exit ok==2?0:1}' "tissue contrast values were not computed from tissue groups"
if grep -q 'heart.*_vs_' "$TISSUE_DIR/out/index_contrasts.tsv"; then
  cat "$TISSUE_DIR/out/index_contrasts.tsv"
  echo "FAIL: unpaired heart stratum should not emit a contrast row" >&2
  exit 1
fi
assert_grep '	PAIRED	' "$TISSUE_DIR/out/phenotype_contrast_pairs.tsv" "paired audit rows absent"
assert_grep '	UNPAIRED_BASELINE	' "$TISSUE_DIR/out/phenotype_contrast_pairs.tsv" "unpaired baseline audit row absent"
assert_grep 'heart' "$TISSUE_DIR/out/phenotype_contrast_pairs.tsv" "heart stratum absent from audit"

# Bug 2 regression: group_counts.tsv must include the extra group_key field (tissue) and
# report per-tissue rows rather than aggregating across all tissues.
assert_grep 'tissue' "$TISSUE_DIR/out/group_counts.tsv" "group_counts.tsv missing tissue column for tissue-stratified design"
assert_awk "$TISSUE_DIR/out/group_counts.tsv" 'BEGIN{FS="\t"; ok=0} NR==1{for(i=1;i<=NF;i++) h[$i]=i} NR>1 && h["tissue"] && $h["tissue"]=="liver"{ok=1} END{exit ok?0:1}' "group_counts.tsv missing per-tissue liver row"

# Bug 3 regression: sample output must include the extra group_key field (tissue).
assert_grep 'tissue' "$TISSUE_DIR/out/index_by_sample.tsv" "index_by_sample.tsv missing tissue column for tissue-stratified design"
assert_awk "$TISSUE_DIR/out/index_by_sample.tsv" 'BEGIN{FS="\t"; ok=0} NR==1{for(i=1;i<=NF;i++) h[$i]=i} NR>1 && h["tissue"] && $h["tissue"]=="liver"{ok=1} END{exit ok?0:1}' "index_by_sample.tsv missing per-tissue liver row"

STALE_DIR="$TMP_DIR/stale_group_key"
mkdir -p "$STALE_DIR"
if python3 "$ROOT_DIR/bin/phenotype_contrasts.py" \
  --phenotype_table "$TISSUE_DIR/out/normalized.tsv" \
  --study_profile "$TISSUE_DIR/profile.yaml" \
  --index_by_group "$DEFAULT_DIR/out/index_by_group.tsv" \
  --indexes_by_group "$DEFAULT_DIR/out/indexes_by_group.tsv" \
  --index_output "$STALE_DIR/index_contrasts.tsv" \
  --component_output "$STALE_DIR/component_contrasts.tsv" \
  --index_long_output "$STALE_DIR/index_contrasts_long.tsv" \
  --contrast_audit "$STALE_DIR/phenotype_contrast_pairs.tsv" > "$STALE_DIR/contrasts.out" 2>&1; then
  cat "$STALE_DIR/contrasts.out"
  echo "FAIL: stale group table should fail when group_key metadata differs from profile" >&2
  exit 1
fi
assert_grep 'different phenotype_design.group_key' "$STALE_DIR/contrasts.out" "stale group key mismatch error absent"

LEGACY_STALE="$TMP_DIR/legacy_stale_group_key"
mkdir -p "$LEGACY_STALE"
awk 'BEGIN{FS=OFS="\t"} NR==1{for(i=1;i<=NF;i++) h[$i]=i; print "profile_id","phenotype_index_name","species","condition","timepoint","replicate_n","index_value","status","message","source_sample_ids"; next} {print $h["profile_id"],$h["phenotype_index_name"],$h["species"],$h["condition"],$h["timepoint"],$h["replicate_n"],$h["index_value"],$h["status"],$h["message"],$h["source_sample_ids"]}' "$DEFAULT_DIR/out/index_by_group.tsv" > "$LEGACY_STALE/legacy_index_by_group.tsv"
if python3 "$ROOT_DIR/bin/phenotype_contrasts.py" \
  --phenotype_table "$TISSUE_DIR/out/normalized.tsv" \
  --study_profile "$TISSUE_DIR/profile.yaml" \
  --index_by_group "$LEGACY_STALE/legacy_index_by_group.tsv" \
  --index_output "$LEGACY_STALE/index_contrasts.tsv" \
  --component_output "$LEGACY_STALE/component_contrasts.tsv" \
  --index_long_output "$LEGACY_STALE/index_contrasts_long.tsv" \
  --contrast_audit "$LEGACY_STALE/phenotype_contrast_pairs.tsv" > "$LEGACY_STALE/contrasts.out" 2>&1; then
  cat "$LEGACY_STALE/contrasts.out"
  echo "FAIL: legacy group table should fail when custom group_key needs missing columns" >&2
  exit 1
fi
assert_grep 'lacks phenotype_group_key metadata' "$LEGACY_STALE/contrasts.out" "legacy group key metadata error absent"

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

# B4 regression: a strata combination present only under a third condition (not baseline or
# response) must not produce a spurious UNPAIRED_RESPONSE audit row.
PHANTOM_DIR="$TMP_DIR/phantom"
mkdir -p "$PHANTOM_DIR"
cat > "$PHANTOM_DIR/pheno.csv" <<'EOF'
sample_id,species,individual_id,replicate_id,condition,timepoint,tissue,assay,measurement,value,unit,batch
liver_base_a,Species_a,ind_liver,rep1,baseline,t0,liver,generic_profile,component_a,2,ratio,b1
liver_base_b,Species_a,ind_liver,rep1,baseline,t0,liver,generic_profile,component_b,0.5,ratio,b1
liver_base_c,Species_a,ind_liver,rep1,baseline,t0,liver,generic_profile,component_c,1,ratio,b1
liver_resp_a,Species_a,ind_liver,rep1,response,t1,liver,generic_profile,component_a,5,ratio,b1
liver_resp_b,Species_a,ind_liver,rep1,response,t1,liver,generic_profile,component_b,1,ratio,b1
liver_resp_c,Species_a,ind_liver,rep1,response,t1,liver,generic_profile,component_c,2,ratio,b1
phantom_ctrl_a,Species_a,ind_ph,rep1,control,t3,phantom,generic_profile,component_a,3,ratio,b1
phantom_ctrl_b,Species_a,ind_ph,rep1,control,t3,phantom,generic_profile,component_b,1,ratio,b1
phantom_ctrl_c,Species_a,ind_ph,rep1,control,t3,phantom,generic_profile,component_c,1,ratio,b1
EOF
write_profile "$PHANTOM_DIR" "phenotype_design:
  replicate_key: [species, individual_id, replicate_id, condition, timepoint, tissue]
  group_key: [species, condition, timepoint, tissue]
"
python3 "$ROOT_DIR/bin/phenotype_normalize.py" \
  --input "$PHANTOM_DIR/pheno.csv" \
  --study_profile "$PHANTOM_DIR/profile.yaml" \
  --output "$PHANTOM_DIR/norm.tsv" \
  --summary "$PHANTOM_DIR/norm_summary.tsv" \
  --design_summary "$PHANTOM_DIR/design_summary.tsv" > "$PHANTOM_DIR/norm.out" 2>&1
python3 "$ROOT_DIR/bin/calc_phenotype_index.py" \
  --input "$PHANTOM_DIR/norm.tsv" \
  --study_profile "$PHANTOM_DIR/profile.yaml" \
  --sample_output "$PHANTOM_DIR/sample.tsv" \
  --group_output "$PHANTOM_DIR/group.tsv" \
  --indexes_group_output "$PHANTOM_DIR/indexes_group.tsv" > "$PHANTOM_DIR/index.out" 2>&1
python3 "$ROOT_DIR/bin/phenotype_contrasts.py" \
  --phenotype_table "$PHANTOM_DIR/norm.tsv" \
  --study_profile "$PHANTOM_DIR/profile.yaml" \
  --index_by_group "$PHANTOM_DIR/group.tsv" \
  --indexes_by_group "$PHANTOM_DIR/indexes_group.tsv" \
  --index_output "$PHANTOM_DIR/contrasts.tsv" \
  --component_output "$PHANTOM_DIR/comp_contrasts.tsv" \
  --contrast_audit "$PHANTOM_DIR/audit.tsv" > "$PHANTOM_DIR/contrasts.out" 2>&1
if grep -q 'phantom' "$PHANTOM_DIR/audit.tsv"; then
  cat "$PHANTOM_DIR/audit.tsv"
  echo "FAIL: phantom strata (neither baseline nor response) must not appear in contrast audit" >&2
  exit 1
fi
assert_grep '	PAIRED	' "$PHANTOM_DIR/audit.tsv" "phantom test: paired liver audit row absent"

check_invalid_design group_missing_species "phenotype_design:
  group_key: [condition, timepoint]
" PROFILE_DESIGN_MISSING_GROUP_FIELD
check_invalid_design group_duplicate "phenotype_design:
  group_key: [species, condition, condition, timepoint]
" PROFILE_DESIGN_DUPLICATE_FIELD
check_invalid_design replicate_missing_group "phenotype_design:
  replicate_key: [species, individual_id, replicate_id, condition, timepoint]
  group_key: [species, condition, timepoint, tissue]
" PROFILE_DESIGN_MISSING_GROUP_FIELD
check_invalid_design unknown_group_field "phenotype_design:
  replicate_key: [species, individual_id, replicate_id, condition, timepoint, nonexistent_field]
  group_key: [species, condition, timepoint, nonexistent_field]
" PROFILE_DESIGN_UNKNOWN_FIELD
check_invalid_design contrast_axis_missing "phenotype_design:
  replicate_key: [species, individual_id, replicate_id, condition, timepoint, tissue]
  group_key: [species, tissue]
" PROFILE_DESIGN_MISSING_CONTRAST_AXIS

COND_AXIS_DIR="$TMP_DIR/condition_axis_missing"
mkdir -p "$COND_AXIS_DIR"
write_profile "$COND_AXIS_DIR" "phenotype_design:
  replicate_key: [species, individual_id, replicate_id, condition, timepoint, tissue]
  group_key: [species, condition, tissue]
"
sed 's/type: baseline_vs_response/type: condition_contrast/' "$COND_AXIS_DIR/profile.yaml" > "$COND_AXIS_DIR/profile_condition.yaml"
if validate_profile "$COND_AXIS_DIR/profile_condition.yaml" "$COND_AXIS_DIR/report.tsv"; then
  cat "$COND_AXIS_DIR/report.tsv"
  echo "FAIL: condition_contrast with timepoint labels should require timepoint in group_key" >&2
  exit 1
fi
assert_grep 'PROFILE_DESIGN_MISSING_CONTRAST_AXIS' "$COND_AXIS_DIR/report.tsv" "condition_contrast optional timepoint axis rule missing"

NO_PAIRED_STRATA="$TMP_DIR/no_paired_strata"
mkdir -p "$NO_PAIRED_STRATA"
awk -F, 'BEGIN{OFS=","} !($1 ~ /^liver_resp/ || $1 ~ /^brain_base/){print}' "$PHENO" > "$NO_PAIRED_STRATA/phenotype.csv"
write_profile "$NO_PAIRED_STRATA" "phenotype_design:
  replicate_key: [species, individual_id, replicate_id, condition, timepoint, tissue]
  group_key: [species, condition, timepoint, tissue]
"
if python3 "$ROOT_DIR/bin/validate_study_profile.py" \
  --study_profile "$NO_PAIRED_STRATA/profile.yaml" \
  --phenotype_samplesheet "$NO_PAIRED_STRATA/phenotype.csv" \
  --species_traits "$TRAITS" \
  --output "$NO_PAIRED_STRATA/report.tsv" > "$NO_PAIRED_STRATA/report.out" 2>&1; then
  cat "$NO_PAIRED_STRATA/report.tsv"
  echo "FAIL: validation should fail when no baseline/response pair exists within group_key strata" >&2
  exit 1
fi
assert_grep 'PROFILE_CONTRAST_NOT_EXECUTABLE' "$NO_PAIRED_STRATA/report.tsv" "stratified contrast executability rule missing"

AXIS_BAD="$TMP_DIR/axis_bad"
mkdir -p "$AXIS_BAD"
write_profile "$AXIS_BAD" "phenotype_design:
  replicate_key: [species, individual_id, replicate_id, condition, timepoint, tissue]
  group_key: [species, timepoint, tissue]
"
if run_pipeline "$AXIS_BAD/profile.yaml" "$AXIS_BAD/out"; then
  cat "$AXIS_BAD/out/contrasts.out"
  echo "FAIL: contrast should fail when group_key omits required contrast axis" >&2
  exit 1
fi
assert_grep 'requires group_key field(s): condition' "$AXIS_BAD/out/contrasts.out" "missing contrast axis error absent"

RUNTIME_BAD="$TMP_DIR/runtime_bad"
mkdir -p "$RUNTIME_BAD"
write_profile "$RUNTIME_BAD" "phenotype_design:
  replicate_key: [species, individual_id, replicate_id, condition, timepoint, runtime_missing]
  group_key: [species, condition, timepoint, runtime_missing]
"
if python3 "$ROOT_DIR/bin/phenotype_normalize.py" \
  --input "$PHENO" \
  --study_profile "$RUNTIME_BAD/profile.yaml" \
  --output "$RUNTIME_BAD/normalized.tsv" \
  --summary "$RUNTIME_BAD/normalization_summary.tsv" \
  --design_summary "$RUNTIME_BAD/phenotype_design_summary.tsv" > "$RUNTIME_BAD/normalize.out" 2>&1; then
  cat "$RUNTIME_BAD/normalize.out"
  echo "FAIL: runtime normalization should fail on missing group field" >&2
  exit 1
fi
assert_grep 'phenotype_design field(s) absent from phenotype table' "$RUNTIME_BAD/normalize.out" "runtime missing group field error absent"

echo "phenotype group design tests passed"
