#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT_DIR/bin/validate_real_mode_metadata.py"
REFS="$ROOT_DIR/assets/example_samplesheets/reference_manifest_minimal.tsv"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

run_validator() {
  metadata="$1"
  report="$2"
  python3 "$VALIDATOR" \
    --metadata "$metadata" \
    --reference_manifest "$REFS" \
    --report "$report" > "$report.out" 2>&1
}

expect_pass() {
  name="$1"
  metadata="$2"
  report="$TMP_DIR/$name.report.tsv"
  if ! run_validator "$metadata" "$report"; then
    cat "$report.out"
    echo "FAIL: $name expected pass" >&2
    exit 1
  fi
  test -s "$report" || {
    echo "FAIL: $name did not write report" >&2
    exit 1
  }
}

expect_fail() {
  name="$1"
  source="$2"
  mutate="$3"
  metadata="$TMP_DIR/$name.metadata.tsv"
  cp "$source" "$metadata"
  sh -c "$mutate" sh "$metadata"
  report="$TMP_DIR/$name.report.tsv"
  if run_validator "$metadata" "$report"; then
    cat "$report"
    echo "FAIL: $name expected failure" >&2
    exit 1
  fi
  grep -q '^ERROR' "$report" || {
    cat "$report"
    echo "FAIL: $name did not emit ERROR records" >&2
    exit 1
  }
}

RNA="$ROOT_DIR/assets/example_samplesheets/real_mode_metadata_rna.tsv"
ATAC="$ROOT_DIR/assets/example_samplesheets/real_mode_metadata_atac.tsv"

expect_pass valid_rna "$RNA"
expect_pass valid_atac "$ATAC"

warning_metadata="$TMP_DIR/warning_only.tsv"
cat > "$warning_metadata" <<'EOF'
sample_id	study_id	species	individual_id	biological_replicate	assay	tissue	condition	platform	library_protocol	read_layout	fastq_1	reference_id	strandedness
rna_warn_1	stage23_example	Mus_musculus	mouse_001	rep1	rna	liver	control	UnknownSeq	Stranded mRNA	single	data/fastq/rna_warn_1.fastq.gz	mmus_ref	reverse
EOF
warning_report="$TMP_DIR/warning_only.report.tsv"
if ! run_validator "$warning_metadata" "$warning_report"; then
  cat "$warning_report.out"
  echo "FAIL: warning-only metadata expected pass" >&2
  exit 1
fi
grep -q '^WARNING' "$warning_report" || {
  cat "$warning_report"
  echo "FAIL: warning-only metadata should emit warnings" >&2
  exit 1
}

expect_fail duplicate_sample_id "$RNA" \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==3{\$1=\"rna_mouse_control_1\"} {print}" "$1" > "$1.tmp" && mv "$1.tmp" "$1"'

expect_fail unknown_assay "$RNA" \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$6=\"proteomics\"} {print}" "$1" > "$1.tmp" && mv "$1.tmp" "$1"'

expect_fail paired_missing_fastq2 "$RNA" \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$13=\"\"} {print}" "$1" > "$1.tmp" && mv "$1.tmp" "$1"'

expect_fail single_with_fastq2 "$RNA" \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$11=\"single\"} {print}" "$1" > "$1.tmp" && mv "$1.tmp" "$1"'

expect_fail rna_missing_strandedness "$RNA" \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$15=\"\"} {print}" "$1" > "$1.tmp" && mv "$1.tmp" "$1"'

expect_fail missing_required_column "$RNA" \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} {for(i=1;i<=NF;i++) if(i!=7) printf \"%s%s\", \$i, (i==NF ? ORS : OFS)}" "$1" > "$1.tmp" && mv "$1.tmp" "$1"'

expect_fail unresolved_reference "$RNA" \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$14=\"missing_ref\"} {print}" "$1" > "$1.tmp" && mv "$1.tmp" "$1"'

expect_fail species_mismatch "$RNA" \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$3=\"Danio_rerio\"} {print}" "$1" > "$1.tmp" && mv "$1.tmp" "$1"'

expect_fail chip_missing_antibody "$RNA" \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$6=\"chip_tf\"; \$15=\"\"} {print}" "$1" > "$1.tmp" && mv "$1.tmp" "$1"'

expect_fail wes_missing_target_bed "$RNA" \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$6=\"wes\"; \$15=\"\"} {print}" "$1" > "$1.tmp" && mv "$1.tmp" "$1"'

expect_fail header_only_metadata "$RNA" \
  'head -n 1 "$1" > "$1.tmp" && mv "$1.tmp" "$1"'

expect_fail malformed_extra_field "$RNA" \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$0=\$0 OFS \"extra\"} {print}" "$1" > "$1.tmp" && mv "$1.tmp" "$1"'

echo "real-mode metadata tests passed"
