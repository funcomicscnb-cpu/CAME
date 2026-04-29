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
  --omics_types rnaseq \
  --reference_cache_dir "$TMP_DIR/reference_cache" \
  --output_dir "$PREP" > "$TMP_DIR/prepare.out" 2>&1

VALID="$TMP_DIR/valid"
mkdir -p "$VALID/bam" "$VALID/logs/star"
printf 'not-empty\n' > "$VALID/bam/smoke_rna_1.bam"
printf 'index\n' > "$VALID/bam/smoke_rna_1.bam.bai"
cat > "$VALID/gene_counts.tsv" <<'EOF'
feature_id	feature_type	annotation_id	smoke_rna_1
smoke_gene_1	gene	featureCounts	7
EOF
cat > "$VALID/logs/star/smoke_rna_1.Log.final.out" <<'EOF'
                          Uniquely mapped reads % |	100.00%
EOF
"$PYTHON" "$ROOT_DIR/bin/collect_real_qc_metrics.py" \
  --assay rnaseq \
  --manifest "$PREP/rnaseq_manifest.tsv" \
  --counts "$VALID/gene_counts.tsv" \
  --bam_dir "$VALID/bam" \
  --logs_dir "$VALID/logs" \
  --output "$VALID/alignment_qc.tsv" > "$TMP_DIR/collect.out" 2>&1
assert_file "$VALID/alignment_qc.tsv" "RNA QC table missing"
assert_grep 'smoke_rna_1' "$VALID/alignment_qc.tsv" "RNA QC sample missing"

"$PYTHON" "$ROOT_DIR/bin/validate_real_outputs.py" \
  --assay rnaseq \
  --manifest "$PREP/rnaseq_manifest.tsv" \
  --counts "$VALID/gene_counts.tsv" \
  --bam_dir "$VALID/bam" \
  --report "$VALID/rna_validation.tsv" > "$TMP_DIR/validate.out" 2>&1
assert_grep 'Validated rnaseq outputs' "$VALID/rna_validation.tsv" "RNA positive validation missing"

if PATH="$TMP_DIR/empty_path" "$PYTHON_BIN" "$ROOT_DIR/bin/check_real_mode_tools.py" \
  --outdir "$TMP_DIR/missing_tools" \
  --mode strict \
  --omics-types rnaseq \
  --project-dir "$ROOT_DIR" > "$TMP_DIR/missing_tools.out" 2>&1; then
  cat "$TMP_DIR/missing_tools/tool_check.tsv" >&2
  fail "strict RNA tool check should fail when STAR is missing"
fi
assert_grep '^STAR	rnaseq	missing	ERROR' "$TMP_DIR/missing_tools/tool_check.tsv" "missing STAR diagnostic absent"

if command -v nextflow >/dev/null 2>&1 && command -v STAR >/dev/null 2>&1 && \
   command -v featureCounts >/dev/null 2>&1 && command -v fastqc >/dev/null 2>&1 && \
   command -v samtools >/dev/null 2>&1 && command -v multiqc >/dev/null 2>&1; then
  NF_OUT="$TMP_DIR/nf_rna"
  if ! nextflow -log "$TMP_DIR/nextflow.log" run "$ROOT_DIR" \
    -work-dir "$TMP_DIR/work" \
    --run_stage bulk_omics \
    --omics_mode real \
    --omics_types rnaseq \
    --real_mode_metadata "$DATA_DIR/real_mode_metadata.tsv" \
    --reference_manifest "$DATA_DIR/reference_manifest.tsv" \
    --reference_cache_dir "$TMP_DIR/nf_reference_cache" \
    --outdir "$NF_OUT" > "$TMP_DIR/nextflow.out" 2>&1; then
    tail -n 120 "$TMP_DIR/nextflow.out" >&2 || true
    fail "optional RNA Nextflow real-mode run failed"
  fi
  assert_file "$NF_OUT/rnaseq/counts/gene_counts.tsv" "RNA Nextflow gene counts missing"
  assert_file "$NF_OUT/rnaseq/qc/alignment_qc.tsv" "RNA Nextflow QC missing"
else
  echo "SKIP: optional RNA Nextflow real-mode run requires Nextflow, STAR, featureCounts, FastQC, samtools, and MultiQC"
fi

echo "real RNA mode tests passed"
