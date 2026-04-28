#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

GENES="$ROOT_DIR/assets/example_samplesheets/orthologous_genes.tsv"
RES="$ROOT_DIR/assets/example_samplesheets/orthologous_res.tsv"
LINKS="$ROOT_DIR/assets/example_samplesheets/re_to_gene_links.tsv"

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

assert_header_prefix() {
  file="$1"
  expected="$2"
  actual=$(head -n 1 "$file" | cut -f 1-"$(printf '%s' "$expected" | awk -F '\t' '{print NF}')")
  if [ "$actual" != "$expected" ]; then
    cat "$file"
    echo "FAIL: unexpected header prefix in $file" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
}

OMICS="$TMP_DIR/omics_samplesheet.csv"
REFS="$TMP_DIR/reference_manifest.tsv"
PROFILE="$TMP_DIR/study_profile.yaml"
RNA_COUNTS="$TMP_DIR/gene_counts.tsv"
ATAC_COUNTS="$TMP_DIR/re_counts.tsv"

cat > "$OMICS" <<'EOF'
sample_id,species,individual_id,replicate_id,omics_type,condition,timepoint,reference_id,batch,fastq_1,fastq_2,read_layout
rna_base_1,Mus_musculus,mouse_rna_1,rep1,rnaseq,baseline,t0,mmus_ref,batch1,data/rna_base_1_R1.fastq.gz,data/rna_base_1_R2.fastq.gz,paired-end
rna_base_2,Mus_musculus,mouse_rna_2,rep2,rnaseq,baseline,t0,mmus_ref,batch2,data/rna_base_2_R1.fastq.gz,data/rna_base_2_R2.fastq.gz,paired-end
rna_resp_1,Mus_musculus,mouse_rna_3,rep3,rnaseq,response,t1,mmus_ref,batch1,data/rna_resp_1_R1.fastq.gz,data/rna_resp_1_R2.fastq.gz,paired-end
rna_resp_2,Mus_musculus,mouse_rna_4,rep4,rnaseq,response,t1,mmus_ref,batch2,data/rna_resp_2_R1.fastq.gz,data/rna_resp_2_R2.fastq.gz,paired-end
atac_base_1,Danio_rerio,fish_atac_1,rep1,atacseq,baseline,t0,drer_ref,batch1,data/atac_base_1_R1.fastq.gz,data/atac_base_1_R2.fastq.gz,paired-end
atac_base_2,Danio_rerio,fish_atac_2,rep2,atacseq,baseline,t0,drer_ref,batch2,data/atac_base_2_R1.fastq.gz,data/atac_base_2_R2.fastq.gz,paired-end
atac_resp_1,Danio_rerio,fish_atac_3,rep3,atacseq,response,t1,drer_ref,batch1,data/atac_resp_1_R1.fastq.gz,data/atac_resp_1_R2.fastq.gz,paired-end
atac_resp_2,Danio_rerio,fish_atac_4,rep4,atacseq,response,t1,drer_ref,batch2,data/atac_resp_2_R1.fastq.gz,data/atac_resp_2_R2.fastq.gz,paired-end
atac_mouse_base_1,Mus_musculus,mouse_atac_1,rep1,atacseq,baseline,t0,mmus_ref,batch1,data/atac_mouse_base_1_R1.fastq.gz,data/atac_mouse_base_1_R2.fastq.gz,paired-end
atac_mouse_resp_1,Mus_musculus,mouse_atac_2,rep2,atacseq,response,t1,mmus_ref,batch2,data/atac_mouse_resp_1_R1.fastq.gz,data/atac_mouse_resp_1_R2.fastq.gz,paired-end
EOF

cat > "$REFS" <<'EOF'
reference_id	species	genome_fasta	gtf	star_index	bwa_index	chrom_sizes
mmus_ref	Mus_musculus	data/ref/mmus.fa	data/ref/mmus.gtf	data/ref/star/mmus	data/ref/bwa/mmus	data/ref/mmus.chrom.sizes
drer_ref	Danio_rerio	data/ref/drer.fa	data/ref/drer.gtf	data/ref/star/drer	data/ref/bwa/drer	data/ref/drer.chrom.sizes
EOF

cat > "$PROFILE" <<'EOF'
study:
  profile_id: gra_test
  name: GRA test
  version: "1.0"
phenotype_index:
  name: synthetic
  formula: "component_a"
  components: [component_a]
  aggregation: mean
  contrasts:
    - name: baseline_vs_response
      type: baseline_vs_response
      baseline_condition: baseline
      response_condition: response
      baseline_timepoint: t0
      response_timepoint: t1
hypotheses:
  - name: placeholder
    model_type: regression
    response: component_a
    predictors: [component_a]
reporting:
  phenotype_label: Synthetic
  condition_label: Condition
  response_label: Response
  external_trait_label: External
  candidate_mechanism_label: Candidate
EOF

cat > "$RNA_COUNTS" <<'EOF'
feature_id	feature_type	annotation_id	rna_base_1	rna_base_2	rna_resp_1	rna_resp_2
gene_0001	gene	synthetic_gene_0001	100	110	500	520
gene_0002	gene	synthetic_gene_0002	200	210	220	230
gene_0003	gene	synthetic_gene_0003	300	310	320	330
gene_0004	gene	synthetic_gene_0004	400	410	420	430
gene_0005	gene	synthetic_gene_0005	500	510	520	530
gene_0006	gene	synthetic_gene_0006	600	610	620	630
EOF

cat > "$ATAC_COUNTS" <<'EOF'
feature_id	feature_type	chrom	start	end	atac_base_1	atac_base_2	atac_resp_1	atac_resp_2	atac_mouse_base_1	atac_mouse_resp_1
re_0001	regulatory_element	chr1	1000	1250	10	12	40	44	9	19
re_0002	regulatory_element	chr2	1500	1750	20	22	30	34	8	18
re_0003	regulatory_element	chr3	2000	2250	30	32	70	74	7	17
re_0004	regulatory_element	chr1	2500	2750	40	42	80	84	6	16
re_0005	regulatory_element	chr2	3000	3250	50	52	90	94	5	15
re_0006	regulatory_element	chr3	3500	3750	60	62	100	104	4	14
EOF

PROJ="$TMP_DIR/projection"
python3 "$ROOT_DIR/bin/project_features_to_orthogroups.py" \
  --omics_samplesheet "$OMICS" \
  --orthologous_genes "$GENES" \
  --orthologous_res "$RES" \
  --omics_types rnaseq,atacseq \
  --rnaseq_counts "$RNA_COUNTS" \
  --atacseq_counts "$ATAC_COUNTS" \
  --output_dir "$PROJ" > "$TMP_DIR/project.out" 2>&1
test -s "$PROJ/gene_orthogroup_counts.tsv"
test -s "$PROJ/re_orthogroup_counts.tsv"
test -s "$PROJ/feature_to_orthogroup_map.tsv"

VALID="$TMP_DIR/re_to_gene_link_validation_report.tsv"
python3 "$ROOT_DIR/bin/validate_re_to_gene_links.py" \
  --re_to_gene_links "$LINKS" \
  --gene_orthogroup_counts "$PROJ/gene_orthogroup_counts.tsv" \
  --re_orthogroup_counts "$PROJ/re_orthogroup_counts.tsv" \
  --feature_to_orthogroup_map "$PROJ/feature_to_orthogroup_map.tsv" \
  --output "$VALID" > "$TMP_DIR/validate.out" 2>&1
assert_grep 'resolved' "$VALID" "validation report missing resolved links"
assert_grep 'unresolved' "$VALID" "validation report missing unresolved test link"

BAD_MISSING="$TMP_DIR/bad_links_missing_column.tsv"
cut -f 2- "$LINKS" > "$BAD_MISSING"
if python3 "$ROOT_DIR/bin/validate_re_to_gene_links.py" \
  --re_to_gene_links "$BAD_MISSING" \
  --gene_orthogroup_counts "$PROJ/gene_orthogroup_counts.tsv" \
  --re_orthogroup_counts "$PROJ/re_orthogroup_counts.tsv" \
  --feature_to_orthogroup_map "$PROJ/feature_to_orthogroup_map.tsv" \
  --output "$TMP_DIR/bad_missing/report.tsv" > "$TMP_DIR/bad_missing.out" 2>&1; then
  cat "$TMP_DIR/bad_missing.out"
  echo "FAIL: missing required link column expected failure" >&2
  exit 1
fi
assert_grep 'Missing required column' "$TMP_DIR/bad_missing/report.tsv" "missing column diagnostic absent"

BAD_EMPTY="$TMP_DIR/bad_links_empty_gene.tsv"
awk 'BEGIN{FS=OFS="\t"} NR==2{$3=""} {print}' "$LINKS" > "$BAD_EMPTY"
if python3 "$ROOT_DIR/bin/validate_re_to_gene_links.py" \
  --re_to_gene_links "$BAD_EMPTY" \
  --gene_orthogroup_counts "$PROJ/gene_orthogroup_counts.tsv" \
  --re_orthogroup_counts "$PROJ/re_orthogroup_counts.tsv" \
  --feature_to_orthogroup_map "$PROJ/feature_to_orthogroup_map.tsv" \
  --output "$TMP_DIR/bad_empty/report.tsv" > "$TMP_DIR/bad_empty.out" 2>&1; then
  cat "$TMP_DIR/bad_empty.out"
  echo "FAIL: empty required gene field expected failure" >&2
  exit 1
fi
assert_grep 'Empty required value' "$TMP_DIR/bad_empty/report.tsv" "empty field diagnostic absent"

GRA_TABLES="$TMP_DIR/gra_tables"
python3 "$ROOT_DIR/bin/build_gra_table.py" \
  --re_to_gene_links "$LINKS" \
  --gene_orthogroup_counts "$PROJ/gene_orthogroup_counts.tsv" \
  --re_orthogroup_counts "$PROJ/re_orthogroup_counts.tsv" \
  --feature_to_orthogroup_map "$PROJ/feature_to_orthogroup_map.tsv" \
  --validation_report "$VALID" \
  --output_dir "$GRA_TABLES" > "$TMP_DIR/build.out" 2>&1
test -s "$GRA_TABLES/gene_regulatory_architectures.tsv"
test -s "$GRA_TABLES/gra_re_membership.tsv"
test -s "$GRA_TABLES/gra_link_warnings.tsv"
assert_header_prefix "$GRA_TABLES/gra_re_membership.tsv" "gra_id	gene_orthogroup_id	re_orthogroup_id	link_type	species_members	n_species	n_res	mapping_status	is_ambiguous"
awk 'BEGIN{FS="\t"; n=0} NR>1 && $1=="GRA_OG_GENE_0001"{n++} END{exit n>=2?0:1}' "$GRA_TABLES/gra_re_membership.tsv" || {
  cat "$GRA_TABLES/gra_re_membership.tsv"
  echo "FAIL: one gene with multiple REs was not represented" >&2
  exit 1
}
awk 'BEGIN{FS="\t"; ok=0} NR>1 && $3=="OG_RE_0003" && $9=="true"{ok=1} END{exit ok?0:1}' "$GRA_TABLES/gra_re_membership.tsv" || {
  cat "$GRA_TABLES/gra_re_membership.tsv"
  echo "FAIL: RE linked to multiple genes was not flagged ambiguous" >&2
  exit 1
}

ACTIVITY="$TMP_DIR/activity"
python3 "$ROOT_DIR/bin/aggregate_gra_activity.py" \
  --re_orthogroup_counts "$PROJ/re_orthogroup_counts.tsv" \
  --gene_regulatory_architectures "$GRA_TABLES/gene_regulatory_architectures.tsv" \
  --gra_re_membership "$GRA_TABLES/gra_re_membership.tsv" \
  --omics_samplesheet "$OMICS" \
  --aggregation mean \
  --output_dir "$ACTIVITY" > "$TMP_DIR/activity.out" 2>&1
test -s "$ACTIVITY/gra_activity_matrix.tsv"
test -s "$ACTIVITY/gra_activity_contributing_res.tsv"
assert_grep 'GRA_OG_GENE_0001' "$ACTIVITY/gra_activity_matrix.tsv" "activity matrix missing expected GRA"
assert_grep 'NA' "$ACTIVITY/gra_activity_matrix.tsv" "activity matrix should preserve NA values"

DIFF="$TMP_DIR/differential"
Rscript "$ROOT_DIR/bin/run_differential_gra_activity.R" \
  --gra_activity_matrix "$ACTIVITY/gra_activity_matrix.tsv" \
  --omics_samplesheet "$OMICS" \
  --study_profile "$PROFILE" \
  --aggregation mean \
  --output_dir "$DIFF" \
  --min_count 1 \
  --min_total_count 1 \
  --min_samples_per_group 1 \
  --alpha 0.05 \
  --force_fallback true > "$TMP_DIR/diff.out" 2>&1
test -s "$DIFF/differential_gra_activity.tsv"
test -s "$DIFF/normalized_gra_activity.tsv"
test -s "$DIFF/differential_gra_activity_warnings.tsv"
assert_header_prefix "$DIFF/differential_gra_activity.tsv" "gra_id	gene_orthogroup_id	contrast_name	baseline_label	response_label	log2_fold_change	statistic	p_value	padj	mean_baseline	mean_response	n_baseline	n_response	method	status"
assert_grep 'species' "$DIFF/differential_gra_activity.tsv" "GRA differential output missing species column"

SUMMARY="$TMP_DIR/summary"
python3 "$ROOT_DIR/bin/summarize_gra_analysis.py" \
  --validation_report "$VALID" \
  --gene_orthogroup_counts "$PROJ/gene_orthogroup_counts.tsv" \
  --gene_regulatory_architectures "$GRA_TABLES/gene_regulatory_architectures.tsv" \
  --gra_re_membership "$GRA_TABLES/gra_re_membership.tsv" \
  --gra_link_warnings "$GRA_TABLES/gra_link_warnings.tsv" \
  --gra_activity_matrix "$ACTIVITY/gra_activity_matrix.tsv" \
  --gra_activity_long "$ACTIVITY/gra_activity_long.tsv" \
  --gra_activity_contributing_res "$ACTIVITY/gra_activity_contributing_res.tsv" \
  --gra_activity_warnings "$ACTIVITY/gra_activity_warnings.tsv" \
  --differential_gra_activity "$DIFF/differential_gra_activity.tsv" \
  --normalized_gra_activity "$DIFF/normalized_gra_activity.tsv" \
  --differential_gra_activity_warnings "$DIFF/differential_gra_activity_warnings.tsv" \
  --output_dir "$SUMMARY" > "$TMP_DIR/summary.out" 2>&1
test -s "$SUMMARY/gra_analysis_summary.tsv"
test -s "$SUMMARY/gra_outputs_manifest.tsv"
assert_grep 'n_gras' "$SUMMARY/gra_analysis_summary.tsv" "GRA summary missing n_gras"

if rg 'DDR|RoR' "$ROOT_DIR/bin/validate_re_to_gene_links.py" "$ROOT_DIR/bin/build_gra_table.py" "$ROOT_DIR/bin/aggregate_gra_activity.py" "$ROOT_DIR/bin/run_differential_gra_activity.R" "$ROOT_DIR/bin/summarize_gra_analysis.py" "$ROOT_DIR/workflows/gra_analysis.nf" "$ROOT_DIR/subworkflows/gra_building.nf" "$ROOT_DIR/subworkflows/gra_activity.nf" "$ROOT_DIR/subworkflows/differential_gra_activity.nf" >/dev/null 2>&1; then
  echo "FAIL: Stage 8 core files contain DDR/RoR-specific terms" >&2
  exit 1
fi

if nextflow run "$ROOT_DIR" \
  --run_stage gra_analysis \
  --omics_samplesheet "$OMICS" \
  --re_to_gene_links "$LINKS" \
  --outdir "$TMP_DIR/missing_stage7" > "$TMP_DIR/nf_missing.out" 2>&1; then
  cat "$TMP_DIR/nf_missing.out"
  echo "FAIL: missing Stage 7 inputs expected Nextflow failure" >&2
  exit 1
fi
assert_grep 'could not find Stage 7 output' "$TMP_DIR/nf_missing.out" "missing Stage 7 diagnostic absent"

NF_OUT="$TMP_DIR/nf_results"
if ! nextflow run "$ROOT_DIR" \
  --run_stage bulk_omics \
  --omics_samplesheet "$OMICS" \
  --reference_manifest "$REFS" \
  --omics_stub true \
  --omics_types rnaseq,atacseq \
  --outdir "$NF_OUT" > "$TMP_DIR/nf_bulk.out" 2>&1; then
  cat "$TMP_DIR/nf_bulk.out"
  echo "FAIL: Nextflow bulk_omics failed" >&2
  exit 1
fi

if ! nextflow run "$ROOT_DIR" \
  --run_stage differential_omics \
  --omics_samplesheet "$OMICS" \
  --omics_types rnaseq,atacseq \
  --rnaseq_counts "$NF_OUT/rnaseq/counts/gene_counts.tsv" \
  --atacseq_counts "$NF_OUT/atacseq/counts/re_counts.tsv" \
  --baseline_condition baseline \
  --response_condition response \
  --baseline_timepoint t0 \
  --response_timepoint t1 \
  --differential_force_fallback true \
  --outdir "$NF_OUT" > "$TMP_DIR/nf_diff.out" 2>&1; then
  cat "$TMP_DIR/nf_diff.out"
  echo "FAIL: Nextflow differential_omics failed" >&2
  exit 1
fi

if ! nextflow run "$ROOT_DIR" \
  --run_stage orthology_projection \
  --omics_samplesheet "$OMICS" \
  --orthologous_genes "$GENES" \
  --orthologous_res "$RES" \
  --omics_stub true \
  --omics_types rnaseq,atacseq \
  --outdir "$NF_OUT" > "$TMP_DIR/nf_orthology.out" 2>&1; then
  cat "$TMP_DIR/nf_orthology.out"
  echo "FAIL: Nextflow orthology_projection failed" >&2
  exit 1
fi

if ! nextflow run "$ROOT_DIR" \
  --run_stage gra_analysis \
  --omics_samplesheet "$OMICS" \
  --re_to_gene_links "$LINKS" \
  --baseline_condition baseline \
  --response_condition response \
  --baseline_timepoint t0 \
  --response_timepoint t1 \
  --differential_force_fallback true \
  --outdir "$NF_OUT" > "$TMP_DIR/nf_gra.out" 2>&1; then
  cat "$TMP_DIR/nf_gra.out"
  echo "FAIL: Nextflow gra_analysis failed" >&2
  exit 1
fi
test -s "$NF_OUT/gra/tables/gene_regulatory_architectures.tsv"
test -s "$NF_OUT/gra/activity/gra_activity_matrix.tsv"
test -s "$NF_OUT/gra/differential/differential_gra_activity.tsv"
test -s "$NF_OUT/gra/summary/gra_analysis_summary.tsv"
assert_grep 'GRA_OG_GENE_0001' "$NF_OUT/gra/activity/gra_activity_matrix.tsv" "Nextflow GRA activity rows missing"

echo "GRA analysis tests passed"
