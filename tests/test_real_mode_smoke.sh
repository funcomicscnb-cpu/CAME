#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MODE="soft"

usage() {
  cat <<'EOF'
Usage: tests/test_real_mode_smoke.sh [--soft|--strict]

--soft     Inventory tools and skip unavailable real-mode execution. This is the default.
--strict   Fail when required tools for requested smoke paths are missing.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --soft) MODE="soft" ;;
    --strict) MODE="strict" ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "FAIL: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

DATA_DIR="$TMP_DIR/data"
TOOL_DIR="$TMP_DIR/tool_check"
TOOL_TSV="$TOOL_DIR/tool_check.tsv"

pass() {
  printf 'PASS: %s\n' "$1"
}

skip() {
  printf 'SKIP: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

tool_status() {
  local tool="$1"
  awk -F '\t' -v tool="$tool" 'NR > 1 && $1 == tool {print $3; exit}' "$TOOL_TSV"
}

tool_found() {
  [ "$(tool_status "$1")" = "found" ]
}

require_file() {
  local path="$1"
  local message="$2"
  [ -s "$path" ] || fail "$message"
}

run_logged() {
  local label="$1"
  local log="$2"
  shift 2
  if ! "$@" > "$log" 2>&1; then
    printf 'FAIL: %s failed; see %s\n' "$label" "$log" >&2
    tail -n 40 "$log" >&2 || true
    exit 1
  fi
}

python3 "$ROOT_DIR/bin/make_real_mode_smoke_data.py" --outdir "$DATA_DIR" > "$TMP_DIR/make_data.out" 2>&1
pass "generated tiny smoke data"

if ! python3 "$ROOT_DIR/bin/check_real_mode_tools.py" \
  --outdir "$TOOL_DIR" \
  --mode "$MODE" \
  --omics-types rnaseq,atacseq \
  --project-dir "$ROOT_DIR" > "$TMP_DIR/tool_check.out" 2>&1; then
  cat "$TMP_DIR/tool_check.out" >&2
  if [ -s "$TOOL_TSV" ]; then
    cat "$TOOL_TSV" >&2
  fi
  fail "real-mode tool check failed in $MODE mode"
fi
require_file "$TOOL_TSV" "tool check TSV was not written"
pass "wrote real-mode tool inventory"

RNA_DIRECT_OK=false
if tool_found fastqc && tool_found STAR && tool_found featureCounts; then
  RNA_WORK="$TMP_DIR/rna_direct"
  mkdir -p "$RNA_WORK/fastqc" "$RNA_WORK/star" "$DATA_DIR/reference/star_index"
  run_logged "RNA FastQC" "$RNA_WORK/fastqc.log" \
    fastqc --outdir "$RNA_WORK/fastqc" "$DATA_DIR/rnaseq/smoke_rna_R1.fastq"
  run_logged "STAR genomeGenerate" "$RNA_WORK/star_index.log" \
    STAR --runThreadN 1 --runMode genomeGenerate \
      --genomeDir "$DATA_DIR/reference/star_index" \
      --genomeFastaFiles "$DATA_DIR/reference/smoke.fa" \
      --sjdbGTFfile "$DATA_DIR/reference/smoke.gtf" \
      --sjdbOverhang 49 \
      --genomeSAindexNbases 3 \
      --genomeChrBinNbits 5
  run_logged "STAR align" "$RNA_WORK/star_align.log" \
    STAR --runThreadN 1 \
      --genomeDir "$DATA_DIR/reference/star_index" \
      --readFilesIn "$DATA_DIR/rnaseq/smoke_rna_R1.fastq" \
      --outSAMtype BAM SortedByCoordinate \
      --outFilterMatchNmin 20 \
      --seedSearchStartLmax 20 \
      --outFileNamePrefix "$RNA_WORK/star/smoke_rna_"
  require_file "$RNA_WORK/star/smoke_rna_Aligned.sortedByCoord.out.bam" "STAR did not write a smoke RNA BAM"
  run_logged "featureCounts" "$RNA_WORK/featureCounts.log" \
    featureCounts -s 0 -a "$DATA_DIR/reference/smoke.gtf" \
      -o "$RNA_WORK/featureCounts.txt" \
      "$RNA_WORK/star/smoke_rna_Aligned.sortedByCoord.out.bam"
  require_file "$RNA_WORK/featureCounts.txt" "featureCounts did not write output"
  grep -q 'smoke_gene_1' "$RNA_WORK/featureCounts.txt" || fail "featureCounts output did not include smoke_gene_1"
  RNA_DIRECT_OK=true
  pass "RNA direct real-mode smoke"
else
  skip "RNA direct real-mode smoke requires FastQC, STAR, and featureCounts"
fi

if tool_found fastqc && tool_found bwa && tool_found samtools && tool_found bedtools; then
  ATAC_WORK="$TMP_DIR/atac_direct"
  mkdir -p "$ATAC_WORK/fastqc"
  run_logged "ATAC FastQC" "$ATAC_WORK/fastqc.log" \
    fastqc --outdir "$ATAC_WORK/fastqc" "$DATA_DIR/atacseq/smoke_atac_R1.fastq"
  run_logged "bwa index" "$ATAC_WORK/bwa_index.log" \
    bwa index "$DATA_DIR/reference/smoke.fa"
  if ! bwa mem "$DATA_DIR/reference/smoke.fa" "$DATA_DIR/atacseq/smoke_atac_R1.fastq" > "$ATAC_WORK/smoke_atac.sam" 2> "$ATAC_WORK/bwa_mem.log"; then
    tail -n 40 "$ATAC_WORK/bwa_mem.log" >&2 || true
    fail "bwa mem failed"
  fi
  if ! samtools view -bS -q 0 "$ATAC_WORK/smoke_atac.sam" | samtools sort -o "$ATAC_WORK/smoke_atac.bam" -; then
    fail "samtools view/sort failed"
  fi
  run_logged "samtools index" "$ATAC_WORK/samtools_index.log" samtools index "$ATAC_WORK/smoke_atac.bam"
  run_logged "samtools quickcheck" "$ATAC_WORK/samtools_quickcheck.log" samtools quickcheck "$ATAC_WORK/smoke_atac.bam"
  if ! bedtools coverage -a "$DATA_DIR/reference/smoke_regions.bed" -b "$ATAC_WORK/smoke_atac.bam" -counts > "$ATAC_WORK/coverage.tsv" 2> "$ATAC_WORK/bedtools_coverage.log"; then
    tail -n 40 "$ATAC_WORK/bedtools_coverage.log" >&2 || true
    fail "bedtools coverage failed"
  fi
  require_file "$ATAC_WORK/coverage.tsv" "bedtools coverage did not write output"
  pass "ATAC direct real-mode smoke"
else
  skip "ATAC direct real-mode smoke requires FastQC, bwa, samtools, and bedtools"
fi

if tool_found hmmratac_resolver; then
  pass "HMMRATAC resolver detected"
else
  skip "HMMRATAC resolver unavailable; soft mode records this as a warning"
fi

if [ "$RNA_DIRECT_OK" = true ] && tool_found multiqc; then
  NF_OUT="$TMP_DIR/nf_results"
  if ! nextflow -log "$TMP_DIR/nextflow.log" run "$ROOT_DIR" \
    -work-dir "$TMP_DIR/nf_work" \
    --run_stage bulk_omics \
    --omics_samplesheet "$DATA_DIR/omics_samplesheet.csv" \
    --reference_manifest "$DATA_DIR/reference_manifest.tsv" \
    --omics_stub false \
    --omics_types rnaseq \
    --outdir "$NF_OUT" > "$TMP_DIR/nextflow.out" 2>&1; then
    tail -n 80 "$TMP_DIR/nextflow.out" >&2 || true
    fail "optional RNA Nextflow real-mode smoke failed"
  fi
  require_file "$NF_OUT/rnaseq/counts/gene_counts.tsv" "Nextflow RNA smoke did not write gene counts"
  pass "optional RNA Nextflow real-mode smoke"
else
  skip "optional RNA Nextflow real-mode smoke requires successful RNA direct smoke and MultiQC"
fi

pass "real-mode smoke test completed in $MODE mode"
