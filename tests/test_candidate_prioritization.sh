#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PROFILE="$ROOT_DIR/profiles/generic/study_profile.yaml"
DEFAULT_CONFIG="$ROOT_DIR/assets/example_samplesheets/candidate_scoring_config.tsv"

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

assert_nonempty_rows() {
  file="$1"
  message="$2"
  awk 'NR>1{found=1} END{exit found?0:1}' "$file" || {
    cat "$file"
    echo "FAIL: $message" >&2
    exit 1
  }
}

FIX="$TMP_DIR/fixtures"
mkdir -p "$FIX"

cat > "$FIX/phenotype_index_contrasts.tsv" <<'EOF'
contrast_name	contrast_type	species	group_id	baseline_label	response_label	difference	fold_change	log2_fold_change	n_baseline	n_response	status	message
baseline_vs_response	baseline_vs_response	Mus_musculus	Mus_musculus|baseline|t0_vs_response|t1	baseline|t0	response|t1	1.0	2.0	1.0	2	2	OK	
baseline_vs_response	baseline_vs_response	Danio_rerio	Danio_rerio|baseline|t0_vs_response|t1	baseline|t0	response|t1	0.5	1.5	0.58	2	2	OK	
EOF

cat > "$FIX/differential_expression_orthogroups.tsv" <<'EOF'
orthogroup_id	feature_type	mapping_status	n_source_features	n_species	is_ambiguous	ambiguity_reason	species_members	source_feature_ids	omics_type	contrast_name	contrast_type	species	baseline_label	response_label	n_baseline	n_response	base_mean	baseline_mean	response_mean	log2_fold_change	statistic	p_value	padj	method	status	message
OG_GENE_0001	gene	mapped	1	2	false		Mus_musculus,Danio_rerio	gene_0001	rnaseq	baseline_vs_response	baseline_vs_response	Mus_musculus	baseline|t0	response|t1	2	2	100	50	200	2.0	5	0.001	0.01	fallback	OK	
OG_GENE_0001	gene	mapped	1	2	false		Mus_musculus,Danio_rerio	gene_0001	rnaseq	baseline_vs_response	baseline_vs_response	Mus_musculus	baseline|t0	response|t1	2	2	100	50	200	2.0	5	0.001	0.01	fallback	OK	
OG_GENE_0002	gene	mapped	1	2	false		Mus_musculus,Danio_rerio	gene_0002	rnaseq	baseline_vs_response	baseline_vs_response	Danio_rerio	baseline|t0	response|t1	2	2	100	120	80	-0.6	-2	0.2	0.4	fallback	OK	
EOF

cat > "$FIX/differential_accessibility_orthogroups.tsv" <<'EOF'
orthogroup_id	feature_type	mapping_status	n_source_features	n_species	is_ambiguous	ambiguity_reason	species_members	source_feature_ids	omics_type	contrast_name	contrast_type	species	baseline_label	response_label	n_baseline	n_response	base_mean	baseline_mean	response_mean	log2_fold_change	statistic	p_value	padj	method	status	message
OG_RE_0001	regulatory_element	mapped	1	2	false		Mus_musculus,Danio_rerio	re_0001	atacseq	baseline_vs_response	baseline_vs_response	Mus_musculus	baseline|t0	response|t1	2	2	100	80	160	1.0	3	0.02	0.08	fallback	OK	
OG_RE_0002	regulatory_element	mapped	1	2	false		Mus_musculus,Danio_rerio	re_0002	atacseq	baseline_vs_response	baseline_vs_response	Danio_rerio	baseline|t0	response|t1	2	2	100	150	75	-1.0	-3	0.03	0.03	fallback	OK	
EOF

cat > "$FIX/differential_gra_activity.tsv" <<'EOF'
gra_id	gene_orthogroup_id	contrast_name	baseline_label	response_label	log2_fold_change	statistic	p_value	padj	mean_baseline	mean_response	n_baseline	n_response	method	status	message	species
GRA_OG_GENE_0001	OG_GENE_0001	baseline_vs_response	baseline|t0	response|t1	1.4	4	0.004	0.02	5	20	2	2	fallback	OK		Mus_musculus
GRA_OG_GENE_0002	OG_GENE_0002	baseline_vs_response	baseline|t0	response|t1	-0.5	-1	0.2	0.5	20	10	2	2	fallback	OK		Danio_rerio
EOF

cat > "$FIX/gene_regulatory_architectures.tsv" <<'EOF'
gra_id	gene_orthogroup_id	feature_type	n_res	n_links	n_species	species_members	link_types	mapping_status	is_ambiguous	ambiguity_reason
GRA_OG_GENE_0001	OG_GENE_0001	gene_regulatory_architecture	1	1	2	orthogroup	promoter	mapped	false	
GRA_OG_GENE_0002	OG_GENE_0002	gene_regulatory_architecture	1	1	2	orthogroup	distal_contact	mapped	false	
EOF

cat > "$FIX/gra_re_membership.tsv" <<'EOF'
gra_id	gene_orthogroup_id	re_orthogroup_id	link_type	species_members	n_species	n_res	mapping_status	is_ambiguous	source_gene_feature_ids	source_re_feature_ids	distance_to_tss	contact_score	link_confidence	source	notes
GRA_OG_GENE_0001	OG_GENE_0001	OG_RE_0001	promoter	orthogroup	2	1	mapped	false	gene_0001	re_0001	100	0.9	0.9	test	
GRA_OG_GENE_0002	OG_GENE_0002	OG_RE_0002	distal_contact	orthogroup	2	1	mapped	false	gene_0002	re_0002	1000	0.6	0.7	test	
EOF

cat > "$FIX/feature_to_orthogroup_map.tsv" <<'EOF'
feature_type	species	feature_id	orthogroup_id	mapping_status	n_mapped_orthogroups	is_ambiguous	ambiguity_reason	gene_symbol	human_anchor_id	transcript_id	chrom	start	end	human_anchor_region	re_type	orthology_type	orthology_confidence	source	notes
gene	Mus_musculus	gene_0001	OG_GENE_0001	mapped	1	false		SynGene1	HGNC:0001	tx1						one_to_one	high	test	
regulatory_element	Mus_musculus	re_0001	OG_RE_0001	mapped	1	false					chr1	100	200	anchor	enhancer	one_to_one	high	test	
EOF

cat > "$FIX/phenotype_expression_associations.tsv" <<'EOF'
feature_layer	feature_id	contrast_name	baseline_label	response_label	phenotype_index_name	phenotype_response_id	phenotype_response_metric	feature_response_metric	model_type	n_species	estimate	std_error	statistic	p_value	aic	r_squared_or_pseudo_r2	phylogeny_id	status	warning
expression	OG_GENE_0001	baseline_vs_response	baseline|t0	response|t1	index	index	difference	log2_fold_change	lm	4	1.2	0.1	12	0.0001	1	0.9		OK	
EOF

cat > "$FIX/phenotype_accessibility_associations.tsv" <<'EOF'
feature_layer	feature_id	contrast_name	baseline_label	response_label	phenotype_index_name	phenotype_response_id	phenotype_response_metric	feature_response_metric	model_type	n_species	estimate	std_error	statistic	p_value	aic	r_squared_or_pseudo_r2	phylogeny_id	status	warning
accessibility	OG_RE_0001	baseline_vs_response	baseline|t0	response|t1	index	index	difference	log2_fold_change	lm	4	0.8	0.2	4	0.02	2	0.8		OK	
EOF

cat > "$FIX/phenotype_gra_associations.tsv" <<'EOF'
feature_layer	feature_id	contrast_name	baseline_label	response_label	phenotype_index_name	phenotype_response_id	phenotype_response_metric	feature_response_metric	model_type	n_species	estimate	std_error	statistic	p_value	aic	r_squared_or_pseudo_r2	phylogeny_id	status	warning
gra_activity	GRA_OG_GENE_0001	baseline_vs_response	baseline|t0	response|t1	index	index	difference	log2_fold_change	lm	4	1.5	0.2	7.5	0.005	2	0.85		OK	
EOF

cat > "$FIX/response_clusters_expression.tsv" <<'EOF'
feature_layer	feature_id	contrast_name	cluster_id	cluster_label	species_pattern	n_species	mean_response	response_direction
expression	OG_GENE_0001	baseline_vs_response	sign_shared_up	shared_up	Mus_musculus:+;Danio_rerio:+	2	1.5	up
EOF

cat > "$FIX/response_clusters_accessibility.tsv" <<'EOF'
feature_layer	feature_id	contrast_name	cluster_id	cluster_label	species_pattern	n_species	mean_response	response_direction
accessibility	OG_RE_0001	baseline_vs_response	sign_mixed	mixed	Mus_musculus:+;Danio_rerio:-	2	0.1	mixed
EOF

cat > "$FIX/response_clusters_gra_activity.tsv" <<'EOF'
feature_layer	feature_id	contrast_name	cluster_id	cluster_label	species_pattern	n_species	mean_response	response_direction
gra_activity	GRA_OG_GENE_0001	baseline_vs_response	sign_shared_up	shared_up	Mus_musculus:+;Danio_rerio:+	2	1.4	up
EOF

cat > "$FIX/pairwise_species_molecular_contrasts.tsv" <<'EOF'
species_a	species_b	contrast_name	baseline_label	response_label	phenotype_response_id	phenotype_response_metric	feature_layer	feature_id	feature_response_metric	delta_phenotype_response	delta_feature_response	direction_match	status
Danio_rerio	Mus_musculus	baseline_vs_response	baseline|t0	response|t1	index	difference	expression	OG_GENE_0001	log2_fold_change	0.5	1.0	same	OK
Danio_rerio	Mus_musculus	baseline_vs_response	baseline|t0	response|t1	index	difference	accessibility	OG_RE_0001	log2_fold_change	0.5	-0.5	opposite	OK
EOF

cat > "$FIX/hypothesis_model_results.tsv" <<'EOF'
hypothesis_name	hypothesis_type	stage	stratum	model_id	model_type	response	predictors	covariates	term	n_species	estimate	std_error	statistic	p_value	aic	r_squared_or_pseudo_r2	phylogeny_id	status	message
external_trait_association	direct_model	direct_model	all	external	lm	external_trait	phenotype_index_response		phenotype_index_response	4	1	1	1	0.1	1	0.2	tree	OK	
EOF

EVID="$TMP_DIR/evidence"
python3 "$ROOT_DIR/bin/collect_candidate_evidence.py" \
  --phenotype_index_contrasts "$FIX/phenotype_index_contrasts.tsv" \
  --hypothesis_model_results "$FIX/hypothesis_model_results.tsv" \
  --differential_expression "$FIX/differential_expression_orthogroups.tsv" \
  --differential_accessibility "$FIX/differential_accessibility_orthogroups.tsv" \
  --differential_gra_activity "$FIX/differential_gra_activity.tsv" \
  --gene_regulatory_architectures "$FIX/gene_regulatory_architectures.tsv" \
  --gra_re_membership "$FIX/gra_re_membership.tsv" \
  --feature_to_orthogroup_map "$FIX/feature_to_orthogroup_map.tsv" \
  --phenotype_expression_associations "$FIX/phenotype_expression_associations.tsv" \
  --phenotype_accessibility_associations "$FIX/phenotype_accessibility_associations.tsv" \
  --phenotype_gra_associations "$FIX/phenotype_gra_associations.tsv" \
  --response_clusters_expression "$FIX/response_clusters_expression.tsv" \
  --response_clusters_accessibility "$FIX/response_clusters_accessibility.tsv" \
  --response_clusters_gra_activity "$FIX/response_clusters_gra_activity.tsv" \
  --pairwise_species_molecular_contrasts "$FIX/pairwise_species_molecular_contrasts.tsv" \
  --output_dir "$EVID" > "$TMP_DIR/collect.out" 2>&1
test -s "$EVID/candidate_evidence_long.tsv"
test -s "$EVID/candidate_evidence_warnings.tsv"
assert_header_contains "$EVID/candidate_evidence_long.tsv" "source_evidence_key" "evidence table missing source_evidence_key"
assert_grep 'linked_gene' "$EVID/candidate_evidence_long.tsv" "linked gene evidence missing"
assert_grep 'Hypothesis results are global' "$EVID/candidate_evidence_warnings.tsv" "global hypothesis warning missing"

RANK="$TMP_DIR/ranked"
python3 "$ROOT_DIR/bin/score_candidate_mechanisms.py" \
  --candidate_evidence_long "$EVID/candidate_evidence_long.tsv" \
  --candidate_scoring_config "$DEFAULT_CONFIG" \
  --output_dir "$RANK" \
  --scored_evidence_output "$EVID/candidate_evidence_scored.tsv" > "$TMP_DIR/score.out" 2>&1
for file in candidate_genes_ranked.tsv candidate_res_ranked.tsv candidate_gras_ranked.tsv candidate_all_ranked.tsv candidate_scoring_warnings.tsv; do
  test -s "$RANK/$file"
done
test -s "$EVID/candidate_evidence_scored.tsv"
assert_nonempty_rows "$RANK/candidate_genes_ranked.tsv" "candidate gene table has no rows"
assert_nonempty_rows "$RANK/candidate_res_ranked.tsv" "candidate RE table has no rows"
assert_nonempty_rows "$RANK/candidate_gras_ranked.tsv" "candidate GRA table has no rows"
assert_nonempty_rows "$RANK/candidate_all_ranked.tsv" "all-candidate table has no rows"
for field in rank candidate_id candidate_type total_score n_evidence_types n_contrasts n_species top_evidence_type top_contrast mean_effect_size combined_direction support_summary linked_gene_orthogroup_id linked_re_orthogroup_id linked_gra_id; do
  assert_header_contains "$RANK/candidate_all_ranked.tsv" "$field" "ranked table missing $field"
done
assert_grep 'duplicate_ignored' "$EVID/candidate_evidence_scored.tsv" "duplicate evidence was not identified"
awk 'BEGIN{FS="\t"} NR==1{for(i=1;i<=NF;i++) h[$i]=i; next}
  $h["candidate_id"]=="OG_GENE_0001" && $h["evidence_type"]=="differential_expression" && $h["evidence_scope"]=="direct" && $h["duplicate_status"]=="counted"{direct=$h["final_score"]}
  $h["candidate_id"]=="OG_RE_0001" && $h["evidence_type"]=="differential_expression" && $h["evidence_scope"]=="linked_gene" && $h["duplicate_status"]=="counted"{linked=$h["final_score"]}
  END{exit (direct>linked && linked>0)?0:1}' "$EVID/candidate_evidence_scored.tsv" || {
  cat "$EVID/candidate_evidence_scored.tsv"
  echo "FAIL: linked evidence was not down-weighted relative to direct evidence" >&2
  exit 1
}
assert_grep 'OG_RE_0001' "$RANK/candidate_genes_ranked.tsv" "linked RE relationship not retained in gene ranking"
assert_grep 'GRA_OG_GENE_0001' "$RANK/candidate_res_ranked.tsv" "linked GRA relationship not retained in RE ranking"

UNIQ="$TMP_DIR/unique"
mkdir -p "$UNIQ"
awk '!seen[$0]++' "$FIX/differential_expression_orthogroups.tsv" > "$UNIQ/differential_expression_orthogroups.tsv"
EVID_UNIQ="$TMP_DIR/evidence_unique"
python3 "$ROOT_DIR/bin/collect_candidate_evidence.py" \
  --phenotype_index_contrasts "$FIX/phenotype_index_contrasts.tsv" \
  --hypothesis_model_results "$FIX/hypothesis_model_results.tsv" \
  --differential_expression "$UNIQ/differential_expression_orthogroups.tsv" \
  --differential_accessibility "$FIX/differential_accessibility_orthogroups.tsv" \
  --differential_gra_activity "$FIX/differential_gra_activity.tsv" \
  --gene_regulatory_architectures "$FIX/gene_regulatory_architectures.tsv" \
  --gra_re_membership "$FIX/gra_re_membership.tsv" \
  --feature_to_orthogroup_map "$FIX/feature_to_orthogroup_map.tsv" \
  --phenotype_expression_associations "$FIX/phenotype_expression_associations.tsv" \
  --phenotype_accessibility_associations "$FIX/phenotype_accessibility_associations.tsv" \
  --phenotype_gra_associations "$FIX/phenotype_gra_associations.tsv" \
  --response_clusters_expression "$FIX/response_clusters_expression.tsv" \
  --response_clusters_accessibility "$FIX/response_clusters_accessibility.tsv" \
  --response_clusters_gra_activity "$FIX/response_clusters_gra_activity.tsv" \
  --pairwise_species_molecular_contrasts "$FIX/pairwise_species_molecular_contrasts.tsv" \
  --output_dir "$EVID_UNIQ" > "$TMP_DIR/collect_unique.out" 2>&1
RANK_UNIQ="$TMP_DIR/ranked_unique"
python3 "$ROOT_DIR/bin/score_candidate_mechanisms.py" \
  --candidate_evidence_long "$EVID_UNIQ/candidate_evidence_long.tsv" \
  --candidate_scoring_config "$DEFAULT_CONFIG" \
  --output_dir "$RANK_UNIQ" \
  --scored_evidence_output "$EVID_UNIQ/candidate_evidence_scored.tsv" > "$TMP_DIR/score_unique.out" 2>&1
awk 'BEGIN{FS="\t"} FNR==1{next} FNR==NR && $2=="OG_GENE_0001"{a=$4; next} $2=="OG_GENE_0001"{b=$4} END{exit (a==b)?0:1}' \
  "$RANK/candidate_all_ranked.tsv" "$RANK_UNIQ/candidate_all_ranked.tsv" || {
  cat "$RANK/candidate_all_ranked.tsv"
  cat "$RANK_UNIQ/candidate_all_ranked.tsv"
  echo "FAIL: duplicate evidence changed candidate score" >&2
  exit 1
}

OVERRIDE="$TMP_DIR/candidate_scoring_config_override.tsv"
cat > "$OVERRIDE" <<'EOF'
evidence_type	weight	enabled	notes
differential_expression	10.0	true	override expression weight
EOF
RANK_OVERRIDE="$TMP_DIR/ranked_override"
python3 "$ROOT_DIR/bin/score_candidate_mechanisms.py" \
  --candidate_evidence_long "$EVID/candidate_evidence_long.tsv" \
  --candidate_scoring_config "$OVERRIDE" \
  --output_dir "$RANK_OVERRIDE" \
  --scored_evidence_output "$TMP_DIR/evidence_scored_override.tsv" > "$TMP_DIR/score_override.out" 2>&1
awk 'BEGIN{FS="\t"} FNR==1{next} FNR==NR && $2=="OG_GENE_0001"{base=$4; next} $2=="OG_GENE_0001"{override=$4} END{exit (override>base)?0:1}' \
  "$RANK/candidate_all_ranked.tsv" "$RANK_OVERRIDE/candidate_all_ranked.tsv" || {
  cat "$RANK/candidate_all_ranked.tsv"
  cat "$RANK_OVERRIDE/candidate_all_ranked.tsv"
  echo "FAIL: scoring config override did not change score" >&2
  exit 1
}

SUMMARY="$TMP_DIR/summary"
python3 "$ROOT_DIR/bin/summarize_candidate_prioritization.py" \
  --candidate_evidence_long "$EVID/candidate_evidence_long.tsv" \
  --candidate_evidence_warnings "$EVID/candidate_evidence_warnings.tsv" \
  --candidate_evidence_scored "$EVID/candidate_evidence_scored.tsv" \
  --candidate_genes_ranked "$RANK/candidate_genes_ranked.tsv" \
  --candidate_res_ranked "$RANK/candidate_res_ranked.tsv" \
  --candidate_gras_ranked "$RANK/candidate_gras_ranked.tsv" \
  --candidate_all_ranked "$RANK/candidate_all_ranked.tsv" \
  --candidate_scoring_warnings "$RANK/candidate_scoring_warnings.tsv" \
  --output_dir "$SUMMARY" > "$TMP_DIR/summary.out" 2>&1
test -s "$SUMMARY/candidate_prioritization_summary.tsv"
test -s "$SUMMARY/candidate_outputs_manifest.tsv"
assert_grep 'n_candidates_gene' "$SUMMARY/candidate_prioritization_summary.tsv" "summary missing gene count"

MISSING_OPTIONAL="$TMP_DIR/missing_optional"
python3 "$ROOT_DIR/bin/collect_candidate_evidence.py" \
  --differential_expression "$FIX/differential_expression_orthogroups.tsv" \
  --differential_accessibility "$FIX/differential_accessibility_orthogroups.tsv" \
  --differential_gra_activity "$FIX/differential_gra_activity.tsv" \
  --gra_re_membership "$FIX/gra_re_membership.tsv" \
  --output_dir "$MISSING_OPTIONAL" > "$TMP_DIR/missing_optional.out" 2>&1
test -s "$MISSING_OPTIONAL/candidate_evidence_long.tsv"
assert_grep 'Missing optional evidence layer' "$MISSING_OPTIONAL/candidate_evidence_warnings.tsv" "missing optional evidence warning absent"

ALL_MISSING="$TMP_DIR/all_missing"
if python3 "$ROOT_DIR/bin/collect_candidate_evidence.py" \
  --gra_re_membership "$FIX/gra_re_membership.tsv" \
  --output_dir "$ALL_MISSING" > "$TMP_DIR/all_missing.out" 2>&1; then
  cat "$TMP_DIR/all_missing.out"
  echo "FAIL: all major evidence missing should fail" >&2
  exit 1
fi
assert_grep 'No major candidate evidence tables' "$TMP_DIR/all_missing.out" "all-missing diagnostic absent"

NF_OUT="$TMP_DIR/nf_results"
mkdir -p "$NF_OUT/phenotype/contrasts" "$NF_OUT/hypotheses" "$NF_OUT/orthology" "$NF_OUT/gra/tables" "$NF_OUT/gra/differential" "$NF_OUT/integration/associations" "$NF_OUT/integration/clustering" "$NF_OUT/integration/pairwise"
cp "$FIX/phenotype_index_contrasts.tsv" "$NF_OUT/phenotype/contrasts/phenotype_index_contrasts.tsv"
cp "$FIX/hypothesis_model_results.tsv" "$NF_OUT/hypotheses/hypothesis_model_results.tsv"
cp "$FIX/differential_expression_orthogroups.tsv" "$NF_OUT/orthology/differential_expression_orthogroups.tsv"
cp "$FIX/differential_accessibility_orthogroups.tsv" "$NF_OUT/orthology/differential_accessibility_orthogroups.tsv"
cp "$FIX/feature_to_orthogroup_map.tsv" "$NF_OUT/orthology/feature_to_orthogroup_map.tsv"
cp "$FIX/gene_regulatory_architectures.tsv" "$NF_OUT/gra/tables/gene_regulatory_architectures.tsv"
cp "$FIX/gra_re_membership.tsv" "$NF_OUT/gra/tables/gra_re_membership.tsv"
cp "$FIX/differential_gra_activity.tsv" "$NF_OUT/gra/differential/differential_gra_activity.tsv"
cp "$FIX/phenotype_expression_associations.tsv" "$NF_OUT/integration/associations/phenotype_expression_associations.tsv"
cp "$FIX/phenotype_accessibility_associations.tsv" "$NF_OUT/integration/associations/phenotype_accessibility_associations.tsv"
cp "$FIX/phenotype_gra_associations.tsv" "$NF_OUT/integration/associations/phenotype_gra_associations.tsv"
cp "$FIX/response_clusters_expression.tsv" "$NF_OUT/integration/clustering/response_clusters_expression.tsv"
cp "$FIX/response_clusters_accessibility.tsv" "$NF_OUT/integration/clustering/response_clusters_accessibility.tsv"
cp "$FIX/response_clusters_gra_activity.tsv" "$NF_OUT/integration/clustering/response_clusters_gra_activity.tsv"
cp "$FIX/pairwise_species_molecular_contrasts.tsv" "$NF_OUT/integration/pairwise/pairwise_species_molecular_contrasts.tsv"

if ! nextflow run "$ROOT_DIR" \
  --run_stage candidate_prioritization \
  --study_profile "$PROFILE" \
  --outdir "$NF_OUT" > "$TMP_DIR/nf_stage10.out" 2>&1; then
  cat "$TMP_DIR/nf_stage10.out"
  echo "FAIL: Nextflow candidate_prioritization failed" >&2
  exit 1
fi
test -s "$NF_OUT/candidates/evidence/candidate_evidence_long.tsv"
test -s "$NF_OUT/candidates/evidence/candidate_evidence_scored.tsv"
test -s "$NF_OUT/candidates/ranked/candidate_genes_ranked.tsv"
test -s "$NF_OUT/candidates/ranked/candidate_res_ranked.tsv"
test -s "$NF_OUT/candidates/ranked/candidate_gras_ranked.tsv"
test -s "$NF_OUT/candidates/ranked/candidate_all_ranked.tsv"
test -s "$NF_OUT/candidates/summary/candidate_prioritization_summary.tsv"

if rg 'DDR|RoR' \
  "$ROOT_DIR/bin/collect_candidate_evidence.py" \
  "$ROOT_DIR/bin/score_candidate_mechanisms.py" \
  "$ROOT_DIR/bin/summarize_candidate_prioritization.py" \
  "$ROOT_DIR/workflows/candidate_prioritization.nf" \
  "$ROOT_DIR/subworkflows/evidence_collection.nf" \
  "$ROOT_DIR/subworkflows/candidate_scoring.nf" \
  "$ROOT_DIR/subworkflows/candidate_tables.nf" >/dev/null 2>&1; then
  echo "FAIL: Stage 10 core files contain profile-specific terms" >&2
  exit 1
fi

echo "candidate prioritization tests passed"
