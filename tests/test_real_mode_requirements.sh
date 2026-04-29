#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
REFQ_FIXTURE="$ROOT_DIR/assets/test_data/reference_quality"

assert_grep() {
  pattern="$1"
  file="$2"
  message="$3"
  if ! grep -Eiq "$pattern" "$file"; then
    cat "$file"
    echo "FAIL: $message" >&2
    exit 1
  fi
}

assert_file() {
  file="$1"
  message="$2"
  if [ ! -s "$file" ]; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

assert_grep 'Bowtie2' "$ROOT_DIR/docs/real_mode_requirements.md" "requirements doc missing Bowtie2 future default"
assert_grep 'MACS3' "$ROOT_DIR/docs/real_mode_requirements.md" "requirements doc missing MACS3 future default"
assert_grep 'Stage 24' "$ROOT_DIR/docs/real_mode_requirements.md" "requirements doc missing Stage 24 boundary"
assert_grep 'does not add production' "$ROOT_DIR/docs/real_mode_requirements.md" "requirements doc should state production workflows are out of scope"
assert_grep 'assembly_report.*required' "$ROOT_DIR/docs/reference_manifest.md" "reference manifest doc should require assembly_report"
assert_grep 'RNA rows require `strandedness`' "$ROOT_DIR/docs/real_mode_metadata.md" "metadata doc missing RNA requirement"

PYTHONDONTWRITEBYTECODE=1 python3 - "$ROOT_DIR" <<'PY'
import importlib.util
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])

def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

ref_validator = load_module(root / "bin" / "validate_reference_manifest.py", "validate_reference_manifest")
metadata_validator = load_module(root / "bin" / "validate_real_mode_metadata.py", "validate_real_mode_metadata")
ref_schema = json.loads((root / "schemas" / "reference_manifest.schema.json").read_text())
metadata_schema = json.loads((root / "schemas" / "real_mode_metadata.schema.json").read_text())

assert set(ref_schema["required"]) == set(ref_validator.REQUIRED_COLUMNS)
for field, allowed in ref_validator.ENUMS.items():
    assert set(ref_schema["properties"][field]["enum"]) == set(allowed)

assert set(metadata_schema["required"]) == set(metadata_validator.REQUIRED_COLUMNS)
assert set(metadata_schema["properties"]["assay"]["enum"]) == set(metadata_validator.ASSAY_ENUM)
assert set(metadata_schema["properties"]["read_layout"]["enum"]) == set(metadata_validator.READ_LAYOUT_ENUM)
assert set(metadata_schema["properties"]["strandedness"]["enum"]) - {None} == set(metadata_validator.RNA_STRANDEDNESS_ENUM)
PY

NF_OUT="$TMP_DIR/nf_results"
if ! nextflow -log "$TMP_DIR/nextflow.log" run "$ROOT_DIR" \
  -work-dir "$TMP_DIR/work" \
  --run_stage validation \
  --enable_real_mode_validation true \
  --reference_manifest "$ROOT_DIR/assets/example_samplesheets/reference_manifest_minimal.tsv" \
  --real_mode_metadata "$ROOT_DIR/assets/example_samplesheets/real_mode_metadata_rna.tsv" \
  --outdir "$NF_OUT" > "$TMP_DIR/nextflow.out" 2>&1; then
  cat "$TMP_DIR/nextflow.out" >&2
  echo "FAIL: real-mode Nextflow validation-only command failed" >&2
  exit 1
fi
assert_file "$NF_OUT/validation/reference_manifest_real_mode_validation_report.tsv" "Nextflow reference validation report missing"
assert_file "$NF_OUT/validation/real_mode_metadata_validation_report.tsv" "Nextflow metadata validation report missing"

BAD_METADATA="$TMP_DIR/bad_real_mode_metadata.tsv"
awk -F '\t' 'BEGIN{OFS="\t"} NR==2{$6="proteomics"} {print}' \
  "$ROOT_DIR/assets/example_samplesheets/real_mode_metadata_rna.tsv" > "$BAD_METADATA"
NF_BAD_OUT="$TMP_DIR/nf_bad_results"
if nextflow -log "$TMP_DIR/nextflow_bad.log" run "$ROOT_DIR" \
  -work-dir "$TMP_DIR/work_bad" \
  --run_stage bulk_omics \
  --enable_real_mode_validation true \
  --omics_mode real \
  --reference_manifest "$ROOT_DIR/assets/example_samplesheets/reference_manifest.tsv" \
  --real_mode_metadata "$BAD_METADATA" \
  --omics_types rnaseq \
  --outdir "$NF_BAD_OUT" > "$TMP_DIR/nextflow_bad.out" 2>&1; then
  cat "$TMP_DIR/nextflow_bad.out" >&2
  echo "FAIL: invalid real-mode metadata should fail the Nextflow gate" >&2
  exit 1
fi
assert_file "$NF_BAD_OUT/validation/reference_manifest_real_mode_validation_report.tsv" "failed Nextflow run did not publish reference validation report"
assert_file "$NF_BAD_OUT/validation/real_mode_metadata_validation_report.tsv" "failed Nextflow run did not publish metadata validation report"
if [ -e "$NF_BAD_OUT/omics/input/omics_manifest_prepared.tsv" ]; then
  echo "FAIL: bulk omics input preparation ran despite failed real-mode validation" >&2
  exit 1
fi

DATA_DIR="$TMP_DIR/real_mode_smoke"
python3 "$ROOT_DIR/bin/make_real_mode_smoke_data.py" --outdir "$DATA_DIR" > "$TMP_DIR/make_real_mode_smoke_data.out" 2>&1
PREFLIGHT_METADATA="$TMP_DIR/reference_quality_real_mode_metadata.tsv"
cat > "$PREFLIGHT_METADATA" <<EOF
sample_id	study_id	species	individual_id	biological_replicate	assay	tissue	condition	platform	library_protocol	read_layout	fastq_1	fastq_2	reference_id	strandedness	batch	read_length	library_id	run_id	lane	timepoint	notes
tiny_rna_1	stage26_refq	Tiny_mammal	tiny_individual_1	rep1	rna	synthetic	control	Illumina	RNA-seq	single	$DATA_DIR/rnaseq/smoke_rna_R1.fastq		tiny_ref	unstranded	tiny_batch	50	tiny_rna_lib	tiny_run	1	0h	reference quality preflight fixture
EOF
NF_PREFLIGHT_OUT="$TMP_DIR/nf_preflight_results"
if nextflow -log "$TMP_DIR/nextflow_preflight.log" run "$ROOT_DIR" \
  -work-dir "$TMP_DIR/work_preflight" \
  --run_stage bulk_omics \
  --enable_real_mode_validation true \
  --omics_mode real \
  --omics_types rnaseq \
  --rna_backend salmon \
  --reference_manifest "$REFQ_FIXTURE/reference_manifest.tsv" \
  --real_mode_metadata "$PREFLIGHT_METADATA" \
  --check_paths false \
  --outdir "$NF_PREFLIGHT_OUT" > "$TMP_DIR/nextflow_preflight.out" 2>&1; then
  cat "$TMP_DIR/nextflow_preflight.out" >&2
  echo "FAIL: Salmon placeholder should fail after real-mode validation preflight" >&2
  exit 1
fi
assert_file "$NF_PREFLIGHT_OUT/reference_quality/reference_quality_summary.tsv" "real-mode preflight did not publish reference quality summary"
assert_grep 'REFERENCE_QUALITY' "$TMP_DIR/nextflow_preflight.log" "real-mode bulk_omics did not call reference-quality preflight"
assert_grep 'Salmon backend is declared but not implemented' "$TMP_DIR/nextflow_preflight.out" "Salmon placeholder failure absent after preflight"

echo "real-mode requirements tests passed"
