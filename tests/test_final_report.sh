#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
BAD_ABS="$ROOT_DIR/bin/final_report_bad_path_tmp.py"
BAD_TERM="$ROOT_DIR/bin/final_report_bad_term_tmp.py"
trap 'rm -rf "$TMP_DIR"; rm -f "$BAD_ABS" "$BAD_TERM"' EXIT INT TERM

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

assert_not_grep() {
  pattern="$1"
  file="$2"
  message="$3"
  if grep -q "$pattern" "$file"; then
    cat "$file"
    echo "FAIL: $message" >&2
    exit 1
  fi
}

assert_header_contains() {
  file="$1"
  field="$2"
  message="$3"
  head -n 1 "$file" | tr '\t' '\n' | grep -qx "$field" || {
    cat "$file"
    echo "FAIL: $message" >&2
    exit 1
  }
}

RESULTS="$TMP_DIR/results"
mkdir -p \
  "$RESULTS/validation" \
  "$RESULTS/phenotype/qc" \
  "$RESULTS/phenotype/index" \
  "$RESULTS/phenotype/contrasts" \
  "$RESULTS/phylo/input" \
  "$RESULTS/phylo/models" \
  "$RESULTS/hypotheses" \
  "$RESULTS/omics/summary" \
  "$RESULTS/rnaseq/summary" \
  "$RESULTS/atacseq/summary" \
  "$RESULTS/differential_omics/summary" \
  "$RESULTS/orthology/summary" \
  "$RESULTS/gra/summary" \
  "$RESULTS/gra/tables" \
  "$RESULTS/integration/summary" \
  "$RESULTS/candidates/summary" \
  "$RESULTS/candidates/ranked" \
  "$RESULTS/interpretation/summary" \
  "$RESULTS/interpretation/enrichment"

cat > "$RESULTS/validation/metadata_validation_report.tsv" <<'EOF'
severity	rule_id	source	field	row	message	suggestion
INFO		validation			ok	n/a
EOF
cat > "$RESULTS/validation/study_profile_validation_report.tsv" <<'EOF'
severity	rule_id	source	field	row	message	suggestion
INFO		study_profile			ok	n/a
EOF
cat > "$RESULTS/phenotype/qc/normalization_summary.tsv" <<'EOF'
metric	value	source
n_rows	4	phenotype
EOF
cat > "$RESULTS/phenotype/qc/phenotype_qc_metrics.tsv" <<'EOF'
severity	metric	value	message
INFO	n_samples	4	ok
EOF
cat > "$RESULTS/phenotype/index/phenotype_index_by_group.tsv" <<'EOF'
profile_id	phenotype_index_name	species	condition	timepoint	value	status
generic_response	generic_index	Species_a	response	t1	1.0	OK
EOF
cat > "$RESULTS/phenotype/contrasts/phenotype_index_contrasts.tsv" <<'EOF'
contrast_name	species	difference	status
baseline_vs_response	Species_a	1.0	OK
EOF
cat > "$RESULTS/phylo/input/phenotype_model_table.tsv" <<'EOF'
species	phenotype_index_response
Species_a	1.0
EOF
cat > "$RESULTS/phylo/models/model_results.tsv" <<'EOF'
model_id	model_type	response	status
m1	lm	phenotype_index_response	OK
EOF
cat > "$RESULTS/hypotheses/hypothesis_model_results.tsv" <<'EOF'
hypothesis_name	hypothesis_type	status
generic_hypothesis	direct_model	OK
EOF
cat > "$RESULTS/hypotheses/hypothesis_test_summary.tsv" <<'EOF'
metric	value	source
n_hypotheses	1	hypotheses
EOF
cat > "$RESULTS/omics/summary/omics_run_summary.tsv" <<'EOF'
metric	value	source
n_samples	4	omics
EOF
cat > "$RESULTS/omics/summary/omics_outputs_manifest.tsv" <<'EOF'
output_name	path	status	n_rows
rnaseq_summary	rnaseq/summary/rnaseq_summary.tsv	present	1
EOF
cat > "$RESULTS/rnaseq/summary/rnaseq_summary.tsv" <<'EOF'
metric	value	source
n_gene_count_rows	2	rnaseq
EOF
cat > "$RESULTS/atacseq/summary/atacseq_summary.tsv" <<'EOF'
metric	value	source
n_re_count_rows	2	atacseq
EOF
cat > "$RESULTS/differential_omics/summary/differential_omics_summary.tsv" <<'EOF'
metric	value	source
n_differential_results	2	differential
EOF
cat > "$RESULTS/orthology/summary/orthology_projection_summary.tsv" <<'EOF'
metric	value	source
n_mapped_features	2	orthology
EOF
cat > "$RESULTS/orthology/summary/orthology_outputs_manifest.tsv" <<'EOF'
output_name	path	status	n_rows
feature_to_orthogroup_map	orthology/feature_to_orthogroup_map.tsv	present	1
EOF
cat > "$RESULTS/orthology/feature_to_orthogroup_map.tsv" <<'EOF'
feature_type	species	feature_id	orthogroup_id	chrom	start	end
gene	Species_a	gene_1	OG_GENE_0001			
EOF
cat > "$RESULTS/gra/summary/gra_analysis_summary.tsv" <<'EOF'
metric	value	source
n_gras	1	gra
EOF
cat > "$RESULTS/gra/summary/gra_outputs_manifest.tsv" <<'EOF'
output_name	path	status	n_rows
gene_regulatory_architectures	gra/tables/gene_regulatory_architectures.tsv	present	1
EOF
cat > "$RESULTS/gra/tables/gene_regulatory_architectures.tsv" <<'EOF'
gra_id	gene_orthogroup_id	n_res
GRA_OG_GENE_0001	OG_GENE_0001	1
EOF
cat > "$RESULTS/gra/tables/gra_re_membership.tsv" <<'EOF'
gra_id	gene_orthogroup_id	re_orthogroup_id
GRA_OG_GENE_0001	OG_GENE_0001	OG_RE_0001
EOF
cat > "$RESULTS/integration/summary/phenotype_omics_integration_summary.tsv" <<'EOF'
metric	value	source
n_associations	3	integration
EOF
cat > "$RESULTS/integration/summary/phenotype_omics_outputs_manifest.tsv" <<'EOF'
output_name	path	status	n_rows
phenotype_expression_associations	integration/associations/phenotype_expression_associations.tsv	present	1
EOF
cat > "$RESULTS/candidates/summary/candidate_prioritization_summary.tsv" <<'EOF'
metric	value	source
n_candidates_all	12	candidates
EOF
cat > "$RESULTS/candidates/summary/candidate_outputs_manifest.tsv" <<'EOF'
output_name	path	status	n_rows
candidate_all_ranked	candidates/ranked/candidate_all_ranked.tsv	present	12
EOF
cat > "$RESULTS/interpretation/summary/functional_interpretation_summary.tsv" <<'EOF'
metric	value	source
n_enrichment_results	12	interpretation
EOF
cat > "$RESULTS/interpretation/summary/functional_interpretation_outputs_manifest.tsv" <<'EOF'
output_name	path	status	n_rows
gene_set_enrichment	interpretation/enrichment/gene_set_enrichment.tsv	present	12
EOF

{
  printf 'rank\tcandidate_id\tcandidate_type\ttotal_score\tn_evidence_types\ttop_evidence_type\ttop_contrast\tcombined_direction\n'
  i=1
  while [ "$i" -le 12 ]; do
    id=$(printf 'CAND_%03d' "$i")
    score=$((100 - i))
    printf '%s\t%s\tgene\t%s\t2\tgeneric_evidence\tbaseline_vs_response\tup\n' "$i" "$id" "$score"
    i=$((i + 1))
  done
} > "$RESULTS/candidates/ranked/candidate_all_ranked.tsv"

{
  printf 'candidate_set\tgene_set_id\tgene_set_name\tn_overlap\tp_value\tpadj\tstatus\n'
  i=1
  while [ "$i" -le 12 ]; do
    id=$(printf 'GS_%03d' "$i")
    printf 'genes\t%s\tGeneric set %s\t2\t0.%03d\t0.%03d\tOK\n' "$id" "$i" "$i" "$i"
    i=$((i + 1))
  done
} > "$RESULTS/interpretation/enrichment/gene_set_enrichment.tsv"

python3 "$ROOT_DIR/bin/collect_run_outputs.py" \
  --results_dir "$RESULTS" \
  --output_dir "$RESULTS/final/manifest" > "$TMP_DIR/collect.out" 2>&1
test -s "$RESULTS/final/manifest/came_outputs_manifest.tsv"
test -s "$RESULTS/final/manifest/came_stage_completion_summary.tsv"
test -s "$RESULTS/final/manifest/came_missing_outputs.tsv"
assert_header_contains "$RESULTS/final/manifest/came_outputs_manifest.tsv" "modified_time_utc" "manifest missing timestamp"
assert_not_grep '^stage_.*	final/' "$RESULTS/final/manifest/came_outputs_manifest.tsv" "manifest should exclude final outputs"
assert_grep 'differential_omics/summary/differential_outputs_manifest.tsv' "$RESULTS/final/manifest/came_missing_outputs.tsv" "missing optional output warning absent"

python3 "$ROOT_DIR/bin/run_release_checks.py" \
  --project_dir "$ROOT_DIR" \
  --results_dir "$RESULTS" \
  --manifest "$RESULTS/final/manifest/came_outputs_manifest.tsv" \
  --output_dir "$RESULTS/final/release_checks" > "$TMP_DIR/release.out" 2>&1
test -s "$RESULTS/final/release_checks/came_release_checks.tsv"
test -s "$RESULTS/final/release_checks/came_release_summary.tsv"
assert_grep '	PASS	' "$RESULTS/final/release_checks/came_release_checks.tsv" "release checks did not emit PASS"
assert_not_grep 'profile_term_scan	ERROR' "$RESULTS/final/release_checks/came_release_checks.tsv" "allowed docs/tests/profiles examples should not trigger core term scan"

python3 "$ROOT_DIR/bin/run_release_checks.py" \
  --project_dir "$ROOT_DIR" \
  --results_dir "$TMP_DIR/missing_results" \
  --manifest "$RESULTS/final/manifest/came_outputs_manifest.tsv" \
  --output_dir "$TMP_DIR/warning_checks" > "$TMP_DIR/warning_release.out" 2>&1
assert_grep '	WARNING	' "$TMP_DIR/warning_checks/came_release_checks.tsv" "release checks did not emit WARNING"

printf 'BAD_PATH = "%s"\n' '/Users/example/local.tsv' > "$BAD_ABS"
printf 'BAD_TERM = "%s"\n' 'DDR' > "$BAD_TERM"
python3 "$ROOT_DIR/bin/run_release_checks.py" \
  --project_dir "$ROOT_DIR" \
  --results_dir "$RESULTS" \
  --manifest "$RESULTS/final/manifest/came_outputs_manifest.tsv" \
  --output_dir "$TMP_DIR/bad_checks" > "$TMP_DIR/bad_release.out" 2>&1
assert_grep 'absolute_path_scan	ERROR' "$TMP_DIR/bad_checks/came_release_checks.tsv" "absolute path detector did not flag temp bad file"
assert_grep 'profile_term_scan	ERROR' "$TMP_DIR/bad_checks/came_release_checks.tsv" "profile term detector did not flag temp bad file"
rm -f "$BAD_ABS" "$BAD_TERM"

python3 "$ROOT_DIR/bin/render_final_report.py" \
  --study_profile "$ROOT_DIR/profiles/generic/study_profile.yaml" \
  --results_dir "$RESULTS" \
  --manifest "$RESULTS/final/manifest/came_outputs_manifest.tsv" \
  --stage_summary "$RESULTS/final/manifest/came_stage_completion_summary.tsv" \
  --missing_outputs "$RESULTS/final/manifest/came_missing_outputs.tsv" \
  --release_checks "$RESULTS/final/release_checks/came_release_checks.tsv" \
  --release_summary "$RESULTS/final/release_checks/came_release_summary.tsv" \
  --output_dir "$RESULTS/final/report" > "$TMP_DIR/render.out" 2>&1
test -s "$RESULTS/final/report/came_final_report.html"
test -s "$RESULTS/final/report/came_final_report.md"
test -s "$RESULTS/final/report/came_report.css"
assert_grep 'href="came_report.css"' "$RESULTS/final/report/came_final_report.html" "HTML report should link external CSS"
assert_not_grep 'href="/' "$RESULTS/final/report/came_final_report.html" "HTML report should not contain absolute hrefs"
assert_grep 'CAND_010' "$RESULTS/final/report/came_final_report.html" "top candidate preview missing tenth row"
assert_not_grep 'CAND_011' "$RESULTS/final/report/came_final_report.html" "candidate preview should be capped"
assert_grep 'GS_010' "$RESULTS/final/report/came_final_report.html" "top enrichment preview missing tenth row"
assert_not_grep 'GS_011' "$RESULTS/final/report/came_final_report.html" "enrichment preview should be capped"

NF_OUT="$TMP_DIR/nf_results"
mkdir -p "$NF_OUT"
cp -R "$RESULTS/." "$NF_OUT/"
rm -rf "$NF_OUT/final"
if ! nextflow run "$ROOT_DIR" \
  --run_stage final_report \
  --study_profile "$ROOT_DIR/profiles/generic/study_profile.yaml" \
  --outdir "$NF_OUT" > "$TMP_DIR/nf_final_report.out" 2>&1; then
  cat "$TMP_DIR/nf_final_report.out"
  echo "FAIL: Nextflow final_report failed" >&2
  exit 1
fi
test -s "$NF_OUT/final/manifest/came_outputs_manifest.tsv"
test -s "$NF_OUT/final/provenance/came_run_provenance.tsv"
test -s "$NF_OUT/final/provenance/came_parameters_snapshot.tsv"
test -s "$NF_OUT/final/assets/report_asset_manifest.tsv"
test -s "$NF_OUT/final/assets/stage_completion_summary.tsv"
test -s "$NF_OUT/final/assets/top_candidates.tsv"
test -s "$NF_OUT/final/assets/top_enriched_gene_sets.tsv"
test -s "$NF_OUT/final/assets/warning_summary.tsv"
test -s "$NF_OUT/final/release_checks/came_release_checks.tsv"
test -s "$NF_OUT/final/report/came_final_report.html"
test -s "$NF_OUT/final/report/came_final_report.md"
test -s "$NF_OUT/final/report/came_report.css"
assert_grep 'Run Provenance' "$NF_OUT/final/report/came_final_report.html" "Nextflow report missing provenance section"

REL_OUT="$TMP_DIR/rel_results"
mkdir -p "$REL_OUT"
cp -R "$RESULTS/." "$REL_OUT/"
rm -rf "$REL_OUT/final"
(
  cd "$TMP_DIR"
  nextflow run "$ROOT_DIR" \
    --run_stage final_report \
    --study_profile "$ROOT_DIR/profiles/generic/study_profile.yaml" \
    --outdir rel_results > "$TMP_DIR/nf_final_report_relative.out" 2>&1
) || {
  cat "$TMP_DIR/nf_final_report_relative.out"
  echo "FAIL: Nextflow final_report failed with relative --outdir" >&2
  exit 1
}
test -s "$REL_OUT/final/manifest/came_stage_completion_summary.tsv"
awk 'BEGIN{FS="\t"} NR==1{for(i=1;i<=NF;i++) h[$i]=i; next} $h["stage"]=="stage_01_metadata_validation" && $h["present_count"]+0>0{ok=1} END{exit ok?0:1}' "$REL_OUT/final/manifest/came_stage_completion_summary.tsv" || {
  cat "$REL_OUT/final/manifest/came_stage_completion_summary.tsv"
  echo "FAIL: relative --outdir final_report did not scan existing results" >&2
  exit 1
}

echo "final report tests passed"
