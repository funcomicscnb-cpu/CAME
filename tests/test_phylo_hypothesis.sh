#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PHENO="$ROOT_DIR/assets/example_samplesheets/phenotype_samplesheet.csv"
TRAITS="$ROOT_DIR/assets/example_samplesheets/species_traits.tsv"
PHYLO="$ROOT_DIR/assets/example_samplesheets/phylogeny_manifest.tsv"

have_phylo_packages() {
  Rscript -e 'ok <- requireNamespace("ape", quietly=TRUE) && requireNamespace("nlme", quietly=TRUE); quit(status=ifelse(ok, 0, 1))' >/dev/null 2>&1
}

run_stage3() {
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
    --group_output "$out/index_by_group.tsv" > "$out/index.out" 2>&1
  python3 "$ROOT_DIR/bin/phenotype_contrasts.py" \
    --phenotype_table "$out/normalized.tsv" \
    --study_profile "$profile" \
    --index_by_group "$out/index_by_group.tsv" \
    --index_output "$out/index_contrasts.tsv" \
    --component_output "$out/component_contrasts.tsv" > "$out/contrasts.out" 2>&1
}

prepare_phylo() {
  profile="$1"
  phylogeny_manifest="$2"
  stage3="$3"
  out="$4"
  mkdir -p "$out"
  python3 "$ROOT_DIR/bin/prepare_phylo_inputs.py" \
    --species_traits "$TRAITS" \
    --phylogeny_manifest "$phylogeny_manifest" \
    --study_profile "$profile" \
    --phenotype_index_by_group "$stage3/index_by_group.tsv" \
    --phenotype_index_contrasts "$stage3/index_contrasts.tsv" \
    --component_trait_contrasts "$stage3/component_contrasts.tsv" \
    --species_traits_wide "$out/species_traits_wide.tsv" \
    --phenotype_model_table "$out/phenotype_model_table.tsv" \
    --hypothesis_model_table "$out/hypothesis_model_table.tsv" > "$out/prepare.out" 2>&1
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

GENERIC_PROFILE="$ROOT_DIR/profiles/generic/study_profile.yaml"
GENERIC_STAGE3="$TMP_DIR/generic_stage3"
GENERIC_INPUT="$TMP_DIR/generic_input"
GENERIC_HYP="$TMP_DIR/generic_hyp"
run_stage3 "$GENERIC_PROFILE" "$GENERIC_STAGE3"
prepare_phylo "$GENERIC_PROFILE" "$PHYLO" "$GENERIC_STAGE3" "$GENERIC_INPUT"
Rscript "$ROOT_DIR/bin/run_hypothesis_tests.R" \
  --input "$GENERIC_INPUT/hypothesis_model_table.tsv" \
  --study_profile "$GENERIC_PROFILE" \
  --model_types lm \
  --output_dir "$GENERIC_HYP" > "$GENERIC_HYP.out" 2>&1
assert_grep 'external_trait_association' "$GENERIC_HYP/hypothesis_test_summary.tsv" "direct_model result missing"
assert_grep 'residual_stage2' "$GENERIC_HYP/hypothesis_test_summary.tsv" "residual second-stage result missing"
assert_grep 'residual_stage1' "$GENERIC_HYP/hypothesis_residuals.tsv" "residual rows missing"

DDR_PROFILE="$ROOT_DIR/profiles/ddr_ror/study_profile.yaml"
DDR_STAGE3="$TMP_DIR/ddr_stage3"
DDR_INPUT="$TMP_DIR/ddr_input"
DDR_HYP_LM="$TMP_DIR/ddr_hyp_lm"
run_stage3 "$DDR_PROFILE" "$DDR_STAGE3"
prepare_phylo "$DDR_PROFILE" "$PHYLO" "$DDR_STAGE3" "$DDR_INPUT"
Rscript "$ROOT_DIR/bin/run_hypothesis_tests.R" \
  --input "$DDR_INPUT/hypothesis_model_table.tsv" \
  --study_profile "$DDR_PROFILE" \
  --model_types lm \
  --output_dir "$DDR_HYP_LM" > "$DDR_HYP_LM.out" 2>&1
assert_grep 'viability_longevity_association' "$DDR_HYP_LM/hypothesis_test_summary.tsv" "DDR/RoR lm hypothesis result missing"
assert_grep 'cancer_body_mass_residual_viability' "$DDR_HYP_LM/hypothesis_residuals.tsv" "DDR/RoR residual output missing"

Rscript "$ROOT_DIR/bin/run_phylo_model.R" \
  --input "$GENERIC_INPUT/hypothesis_model_table.tsv" \
  --response phenotype_index_response \
  --predictors external_trait_alpha \
  --model_types lm \
  --output_dir "$TMP_DIR/lm_model" > "$TMP_DIR/lm_model.out" 2>&1
assert_grep 'phenotype_index_response' "$TMP_DIR/lm_model/model_results.tsv" "lm-only model result missing"

BAD_PROFILE="$TMP_DIR/missing_trait_profile.yaml"
sed 's/external_trait_alpha/missing_trait/g' "$GENERIC_PROFILE" > "$BAD_PROFILE"
if Rscript "$ROOT_DIR/bin/run_hypothesis_tests.R" \
  --input "$GENERIC_INPUT/hypothesis_model_table.tsv" \
  --study_profile "$BAD_PROFILE" \
  --model_types lm \
  --output_dir "$TMP_DIR/missing_trait_hyp" > "$TMP_DIR/missing_trait.out" 2>&1; then
  cat "$TMP_DIR/missing_trait.out"
  echo "FAIL: missing trait variable expected failure" >&2
  exit 1
fi
assert_grep 'Missing required model variable' "$TMP_DIR/missing_trait_hyp/hypothesis_warnings.tsv" "missing trait error message absent"

if have_phylo_packages; then
  DDR_HYP_PHYLO="$TMP_DIR/ddr_hyp_phylo"
  Rscript "$ROOT_DIR/bin/run_hypothesis_tests.R" \
    --input "$DDR_INPUT/hypothesis_model_table.tsv" \
    --study_profile "$DDR_PROFILE" \
    --output_dir "$DDR_HYP_PHYLO" > "$DDR_HYP_PHYLO.out" 2>&1
  assert_grep 'pgls_brownian' "$DDR_HYP_PHYLO/hypothesis_test_summary.tsv" "PGLS hypothesis result missing"
  assert_grep 'fewer than 6 species' "$DDR_HYP_PHYLO/hypothesis_warnings.tsv" "PGLS small-n hypothesis warning missing"

  TREE_DIR="$TMP_DIR/trees"
  mkdir -p "$TREE_DIR"
  cat > "$TREE_DIR/three_species.nwk" <<'EOF'
((Mus_musculus:0.20,Gallus_gallus:0.30):0.40,Danio_rerio:0.50);
EOF
  cat > "$TREE_DIR/two_species.nwk" <<'EOF'
(Mus_musculus:0.20,Danio_rerio:0.50);
EOF
  MISSING_PHYLO="$TMP_DIR/missing_tree_manifest.tsv"
  awk -F'\t' 'BEGIN{OFS="\t"} NR==1{print; next} {$2="missing_tree.nwk"; print}' "$PHYLO" > "$MISSING_PHYLO"
  prepare_phylo "$GENERIC_PROFILE" "$MISSING_PHYLO" "$GENERIC_STAGE3" "$TMP_DIR/missing_tree_input"
  if Rscript "$ROOT_DIR/bin/run_phylo_model.R" \
    --input "$TMP_DIR/missing_tree_input/hypothesis_model_table.tsv" \
    --response phenotype_index_response \
    --predictors external_trait_alpha \
    --model_types pgls_brownian \
    --output_dir "$TMP_DIR/missing_tree_model" > "$TMP_DIR/missing_tree.out" 2>&1; then
    cat "$TMP_DIR/missing_tree.out"
    echo "FAIL: missing tree expected failure" >&2
    exit 1
  fi
  assert_grep 'Phylogeny file does not exist' "$TMP_DIR/missing_tree_model/model_warnings.tsv" "missing tree diagnostic absent"

  THREE_PHYLO="$TMP_DIR/three_species_manifest.tsv"
  awk -F'\t' -v tree="$TREE_DIR/three_species.nwk" 'BEGIN{OFS="\t"} NR==1{print; next} {$2=tree; print}' "$PHYLO" > "$THREE_PHYLO"
  prepare_phylo "$GENERIC_PROFILE" "$THREE_PHYLO" "$GENERIC_STAGE3" "$TMP_DIR/three_species_input"
  Rscript "$ROOT_DIR/bin/run_phylo_model.R" \
    --input "$TMP_DIR/three_species_input/hypothesis_model_table.tsv" \
    --response phenotype_index_response \
    --predictors external_trait_alpha \
    --model_types pgls_brownian \
    --output_dir "$TMP_DIR/three_species_model" > "$TMP_DIR/three_species.out" 2>&1
  assert_grep 'Dropped species absent from tree' "$TMP_DIR/three_species_model/model_warnings.tsv" "tree species-drop warning absent"

  TWO_PHYLO="$TMP_DIR/two_species_manifest.tsv"
  awk -F'\t' -v tree="$TREE_DIR/two_species.nwk" 'BEGIN{OFS="\t"} NR==1{print; next} {$2=tree; print}' "$PHYLO" > "$TWO_PHYLO"
  prepare_phylo "$GENERIC_PROFILE" "$TWO_PHYLO" "$GENERIC_STAGE3" "$TMP_DIR/two_species_input"
  if Rscript "$ROOT_DIR/bin/run_phylo_model.R" \
    --input "$TMP_DIR/two_species_input/hypothesis_model_table.tsv" \
    --response phenotype_index_response \
    --predictors external_trait_alpha \
    --model_types pgls_brownian \
    --output_dir "$TMP_DIR/two_species_model" > "$TMP_DIR/two_species.out" 2>&1; then
    cat "$TMP_DIR/two_species.out"
    echo "FAIL: fewer than 3 matched species expected failure" >&2
    exit 1
  fi
  assert_grep 'Fewer than 3 species remain' "$TMP_DIR/two_species_model/model_warnings.tsv" "fewer-than-3 diagnostic absent"

  MALFORMED_NWK="$TREE_DIR/malformed.nwk"
  printf '((A,B);\n' > "$MALFORMED_NWK"
  MALFORMED_PHYLO="$TMP_DIR/malformed_manifest.tsv"
  awk -F'\t' -v tree="$MALFORMED_NWK" 'BEGIN{OFS="\t"} NR==1{print; next} {$2=tree; print}' "$PHYLO" > "$MALFORMED_PHYLO"
  prepare_phylo "$GENERIC_PROFILE" "$MALFORMED_PHYLO" "$GENERIC_STAGE3" "$TMP_DIR/malformed_input"
  if Rscript "$ROOT_DIR/bin/run_phylo_model.R" \
    --input "$TMP_DIR/malformed_input/hypothesis_model_table.tsv" \
    --response phenotype_index_response \
    --predictors external_trait_alpha \
    --model_types pgls_brownian \
    --output_dir "$TMP_DIR/malformed_model" > "$TMP_DIR/malformed.out" 2>&1; then
    cat "$TMP_DIR/malformed.out"
    echo "FAIL: malformed Newick expected failure" >&2
    exit 1
  fi
  assert_grep 'ERROR' "$TMP_DIR/malformed_model/model_warnings.tsv" "malformed Newick error absent"

else
  if Rscript "$ROOT_DIR/bin/run_phylo_model.R" \
    --input "$GENERIC_INPUT/hypothesis_model_table.tsv" \
    --response phenotype_index_response \
    --predictors external_trait_alpha \
    --model_types pgls_brownian \
    --output_dir "$TMP_DIR/missing_dependency_model" > "$TMP_DIR/missing_dependency.out" 2>&1; then
    cat "$TMP_DIR/missing_dependency.out"
    echo "FAIL: missing phylogenetic dependency expected failure" >&2
    exit 1
  fi
  assert_grep 'Missing required R package' "$TMP_DIR/missing_dependency_model/model_warnings.tsv" "missing dependency diagnostic absent"
fi

bash "$ROOT_DIR/tests/test_metadata_validation.sh"
bash "$ROOT_DIR/tests/test_study_profile_validation.sh"
bash "$ROOT_DIR/tests/test_phenotype_processing.sh"

echo "phylogenetic hypothesis tests passed"
