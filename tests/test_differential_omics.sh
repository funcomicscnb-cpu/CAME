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

assert_header() {
  file="$1"
  expected="$2"
  actual=$(head -n 1 "$file")
  if [ "$actual" != "$expected" ]; then
    cat "$file"
    echo "FAIL: unexpected header in $file" >&2
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

cat > "$PROFILE" <<'EOF'
study:
  profile_id: diff_test
  name: Differential test
  description: Synthetic differential omics test profile.
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
gene_0002	gene	synthetic_gene_0002	400	410	100	90
gene_0003	gene	synthetic_gene_0003	1	0	1	0
EOF

cat > "$ATAC_COUNTS" <<'EOF'
feature_id	feature_type	chrom	start	end	atac_base_1	atac_base_2	atac_resp_1	atac_resp_2
re_0001	regulatory_element	chr1	100	200	50	60	300	330
re_0002	regulatory_element	chr2	200	300	300	280	40	45
re_0003	regulatory_element	chr3	300	400	0	1	0	1
EOF

PREP="$TMP_DIR/prep"
python3 "$ROOT_DIR/bin/prepare_differential_inputs.py" \
  --omics_samplesheet "$OMICS" \
  --study_profile "$PROFILE" \
  --omics_types rnaseq,atacseq \
  --rnaseq_counts "$RNA_COUNTS" \
  --atacseq_counts "$ATAC_COUNTS" \
  --output_dir "$PREP" > "$TMP_DIR/prepare.out" 2>&1
test -s "$PREP/rnaseq_sample_annotation.tsv"
test -s "$PREP/atacseq_sample_annotation.tsv"
assert_grep 'baseline_vs_response' "$PREP/differential_contrasts.tsv" "prepared contrast missing"

BAD_COUNTS="$TMP_DIR/bad_gene_counts.tsv"
awk 'BEGIN{FS=OFS="\t"} NR==1{$NF="rna_missing"} {print}' "$RNA_COUNTS" > "$BAD_COUNTS"
if python3 "$ROOT_DIR/bin/prepare_differential_inputs.py" \
  --omics_samplesheet "$OMICS" \
  --study_profile "$PROFILE" \
  --omics_types rnaseq \
  --rnaseq_counts "$BAD_COUNTS" \
  --output_dir "$TMP_DIR/bad_prep" > "$TMP_DIR/bad_prep.out" 2>&1; then
  cat "$TMP_DIR/bad_prep.out"
  echo "FAIL: sample mismatch expected failure" >&2
  exit 1
fi
assert_grep 'absent from rnaseq count matrix' "$TMP_DIR/bad_prep/differential_input_warnings.tsv" "missing count sample diagnostic absent"

if python3 "$ROOT_DIR/bin/prepare_differential_inputs.py" \
  --omics_samplesheet "$OMICS" \
  --omics_types rnaseq \
  --rnaseq_counts "$RNA_COUNTS" \
  --baseline_condition missing_condition \
  --response_condition response \
  --baseline_timepoint t0 \
  --response_timepoint t1 \
  --output_dir "$TMP_DIR/missing_contrast" > "$TMP_DIR/missing_contrast.out" 2>&1; then
  cat "$TMP_DIR/missing_contrast.out"
  echo "FAIL: missing contrast label expected failure" >&2
  exit 1
fi
assert_grep 'missing condition' "$TMP_DIR/missing_contrast/differential_input_warnings.tsv" "missing contrast diagnostic absent"

R_OUT="$TMP_DIR/r_out"
Rscript "$ROOT_DIR/bin/run_differential_analysis.R" \
  --counts "$RNA_COUNTS" \
  --samples "$PREP/rnaseq_sample_annotation.tsv" \
  --contrasts "$PREP/rnaseq_contrasts.tsv" \
  --omics_type rnaseq \
  --output_dir "$R_OUT" \
  --min_count 5 \
  --min_total_count 10 \
  --min_samples_per_group 1 \
  --alpha 0.05 \
  --force_fallback true > "$TMP_DIR/r.out" 2>&1
test -s "$R_OUT/differential_results.tsv"
test -s "$R_OUT/normalized_counts.tsv"
test -s "$R_OUT/differential_warnings.tsv"
assert_header "$R_OUT/differential_results.tsv" "omics_type	contrast_name	contrast_type	species	feature_id	feature_type	baseline_label	response_label	n_baseline	n_response	base_mean	baseline_mean	response_mean	log2_fold_change	statistic	p_value	padj	method	status	message	annotation_id"
assert_grep 'filtered_low_count' "$R_OUT/differential_results.tsv" "filtered feature status missing"

if Rscript -e "library(DESeq2)" 2>/dev/null; then
  DESEQ2_OUT="$TMP_DIR/deseq2_out"
  Rscript "$ROOT_DIR/bin/run_differential_analysis.R" \
    --counts "$RNA_COUNTS" \
    --samples "$PREP/rnaseq_sample_annotation.tsv" \
    --contrasts "$PREP/rnaseq_contrasts.tsv" \
    --omics_type rnaseq \
    --output_dir "$DESEQ2_OUT" \
    --min_count 5 \
    --min_total_count 10 \
    --min_samples_per_group 1 \
    --alpha 0.05 > "$TMP_DIR/deseq2_r.out" 2>&1
  deseq2_header=$(head -n 1 "$DESEQ2_OUT/differential_results.tsv")
  fallback_header=$(head -n 1 "$R_OUT/differential_results.tsv")
  if [ "$deseq2_header" != "$fallback_header" ]; then
    echo "FAIL: DESeq2 and fallback differential_results.tsv headers differ" >&2
    echo "DESeq2:   $deseq2_header" >&2
    echo "fallback: $fallback_header" >&2
    exit 1
  fi
fi

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
test -s "$NF_OUT/rnaseq/counts/gene_counts.tsv"
test -s "$NF_OUT/atacseq/counts/re_counts.tsv"

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
test -s "$NF_OUT/differential_omics/rnaseq/differential_results.tsv"
test -s "$NF_OUT/differential_omics/atacseq/differential_results.tsv"
test -s "$NF_OUT/differential_omics/rnaseq/normalized_counts.tsv"
test -s "$NF_OUT/differential_omics/summary/differential_omics_summary.tsv"
test -s "$NF_OUT/differential_omics/summary/differential_outputs_manifest.tsv"
assert_grep 'gene_' "$NF_OUT/differential_omics/rnaseq/differential_results.tsv" "Nextflow RNA differential rows missing"
assert_grep 're_' "$NF_OUT/differential_omics/atacseq/differential_results.tsv" "Nextflow ATAC differential rows missing"

python3 "$ROOT_DIR/bin/prepare_differential_inputs.py" \
  --omics_samplesheet "$OMICS" \
  --omics_types rnaseq \
  --rnaseq_counts "$RNA_COUNTS" \
  --baseline_condition baseline \
  --response_condition baseline \
  --baseline_timepoint t0 \
  --response_timepoint t0 \
  --output_dir "$TMP_DIR/self_contrast" > "$TMP_DIR/self_contrast.out" 2>&1
assert_grep 'identical' "$TMP_DIR/self_contrast/differential_input_warnings.tsv" "self-contrast WARNING not emitted"

echo "differential omics tests passed"
