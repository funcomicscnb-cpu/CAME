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

assert_file "$PREP/omics_manifest_prepared.tsv" "prepared real-mode manifest missing"
assert_file "$PREP/rnaseq_manifest.tsv" "prepared RNA manifest missing"
assert_file "$PREP/atacseq_manifest.tsv" "prepared ATAC manifest missing"
assert_file "$PREP/reference_assets.tsv" "prepared reference assets missing"
assert_grep 'smoke_rna_1' "$PREP/rnaseq_manifest.tsv" "RNA sample missing from prepared manifest"
assert_grep 'smoke_atac_1' "$PREP/atacseq_manifest.tsv" "ATAC sample missing from prepared manifest"
assert_grep "$TMP_DIR/reference_cache/smoke_ref/star" "$PREP/rnaseq_manifest.tsv" "STAR cache path not assigned"
assert_grep "$TMP_DIR/reference_cache/smoke_ref/bowtie2/genome" "$PREP/atacseq_manifest.tsv" "Bowtie2 cache path not assigned"

BAD_PAIRED="$TMP_DIR/bad_paired.tsv"
awk -F '\t' 'BEGIN{OFS="\t"} NR==2{$11="paired"; $13=""} {print}' "$DATA_DIR/real_mode_metadata.tsv" > "$BAD_PAIRED"
if "$PYTHON" "$ROOT_DIR/bin/prepare_real_omics_inputs.py" \
  --real_mode_metadata "$BAD_PAIRED" \
  --reference_manifest "$DATA_DIR/reference_manifest.tsv" \
  --omics_types rnaseq \
  --reference_cache_dir "$TMP_DIR/reference_cache_bad_paired" \
  --output_dir "$TMP_DIR/bad_paired_out" > "$TMP_DIR/bad_paired.out" 2>&1; then
  cat "$TMP_DIR/bad_paired.out" >&2
  fail "paired metadata without fastq_2 should fail"
fi
assert_grep 'Paired-end sample requires fastq_2' "$TMP_DIR/bad_paired_out/omics_input_warnings.tsv" "missing fastq_2 diagnostic absent"

BAD_REF="$TMP_DIR/bad_reference.tsv"
awk -F '\t' 'BEGIN{OFS="\t"} NR==2{$14="missing_ref"} {print}' "$DATA_DIR/real_mode_metadata.tsv" > "$BAD_REF"
if "$PYTHON" "$ROOT_DIR/bin/prepare_real_omics_inputs.py" \
  --real_mode_metadata "$BAD_REF" \
  --reference_manifest "$DATA_DIR/reference_manifest.tsv" \
  --omics_types rnaseq \
  --reference_cache_dir "$TMP_DIR/reference_cache_bad_ref" \
  --output_dir "$TMP_DIR/bad_ref_out" > "$TMP_DIR/bad_ref.out" 2>&1; then
  cat "$TMP_DIR/bad_ref.out" >&2
  fail "unresolved reference_id should fail"
fi
assert_grep 'Unknown reference_id' "$TMP_DIR/bad_ref_out/omics_input_warnings.tsv" "unresolved reference diagnostic absent"

MALFORMED="$TMP_DIR/malformed.tsv"
printf 'not_a_real_header\nvalue\n' > "$MALFORMED"
if "$PYTHON" "$ROOT_DIR/bin/prepare_real_omics_inputs.py" \
  --real_mode_metadata "$MALFORMED" \
  --reference_manifest "$DATA_DIR/reference_manifest.tsv" \
  --omics_types rnaseq \
  --reference_cache_dir "$TMP_DIR/reference_cache_malformed" \
  --output_dir "$TMP_DIR/malformed_out" > "$TMP_DIR/malformed.out" 2>&1; then
  cat "$TMP_DIR/malformed.out" >&2
  fail "malformed metadata should fail"
fi
assert_grep 'No real-mode samples matched' "$TMP_DIR/malformed_out/omics_input_warnings.tsv" "malformed manifest diagnostic absent"

VALIDATE_DIR="$TMP_DIR/validate"
mkdir -p "$VALIDATE_DIR/bam" "$VALIDATE_DIR/peaks"
printf 'not-empty\n' > "$VALIDATE_DIR/bam/smoke_rna_1.bam"
printf 'index\n' > "$VALIDATE_DIR/bam/smoke_rna_1.bam.bai"
printf 'feature_id\tfeature_type\tannotation_id\tsmoke_rna_1\n' > "$VALIDATE_DIR/empty_gene_counts.tsv"
if "$PYTHON" "$ROOT_DIR/bin/validate_real_outputs.py" \
  --assay rnaseq \
  --manifest "$PREP/rnaseq_manifest.tsv" \
  --counts "$VALIDATE_DIR/empty_gene_counts.tsv" \
  --bam_dir "$VALIDATE_DIR/bam" \
  --report "$VALIDATE_DIR/empty_counts_validation.tsv" > "$TMP_DIR/empty_counts.out" 2>&1; then
  cat "$VALIDATE_DIR/empty_counts_validation.tsv" >&2
  fail "empty RNA count matrix should fail"
fi
assert_grep 'RNA gene count matrix has no feature rows' "$VALIDATE_DIR/empty_counts_validation.tsv" "empty count matrix diagnostic absent"

printf 'not-empty\n' > "$VALIDATE_DIR/bam/smoke_atac_1.bam"
printf 'index\n' > "$VALIDATE_DIR/bam/smoke_atac_1.bam.bai"
printf 'feature_id\tfeature_type\tchrom\tstart\tend\tsmoke_atac_1\nre_1\tregulatory_element\tchrSmoke\t10\t20\t1\n' > "$VALIDATE_DIR/re_counts.tsv"
printf 'chrSmoke\t10\t5\tbad_peak\n' > "$VALIDATE_DIR/peaks/smoke_atac_1_peaks.narrowPeak"
printf 'chrSmoke\t10\t5\n' > "$VALIDATE_DIR/peak_consensus.bed"
if "$PYTHON" "$ROOT_DIR/bin/validate_real_outputs.py" \
  --assay atacseq \
  --manifest "$PREP/atacseq_manifest.tsv" \
  --counts "$VALIDATE_DIR/re_counts.tsv" \
  --bam_dir "$VALIDATE_DIR/bam" \
  --peaks_dir "$VALIDATE_DIR/peaks" \
  --consensus_peaks "$VALIDATE_DIR/peak_consensus.bed" \
  --report "$VALIDATE_DIR/malformed_bed_validation.tsv" > "$TMP_DIR/malformed_bed.out" 2>&1; then
  cat "$VALIDATE_DIR/malformed_bed_validation.tsv" >&2
  fail "malformed BED intervals should fail"
fi
assert_grep 'invalid interval' "$VALIDATE_DIR/malformed_bed_validation.tsv" "malformed BED diagnostic absent"

printf '' > "$VALIDATE_DIR/peaks/smoke_atac_1_peaks.narrowPeak"
printf '' > "$VALIDATE_DIR/peak_consensus.bed"
if "$PYTHON" "$ROOT_DIR/bin/validate_real_outputs.py" \
  --assay atacseq \
  --manifest "$PREP/atacseq_manifest.tsv" \
  --counts "$VALIDATE_DIR/re_counts.tsv" \
  --bam_dir "$VALIDATE_DIR/bam" \
  --peaks_dir "$VALIDATE_DIR/peaks" \
  --consensus_peaks "$VALIDATE_DIR/peak_consensus.bed" \
  --report "$VALIDATE_DIR/no_peaks_validation.tsv" > "$TMP_DIR/no_peaks.out" 2>&1; then
  cat "$VALIDATE_DIR/no_peaks_validation.tsv" >&2
  fail "zero ATAC peaks should fail"
fi
assert_grep 'MACS3 emitted no peaks' "$VALIDATE_DIR/no_peaks_validation.tsv" "zero-peak diagnostic absent"

echo "real-mode core tests passed"
