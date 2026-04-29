#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PYTHON=${PYTHON:-python3}
PYTHON_BIN=$(command -v "$PYTHON")

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
  --omics_types atacseq \
  --reference_cache_dir "$TMP_DIR/reference_cache" \
  --output_dir "$PREP" > "$TMP_DIR/prepare.out" 2>&1

VALID="$TMP_DIR/valid"
mkdir -p "$VALID/bam" "$VALID/logs/samtools" "$VALID/peaks"
printf 'not-empty\n' > "$VALID/bam/smoke_atac_1.bam"
printf 'index\n' > "$VALID/bam/smoke_atac_1.bam.bai"
cat > "$VALID/re_counts.tsv" <<'EOF'
feature_id	feature_type	chrom	start	end	smoke_atac_1
re_000001	regulatory_element	chrSmoke	300	380	5
EOF
cat > "$VALID/peaks/smoke_atac_1_peaks.narrowPeak" <<'EOF'
chrSmoke	300	380	smoke_atac_1_peak	10	.	5	1	1	40
EOF
cat > "$VALID/peak_consensus.bed" <<'EOF'
chrSmoke	300	380
EOF
cat > "$VALID/logs/samtools/smoke_atac_1.idxstats.tsv" <<'EOF'
chrSmoke	1200	5	0
EOF

"$PYTHON" "$ROOT_DIR/bin/collect_real_qc_metrics.py" \
  --assay atacseq \
  --manifest "$PREP/atacseq_manifest.tsv" \
  --counts "$VALID/re_counts.tsv" \
  --bam_dir "$VALID/bam" \
  --logs_dir "$VALID/logs" \
  --peaks_dir "$VALID/peaks" \
  --output "$VALID/atac_qc.tsv" > "$TMP_DIR/collect.out" 2>&1
assert_file "$VALID/atac_qc.tsv" "ATAC QC table missing"
assert_grep 'smoke_atac_1' "$VALID/atac_qc.tsv" "ATAC QC sample missing"

"$PYTHON" "$ROOT_DIR/bin/validate_real_outputs.py" \
  --assay atacseq \
  --manifest "$PREP/atacseq_manifest.tsv" \
  --counts "$VALID/re_counts.tsv" \
  --bam_dir "$VALID/bam" \
  --peaks_dir "$VALID/peaks" \
  --consensus_peaks "$VALID/peak_consensus.bed" \
  --report "$VALID/atac_validation.tsv" > "$TMP_DIR/validate.out" 2>&1
assert_grep 'Validated atacseq outputs' "$VALID/atac_validation.tsv" "ATAC positive validation missing"

if PATH="$TMP_DIR/empty_path" "$PYTHON_BIN" "$ROOT_DIR/bin/check_real_mode_tools.py" \
  --outdir "$TMP_DIR/missing_tools" \
  --mode strict \
  --omics-types atacseq \
  --project-dir "$ROOT_DIR" > "$TMP_DIR/missing_tools.out" 2>&1; then
  cat "$TMP_DIR/missing_tools/tool_check.tsv" >&2
  fail "strict ATAC tool check should fail when Bowtie2 is missing"
fi
assert_grep '^bowtie2	atacseq	missing	ERROR' "$TMP_DIR/missing_tools/tool_check.tsv" "missing Bowtie2 diagnostic absent"
assert_grep '^macs3	atacseq	missing	ERROR' "$TMP_DIR/missing_tools/tool_check.tsv" "missing MACS3 diagnostic absent"

if command -v nextflow >/dev/null 2>&1 && command -v bowtie2 >/dev/null 2>&1 && \
   command -v bowtie2-build >/dev/null 2>&1 && command -v macs3 >/dev/null 2>&1 && \
   command -v fastqc >/dev/null 2>&1 && command -v samtools >/dev/null 2>&1 && \
   command -v bedtools >/dev/null 2>&1 && command -v multiqc >/dev/null 2>&1; then
  NF_OUT="$TMP_DIR/nf_atac"
  if ! nextflow -log "$TMP_DIR/nextflow.log" run "$ROOT_DIR" \
    -work-dir "$TMP_DIR/work" \
    --run_stage bulk_omics \
    --omics_mode real \
    --omics_types atacseq \
    --real_mode_metadata "$DATA_DIR/real_mode_metadata.tsv" \
    --reference_manifest "$DATA_DIR/reference_manifest.tsv" \
    --reference_cache_dir "$TMP_DIR/nf_reference_cache" \
    --outdir "$NF_OUT" > "$TMP_DIR/nextflow.out" 2>&1; then
    tail -n 120 "$TMP_DIR/nextflow.out" >&2 || true
    fail "optional ATAC Nextflow real-mode run failed"
  fi
  assert_file "$NF_OUT/atacseq/counts/re_counts.tsv" "ATAC Nextflow count matrix missing"
  assert_file "$NF_OUT/atacseq/qc/atac_qc.tsv" "ATAC Nextflow QC missing"
else
  echo "SKIP: optional ATAC Nextflow real-mode run requires Nextflow, Bowtie2, MACS3, FastQC, samtools, bedtools, and MultiQC"
fi

echo "real ATAC mode tests passed"
