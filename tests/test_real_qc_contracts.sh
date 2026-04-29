#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PYTHON=${PYTHON:-python3}

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_file() {
  [ -s "$1" ] || fail "$2"
}

assert_grep() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if ! grep -Eq "$pattern" "$file"; then
    cat "$file" >&2
    fail "$message"
  fi
}

DATA_DIR="$TMP_DIR/data"
"$PYTHON" "$ROOT_DIR/bin/make_real_mode_smoke_data.py" --outdir "$DATA_DIR" > "$TMP_DIR/make_data.out" 2>&1

PREP="$TMP_DIR/prepared"
"$PYTHON" "$ROOT_DIR/bin/prepare_real_omics_inputs.py" \
  --real_mode_metadata "$DATA_DIR/real_mode_metadata.tsv" \
  --reference_manifest "$DATA_DIR/reference_manifest.tsv" \
  --omics_types rnaseq,atacseq \
  --reference_cache_dir "$TMP_DIR/reference_cache" \
  --output_dir "$PREP" > "$TMP_DIR/prepare.out" 2>&1

RNA="$TMP_DIR/rna"
mkdir -p "$RNA/bam" "$RNA/logs/star" "$RNA/logs/featurecounts"
printf 'bam\n' > "$RNA/bam/smoke_rna_1.bam"
printf 'bai\n' > "$RNA/bam/smoke_rna_1.bam.bai"
cat > "$RNA/gene_counts.tsv" <<'EOF'
feature_id	feature_type	annotation_id	smoke_rna_1
smoke_gene_1	gene	featureCounts	7
EOF
cat > "$RNA/logs/star/smoke_rna_1.Log.final.out" <<'EOF'
Number of input reads |	10
Uniquely mapped reads number |	8
Uniquely mapped reads % |	80.00%
Number of reads mapped to multiple loci |	1
% of reads mapped to multiple loci |	10.00%
EOF
cat > "$RNA/logs/featurecounts/smoke_rna_1.featureCounts.summary.tsv" <<'EOF'
Status	sample.bam
Assigned	7
Unassigned_NoFeatures	3
EOF
"$PYTHON" "$ROOT_DIR/bin/collect_real_qc_metrics.py" \
  --assay rnaseq \
  --manifest "$PREP/rnaseq_manifest.tsv" \
  --counts "$RNA/gene_counts.tsv" \
  --bam_dir "$RNA/bam" \
  --logs_dir "$RNA/logs" \
  --output "$RNA/alignment_qc.tsv" \
  --featurecounts_summary_output "$RNA/featurecounts_summary.tsv" \
  --warnings_output "$RNA/rna_qc_warnings.tsv" > "$TMP_DIR/rna_collect.out" 2>&1
assert_file "$RNA/alignment_qc.tsv" "RNA alignment QC missing"
assert_grep 'assigned_fraction' "$RNA/alignment_qc.tsv" "RNA QC assigned_fraction column missing"
assert_grep 'smoke_rna_1	Assigned	7' "$RNA/featurecounts_summary.tsv" "featureCounts summary not parsed"
"$PYTHON" "$ROOT_DIR/bin/validate_real_outputs.py" \
  --assay rnaseq \
  --manifest "$PREP/rnaseq_manifest.tsv" \
  --counts "$RNA/gene_counts.tsv" \
  --bam_dir "$RNA/bam" \
  --qc "$RNA/alignment_qc.tsv" \
  --featurecounts_summary "$RNA/featurecounts_summary.tsv" \
  --report "$RNA/rna_validation.tsv" > "$TMP_DIR/rna_validate.out" 2>&1
assert_grep 'Validated rnaseq outputs' "$RNA/rna_validation.tsv" "valid RNA outputs were not accepted"

RNA_MISSING_LOG="$TMP_DIR/rna_missing_log"
mkdir -p "$RNA_MISSING_LOG/bam" "$RNA_MISSING_LOG/logs/featurecounts"
cp "$RNA/bam/smoke_rna_1.bam" "$RNA_MISSING_LOG/bam/"
cp "$RNA/bam/smoke_rna_1.bam.bai" "$RNA_MISSING_LOG/bam/"
cp "$RNA/gene_counts.tsv" "$RNA_MISSING_LOG/gene_counts.tsv"
"$PYTHON" "$ROOT_DIR/bin/collect_real_qc_metrics.py" \
  --assay rnaseq \
  --manifest "$PREP/rnaseq_manifest.tsv" \
  --counts "$RNA_MISSING_LOG/gene_counts.tsv" \
  --bam_dir "$RNA_MISSING_LOG/bam" \
  --logs_dir "$RNA_MISSING_LOG/logs" \
  --output "$RNA_MISSING_LOG/alignment_qc.tsv" \
  --warnings_output "$RNA_MISSING_LOG/rna_qc_warnings.tsv" > "$TMP_DIR/rna_missing_collect.out" 2>&1
assert_grep 'STAR Log.final.out not found' "$RNA_MISSING_LOG/rna_qc_warnings.tsv" "missing STAR log warning absent"

BAD_QC="$TMP_DIR/bad_alignment_qc.tsv"
awk 'BEGIN{FS=OFS="\t"} NR==1{for(i=1;i<=NF;i++) if($i=="assigned_reads") c=i} NR==2{$c="not_numeric"} {print}' "$RNA/alignment_qc.tsv" > "$BAD_QC"
if "$PYTHON" "$ROOT_DIR/bin/validate_real_outputs.py" \
  --assay rnaseq \
  --manifest "$PREP/rnaseq_manifest.tsv" \
  --counts "$RNA/gene_counts.tsv" \
  --bam_dir "$RNA/bam" \
  --qc "$BAD_QC" \
  --report "$TMP_DIR/bad_qc_validation.tsv" > "$TMP_DIR/bad_qc.out" 2>&1; then
  cat "$TMP_DIR/bad_qc_validation.tsv" >&2
  fail "malformed RNA QC table should fail validation"
fi
assert_grep 'Non-numeric QC value' "$TMP_DIR/bad_qc_validation.tsv" "malformed QC diagnostic absent"

ATAC="$TMP_DIR/atac"
mkdir -p "$ATAC/bam" "$ATAC/logs/samtools" "$ATAC/peaks"
printf 'bam\n' > "$ATAC/bam/smoke_atac_1.bam"
printf 'bai\n' > "$ATAC/bam/smoke_atac_1.bam.bai"
cat > "$ATAC/re_counts.tsv" <<'EOF'
feature_id	feature_type	chrom	start	end	smoke_atac_1
re_000001	regulatory_element	chrSmoke	300	380	5
EOF
cat > "$ATAC/peaks/smoke_atac_1_peaks.narrowPeak" <<'EOF'
chrSmoke	300	380	smoke_atac_1_peak	10	.	5	1	1	40
EOF
cat > "$ATAC/peak_consensus.bed" <<'EOF'
chrSmoke	300	380
EOF
cat > "$ATAC/logs/samtools/smoke_atac_1.flagstat.txt" <<'EOF'
10 + 0 in total (QC-passed reads + QC-failed reads)
8 + 0 mapped (80.00% : N/A)
1 + 0 duplicates
EOF
cat > "$ATAC/logs/samtools/smoke_atac_1.idxstats.tsv" <<'EOF'
chrSmoke	1200	8	0
EOF
cat > "$ATAC/logs/samtools/smoke_atac_1.stats.txt" <<'EOF'
SN	insert size average:	150
SN	insert size standard deviation:	20
EOF
"$PYTHON" "$ROOT_DIR/bin/collect_real_qc_metrics.py" \
  --assay atacseq \
  --manifest "$PREP/atacseq_manifest.tsv" \
  --counts "$ATAC/re_counts.tsv" \
  --bam_dir "$ATAC/bam" \
  --logs_dir "$ATAC/logs" \
  --peaks_dir "$ATAC/peaks" \
  --output "$ATAC/atac_qc.tsv" \
  --library_complexity_output "$ATAC/library_complexity.tsv" \
  --warnings_output "$ATAC/atac_qc_warnings.tsv" > "$TMP_DIR/atac_collect.out" 2>&1
assert_file "$ATAC/atac_qc.tsv" "ATAC QC table missing"
assert_grep 'frip' "$ATAC/atac_qc.tsv" "ATAC QC FRiP column missing"
assert_grep 'mitochondrial contig unavailable' "$ATAC/atac_qc_warnings.tsv" "missing mitochondrial contig warning absent"
assert_grep 'no_idr' "$ATAC/atac_qc_warnings.tsv" "ATAC no_idr warning absent"
assert_grep 'no_tss_enrichment' "$ATAC/atac_qc_warnings.tsv" "ATAC no_tss_enrichment warning absent"
assert_grep 'no_nrf_pbc' "$ATAC/atac_qc_warnings.tsv" "ATAC no_nrf_pbc warning absent"
assert_grep 'bedtools_merge_consensus' "$ATAC/atac_qc_warnings.tsv" "ATAC bedtools merge warning absent"
"$PYTHON" "$ROOT_DIR/bin/validate_real_outputs.py" \
  --assay atacseq \
  --manifest "$PREP/atacseq_manifest.tsv" \
  --counts "$ATAC/re_counts.tsv" \
  --bam_dir "$ATAC/bam" \
  --peaks_dir "$ATAC/peaks" \
  --consensus_peaks "$ATAC/peak_consensus.bed" \
  --qc "$ATAC/atac_qc.tsv" \
  --library_complexity "$ATAC/library_complexity.tsv" \
  --report "$ATAC/atac_validation.tsv" > "$TMP_DIR/atac_validate.out" 2>&1
assert_grep 'Validated atacseq outputs' "$ATAC/atac_validation.tsv" "valid ATAC outputs were not accepted"

BAD_ATAC_QC="$TMP_DIR/bad_atac_qc.tsv"
awk 'BEGIN{FS=OFS="\t"} NR==1{for(i=1;i<=NF;i++) if($i=="frip") c=i} NR==2{$c="bad_frip"} {print}' "$ATAC/atac_qc.tsv" > "$BAD_ATAC_QC"
if "$PYTHON" "$ROOT_DIR/bin/validate_real_outputs.py" \
  --assay atacseq \
  --manifest "$PREP/atacseq_manifest.tsv" \
  --counts "$ATAC/re_counts.tsv" \
  --bam_dir "$ATAC/bam" \
  --peaks_dir "$ATAC/peaks" \
  --consensus_peaks "$ATAC/peak_consensus.bed" \
  --qc "$BAD_ATAC_QC" \
  --report "$TMP_DIR/bad_atac_qc_validation.tsv" > "$TMP_DIR/bad_atac_qc.out" 2>&1; then
  cat "$TMP_DIR/bad_atac_qc_validation.tsv" >&2
  fail "malformed ATAC QC table should fail validation"
fi
assert_grep 'Non-numeric QC value' "$TMP_DIR/bad_atac_qc_validation.tsv" "malformed ATAC QC diagnostic absent"

SAFE_KEYS="$TMP_DIR/safe_keys"
mkdir -p "$SAFE_KEYS/rna/bam" "$SAFE_KEYS/atac/bam" "$SAFE_KEYS/atac/peaks"
cat > "$SAFE_KEYS/rna_manifest.tsv" <<'EOF'
sample_id	sample_key	omics_type
sample/a	sample_a	rnaseq
EOF
cat > "$SAFE_KEYS/rna_counts.tsv" <<'EOF'
feature_id	feature_type	annotation_id	sample/a
gene1	gene	featureCounts	1
EOF
printf 'bam\n' > "$SAFE_KEYS/rna/bam/sample_a.bam"
printf 'bai\n' > "$SAFE_KEYS/rna/bam/sample_a.bam.bai"
"$PYTHON" "$ROOT_DIR/bin/validate_real_outputs.py" \
  --assay rnaseq \
  --manifest "$SAFE_KEYS/rna_manifest.tsv" \
  --counts "$SAFE_KEYS/rna_counts.tsv" \
  --bam_dir "$SAFE_KEYS/rna/bam" \
  --report "$SAFE_KEYS/rna_validation.tsv" > "$TMP_DIR/safe_rna_validate.out" 2>&1
assert_grep 'Validated rnaseq outputs' "$SAFE_KEYS/rna_validation.tsv" "safe RNA sample_key BAM lookup failed"

cat > "$SAFE_KEYS/atac_manifest.tsv" <<'EOF'
sample_id	sample_key	omics_type
sample/a	sample_a	atacseq
EOF
cat > "$SAFE_KEYS/atac_counts.tsv" <<'EOF'
feature_id	feature_type	chrom	start	end	sample/a
re_000001	regulatory_element	chr1	10	20	1
EOF
cat > "$SAFE_KEYS/atac/consensus.bed" <<'EOF'
chr1	10	20
EOF
cat > "$SAFE_KEYS/atac/peaks/sample_a_peaks.narrowPeak" <<'EOF'
chr1	10	20	peak1	1	.	1	1	1	5
EOF
printf 'bam\n' > "$SAFE_KEYS/atac/bam/sample_a.bam"
printf 'bai\n' > "$SAFE_KEYS/atac/bam/sample_a.bam.bai"
"$PYTHON" "$ROOT_DIR/bin/validate_real_outputs.py" \
  --assay atacseq \
  --manifest "$SAFE_KEYS/atac_manifest.tsv" \
  --counts "$SAFE_KEYS/atac_counts.tsv" \
  --bam_dir "$SAFE_KEYS/atac/bam" \
  --peaks_dir "$SAFE_KEYS/atac/peaks" \
  --consensus_peaks "$SAFE_KEYS/atac/consensus.bed" \
  --report "$SAFE_KEYS/atac_validation.tsv" > "$TMP_DIR/safe_atac_validate.out" 2>&1
assert_grep 'Validated atacseq outputs' "$SAFE_KEYS/atac_validation.tsv" "safe ATAC sample_key BAM/peak lookup failed"

echo "real QC contract tests passed"
