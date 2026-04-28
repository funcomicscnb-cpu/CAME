#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

GENES="$ROOT_DIR/assets/example_samplesheets/orthologous_genes.tsv"
RES="$ROOT_DIR/assets/example_samplesheets/orthologous_res.tsv"

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
RNA_COUNTS="$TMP_DIR/gene_counts.tsv"
ATAC_COUNTS="$TMP_DIR/re_counts.tsv"
DE="$TMP_DIR/differential_expression.tsv"
DA="$TMP_DIR/differential_accessibility.tsv"

cat > "$OMICS" <<'EOF'
sample_id,species,individual_id,replicate_id,omics_type,condition,timepoint,reference_id,batch,fastq_1,fastq_2,read_layout
rna_base_1,Mus_musculus,mouse_1,rep1,rnaseq,baseline,t0,mmus_ref,batch1,data/rna_base_1_R1.fastq.gz,data/rna_base_1_R2.fastq.gz,paired-end
rna_base_2,Mus_musculus,mouse_2,rep2,rnaseq,baseline,t0,mmus_ref,batch2,data/rna_base_2_R1.fastq.gz,data/rna_base_2_R2.fastq.gz,paired-end
rna_resp_1,Mus_musculus,mouse_3,rep3,rnaseq,response,t1,mmus_ref,batch1,data/rna_resp_1_R1.fastq.gz,data/rna_resp_1_R2.fastq.gz,paired-end
rna_resp_2,Mus_musculus,mouse_4,rep4,rnaseq,response,t1,mmus_ref,batch2,data/rna_resp_2_R1.fastq.gz,data/rna_resp_2_R2.fastq.gz,paired-end
atac_base_1,Danio_rerio,fish_1,rep1,atacseq,baseline,t0,drer_ref,batch1,data/atac_base_1_R1.fastq.gz,data/atac_base_1_R2.fastq.gz,paired-end
atac_base_2,Danio_rerio,fish_2,rep2,atacseq,baseline,t0,drer_ref,batch2,data/atac_base_2_R1.fastq.gz,data/atac_base_2_R2.fastq.gz,paired-end
atac_resp_1,Danio_rerio,fish_3,rep3,atacseq,response,t1,drer_ref,batch1,data/atac_resp_1_R1.fastq.gz,data/atac_resp_1_R2.fastq.gz,paired-end
atac_resp_2,Danio_rerio,fish_4,rep4,atacseq,response,t1,drer_ref,batch2,data/atac_resp_2_R1.fastq.gz,data/atac_resp_2_R2.fastq.gz,paired-end
EOF

cat > "$REFS" <<'EOF'
reference_id	species	genome_fasta	gtf	star_index	bwa_index	chrom_sizes
mmus_ref	Mus_musculus	data/ref/mmus.fa	data/ref/mmus.gtf	data/ref/star/mmus	data/ref/bwa/mmus	data/ref/mmus.chrom.sizes
drer_ref	Danio_rerio	data/ref/drer.fa	data/ref/drer.gtf	data/ref/star/drer	data/ref/bwa/drer	data/ref/drer.chrom.sizes
EOF

cat > "$RNA_COUNTS" <<'EOF'
feature_id	feature_type	annotation_id	rna_base_1	rna_base_2	rna_resp_1	rna_resp_2
gene_0001	gene	synthetic_gene_0001	10	11	12	13
gene_0002	gene	synthetic_gene_0002	20	21	22	23
gene_0003	gene	synthetic_gene_0003	30	31	32	33
gene_0004	gene	synthetic_gene_0004	40	41	42	43
gene_0005	gene	synthetic_gene_0005	50	51	52	53
gene_0006	gene	synthetic_gene_0006	60	61	62	63
EOF

cat > "$ATAC_COUNTS" <<'EOF'
feature_id	feature_type	chrom	start	end	atac_base_1	atac_base_2	atac_resp_1	atac_resp_2
re_0001	regulatory_element	chr1	1000	1250	10	11	12	13
re_0002	regulatory_element	chr2	1500	1750	20	21	22	23
re_0003	regulatory_element	chr3	2000	2250	30	31	32	33
re_0004	regulatory_element	chr1	2500	2750	40	41	42	43
re_0005	regulatory_element	chr2	3000	3250	50	51	52	53
re_0006	regulatory_element	chr3	3500	3750	60	61	62	63
EOF

cat > "$DE" <<'EOF'
omics_type	contrast_name	contrast_type	species	feature_id	feature_type	baseline_label	response_label	n_baseline	n_response	base_mean	baseline_mean	response_mean	log2_fold_change	statistic	p_value	padj	method	status	message	annotation_id
rnaseq	baseline_vs_response	baseline_vs_response	Mus_musculus	gene_0001	gene	baseline|t0	response|t1	2	2	10	9	11	0.2	1	0.5	0.6	fallback	OK		synthetic_gene_0001
rnaseq	baseline_vs_response	baseline_vs_response	Mus_musculus	gene_0003	gene	baseline|t0	response|t1	2	2	30	29	31	1.0	2	0.3	0.4	fallback	OK		synthetic_gene_0003
rnaseq	baseline_vs_response	baseline_vs_response	Mus_musculus	gene_0004	gene	baseline|t0	response|t1	2	2	40	39	41	3.0	4	0.1	0.2	fallback	OK		synthetic_gene_0004
rnaseq	baseline_vs_response	baseline_vs_response	Mus_musculus	gene_0005	gene	baseline|t0	response|t1	2	2	50	49	51	2.0	3	0.2	0.3	fallback	OK		synthetic_gene_0005
EOF

cat > "$DA" <<'EOF'
omics_type	contrast_name	contrast_type	species	feature_id	feature_type	baseline_label	response_label	n_baseline	n_response	base_mean	baseline_mean	response_mean	log2_fold_change	statistic	p_value	padj	method	status	message	chrom	start	end
atacseq	baseline_vs_response	baseline_vs_response	Danio_rerio	re_0001	regulatory_element	baseline|t0	response|t1	2	2	10	9	11	0.2	1	0.5	0.6	fallback	OK		chr1	1000	1250
atacseq	baseline_vs_response	baseline_vs_response	Danio_rerio	re_0003	regulatory_element	baseline|t0	response|t1	2	2	30	29	31	1.0	2	0.3	0.4	fallback	OK		chr3	2000	2250
atacseq	baseline_vs_response	baseline_vs_response	Danio_rerio	re_0004	regulatory_element	baseline|t0	response|t1	2	2	40	39	41	3.0	4	0.1	0.2	fallback	OK		chr1	2500	2750
atacseq	baseline_vs_response	baseline_vs_response	Danio_rerio	re_0005	regulatory_element	baseline|t0	response|t1	2	2	50	49	51	2.0	3	0.2	0.3	fallback	OK		chr2	3000	3250
EOF

VALID_OUT="$TMP_DIR/validation.tsv"
python3 "$ROOT_DIR/bin/validate_orthology_tables.py" \
  --omics_samplesheet "$OMICS" \
  --orthologous_genes "$GENES" \
  --orthologous_res "$RES" \
  --rnaseq_counts "$RNA_COUNTS" \
  --atacseq_counts "$ATAC_COUNTS" \
  --differential_expression "$DE" \
  --differential_accessibility "$DA" \
  --output "$VALID_OUT" > "$TMP_DIR/validate.out" 2>&1
assert_grep 'INFO' "$VALID_OUT" "validation report missing INFO rows"

BAD_GENES="$TMP_DIR/bad_genes_missing_column.tsv"
cut -f 1,2,4- "$GENES" > "$BAD_GENES"
if python3 "$ROOT_DIR/bin/validate_orthology_tables.py" \
  --orthologous_genes "$BAD_GENES" \
  --orthologous_res "$RES" \
  --output "$TMP_DIR/bad_missing/report.tsv" > "$TMP_DIR/bad_missing.out" 2>&1; then
  cat "$TMP_DIR/bad_missing.out"
  echo "FAIL: missing required orthology column expected failure" >&2
  exit 1
fi
assert_grep 'Missing required column' "$TMP_DIR/bad_missing/report.tsv" "missing column diagnostic absent"

BAD_EMPTY="$TMP_DIR/bad_genes_empty_orthogroup.tsv"
awk 'BEGIN{FS=OFS="\t"} NR==2{$3=""} {print}' "$GENES" > "$BAD_EMPTY"
if python3 "$ROOT_DIR/bin/validate_orthology_tables.py" \
  --orthologous_genes "$BAD_EMPTY" \
  --orthologous_res "$RES" \
  --output "$TMP_DIR/bad_empty/report.tsv" > "$TMP_DIR/bad_empty.out" 2>&1; then
  cat "$TMP_DIR/bad_empty.out"
  echo "FAIL: empty orthogroup_id expected failure" >&2
  exit 1
fi
assert_grep 'Empty required value' "$TMP_DIR/bad_empty/report.tsv" "empty orthogroup diagnostic absent"

PROJ="$TMP_DIR/projection"
python3 "$ROOT_DIR/bin/project_features_to_orthogroups.py" \
  --omics_samplesheet "$OMICS" \
  --orthologous_genes "$GENES" \
  --orthologous_res "$RES" \
  --omics_types rnaseq,atacseq \
  --rnaseq_counts "$RNA_COUNTS" \
  --atacseq_counts "$ATAC_COUNTS" \
  --differential_expression "$DE" \
  --differential_accessibility "$DA" \
  --output_dir "$PROJ" > "$TMP_DIR/project.out" 2>&1
test -s "$PROJ/gene_orthogroup_counts.tsv"
test -s "$PROJ/re_orthogroup_counts.tsv"
test -s "$PROJ/differential_expression_orthogroups.tsv"
test -s "$PROJ/differential_accessibility_orthogroups.tsv"
test -s "$PROJ/feature_to_orthogroup_map.tsv"
test -s "$PROJ/orthology_projection_warnings.tsv"
assert_header_prefix "$PROJ/gene_orthogroup_counts.tsv" "orthogroup_id	feature_type	mapping_status	n_source_features	n_species	is_ambiguous	ambiguity_reason	species_members	source_feature_ids"
awk 'BEGIN{FS=OFS="\t"; ok=0} $1=="OG_GENE_0003" && $10=="70"{ok=1} END{exit ok?0:1}' "$PROJ/gene_orthogroup_counts.tsv" || {
  cat "$PROJ/gene_orthogroup_counts.tsv"
  echo "FAIL: many-to-one RNA count aggregation expected 70 for OG_GENE_0003 rna_base_1" >&2
  exit 1
}
assert_grep 'OG_GENE_0005' "$PROJ/gene_orthogroup_counts.tsv" "one-to-many duplicated orthogroup missing"
assert_grep 'gene_0005.*true' "$PROJ/feature_to_orthogroup_map.tsv" "ambiguous gene mapping not flagged"
assert_grep 'minimum mapped-feature value' "$PROJ/orthology_projection_warnings.tsv" "p-value aggregation warning missing"

SUMMARY="$TMP_DIR/summary"
python3 "$ROOT_DIR/bin/summarize_orthology_projection.py" \
  --omics_samplesheet "$OMICS" \
  --rnaseq_counts "$RNA_COUNTS" \
  --atacseq_counts "$ATAC_COUNTS" \
  --differential_expression "$DE" \
  --differential_accessibility "$DA" \
  --feature_map "$PROJ/feature_to_orthogroup_map.tsv" \
  --gene_orthogroup_counts "$PROJ/gene_orthogroup_counts.tsv" \
  --re_orthogroup_counts "$PROJ/re_orthogroup_counts.tsv" \
  --differential_expression_orthogroups "$PROJ/differential_expression_orthogroups.tsv" \
  --differential_accessibility_orthogroups "$PROJ/differential_accessibility_orthogroups.tsv" \
  --warnings "$PROJ/orthology_projection_warnings.tsv" \
  --output_dir "$SUMMARY" > "$TMP_DIR/summary.out" 2>&1
test -s "$SUMMARY/orthology_projection_summary.tsv"
test -s "$SUMMARY/orthology_outputs_manifest.tsv"
assert_grep 'rnaseq_counts' "$SUMMARY/orthology_projection_summary.tsv" "summary missing RNA count coverage"

if python3 "$ROOT_DIR/bin/project_features_to_orthogroups.py" \
  --omics_samplesheet "$OMICS" \
  --orthologous_genes "$GENES" \
  --orthologous_res "$RES" \
  --omics_types rnaseq \
  --rnaseq_counts "$TMP_DIR/missing_gene_counts.tsv" \
  --output_dir "$TMP_DIR/missing_counts" > "$TMP_DIR/missing_counts.out" 2>&1; then
  cat "$TMP_DIR/missing_counts.out"
  echo "FAIL: missing requested count matrix expected failure" >&2
  exit 1
fi
assert_grep 'RNA-seq count matrix not found' "$TMP_DIR/missing_counts.out" "missing count diagnostic absent"

COUNT_ONLY="$TMP_DIR/count_only"
python3 "$ROOT_DIR/bin/project_features_to_orthogroups.py" \
  --omics_samplesheet "$OMICS" \
  --orthologous_genes "$GENES" \
  --orthologous_res "$RES" \
  --omics_types rnaseq,atacseq \
  --rnaseq_counts "$RNA_COUNTS" \
  --atacseq_counts "$ATAC_COUNTS" \
  --output_dir "$COUNT_ONLY" > "$TMP_DIR/count_only.out" 2>&1
test -s "$COUNT_ONLY/differential_expression_orthogroups.tsv"
test -s "$COUNT_ONLY/differential_accessibility_orthogroups.tsv"
assert_grep 'Differential input absent' "$COUNT_ONLY/orthology_projection_warnings.tsv" "missing optional differential warning absent"

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
test -s "$NF_OUT/orthology/gene_orthogroup_counts.tsv"
test -s "$NF_OUT/orthology/re_orthogroup_counts.tsv"
test -s "$NF_OUT/orthology/summary/orthology_projection_summary.tsv"
assert_grep 'OG_GENE_0001' "$NF_OUT/orthology/gene_orthogroup_counts.tsv" "Nextflow orthology gene rows missing"
assert_grep 'OG_RE_0001' "$NF_OUT/orthology/re_orthogroup_counts.tsv" "Nextflow orthology RE rows missing"

echo "orthology projection tests passed"
