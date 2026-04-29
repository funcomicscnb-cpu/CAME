#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

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

STAGES="validation phenotype_response phylo_hypothesis bulk_omics differential_omics orthology_projection gra_analysis phenotype_omics_integration candidate_prioritization functional_interpretation final_report"

EMPTY="$TMP_DIR/empty"
mkdir -p "$EMPTY"
python3 "$ROOT_DIR/bin/check_stage_outputs.py" \
  --stage validation \
  --outdir "$EMPTY" \
  --output "$TMP_DIR/empty_validation_status.tsv" > "$TMP_DIR/empty_check.out" 2>&1
assert_grep '	MISSING	' "$TMP_DIR/empty_validation_status.tsv" "empty outdir should report MISSING"

SYN="$TMP_DIR/synthetic"
mkdir -p "$SYN/validation" "$SYN/all/stage_status"
cat > "$SYN/validation/metadata_validation_report.tsv" <<'EOF'
severity	source	field	row	message
INFO	validation			ok
EOF
cat > "$SYN/validation/study_profile_validation_report.tsv" <<'EOF'
severity	source	field	row	message
INFO	study_profile			ok
EOF
python3 "$ROOT_DIR/bin/check_stage_outputs.py" \
  --stage validation \
  --outdir "$SYN" \
  --output "$SYN/all/stage_status/validation_status.tsv" > "$TMP_DIR/complete_check.out" 2>&1
assert_grep '	COMPLETE	' "$SYN/all/stage_status/validation_status.tsv" "synthetic validation outputs should report COMPLETE"

for stage in $STAGES; do
  if [ "$stage" = "validation" ]; then
    continue
  fi
  python3 "$ROOT_DIR/bin/check_stage_outputs.py" \
    --stage "$stage" \
    --outdir "$SYN" \
    --output "$SYN/all/stage_status/${stage}_status.tsv" > "$TMP_DIR/${stage}_check.out" 2>&1
done
python3 "$ROOT_DIR/bin/summarize_all_run.py" \
  --outdir "$SYN" \
  --stage_status_dir "$SYN/all/stage_status" \
  --output_dir "$SYN/all/summary" > "$TMP_DIR/summary.out" 2>&1
test -s "$SYN/all/summary/came_all_run_summary.tsv"
test -s "$SYN/all/summary/came_all_outputs_manifest.tsv"
assert_grep 'validation	stage_status	COMPLETE' "$SYN/all/summary/came_all_run_summary.tsv" "summary missing validation COMPLETE status"

NF_OUT="$TMP_DIR/nf_results"
if ! nextflow run "$ROOT_DIR" \
  --run_stage all \
  --study_profile "$ROOT_DIR/profiles/generic/study_profile.yaml" \
  --phenotype_samplesheet "$ROOT_DIR/assets/example_samplesheets/phenotype_samplesheet.csv" \
  --omics_samplesheet "$ROOT_DIR/assets/example_samplesheets/omics_samplesheet.csv" \
  --species_traits "$ROOT_DIR/assets/example_samplesheets/species_traits.tsv" \
  --reference_manifest "$ROOT_DIR/assets/example_samplesheets/reference_manifest.tsv" \
  --phylogeny_manifest "$ROOT_DIR/assets/example_samplesheets/phylogeny_manifest.tsv" \
  --study_design "$ROOT_DIR/assets/example_samplesheets/study_design.yaml" \
  --orthologous_genes "$ROOT_DIR/assets/example_samplesheets/orthologous_genes.tsv" \
  --orthologous_res "$ROOT_DIR/assets/example_samplesheets/orthologous_res.tsv" \
  --re_to_gene_links "$ROOT_DIR/assets/example_samplesheets/re_to_gene_links.tsv" \
  --gene_annotations "$ROOT_DIR/assets/example_samplesheets/gene_annotations.tsv" \
  --gene_sets "$ROOT_DIR/assets/example_samplesheets/gene_sets.tsv" \
  --candidate_scoring_config "$ROOT_DIR/assets/example_samplesheets/candidate_scoring_config.tsv" \
  --omics_stub true \
  --omics_types rnaseq,atacseq \
  --outdir "$NF_OUT" > "$TMP_DIR/nf_all.out" 2>&1; then
  cat "$TMP_DIR/nf_all.out"
  echo "FAIL: Nextflow all run failed" >&2
  exit 1
fi
assert_grep '\[CAME WARNING\].*reference_prepare' "$TMP_DIR/nf_all.out" "all-run excluded-stage warning missing"
assert_grep 'wgs_variants' "$TMP_DIR/nf_all.out" "all-run warning missing wgs_variants"
assert_grep 'advanced_statistics' "$TMP_DIR/nf_all.out" "all-run warning missing advanced_statistics"
test -s "$NF_OUT/final/report/came_final_report.html"
test -s "$NF_OUT/final/report/came_final_report.md"
test -s "$NF_OUT/final/report/came_report.css"
test -s "$NF_OUT/final/provenance/came_run_provenance.tsv"
test -s "$NF_OUT/final/provenance/came_parameters_snapshot.tsv"
test -s "$NF_OUT/final/assets/report_asset_manifest.tsv"
test -s "$NF_OUT/final/assets/stage_completion_summary.tsv"
test -s "$NF_OUT/all/summary/came_all_run_summary.tsv"
test -s "$NF_OUT/all/summary/came_all_outputs_manifest.tsv"
test -s "$NF_OUT/all/summary/came_all_run_status.txt"
assert_grep 'all_run_status	COMPLETE' "$NF_OUT/all/summary/came_all_run_status.txt" "all-run status did not report COMPLETE"

if rg 'DDR|RoR' \
  "$ROOT_DIR/bin/prepare_all_stub_omics_contrasts.py" \
  "$ROOT_DIR/bin/check_stage_outputs.py" \
  "$ROOT_DIR/bin/summarize_all_run.py" \
  "$ROOT_DIR/workflows/all.nf" \
  "$ROOT_DIR/subworkflows/stage_orchestration.nf" >/dev/null 2>&1; then
  echo "FAIL: Stage 13 core files contain profile-specific terms" >&2
  exit 1
fi

if [ "${CAME_STAGE13_SKIP_REGRESSION:-false}" != "true" ]; then
  for test_script in \
    test_final_report.sh \
    test_functional_interpretation.sh \
    test_candidate_prioritization.sh \
    test_phenotype_omics_integration.sh \
    test_gra_analysis.sh \
    test_orthology_projection.sh \
    test_differential_omics.sh \
    test_bulk_omics.sh \
    test_phylo_hypothesis.sh \
    test_phenotype_processing.sh \
    test_study_profile_validation.sh \
    test_metadata_validation.sh
  do
    bash "$ROOT_DIR/tests/$test_script"
  done
fi

echo "end-to-end orchestration tests passed"
