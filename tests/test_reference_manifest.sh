#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT_DIR/bin/validate_reference_manifest.py"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

run_validator() {
  manifest="$1"
  report="$2"
  python3 "$VALIDATOR" \
    --manifest "$manifest" \
    --assays rna,atac,wgs,wes \
    --report "$report" > "$report.out" 2>&1
}

expect_pass() {
  name="$1"
  manifest="$2"
  report="$TMP_DIR/$name.tsv"
  if ! run_validator "$manifest" "$report"; then
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
  mutate="$2"
  manifest="$TMP_DIR/$name.manifest.tsv"
  cp "$ROOT_DIR/assets/example_samplesheets/reference_manifest_minimal.tsv" "$manifest"
  sh -c "$mutate" sh "$manifest"
  report="$TMP_DIR/$name.report.tsv"
  if run_validator "$manifest" "$report"; then
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

expect_pass full_manifest "$ROOT_DIR/assets/example_samplesheets/reference_manifest.tsv"

minimal_report="$TMP_DIR/minimal.report.tsv"
if ! run_validator "$ROOT_DIR/assets/example_samplesheets/reference_manifest_minimal.tsv" "$minimal_report"; then
  cat "$minimal_report.out"
  echo "FAIL: minimal manifest expected warning-only pass" >&2
  exit 1
fi
grep -q '^WARNING' "$minimal_report" || {
  cat "$minimal_report"
  echo "FAIL: minimal manifest should emit warnings" >&2
  exit 1
}

expect_fail duplicate_reference_id \
  'tail -n 1 "$1" >> "$1"'

expect_fail missing_required_column \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} {for(i=1;i<=NF;i++) if(i!=8) printf \"%s%s\", \$i, (i==NF || (i==NF-1 && NF==8) ? ORS : OFS)}" "$1" > "$1.tmp" && mv "$1.tmp" "$1"'

expect_fail invalid_enum \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$12=\"invalid_format\"} {print}" "$1" > "$1.tmp" && mv "$1.tmp" "$1"'

expect_fail conflicting_species_assembly \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{print; \$1=\"mmus_alt\"; \$4=\"DifferentAssembly\"; \$5=\"GCF_999999999.1\"; print; next} {print}" "$1" > "$1.tmp" && mv "$1.tmp" "$1"'

expect_fail header_only_manifest \
  'head -n 1 "$1" > "$1.tmp" && mv "$1.tmp" "$1"'

expect_fail malformed_extra_field \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$0=\$0 OFS \"extra\"} {print}" "$1" > "$1.tmp" && mv "$1.tmp" "$1"'

echo "reference manifest tests passed"
