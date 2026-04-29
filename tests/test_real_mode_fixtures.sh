#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MODE="soft"

usage() {
  cat <<'EOF'
Usage: tests/test_real_mode_fixtures.sh [--soft|--strict]

--soft     Validate fixtures and skip unavailable executable RNA/ATAC/WGS paths. Default.
--strict   Fail when any required RNA/ATAC/WGS fixture execution tool is absent.
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

PYTHON=${PYTHON:-python3}
PYTHON_BIN=$(command -v "$PYTHON")
DATA_DIR="$TMP_DIR/real_mode_fixtures"
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

assert_file() {
  [ -s "$1" ] || fail "$2"
}

assert_grep() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if ! grep -Eq "$pattern" "$file"; then
    cat "$file" >&2 || true
    fail "$message"
  fi
}

assert_no_error() {
  local file="$1"
  local message="$2"
  if grep -Eq '^ERROR(\t|,)' "$file"; then
    cat "$file" >&2
    fail "$message"
  fi
}

assert_no_status_error() {
  local file="$1"
  local message="$2"
  if awk -F '\t' 'NR == 1 {for (i = 1; i <= NF; i++) h[$i] = i; next} h["overall_status"] && $h["overall_status"] == "ERROR" {bad = 1} END {exit bad ? 0 : 1}' "$file"; then
    cat "$file" >&2
    fail "$message"
  fi
}

run_logged() {
  local label="$1"
  local log="$2"
  shift 2
  if ! "$@" > "$log" 2>&1; then
    printf 'FAIL: %s failed; see %s\n' "$label" "$log" >&2
    tail -n 80 "$log" >&2 || true
    exit 1
  fi
}

tool_status() {
  local tool="$1"
  awk -F '\t' -v tool="$tool" 'NR > 1 && $1 == tool {print $3; exit}' "$TOOL_TSV"
}

tool_found() {
  [ "$(tool_status "$1")" = "found" ]
}

all_tools_found() {
  local tool
  for tool in "$@"; do
    tool_found "$tool" || return 1
  done
  return 0
}

command -v nextflow >/dev/null 2>&1 || fail "Nextflow is required for Stage 28 fixture reference_quality checks"

run_logged "fixture generation" "$TMP_DIR/generate.out" \
  "$PYTHON" "$ROOT_DIR/bin/make_real_mode_fixtures.py" --outdir "$DATA_DIR"
pass "generated Stage 28 fixtures"

VALID_OUT="$TMP_DIR/fixture_validation"
run_logged "fixture validation" "$TMP_DIR/validate.out" \
  "$PYTHON" "$ROOT_DIR/bin/validate_real_mode_fixtures.py" \
    --fixture-dir "$DATA_DIR" \
    --outdir "$VALID_OUT"
assert_file "$VALID_OUT/fixture_validation.tsv" "fixture validation report missing"
assert_file "$VALID_OUT/fixture_manifest.tsv" "fixture manifest missing"
assert_no_error "$VALID_OUT/fixture_validation.tsv" "valid fixtures emitted fixture validation errors"
pass "validated fixture structure and contracts"

BAD_REF="$TMP_DIR/bad_reference_id"
cp -R "$DATA_DIR" "$BAD_REF"
"$PYTHON" - "$BAD_REF/manifests/real_mode_metadata.tsv" <<'PY'
import csv
import sys

path = sys.argv[1]
rows = list(csv.DictReader(open(path), delimiter="\t"))
rows[0]["reference_id"] = "missing_reference"
with open(path, "w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()), delimiter="\t", lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
PY
if "$PYTHON" "$ROOT_DIR/bin/validate_real_mode_fixtures.py" \
  --fixture-dir "$BAD_REF" \
  --outdir "$TMP_DIR/bad_reference_validation" > "$TMP_DIR/bad_reference.out" 2>&1; then
  cat "$TMP_DIR/bad_reference_validation/fixture_validation.tsv" >&2
  fail "malformed fixture manifest should fail"
fi
assert_grep 'Unknown reference_id' "$TMP_DIR/bad_reference_validation/fixture_validation.tsv" "unknown reference_id diagnostic absent"
pass "malformed fixture manifest fails"

BAD_SEQ="$TMP_DIR/bad_seqnames"
cp -R "$DATA_DIR" "$BAD_SEQ"
"$PYTHON" - "$BAD_SEQ/tiny_reference/tiny.gtf" <<'PY'
import sys

path = sys.argv[1]
lines = []
for line in open(path):
    if line.strip() and not line.startswith("#"):
        parts = line.rstrip("\n").split("\t")
        parts[0] = "chrMissing"
        line = "\t".join(parts) + "\n"
    lines.append(line)
open(path, "w").writelines(lines)
PY
if "$PYTHON" "$ROOT_DIR/bin/validate_real_mode_fixtures.py" \
  --fixture-dir "$BAD_SEQ" \
  --outdir "$TMP_DIR/bad_seq_validation" > "$TMP_DIR/bad_seq.out" 2>&1; then
  cat "$TMP_DIR/bad_seq_validation/fixture_validation.tsv" >&2
  fail "FASTA/GTF seqname mismatch should fail"
fi
assert_grep 'Annotation seqnames are absent from FASTA' "$TMP_DIR/bad_seq_validation/fixture_validation.tsv" "FASTA/GTF mismatch diagnostic absent"
pass "FASTA/GTF mismatch fails"

BAD_ABS="$TMP_DIR/bad_absolute_path"
cp -R "$DATA_DIR" "$BAD_ABS"
"$PYTHON" - "$BAD_ABS/manifests/real_mode_metadata.tsv" <<'PY'
import csv
import sys

path = sys.argv[1]
rows = list(csv.DictReader(open(path), delimiter="\t"))
rows[0]["fastq_1"] = "/tmp/came_stage28_absolute.fastq"
with open(path, "w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()), delimiter="\t", lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
PY
if "$PYTHON" "$ROOT_DIR/bin/validate_real_mode_fixtures.py" \
  --fixture-dir "$BAD_ABS" \
  --outdir "$TMP_DIR/bad_absolute_validation" > "$TMP_DIR/bad_absolute.out" 2>&1; then
  cat "$TMP_DIR/bad_absolute_validation/fixture_validation.tsv" >&2
  fail "absolute-path fixture should fail"
fi
assert_grep 'absolute path|must be relative' "$TMP_DIR/bad_absolute_validation/fixture_validation.tsv" "absolute path diagnostic absent"
pass "absolute local path fails"

METADATA_OUT="$TMP_DIR/metadata_validation.tsv"
run_logged "real-mode metadata validation" "$TMP_DIR/metadata_validation.out" \
  "$PYTHON" "$ROOT_DIR/bin/validate_real_mode_metadata.py" \
    --metadata "$DATA_DIR/manifests/real_mode_metadata.tsv" \
    --reference_manifest "$DATA_DIR/manifests/reference_manifest.tsv" \
    --report "$METADATA_OUT"
assert_no_error "$METADATA_OUT" "valid fixture metadata emitted errors"
pass "real-mode metadata validator accepts fixtures"

PREP_OMICS="$TMP_DIR/prepared_omics"
run_logged "real omics input preparation" "$TMP_DIR/prepare_omics.out" \
  "$PYTHON" "$ROOT_DIR/bin/prepare_real_omics_inputs.py" \
    --real_mode_metadata "$DATA_DIR/manifests/real_mode_metadata.tsv" \
    --reference_manifest "$DATA_DIR/manifests/reference_manifest.tsv" \
    --omics_types rnaseq,atacseq \
    --reference_cache_dir "$TMP_DIR/reference_cache" \
    --output_dir "$PREP_OMICS"
assert_file "$PREP_OMICS/rnaseq_manifest.tsv" "prepared RNA fixture manifest missing"
assert_file "$PREP_OMICS/atacseq_manifest.tsv" "prepared ATAC fixture manifest missing"
assert_grep 'tiny_rna_1' "$PREP_OMICS/rnaseq_manifest.tsv" "prepared RNA fixture sample missing"
assert_grep 'tiny_atac_1' "$PREP_OMICS/atacseq_manifest.tsv" "prepared ATAC fixture sample missing"
pass "prepared RNA/ATAC fixture inputs"

PREP_WGS="$TMP_DIR/prepared_wgs"
run_logged "WGS input preparation" "$TMP_DIR/prepare_wgs.out" \
  "$PYTHON" "$ROOT_DIR/bin/prepare_wgs_inputs.py" \
    --wgs_samplesheet "$DATA_DIR/manifests/wgs_samplesheet.csv" \
    --reference_manifest "$DATA_DIR/manifests/reference_manifest.tsv" \
    --wgs_mode real \
    --reference_cache_dir "$TMP_DIR/reference_cache" \
    --output_dir "$PREP_WGS"
assert_file "$PREP_WGS/wgs_manifest.tsv" "prepared WGS fixture manifest missing"
assert_grep 'tiny_wgs_1' "$PREP_WGS/wgs_manifest.tsv" "prepared WGS fixture sample missing"
pass "prepared WGS fixture inputs"

REF_OUT="$TMP_DIR/reference_quality_results"
run_logged "reference_quality fixture run" "$TMP_DIR/reference_quality.out" \
  nextflow -log "$TMP_DIR/reference_quality.nextflow.log" run "$ROOT_DIR" \
    -work-dir "$TMP_DIR/reference_quality_work" \
    --run_stage reference_quality \
    --reference_manifest "$DATA_DIR/manifests/reference_manifest.tsv" \
    --reference_quality_assay rna,atac,wgs \
    --check_paths true \
    --outdir "$REF_OUT"
assert_file "$REF_OUT/reference_quality/reference_quality_summary.tsv" "reference_quality summary missing"
assert_no_status_error "$REF_OUT/reference_quality/reference_quality_summary.tsv" "reference_quality reported fixture errors"
pass "reference_quality accepts fixtures"

if ! "$PYTHON" "$ROOT_DIR/bin/check_real_mode_tools.py" \
  --outdir "$TOOL_DIR" \
  --mode "$MODE" \
  --omics-types rnaseq,atacseq,wgs \
  --project-dir "$ROOT_DIR" > "$TMP_DIR/tool_check.out" 2>&1; then
  cat "$TMP_DIR/tool_check.out" >&2
  [ ! -s "$TOOL_TSV" ] || cat "$TOOL_TSV" >&2
  fail "real-mode tool check failed in $MODE mode"
fi
assert_file "$TOOL_TSV" "tool inventory missing"
pass "wrote real-mode fixture tool inventory"

EMPTY_PATH="$TMP_DIR/empty_path"
mkdir -p "$EMPTY_PATH"
if PATH="$EMPTY_PATH" "$PYTHON_BIN" "$ROOT_DIR/bin/check_real_mode_tools.py" \
  --outdir "$TMP_DIR/strict_missing_tools" \
  --mode strict \
  --omics-types rnaseq,atacseq,wgs \
  --project-dir "$ROOT_DIR" > "$TMP_DIR/strict_missing_tools.out" 2>&1; then
  cat "$TMP_DIR/strict_missing_tools/tool_check.tsv" >&2
  fail "strict tool detection should fail when requested tools are absent"
fi
assert_grep '^fastqc	.*	missing	ERROR' "$TMP_DIR/strict_missing_tools/tool_check.tsv" "strict missing FastQC diagnostic absent"
assert_grep '^STAR	.*	missing	ERROR' "$TMP_DIR/strict_missing_tools/tool_check.tsv" "strict missing STAR diagnostic absent"
assert_grep '^bwa-mem2	.*	missing	ERROR' "$TMP_DIR/strict_missing_tools/tool_check.tsv" "strict missing BWA-MEM2 diagnostic absent"
pass "strict mode fails clearly when tools are absent"

if all_tools_found fastqc STAR featureCounts samtools multiqc; then
  RNA_OUT="$TMP_DIR/rna_results"
  run_logged "RNA real-mode fixture Nextflow run" "$TMP_DIR/rna_nextflow.out" \
    nextflow -log "$TMP_DIR/rna.nextflow.log" run "$ROOT_DIR" \
      -work-dir "$TMP_DIR/rna_work" \
      --run_stage bulk_omics \
      --omics_mode real \
      --omics_stub false \
      --omics_types rnaseq \
      --real_mode_metadata "$DATA_DIR/manifests/real_mode_metadata.tsv" \
      --reference_manifest "$DATA_DIR/manifests/reference_manifest.tsv" \
      --reference_cache_dir "$TMP_DIR/rna_reference_cache" \
      --outdir "$RNA_OUT"
  assert_file "$RNA_OUT/rnaseq/counts/gene_counts.tsv" "RNA fixture gene counts missing"
  assert_grep 'tiny_rna_1' "$RNA_OUT/rnaseq/counts/gene_counts.tsv" "RNA fixture sample absent from gene count header"
  assert_file "$RNA_OUT/rnaseq/validation/rna_real_validation.tsv" "RNA fixture validation report missing"
  assert_no_error "$RNA_OUT/rnaseq/validation/rna_real_validation.tsv" "RNA fixture output validation reported errors"
  pass "RNA real-mode fixture execution"
else
  skip "RNA real-mode fixture execution requires FastQC, STAR, featureCounts, samtools, and MultiQC"
fi

if all_tools_found fastqc bowtie2 bowtie2-build macs3 samtools bedtools multiqc; then
  ATAC_OUT="$TMP_DIR/atac_results"
  run_logged "ATAC real-mode fixture Nextflow run" "$TMP_DIR/atac_nextflow.out" \
    nextflow -log "$TMP_DIR/atac.nextflow.log" run "$ROOT_DIR" \
      -work-dir "$TMP_DIR/atac_work" \
      --run_stage bulk_omics \
      --omics_mode real \
      --omics_stub false \
      --omics_types atacseq \
      --real_mode_metadata "$DATA_DIR/manifests/real_mode_metadata.tsv" \
      --reference_manifest "$DATA_DIR/manifests/reference_manifest.tsv" \
      --reference_cache_dir "$TMP_DIR/atac_reference_cache" \
      --outdir "$ATAC_OUT"
  assert_file "$ATAC_OUT/atacseq/counts/re_counts.tsv" "ATAC fixture RE counts missing"
  assert_grep 'tiny_atac_1' "$ATAC_OUT/atacseq/counts/re_counts.tsv" "ATAC fixture sample absent from RE count header"
  assert_file "$ATAC_OUT/atacseq/validation/atac_real_validation.tsv" "ATAC fixture validation report missing"
  assert_no_error "$ATAC_OUT/atacseq/validation/atac_real_validation.tsv" "ATAC fixture output validation reported errors"
  pass "ATAC real-mode fixture execution"
else
  skip "ATAC real-mode fixture execution requires FastQC, Bowtie2, MACS3, samtools, bedtools, and MultiQC"
fi

if all_tools_found fastqc bwa-mem2 samtools gatk; then
  WGS_OUT="$TMP_DIR/wgs_results"
  run_logged "WGS real-mode fixture Nextflow run" "$TMP_DIR/wgs_nextflow.out" \
    nextflow -log "$TMP_DIR/wgs.nextflow.log" run "$ROOT_DIR" \
      -work-dir "$TMP_DIR/wgs_work" \
      --run_stage wgs_variants \
      --wgs_samplesheet "$DATA_DIR/manifests/wgs_samplesheet.csv" \
      --reference_manifest "$DATA_DIR/manifests/reference_manifest.tsv" \
      --wgs_mode real \
      --allow_no_bqsr true \
      --reference_cache_dir "$TMP_DIR/wgs_reference_cache" \
      --outdir "$WGS_OUT"
  assert_file "$WGS_OUT/wgs/bam/tiny_wgs_1.bam" "WGS fixture BAM missing"
  assert_file "$WGS_OUT/wgs/variants/tiny_wgs_1.vcf.gz" "WGS fixture VCF missing"
  assert_file "$WGS_OUT/wgs/validation/wgs_outputs_validation.tsv" "WGS fixture validation report missing"
  assert_no_error "$WGS_OUT/wgs/validation/wgs_outputs_validation.tsv" "WGS fixture output validation reported errors"
  assert_grep '	real$|	real	' "$WGS_OUT/wgs/qc/variant_qc.tsv" "WGS fixture variant QC did not record real mode"
  pass "WGS real-mode fixture execution"
else
  skip "WGS real-mode fixture execution requires FastQC, BWA-MEM2, samtools, and GATK"
fi

if rg 'wgs_variants' "$ROOT_DIR/workflows/all.nf" >/dev/null 2>&1; then
  fail "wgs_variants should not be included in workflows/all.nf"
fi
pass "WGS remains outside --run_stage all"

pass "real-mode fixture test completed in $MODE mode"
