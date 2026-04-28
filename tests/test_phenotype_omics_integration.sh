#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PROFILE="$ROOT_DIR/profiles/generic/study_profile.yaml"
PHENO="$ROOT_DIR/assets/example_samplesheets/phenotype_samplesheet.csv"
SPECIES_TRAITS="$ROOT_DIR/assets/example_samplesheets/species_traits.tsv"
PHYLO_MANIFEST="$ROOT_DIR/assets/example_samplesheets/phylogeny_manifest.tsv"
OMICS="$ROOT_DIR/assets/example_samplesheets/omics_samplesheet.csv"

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

assert_nonempty_rows() {
  file="$1"
  message="$2"
  awk 'NR>1{found=1} END{exit found?0:1}' "$file" || {
    cat "$file"
    echo "FAIL: $message" >&2
    exit 1
  }
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

PHENO_OUT="$TMP_DIR/phenotype"
mkdir -p "$PHENO_OUT"
python3 "$ROOT_DIR/bin/phenotype_normalize.py" \
  --input "$PHENO" \
  --output "$PHENO_OUT/normalized.tsv" \
  --summary "$PHENO_OUT/normalization_summary.tsv" > "$TMP_DIR/normalize.out" 2>&1
python3 "$ROOT_DIR/bin/phenotype_qc.py" \
  --input "$PHENO_OUT/normalized.tsv" \
  --study_profile "$PROFILE" \
  --metrics "$PHENO_OUT/qc_metrics.tsv" \
  --outliers "$PHENO_OUT/outliers.tsv" \
  --group_counts "$PHENO_OUT/group_counts.tsv" > "$TMP_DIR/qc.out" 2>&1
python3 "$ROOT_DIR/bin/calc_phenotype_index.py" \
  --input "$PHENO_OUT/normalized.tsv" \
  --study_profile "$PROFILE" \
  --sample_output "$PHENO_OUT/index_by_sample.tsv" \
  --group_output "$PHENO_OUT/index_by_group.tsv" > "$TMP_DIR/index.out" 2>&1
python3 "$ROOT_DIR/bin/phenotype_contrasts.py" \
  --phenotype_table "$PHENO_OUT/normalized.tsv" \
  --study_profile "$PROFILE" \
  --index_by_group "$PHENO_OUT/index_by_group.tsv" \
  --index_output "$PHENO_OUT/phenotype_index_contrasts.tsv" \
  --component_output "$PHENO_OUT/component_trait_contrasts.tsv" > "$TMP_DIR/contrasts.out" 2>&1

MOLECULAR="$TMP_DIR/molecular"
mkdir -p "$MOLECULAR"
cat > "$MOLECULAR/differential_expression_orthogroups.tsv" <<'EOF'
orthogroup_id	feature_type	mapping_status	n_source_features	n_species	is_ambiguous	ambiguity_reason	species_members	source_feature_ids	omics_type	contrast_name	contrast_type	species	baseline_label	response_label	n_baseline	n_response	base_mean	baseline_mean	response_mean	log2_fold_change	statistic	p_value	padj	method	status	message
OG_EXPR_0001	gene	mapped	1	4	false		Danio_rerio,Gallus_gallus,Mus_musculus,Xenopus_tropicalis	gene_0001	rnaseq	baseline_vs_response	baseline_vs_response	Danio_rerio	baseline|t0	response|t1	1	1	10	8	16	0.51	1	0.1	0.2	fallback	OK	
OG_EXPR_0001	gene	mapped	1	4	false		Danio_rerio,Gallus_gallus,Mus_musculus,Xenopus_tropicalis	gene_0001	rnaseq	baseline_vs_response	baseline_vs_response	Gallus_gallus	baseline|t0	response|t1	1	1	10	8	14	0.36	1	0.1	0.2	fallback	OK	
OG_EXPR_0001	gene	mapped	1	4	false		Danio_rerio,Gallus_gallus,Mus_musculus,Xenopus_tropicalis	gene_0001	rnaseq	baseline_vs_response	baseline_vs_response	Mus_musculus	baseline|t0	response|t1	1	1	10	8	13	0.30	1	0.1	0.2	fallback	OK	
OG_EXPR_0001	gene	mapped	1	4	false		Danio_rerio,Gallus_gallus,Mus_musculus,Xenopus_tropicalis	gene_0001	rnaseq	baseline_vs_response	baseline_vs_response	Xenopus_tropicalis	baseline|t0	response|t1	1	1	10	8	12	0.28	1	0.1	0.2	fallback	OK	
OG_EXPR_0002	gene	mapped	1	4	false		Danio_rerio,Gallus_gallus,Mus_musculus,Xenopus_tropicalis	gene_0002	rnaseq	baseline_vs_response	baseline_vs_response	Danio_rerio	baseline|t0	response|t1	1	1	10	8	6	-0.2	1	0.1	0.2	fallback	OK	
OG_EXPR_0002	gene	mapped	1	4	false		Danio_rerio,Gallus_gallus,Mus_musculus,Xenopus_tropicalis	gene_0002	rnaseq	baseline_vs_response	baseline_vs_response	Gallus_gallus	baseline|t0	response|t1	1	1	10	8	11	0.1	1	0.1	0.2	fallback	OK	
OG_EXPR_0002	gene	mapped	1	4	false		Danio_rerio,Gallus_gallus,Mus_musculus,Xenopus_tropicalis	gene_0002	rnaseq	baseline_vs_response	baseline_vs_response	Mus_musculus	baseline|t0	response|t1	1	1	10	8	5	-0.3	1	0.1	0.2	fallback	OK	
OG_EXPR_0002	gene	mapped	1	4	false		Danio_rerio,Gallus_gallus,Mus_musculus,Xenopus_tropicalis	gene_0002	rnaseq	baseline_vs_response	baseline_vs_response	Xenopus_tropicalis	baseline|t0	response|t1	1	1	10	8	8	0	1	0.1	0.2	fallback	OK	
EOF

cat > "$MOLECULAR/differential_accessibility_orthogroups.tsv" <<'EOF'
orthogroup_id	feature_type	mapping_status	n_source_features	n_species	is_ambiguous	ambiguity_reason	species_members	source_feature_ids	omics_type	contrast_name	contrast_type	species	baseline_label	response_label	n_baseline	n_response	base_mean	baseline_mean	response_mean	log2_fold_change	statistic	p_value	padj	method	status	message
OG_ACC_0001	regulatory_element	mapped	1	4	false		Danio_rerio,Gallus_gallus,Mus_musculus,Xenopus_tropicalis	re_0001	atacseq	baseline_vs_response	baseline_vs_response	Danio_rerio	baseline|t0	response|t1	1	1	10	5	12	0.7	1	0.1	0.2	fallback	OK	
OG_ACC_0001	regulatory_element	mapped	1	4	false		Danio_rerio,Gallus_gallus,Mus_musculus,Xenopus_tropicalis	re_0001	atacseq	baseline_vs_response	baseline_vs_response	Gallus_gallus	baseline|t0	response|t1	1	1	10	5	11	0.5	1	0.1	0.2	fallback	OK	
OG_ACC_0001	regulatory_element	mapped	1	4	false		Danio_rerio,Gallus_gallus,Mus_musculus,Xenopus_tropicalis	re_0001	atacseq	baseline_vs_response	baseline_vs_response	Mus_musculus	baseline|t0	response|t1	1	1	10	5	10	0.4	1	0.1	0.2	fallback	OK	
OG_ACC_0001	regulatory_element	mapped	1	4	false		Danio_rerio,Gallus_gallus,Mus_musculus,Xenopus_tropicalis	re_0001	atacseq	baseline_vs_response	baseline_vs_response	Xenopus_tropicalis	baseline|t0	response|t1	1	1	10	5	9	0.3	1	0.1	0.2	fallback	OK	
OG_ACC_0002	regulatory_element	mapped	1	4	false		Danio_rerio,Gallus_gallus,Mus_musculus,Xenopus_tropicalis	re_0002	atacseq	baseline_vs_response	baseline_vs_response	Danio_rerio	baseline|t0	response|t1	1	1	10	5	4	-0.2	1	0.1	0.2	fallback	OK	
OG_ACC_0002	regulatory_element	mapped	1	4	false		Danio_rerio,Gallus_gallus,Mus_musculus,Xenopus_tropicalis	re_0002	atacseq	baseline_vs_response	baseline_vs_response	Gallus_gallus	baseline|t0	response|t1	1	1	10	5	4	-0.2	1	0.1	0.2	fallback	OK	
OG_ACC_0002	regulatory_element	mapped	1	4	false		Danio_rerio,Gallus_gallus,Mus_musculus,Xenopus_tropicalis	re_0002	atacseq	baseline_vs_response	baseline_vs_response	Mus_musculus	baseline|t0	response|t1	1	1	10	5	4	-0.2	1	0.1	0.2	fallback	OK	
OG_ACC_0002	regulatory_element	mapped	1	4	false		Danio_rerio,Gallus_gallus,Mus_musculus,Xenopus_tropicalis	re_0002	atacseq	baseline_vs_response	baseline_vs_response	Xenopus_tropicalis	baseline|t0	response|t1	1	1	10	5	4	-0.2	1	0.1	0.2	fallback	OK	
EOF

cat > "$MOLECULAR/differential_gra_activity.tsv" <<'EOF'
gra_id	gene_orthogroup_id	contrast_name	baseline_label	response_label	log2_fold_change	statistic	p_value	padj	mean_baseline	mean_response	n_baseline	n_response	method	status	message	species
GRA_OG_GENE_0001	OG_GENE_0001	baseline_vs_response	baseline|t0	response|t1	0.51	1	0.1	0.2	5	12	1	1	fallback	OK		Danio_rerio
GRA_OG_GENE_0001	OG_GENE_0001	baseline_vs_response	baseline|t0	response|t1	0.36	1	0.1	0.2	5	11	1	1	fallback	OK		Gallus_gallus
GRA_OG_GENE_0001	OG_GENE_0001	baseline_vs_response	baseline|t0	response|t1	0.30	1	0.1	0.2	5	10	1	1	fallback	OK		Mus_musculus
GRA_OG_GENE_0001	OG_GENE_0001	baseline_vs_response	baseline|t0	response|t1	0.28	1	0.1	0.2	5	9	1	1	fallback	OK		Xenopus_tropicalis
EOF

INPUT="$TMP_DIR/integration/input"
python3 "$ROOT_DIR/bin/prepare_phenotype_omics_inputs.py" \
  --phenotype_index_contrasts "$PHENO_OUT/phenotype_index_contrasts.tsv" \
  --component_trait_contrasts "$PHENO_OUT/component_trait_contrasts.tsv" \
  --differential_expression_orthogroups "$MOLECULAR/differential_expression_orthogroups.tsv" \
  --differential_accessibility_orthogroups "$MOLECULAR/differential_accessibility_orthogroups.tsv" \
  --differential_gra_activity "$MOLECULAR/differential_gra_activity.tsv" \
  --study_profile "$PROFILE" \
  --output_dir "$INPUT" > "$TMP_DIR/prepare_stage9.out" 2>&1
test -s "$INPUT/phenotype_response_table.tsv"
test -s "$INPUT/molecular_response_long.tsv"
test -s "$INPUT/phenotype_omics_model_table.tsv"
test -s "$INPUT/phenotype_omics_input_warnings.tsv"
assert_nonempty_rows "$INPUT/phenotype_omics_model_table.tsv" "model table has no rows"
for field in species contrast_name phenotype_index_name phenotype_response_metric phenotype_response_value feature_layer feature_id feature_response_metric feature_response_value baseline_label response_label; do
  assert_header_contains "$INPUT/phenotype_omics_model_table.tsv" "$field" "model table missing $field"
done

CLUST="$TMP_DIR/integration/clustering"
python3 "$ROOT_DIR/bin/cluster_molecular_responses.py" \
  --molecular_response_long "$INPUT/molecular_response_long.tsv" \
  --output_dir "$CLUST" > "$TMP_DIR/cluster.out" 2>&1
test -s "$CLUST/response_clusters_expression.tsv"
test -s "$CLUST/response_clusters_accessibility.tsv"
test -s "$CLUST/response_clusters_gra_activity.tsv"
test -s "$CLUST/response_cluster_summary.tsv"
assert_grep 'shared_up' "$CLUST/response_clusters_expression.tsv" "shared_up cluster missing"
assert_grep 'mixed' "$CLUST/response_clusters_expression.tsv" "mixed cluster missing"

ASSOC="$TMP_DIR/integration/associations"
Rscript "$ROOT_DIR/bin/run_phenotype_omics_associations.R" \
  --model_table "$INPUT/phenotype_omics_model_table.tsv" \
  --species_traits "$SPECIES_TRAITS" \
  --phylogeny_manifest "$PHYLO_MANIFEST" \
  --phylogeny_base_dir "$ROOT_DIR/assets/example_samplesheets" \
  --model_types lm,pgls_brownian \
  --min_species 3 \
  --output_dir "$ASSOC" > "$TMP_DIR/assoc.out" 2>&1
test -s "$ASSOC/phenotype_expression_associations.tsv"
test -s "$ASSOC/phenotype_accessibility_associations.tsv"
test -s "$ASSOC/phenotype_gra_associations.tsv"
test -s "$ASSOC/phenotype_omics_association_warnings.tsv"
assert_grep 'lm' "$ASSOC/phenotype_expression_associations.tsv" "LM association missing"
assert_grep 'OK' "$ASSOC/phenotype_expression_associations.tsv" "successful LM association missing"
if ! grep -q 'pgls_brownian' "$ASSOC/phenotype_expression_associations.tsv" "$ASSOC/phenotype_accessibility_associations.tsv" "$ASSOC/phenotype_gra_associations.tsv" "$ASSOC/phenotype_omics_association_warnings.tsv"; then
  cat "$ASSOC/phenotype_omics_association_warnings.tsv"
  echo "FAIL: PGLS result or skip warning missing" >&2
  exit 1
fi

PAIRWISE="$TMP_DIR/integration/pairwise"
python3 "$ROOT_DIR/bin/run_pairwise_species_contrasts.py" \
  --phenotype_response_table "$INPUT/phenotype_response_table.tsv" \
  --molecular_response_long "$INPUT/molecular_response_long.tsv" \
  --output_dir "$PAIRWISE" > "$TMP_DIR/pairwise.out" 2>&1
test -s "$PAIRWISE/pairwise_species_molecular_contrasts.tsv"
test -s "$PAIRWISE/pairwise_species_contrast_summary.tsv"
assert_grep 'same' "$PAIRWISE/pairwise_species_molecular_contrasts.tsv" "same-direction pairwise row missing"
awk 'BEGIN{FS="\t"; ok=0} NR>1 && $1=="Danio_rerio" && $2=="Mus_musculus" && $8=="expression" && $9=="OG_EXPR_0001" && $11<0 && $12<0 && $13=="same"{ok=1} END{exit ok?0:1}' "$PAIRWISE/pairwise_species_molecular_contrasts.tsv" || {
  cat "$PAIRWISE/pairwise_species_molecular_contrasts.tsv"
  echo "FAIL: pairwise species_b - species_a sign check failed" >&2
  exit 1
}

SUMMARY="$TMP_DIR/integration/summary"
python3 "$ROOT_DIR/bin/summarize_phenotype_omics_integration.py" \
  --phenotype_response_table "$INPUT/phenotype_response_table.tsv" \
  --molecular_response_long "$INPUT/molecular_response_long.tsv" \
  --model_table "$INPUT/phenotype_omics_model_table.tsv" \
  --input_warnings "$INPUT/phenotype_omics_input_warnings.tsv" \
  --response_clusters_expression "$CLUST/response_clusters_expression.tsv" \
  --response_clusters_accessibility "$CLUST/response_clusters_accessibility.tsv" \
  --response_clusters_gra_activity "$CLUST/response_clusters_gra_activity.tsv" \
  --response_cluster_summary "$CLUST/response_cluster_summary.tsv" \
  --phenotype_expression_associations "$ASSOC/phenotype_expression_associations.tsv" \
  --phenotype_accessibility_associations "$ASSOC/phenotype_accessibility_associations.tsv" \
  --phenotype_gra_associations "$ASSOC/phenotype_gra_associations.tsv" \
  --association_warnings "$ASSOC/phenotype_omics_association_warnings.tsv" \
  --pairwise_species_molecular_contrasts "$PAIRWISE/pairwise_species_molecular_contrasts.tsv" \
  --pairwise_species_contrast_summary "$PAIRWISE/pairwise_species_contrast_summary.tsv" \
  --output_dir "$SUMMARY" > "$TMP_DIR/summary.out" 2>&1
test -s "$SUMMARY/phenotype_omics_integration_summary.tsv"
test -s "$SUMMARY/phenotype_omics_outputs_manifest.tsv"
assert_grep 'n_successful_lm_associations' "$SUMMARY/phenotype_omics_integration_summary.tsv" "summary missing LM count"

if python3 "$ROOT_DIR/bin/prepare_phenotype_omics_inputs.py" \
  --phenotype_index_contrasts "$TMP_DIR/missing_phenotype.tsv" \
  --component_trait_contrasts "$PHENO_OUT/component_trait_contrasts.tsv" \
  --differential_expression_orthogroups "$MOLECULAR/differential_expression_orthogroups.tsv" \
  --differential_accessibility_orthogroups "$MOLECULAR/differential_accessibility_orthogroups.tsv" \
  --differential_gra_activity "$MOLECULAR/differential_gra_activity.tsv" \
  --output_dir "$TMP_DIR/missing_pheno" > "$TMP_DIR/missing_pheno.out" 2>&1; then
  cat "$TMP_DIR/missing_pheno.out"
  echo "FAIL: missing phenotype contrasts expected failure" >&2
  exit 1
fi
assert_grep 'Missing required input table' "$TMP_DIR/missing_pheno.out" "missing phenotype diagnostic absent"

if python3 "$ROOT_DIR/bin/prepare_phenotype_omics_inputs.py" \
  --phenotype_index_contrasts "$PHENO_OUT/phenotype_index_contrasts.tsv" \
  --component_trait_contrasts "$PHENO_OUT/component_trait_contrasts.tsv" \
  --differential_expression_orthogroups "$TMP_DIR/missing_expression.tsv" \
  --differential_accessibility_orthogroups "$MOLECULAR/differential_accessibility_orthogroups.tsv" \
  --differential_gra_activity "$MOLECULAR/differential_gra_activity.tsv" \
  --output_dir "$TMP_DIR/missing_molecular" > "$TMP_DIR/missing_molecular.out" 2>&1; then
  cat "$TMP_DIR/missing_molecular.out"
  echo "FAIL: missing molecular table expected failure" >&2
  exit 1
fi
assert_grep 'Missing required input table' "$TMP_DIR/missing_molecular.out" "missing molecular diagnostic absent"

NF_OUT="$TMP_DIR/nf_results"
mkdir -p "$NF_OUT/phenotype/contrasts" "$NF_OUT/orthology" "$NF_OUT/gra/differential"
cp "$PHENO_OUT/phenotype_index_contrasts.tsv" "$NF_OUT/phenotype/contrasts/phenotype_index_contrasts.tsv"
cp "$PHENO_OUT/component_trait_contrasts.tsv" "$NF_OUT/phenotype/contrasts/component_trait_contrasts.tsv"
cp "$MOLECULAR/differential_expression_orthogroups.tsv" "$NF_OUT/orthology/differential_expression_orthogroups.tsv"
cp "$MOLECULAR/differential_accessibility_orthogroups.tsv" "$NF_OUT/orthology/differential_accessibility_orthogroups.tsv"
cp "$MOLECULAR/differential_gra_activity.tsv" "$NF_OUT/gra/differential/differential_gra_activity.tsv"

if ! nextflow run "$ROOT_DIR" \
  --run_stage phenotype_omics_integration \
  --study_profile "$PROFILE" \
  --omics_samplesheet "$OMICS" \
  --species_traits "$SPECIES_TRAITS" \
  --phylogeny_manifest "$PHYLO_MANIFEST" \
  --outdir "$NF_OUT" > "$TMP_DIR/nf_stage9.out" 2>&1; then
  cat "$TMP_DIR/nf_stage9.out"
  echo "FAIL: Nextflow phenotype_omics_integration failed" >&2
  exit 1
fi
test -s "$NF_OUT/integration/input/phenotype_omics_model_table.tsv"
test -s "$NF_OUT/integration/associations/phenotype_expression_associations.tsv"
test -s "$NF_OUT/integration/clustering/response_cluster_summary.tsv"
test -s "$NF_OUT/integration/pairwise/pairwise_species_molecular_contrasts.tsv"
test -s "$NF_OUT/integration/summary/phenotype_omics_integration_summary.tsv"

if rg 'DDR|RoR' \
  "$ROOT_DIR/bin/prepare_phenotype_omics_inputs.py" \
  "$ROOT_DIR/bin/cluster_molecular_responses.py" \
  "$ROOT_DIR/bin/run_phenotype_omics_associations.R" \
  "$ROOT_DIR/bin/run_pairwise_species_contrasts.py" \
  "$ROOT_DIR/bin/summarize_phenotype_omics_integration.py" \
  "$ROOT_DIR/workflows/phenotype_omics_integration.nf" \
  "$ROOT_DIR/subworkflows/phenotype_molecular_association.nf" \
  "$ROOT_DIR/subworkflows/molecular_response_clustering.nf" \
  "$ROOT_DIR/subworkflows/pairwise_species_contrast.nf" >/dev/null 2>&1; then
  echo "FAIL: Stage 9 core files contain profile-specific terms" >&2
  exit 1
fi

echo "phenotype-omics integration tests passed"
