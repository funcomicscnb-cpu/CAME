#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

CONFIG="$ROOT_DIR/assets/example_samplesheets/advanced_model_config.tsv"

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

assert_no_ok_rows() {
  file="$1"
  message="$2"
  if awk 'BEGIN{FS="\t"; ok=0} NR>1 {for (i=1; i<=NF; i++) if ($i=="OK") ok=1} END{exit ok?0:1}' "$file"; then
    cat "$file"
    echo "FAIL: $message" >&2
    exit 1
  fi
}

TREE="$TMP_DIR/example_tree.nwk"
cat > "$TREE" <<'EOF'
((Species_a:0.1,Species_b:0.2):0.3,(Species_c:0.2,Species_d:0.3):0.4);
EOF

SYN_OUT="$TMP_DIR/synthetic_results"
mkdir -p "$SYN_OUT/phylo/input" "$SYN_OUT/integration/input" "$SYN_OUT/phenotype/contrasts"
cat > "$SYN_OUT/phylo/input/hypothesis_model_table.tsv" <<EOF
species	phylogeny_label	phylogeny_id	phylogeny_file	phenotype_index_response	external_trait_alpha	phenotype_index_difference	phenotype_index_fold_change	phenotype_index_log2_fold_change
Species_a	Species_a	synthetic_tree	$TREE	1.0	2.0	1.0	2.0	1.0
Species_b	Species_b	synthetic_tree	$TREE	2.0	4.0	2.0	3.0	1.5
Species_c	Species_c	synthetic_tree	$TREE	3.0	5.0	3.0	4.0	2.0
Species_d	Species_d	synthetic_tree	$TREE	4.0	8.0	4.0	5.0	2.5
EOF
cat > "$SYN_OUT/integration/input/phenotype_omics_model_table.tsv" <<'EOF'
species	phenotype_response_value	feature_response_value	feature_layer	feature_id	contrast_name	phenotype_response_id
Species_a	1.0	1.5	expression	feature_1	contrast_1	response_1
Species_b	2.0	2.5	expression	feature_1	contrast_1	response_1
Species_c	3.0	2.8	expression	feature_1	contrast_1	response_1
Species_d	4.0	4.2	expression	feature_1	contrast_1	response_1
EOF
cat > "$SYN_OUT/phenotype/contrasts/phenotype_index_contrasts.tsv" <<'EOF'
contrast_name	species	difference	status
contrast_1	Species_a	1.0	OK
EOF
cat > "$SYN_OUT/phenotype/contrasts/component_trait_contrasts.tsv" <<'EOF'
trait	contrast_name	species	difference	status
component_1	contrast_1	Species_a	1.0	OK
EOF

PREP="$TMP_DIR/prep_default"
python3 "$ROOT_DIR/bin/prepare_advanced_model_inputs.py" \
  --config "$CONFIG" \
  --outdir "$SYN_OUT" \
  --output_dir "$PREP" > "$TMP_DIR/prepare_default.out" 2>&1
assert_file "$PREP/advanced_model_manifest.tsv" "advanced model manifest missing"
assert_file "$PREP/advanced_model_warnings.tsv" "advanced model warnings missing"
assert_grep 'hypothesis_lm_screen' "$PREP/advanced_model_manifest.tsv" "default config model missing from manifest"

BAD_CONFIG="$TMP_DIR/bad_config.tsv"
awk -F'\t' 'BEGIN{OFS="\t"} NR==1{print $1,$2,$4; next} {print $1,$2,$4}' "$CONFIG" > "$BAD_CONFIG"
if python3 "$ROOT_DIR/bin/prepare_advanced_model_inputs.py" \
  --config "$BAD_CONFIG" \
  --outdir "$SYN_OUT" \
  --output_dir "$TMP_DIR/bad_prep" > "$TMP_DIR/bad_prepare.out" 2>&1; then
  cat "$TMP_DIR/bad_prepare.out"
  echo "FAIL: missing required config column expected failure" >&2
  exit 1
fi
assert_grep 'missing required column' "$TMP_DIR/bad_prepare.out" "missing required column diagnostic absent"

MODEL_STUB="$TMP_DIR/model_stub"
Rscript "$ROOT_DIR/bin/run_model_comparison.R" \
  --manifest "$PREP/advanced_model_manifest.tsv" \
  --advanced_statistics_stub true \
  --output_dir "$MODEL_STUB" > "$TMP_DIR/model_stub.out" 2>&1
assert_file "$MODEL_STUB/model_comparison_results.tsv" "stub model comparison results missing"
assert_file "$MODEL_STUB/model_comparison_warnings.tsv" "stub model comparison warnings missing"
assert_grep 'advanced_statistics_stub=true' "$MODEL_STUB/model_comparison_warnings.tsv" "stub warning missing"
assert_grep 'Placeholder model family is not implemented' "$MODEL_STUB/model_comparison_warnings.tsv" "placeholder warning missing"
assert_no_ok_rows "$MODEL_STUB/model_comparison_results.tsv" "stub mode emitted fake OK model results"

ROBUST_STUB="$TMP_DIR/robust_stub"
Rscript "$ROOT_DIR/bin/run_robustness_checks.R" \
  --manifest "$PREP/advanced_model_manifest.tsv" \
  --advanced_statistics_stub true \
  --output_dir "$ROBUST_STUB" > "$TMP_DIR/robust_stub.out" 2>&1
assert_file "$ROBUST_STUB/robustness_check_results.tsv" "stub robustness results missing"
assert_file "$ROBUST_STUB/robustness_warnings.tsv" "stub robustness warnings missing"

LM_CONFIG="$TMP_DIR/lm_config.tsv"
cat > "$LM_CONFIG" <<'EOF'
model_id	analysis_target	model_family	enabled	response	predictors	covariates	phylogenetic_model	min_species	notes
synthetic_lm	hypothesis_model_table	lm	true	phenotype_index_response	external_trait_alpha			3	Small synthetic LM model.
EOF
LM_PREP="$TMP_DIR/lm_prep"
python3 "$ROOT_DIR/bin/prepare_advanced_model_inputs.py" \
  --config "$LM_CONFIG" \
  --outdir "$SYN_OUT" \
  --output_dir "$LM_PREP" > "$TMP_DIR/lm_prepare.out" 2>&1
LM_MODEL="$TMP_DIR/lm_model"
Rscript "$ROOT_DIR/bin/run_model_comparison.R" \
  --manifest "$LM_PREP/advanced_model_manifest.tsv" \
  --advanced_statistics_stub false \
  --output_dir "$LM_MODEL" > "$TMP_DIR/lm_model.out" 2>&1
assert_grep 'synthetic_lm' "$LM_MODEL/model_comparison_results.tsv" "LM comparison result missing"
assert_grep 'OK' "$LM_MODEL/model_comparison_results.tsv" "LM comparison did not succeed"

LM_ROBUST="$TMP_DIR/lm_robust"
Rscript "$ROOT_DIR/bin/run_robustness_checks.R" \
  --manifest "$LM_PREP/advanced_model_manifest.tsv" \
  --advanced_statistics_stub false \
  --output_dir "$LM_ROBUST" > "$TMP_DIR/lm_robust.out" 2>&1
assert_grep 'missingness' "$LM_ROBUST/robustness_check_results.tsv" "missingness robustness row missing"
assert_grep 'leave_one_species_out' "$LM_ROBUST/robustness_check_results.tsv" "leave-one-species-out rows missing"

SUMMARY="$TMP_DIR/summary"
python3 "$ROOT_DIR/bin/summarize_advanced_statistics.py" \
  --advanced_model_manifest "$LM_PREP/advanced_model_manifest.tsv" \
  --advanced_model_warnings "$LM_PREP/advanced_model_warnings.tsv" \
  --model_comparison_results "$LM_MODEL/model_comparison_results.tsv" \
  --model_comparison_warnings "$LM_MODEL/model_comparison_warnings.tsv" \
  --robustness_check_results "$LM_ROBUST/robustness_check_results.tsv" \
  --robustness_warnings "$LM_ROBUST/robustness_warnings.tsv" \
  --output_dir "$SUMMARY" > "$TMP_DIR/summary.out" 2>&1
assert_file "$SUMMARY/advanced_statistics_summary.tsv" "advanced statistics summary missing"
assert_file "$SUMMARY/advanced_statistics_outputs_manifest.tsv" "advanced statistics outputs manifest missing"
assert_grep 'n_model_comparison_ok' "$SUMMARY/advanced_statistics_summary.tsv" "summary missing model comparison count"

NF_OUT="$TMP_DIR/nf_results"
mkdir -p "$NF_OUT/phylo/input" "$NF_OUT/integration/input" "$NF_OUT/phenotype/contrasts"
cp "$SYN_OUT/phylo/input/hypothesis_model_table.tsv" "$NF_OUT/phylo/input/hypothesis_model_table.tsv"
cp "$SYN_OUT/integration/input/phenotype_omics_model_table.tsv" "$NF_OUT/integration/input/phenotype_omics_model_table.tsv"
cp "$SYN_OUT/phenotype/contrasts/phenotype_index_contrasts.tsv" "$NF_OUT/phenotype/contrasts/phenotype_index_contrasts.tsv"
cp "$SYN_OUT/phenotype/contrasts/component_trait_contrasts.tsv" "$NF_OUT/phenotype/contrasts/component_trait_contrasts.tsv"
if ! nextflow run "$ROOT_DIR" \
  --run_stage advanced_statistics \
  --advanced_model_config "$CONFIG" \
  --advanced_statistics_stub true \
  --outdir "$NF_OUT" > "$TMP_DIR/nf_advanced.out" 2>&1; then
  cat "$TMP_DIR/nf_advanced.out"
  echo "FAIL: Nextflow advanced_statistics stub run failed" >&2
  exit 1
fi
assert_file "$NF_OUT/advanced_statistics/input/advanced_model_manifest.tsv" "Nextflow advanced manifest missing"
assert_file "$NF_OUT/advanced_statistics/models/model_comparison_warnings.tsv" "Nextflow model warnings missing"
assert_file "$NF_OUT/advanced_statistics/robustness/robustness_warnings.tsv" "Nextflow robustness warnings missing"
assert_file "$NF_OUT/advanced_statistics/summary/advanced_statistics_summary.tsv" "Nextflow advanced summary missing"

if rg 'advanced_statistics' "$ROOT_DIR/workflows/all.nf" >/dev/null 2>&1; then
  echo "FAIL: advanced_statistics should not be included in workflows/all.nf" >&2
  exit 1
fi

NEW_CORE_FILES="
$ROOT_DIR/main.nf
$ROOT_DIR/nextflow.config
$ROOT_DIR/workflows/advanced_statistics.nf
$ROOT_DIR/subworkflows/model_comparison.nf
$ROOT_DIR/subworkflows/multivariate_models.nf
$ROOT_DIR/subworkflows/robustness_checks.nf
$ROOT_DIR/bin/prepare_advanced_model_inputs.py
$ROOT_DIR/bin/run_model_comparison.R
$ROOT_DIR/bin/run_robustness_checks.R
$ROOT_DIR/bin/summarize_advanced_statistics.py
"
if rg 'DDR|RoR|DNA damage|immune_response|metabolic_response|stress_tolerance' $NEW_CORE_FILES >/dev/null 2>&1; then
  rg 'DDR|RoR|DNA damage|immune_response|metabolic_response|stress_tolerance' $NEW_CORE_FILES
  echo "FAIL: profile-specific biology found in advanced statistics core files" >&2
  exit 1
fi
if rg '/Users/|/home/|/var/folders/' $NEW_CORE_FILES >/dev/null 2>&1; then
  rg '/Users/|/home/|/var/folders/' $NEW_CORE_FILES
  echo "FAIL: local absolute path found in advanced statistics core files" >&2
  exit 1
fi

if [ "${CAME_ADVANCED_SKIP_REGRESSION:-false}" != "true" ]; then
  bash "$ROOT_DIR/tests/test_metadata_validation.sh"
  bash "$ROOT_DIR/tests/test_study_profile_validation.sh"
fi

echo "advanced statistics tests passed"
