#!/usr/bin/env sh
# Centralised output-contract test: verifies that key TSV outputs are tab-delimited,
# carry the required column headers, and contain at least one data row.
# Runs Python scripts directly (no Nextflow) to stay fast in CI.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

assert_tsv_delimited() {
  file="$1"
  message="$2"
  head -n 1 "$file" | grep -q "	" || {
    echo "FAIL: $message — first line contains no tab; file may be comma-delimited or empty" >&2
    head -n 1 "$file" >&2
    exit 1
  }
}

assert_column() {
  file="$1"
  col="$2"
  message="$3"
  head -n 1 "$file" | tr '\t' '\n' | grep -qx "$col" || {
    echo "FAIL: $message — column '$col' not found" >&2
    head -n 1 "$file" >&2
    exit 1
  }
}

assert_data_rows() {
  file="$1"
  message="$2"
  lines=$(wc -l < "$file")
  if [ "$lines" -lt 2 ]; then
    echo "FAIL: $message — file has no data rows (only $lines line(s))" >&2
    cat "$file" >&2
    exit 1
  fi
}

assert_contract() {
  file="$1"
  label="$2"
  shift 2
  test -s "$file" || { echo "FAIL: $label — file missing or empty: $file" >&2; exit 1; }
  assert_tsv_delimited "$file" "$label delimiter"
  for col; do
    assert_column "$file" "$col" "$label"
  done
  assert_data_rows "$file" "$label data rows"
}

# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------

OMICS="$ROOT_DIR/assets/example_samplesheets/omics_samplesheet.csv"
REFS="$ROOT_DIR/assets/example_samplesheets/reference_manifest.tsv"

# ---------------------------------------------------------------------------
# 1. prepare_omics_inputs → omics_manifest_prepared.tsv
# ---------------------------------------------------------------------------

PREP="$TMP_DIR/prepared"
python3 "$ROOT_DIR/bin/prepare_omics_inputs.py" \
  --omics_samplesheet "$OMICS" \
  --reference_manifest "$REFS" \
  --omics_types rnaseq,atacseq \
  --omics_stub true \
  --output_dir "$PREP" > "$TMP_DIR/prepare.out" 2>&1

assert_contract "$PREP/omics_manifest_prepared.tsv" "omics_manifest_prepared.tsv" \
  sample_id omics_type reference_id species

assert_contract "$PREP/rnaseq_manifest.tsv" "rnaseq_manifest.tsv" \
  sample_id reference_id fastq_1

assert_contract "$PREP/atacseq_manifest.tsv" "atacseq_manifest.tsv" \
  sample_id reference_id fastq_1

# ---------------------------------------------------------------------------
# 2. make_synthetic_counts → gene_counts.tsv  (RNA contract)
# ---------------------------------------------------------------------------

RNA_COUNTS="$TMP_DIR/gene_counts.tsv"
python3 "$ROOT_DIR/bin/make_synthetic_counts.py" \
  --manifest "$PREP/rnaseq_manifest.tsv" \
  --omics_type rnaseq \
  --output "$RNA_COUNTS" \
  --summary "$TMP_DIR/rnaseq_summary.tsv" > "$TMP_DIR/rna_counts.out" 2>&1

assert_contract "$RNA_COUNTS" "gene_counts.tsv" \
  feature_id feature_type annotation_id

assert_contract "$TMP_DIR/rnaseq_summary.tsv" "rnaseq_summary.tsv" \
  sample_id omics_type

# ---------------------------------------------------------------------------
# 3. make_synthetic_counts → re_counts.tsv  (ATAC contract)
# ---------------------------------------------------------------------------

ATAC_COUNTS="$TMP_DIR/re_counts.tsv"
python3 "$ROOT_DIR/bin/make_synthetic_counts.py" \
  --manifest "$PREP/atacseq_manifest.tsv" \
  --omics_type atacseq \
  --output "$ATAC_COUNTS" \
  --summary "$TMP_DIR/atacseq_summary.tsv" > "$TMP_DIR/atac_counts.out" 2>&1

assert_contract "$ATAC_COUNTS" "re_counts.tsv" \
  feature_id feature_type chrom start end

assert_contract "$TMP_DIR/atacseq_summary.tsv" "atacseq_summary.tsv" \
  sample_id omics_type

# ---------------------------------------------------------------------------
# 4. summarize_omics_outputs → omics_run_summary.tsv
# ---------------------------------------------------------------------------

SUMMARY_DIR="$TMP_DIR/summary"
python3 "$ROOT_DIR/bin/summarize_omics_outputs.py" \
  --prepared_manifest "$PREP/omics_manifest_prepared.tsv" \
  --rnaseq_counts "$RNA_COUNTS" \
  --rnaseq_summary "$TMP_DIR/rnaseq_summary.tsv" \
  --atacseq_counts "$ATAC_COUNTS" \
  --atacseq_summary "$TMP_DIR/atacseq_summary.tsv" \
  --warnings "$PREP/omics_input_warnings.tsv" \
  --output_dir "$SUMMARY_DIR" > "$TMP_DIR/summary.out" 2>&1

assert_contract "$SUMMARY_DIR/omics_run_summary.tsv" "omics_run_summary.tsv" \
  sample_id omics_type status

# ---------------------------------------------------------------------------
# 5. run_differential_analysis.R (force_fallback) → differential_results.tsv
# ---------------------------------------------------------------------------

cat > "$TMP_DIR/diff_omics.csv" <<'EOF'
sample_id,species,individual_id,replicate_id,omics_type,condition,timepoint,reference_id,batch,fastq_1,fastq_2,read_layout
rna_base_1,Mus_musculus,mouse_1,rep1,rnaseq,baseline,t0,mmus_ref,batch1,d/r1.fq.gz,d/r1_2.fq.gz,paired-end
rna_base_2,Mus_musculus,mouse_2,rep2,rnaseq,baseline,t0,mmus_ref,batch2,d/r2.fq.gz,d/r2_2.fq.gz,paired-end
rna_resp_1,Mus_musculus,mouse_3,rep3,rnaseq,response,t1,mmus_ref,batch1,d/r3.fq.gz,d/r3_2.fq.gz,paired-end
rna_resp_2,Mus_musculus,mouse_4,rep4,rnaseq,response,t1,mmus_ref,batch2,d/r4.fq.gz,d/r4_2.fq.gz,paired-end
EOF

cat > "$TMP_DIR/rna_for_diff.tsv" <<'EOF'
feature_id	feature_type	annotation_id	rna_base_1	rna_base_2	rna_resp_1	rna_resp_2
gene_0001	gene	sg_0001	100	110	500	520
gene_0002	gene	sg_0002	400	410	100	90
gene_0003	gene	sg_0003	50	60	200	210
EOF

DIFF_PREP="$TMP_DIR/diff_prep"
python3 "$ROOT_DIR/bin/prepare_differential_inputs.py" \
  --omics_samplesheet "$TMP_DIR/diff_omics.csv" \
  --omics_types rnaseq \
  --rnaseq_counts "$TMP_DIR/rna_for_diff.tsv" \
  --baseline_condition baseline \
  --response_condition response \
  --baseline_timepoint t0 \
  --response_timepoint t1 \
  --output_dir "$DIFF_PREP" > "$TMP_DIR/diff_prep.out" 2>&1

DIFF_OUT="$TMP_DIR/diff_out"
Rscript "$ROOT_DIR/bin/run_differential_analysis.R" \
  --counts "$TMP_DIR/rna_for_diff.tsv" \
  --samples "$DIFF_PREP/rnaseq_sample_annotation.tsv" \
  --contrasts "$DIFF_PREP/rnaseq_contrasts.tsv" \
  --omics_type rnaseq \
  --output_dir "$DIFF_OUT" \
  --min_count 1 \
  --min_total_count 2 \
  --min_samples_per_group 1 \
  --alpha 0.05 \
  --force_fallback true > "$TMP_DIR/diff_r.out" 2>&1

assert_contract "$DIFF_OUT/differential_results.tsv" "differential_results.tsv" \
  omics_type contrast_name feature_id feature_type log2_fold_change p_value padj status

assert_contract "$DIFF_OUT/normalized_counts.tsv" "normalized_counts.tsv" \
  feature_id feature_type

# ---------------------------------------------------------------------------
# 6. collect_run_provenance → provenance contract
# ---------------------------------------------------------------------------

PROV_OUT="$TMP_DIR/provenance"
python3 "$ROOT_DIR/bin/collect_run_provenance.py" \
  --run_stage bulk_omics \
  --outdir "$PROV_OUT" \
  --pipeline_version "$(cat "$ROOT_DIR/VERSION" 2>/dev/null || echo 'unknown')" \
  --output_dir "$PROV_OUT" > "$TMP_DIR/prov.out" 2>&1 || true

# provenance is best-effort; only check if file was written
if test -s "$PROV_OUT/run_provenance.tsv"; then
  assert_tsv_delimited "$PROV_OUT/run_provenance.tsv" "run_provenance.tsv delimiter"
  assert_column "$PROV_OUT/run_provenance.tsv" "run_stage" "run_provenance.tsv"
fi

echo "output contract tests passed"
