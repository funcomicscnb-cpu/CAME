#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT_DIR/bin/validate_ceeg_model_bundle.py"
IMPORTER="$ROOT_DIR/bin/import_ceeg_model_bundle.py"
SUMMARIZER="$ROOT_DIR/bin/summarize_ceeg_compatibility.py"
FIXTURE_DIR="$ROOT_DIR/assets/example_samplesheets/ceeg_model_bundle"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

write_valid_bundle() {
  dir="$1"; mkdir -p "$dir"
  cp "$FIXTURE_DIR"/*.tsv "$dir/"
}

run_validator() {
  dir="$1"; shift || true
  python3 "$VALIDATOR" "$dir" --report "$dir/report.tsv" "$@" > "$dir/stdout.txt" 2>&1
}
run_importer() {
  bundle="$1"; outdir="$2"; mkdir -p "$outdir"
  python3 "$IMPORTER" --bundle "$bundle" --outdir "$outdir" > "$outdir/stdout.txt" 2>&1
}
run_summarizer() {
  import_dir="$1"; outdir="$2"; mkdir -p "$outdir"
  python3 "$SUMMARIZER" --import-dir "$import_dir" --outdir "$outdir" > "$outdir/stdout.txt" 2>&1
}
assert_no_import_outputs() {
  outdir="$1"
  for f in ceeg_imported_nodes.tsv ceeg_imported_edges.tsv ceeg_imported_evidence.tsv ceeg_imported_metrics.tsv; do
    if [ -f "$outdir/$f" ]; then
      echo "FAIL: importer wrote $f despite invalid input" >&2; exit 1
    fi
  done
}

expect_pass() {
  name="$1"; dir="$TMP_DIR/$name"; write_valid_bundle "$dir"
  if ! run_validator "$dir"; then
    cat "$dir/stdout.txt"
    echo "FAIL: $name expected pass" >&2; exit 1
  fi
}
expect_fail() {
  name="$1"; mutate="$2"; dir="$TMP_DIR/$name"; write_valid_bundle "$dir"
  sh -c "$mutate" sh "$dir"
  if run_validator "$dir"; then
    cat "$dir/stdout.txt"
    echo "FAIL: $name expected failure" >&2; exit 1
  fi
}
expect_rule() {
  name="$1"; rule="$2"; dir="$TMP_DIR/$name"
  if ! grep -q "$rule" "$dir/report.tsv"; then
    cat "$dir/report.tsv"
    echo "FAIL: $name missing rule $rule" >&2; exit 1
  fi
}

# ── 1. valid bundle passes ────────────────────────────────────────────────────

expect_pass valid_bundle

# ── 2. report header ─────────────────────────────────────────────────────────

if ! head -n 1 "$TMP_DIR/valid_bundle/report.tsv" | grep -q 'severity	rule_id	source	field	row	message	suggestion'; then
  cat "$TMP_DIR/valid_bundle/report.tsv"
  echo "FAIL: validation report header missing expected columns" >&2; exit 1
fi

# ── 3. missing file ───────────────────────────────────────────────────────────
# nodes.tsv is a required file; removing it triggers CEEG_BUNDLE_MISSING_FILE

expect_fail missing_file 'rm "$1/nodes.tsv"'
expect_rule  missing_file CEEG_BUNDLE_MISSING_FILE

# ── 4. missing required column ───────────────────────────────────────────────
# Remove the evidence_status header from nodes.tsv (tab-prefixed in header row)

expect_fail missing_required_column \
  'awk "NR==1{sub(/\tevidence_status/,\"\")} {print}" "$1/nodes.tsv" > "$1/tmp" && mv "$1/tmp" "$1/nodes.tsv"'
expect_rule  missing_required_column CEEG_BUNDLE_MISSING_REQUIRED_COLUMN

# ── 5. invalid data_mode ─────────────────────────────────────────────────────
# nodes.tsv: col 4 is data_mode; NR==2 is the biological_system node (bulk)

expect_fail invalid_data_mode \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$4=\"proteomics\"} {print}" "$1/nodes.tsv" > "$1/tmp" && mv "$1/tmp" "$1/nodes.tsv"'
expect_rule  invalid_data_mode CEEG_BUNDLE_INVALID_DATA_MODE

# ── 6. invalid evidence_status ───────────────────────────────────────────────
# nodes.tsv: col 5 is evidence_status; NR==3 is RE:obs_001 (observed)

expect_fail invalid_evidence_status \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==3{\$5=\"inferred\"} {print}" "$1/nodes.tsv" > "$1/tmp" && mv "$1/tmp" "$1/nodes.tsv"'
expect_rule  invalid_evidence_status CEEG_BUNDLE_INVALID_EVIDENCE_STATUS

# ── 7. invalid mapping_state ─────────────────────────────────────────────────
# nodes.tsv: col 7 is mapping_state; NR==2 has mappable

expect_fail invalid_mapping_state \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$7=\"ambiguous\"} {print}" "$1/nodes.tsv" > "$1/tmp" && mv "$1/tmp" "$1/nodes.tsv"'
expect_rule  invalid_mapping_state CEEG_BUNDLE_INVALID_MAPPING_STATE

# ── 8. unknown represented as absent ─────────────────────────────────────────
# evidence.tsv: col 6 is unknown_absent; NR==6 is EV:unk_001 (unknown_unmappable node)
# Setting absent on an unknown_unmappable node triggers CEEG_BUNDLE_UNKNOWN_REPRESENTED_AS_ABSENT

expect_fail unknown_as_absent \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==6{\$6=\"absent\"} {print}" "$1/evidence.tsv" > "$1/tmp" && mv "$1/tmp" "$1/evidence.tsv"'
expect_rule  unknown_as_absent CEEG_BUNDLE_UNKNOWN_REPRESENTED_AS_ABSENT

# ── 9. missing biological_system ─────────────────────────────────────────────
# nodes.tsv: col 3 is biological_system; NR==2 is the first data row

expect_fail missing_biological_system \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$3=\"\"} {print}" "$1/nodes.tsv" > "$1/tmp" && mv "$1/tmp" "$1/nodes.tsv"'
expect_rule  missing_biological_system CEEG_BUNDLE_MISSING_BIOLOGICAL_SYSTEM

# ── 10. duplicate node_id ────────────────────────────────────────────────────
# Append a row reusing the first data row's node_id (BS:generic_immune)

expect_fail duplicate_node_id \
  'printf "BS:generic_immune\tbiological_system\tgeneric_immune\tbulk\tobserved\tnone\tmappable\tDuplicate\tmulti-species\tdup\n" >> "$1/nodes.tsv"'
expect_rule  duplicate_node_id CEEG_BUNDLE_DUPLICATE_NODE_ID

# ── 11. unknown_absent must not accept mapping_state token 'unknown_unmappable' ─
# Bug fix: VALID_UNKNOWN_ABSENT previously included "unknown_unmappable" (a mapping_state
# value), allowing it through validation. Evidence col 6 is unknown_absent; NR==2 is EV:obs_001.

expect_fail unknown_absent_wrong_token \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$6=\"unknown_unmappable\"} {print}" \
   "$1/evidence.tsv" > "$1/tmp" && mv "$1/tmp" "$1/evidence.tsv"'
expect_rule  unknown_absent_wrong_token CEEG_BUNDLE_INVALID_UNKNOWN_ABSENT

# ── 12. mappable node must not have unknown_absent=unknown ───────────────────
# Bug fix: converse contract; a successfully mapped node has a determined state.
# NR==2 is EV:obs_001 whose node RE:obs_001 has mapping_state=mappable.

expect_fail mappable_with_unknown_absent \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$6=\"unknown\"} {print}" \
   "$1/evidence.tsv" > "$1/tmp" && mv "$1/tmp" "$1/evidence.tsv"'
expect_rule  mappable_with_unknown_absent CEEG_BUNDLE_MAPPABLE_UNKNOWN_ABSENT

# ── 13. missing nodes.tsv must not cascade into UNRESOLVED_NODE_REF errors ───
# Robustness fix: when nodes.tsv is absent, cross-reference checks are suppressed.
# Report should contain CEEG_BUNDLE_MISSING_FILE but no CEEG_BUNDLE_UNRESOLVED_NODE_REF.

expect_fail missing_nodes_no_cascade 'rm "$1/nodes.tsv"'
expect_rule  missing_nodes_no_cascade CEEG_BUNDLE_MISSING_FILE
dir="$TMP_DIR/missing_nodes_no_cascade"
if grep -q 'CEEG_BUNDLE_UNRESOLVED_NODE_REF' "$dir/report.tsv"; then
  cat "$dir/report.tsv"
  echo "FAIL: missing nodes.tsv produced spurious CEEG_BUNDLE_UNRESOLVED_NODE_REF errors" >&2; exit 1
fi

# ── 14. non-float ceeg_score must be rejected ─────────────────────────────────
# metrics col 4 is ceeg_score; NR==2 is the first data row (RE:obs_001)

expect_fail nonfloat_score \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$4=\"very_high\"} {print}" \
   "$1/metrics.tsv" > "$1/tmp" && mv "$1/tmp" "$1/metrics.tsv"'
expect_rule  nonfloat_score CEEG_BUNDLE_INVALID_SCORE_FORMAT

# ── 15. non-integer n_supporting_species must be rejected ────────────────────
# metrics col 6 is n_supporting_species; NR==2 is the first data row

expect_fail nonint_species \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$6=\"many\"} {print}" \
   "$1/metrics.tsv" > "$1/tmp" && mv "$1/tmp" "$1/metrics.tsv"'
expect_rule  nonint_species CEEG_BUNDLE_INVALID_SPECIES_COUNT_FORMAT

# ── 16. duplicate edge_id must be rejected ───────────────────────────────────

expect_fail duplicate_edge_id \
  'printf "E:proj_d_001\tRE:obs_001\tRE:proj_i_001\tregulatory_projection\tdirect_alignment\tgeneric_immune\t0.5\tdup\n" >> "$1/edges.tsv"'
expect_rule  duplicate_edge_id CEEG_BUNDLE_DUPLICATE_EDGE_ID

# ── 17. evidence referencing a nonexistent edge must be rejected ──────────────
# evidence col 3 is edge_id; NR==2 is EV:obs_001

expect_fail unresolved_edge_ref \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$3=\"E:nonexistent\"} {print}" \
   "$1/evidence.tsv" > "$1/tmp" && mv "$1/tmp" "$1/evidence.tsv"'
expect_rule  unresolved_edge_ref CEEG_BUNDLE_UNRESOLVED_EDGE_REF

# ── 18. multiple projection edges to the same target must be rejected ─────────
# Add a second regulatory_projection to RE:proj_d_001 (already targeted by E:proj_d_001)

expect_fail duplicate_projection_target \
  'printf "E:dup_target\tRE:obs_001\tRE:proj_d_001\tregulatory_projection\tdirect_alignment\tgeneric_immune\t0.5\tdup\n" >> "$1/edges.tsv"'
expect_rule  duplicate_projection_target CEEG_BUNDLE_DUPLICATE_PROJECTION_TARGET

# ── 19. self-referencing projection edge must be rejected ─────────────────────

expect_fail self_ref_edge \
  'printf "E:self\tRE:obs_001\tRE:obs_001\tregulatory_projection\tdirect_alignment\tgeneric_immune\t1.0\tself\n" >> "$1/edges.tsv"'
expect_rule  self_ref_edge CEEG_BUNDLE_SELF_REFERENCE_EDGE

# ── 20. duplicate evidence_id must be rejected ────────────────────────────────

expect_fail duplicate_evidence_id \
  'printf "EV:obs_001\tRE:obs_001\t\tdirect_observation\tbulk\tabsent\tceeg_v0.1:assay:ATAC-seq\tdup\n" >> "$1/evidence.tsv"'
expect_rule  duplicate_evidence_id CEEG_BUNDLE_DUPLICATE_EVIDENCE_ID

# ── 21. duplicate node_id in metrics must be rejected ────────────────────────

expect_fail duplicate_metrics_node \
  'printf "RE:obs_001\tgeneric_immune\tbulk\t0.91\t1\t3\tdup\n" >> "$1/metrics.tsv"'
expect_rule  duplicate_metrics_node CEEG_BUNDLE_DUPLICATE_METRICS_NODE

# ── 22–24. importer: all 4 output files, ceeg_bundle_source, unknown preserved ─

IMPORT_OUT="$TMP_DIR/import_out"
if ! run_importer "$FIXTURE_DIR" "$IMPORT_OUT"; then
  cat "$IMPORT_OUT/stdout.txt"
  echo "FAIL: importer failed on valid bundle" >&2; exit 1
fi

for f in ceeg_imported_nodes.tsv ceeg_imported_edges.tsv ceeg_imported_evidence.tsv ceeg_imported_metrics.tsv; do
  if [ ! -f "$IMPORT_OUT/$f" ]; then
    echo "FAIL: importer did not produce $f" >&2; exit 1
  fi
done

if ! head -n 1 "$IMPORT_OUT/ceeg_imported_nodes.tsv" | grep -q 'ceeg_bundle_source'; then
  head -n 1 "$IMPORT_OUT/ceeg_imported_nodes.tsv"
  echo "FAIL: ceeg_imported_nodes.tsv missing ceeg_bundle_source column" >&2; exit 1
fi

# Verify unknown_absent=unknown is preserved verbatim (not collapsed to absent or "")
if ! awk -F'\t' 'NR==1{for(i=1;i<=NF;i++)if($i=="unknown_absent"){col=i}} NR>1&&col&&$col=="unknown"{found=1} END{exit !found}' \
     "$IMPORT_OUT/ceeg_imported_evidence.tsv"; then
  cat "$IMPORT_OUT/ceeg_imported_evidence.tsv"
  echo "FAIL: unknown_absent=unknown not preserved verbatim in imported evidence" >&2; exit 1
fi

# ── 25. ceeg_bundle_source present in all 4 output files ─────────────────────

for f in ceeg_imported_nodes.tsv ceeg_imported_edges.tsv ceeg_imported_evidence.tsv ceeg_imported_metrics.tsv; do
  if ! head -n 1 "$IMPORT_OUT/$f" | grep -q 'ceeg_bundle_source'; then
    head -n 1 "$IMPORT_OUT/$f"
    echo "FAIL: $f missing ceeg_bundle_source column" >&2; exit 1
  fi
done

# ── 26. row counts match source (no silent row dropping) ─────────────────────

check_row_count() {
  source_file="$1"; imported_file="$2"
  expected=$(awk 'NR>1{c++} END{print c+0}' "$FIXTURE_DIR/$source_file")
  actual=$(awk 'NR>1{c++} END{print c+0}' "$IMPORT_OUT/$imported_file")
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: $imported_file expected $expected data rows from $source_file, got $actual" >&2; exit 1
  fi
}
check_row_count nodes.tsv    ceeg_imported_nodes.tsv
check_row_count edges.tsv    ceeg_imported_edges.tsv
check_row_count evidence.tsv ceeg_imported_evidence.tsv
check_row_count metrics.tsv  ceeg_imported_metrics.tsv

# ── 27. unknown_absent=absent preserved verbatim ─────────────────────────────

if ! awk -F'\t' 'NR==1{for(i=1;i<=NF;i++)if($i=="unknown_absent"){col=i}} NR>1&&col&&$col=="absent"{found=1} END{exit !found}' \
     "$IMPORT_OUT/ceeg_imported_evidence.tsv"; then
  cat "$IMPORT_OUT/ceeg_imported_evidence.tsv"
  echo "FAIL: unknown_absent=absent not preserved verbatim in imported evidence" >&2; exit 1
fi

# ── 28. data_mode single_cell and hybrid preserved verbatim ──────────────────

for mode in single_cell hybrid; do
  if ! awk -F'\t' -v m="$mode" \
       'NR==1{for(i=1;i<=NF;i++)if($i=="data_mode"){col=i}} NR>1&&col&&$col==m{found=1} END{exit !found}' \
       "$IMPORT_OUT/ceeg_imported_evidence.tsv"; then
    cat "$IMPORT_OUT/ceeg_imported_evidence.tsv"
    echo "FAIL: data_mode=$mode not preserved verbatim in imported evidence" >&2; exit 1
  fi
done

# ── 29. invariant violation blocks import; no output files written ────────────
# Bundle where unknown_unmappable node has unknown_absent=absent triggers invariant check.
# Importer must exit non-zero and write NO output files.

INV_DIR="$TMP_DIR/inv_bundle"
write_valid_bundle "$INV_DIR"
awk -F'\t' 'BEGIN{OFS="\t"} NR==6{$6="absent"} {print}' \
  "$INV_DIR/evidence.tsv" > "$INV_DIR/tmp" && mv "$INV_DIR/tmp" "$INV_DIR/evidence.tsv"
INV_OUT="$TMP_DIR/inv_out"
mkdir -p "$INV_OUT"
if python3 "$IMPORTER" --bundle "$INV_DIR" --outdir "$INV_OUT" > "$INV_OUT/stdout.txt" 2>&1; then
  cat "$INV_OUT/stdout.txt"
  echo "FAIL: importer should have exited non-zero on invariant violation" >&2; exit 1
fi
for f in ceeg_imported_nodes.tsv ceeg_imported_edges.tsv ceeg_imported_evidence.tsv ceeg_imported_metrics.tsv; do
  if [ -f "$INV_OUT/$f" ]; then
    echo "FAIL: importer wrote $f despite invariant violation (no outputs must be written)" >&2; exit 1
  fi
done

# ── 30. importer rejects malformed source row; no partial outputs ─────────────

IMP_BAD_ROW="$TMP_DIR/import_bad_row_bundle"
write_valid_bundle "$IMP_BAD_ROW"
awk -F'\t' 'BEGIN{OFS="\t"} NR==3{$0=$0 "\textra_field"} {print}' \
  "$IMP_BAD_ROW/nodes.tsv" > "$IMP_BAD_ROW/tmp" && mv "$IMP_BAD_ROW/tmp" "$IMP_BAD_ROW/nodes.tsv"
IMP_BAD_ROW_OUT="$TMP_DIR/import_bad_row_out"
mkdir -p "$IMP_BAD_ROW_OUT"
if python3 "$IMPORTER" --bundle "$IMP_BAD_ROW" --outdir "$IMP_BAD_ROW_OUT" \
   > "$IMP_BAD_ROW_OUT/stdout.txt" 2>&1; then
  cat "$IMP_BAD_ROW_OUT/stdout.txt"
  echo "FAIL: importer accepted malformed source row with extra field" >&2; exit 1
fi
if ! grep -q 'malformed TSV row' "$IMP_BAD_ROW_OUT/stdout.txt"; then
  cat "$IMP_BAD_ROW_OUT/stdout.txt"
  echo "FAIL: importer did not clearly report malformed source row" >&2; exit 1
fi
assert_no_import_outputs "$IMP_BAD_ROW_OUT"

# ── 31. importer rejects missing required source columns; no partial outputs ──

IMP_MISSING_COL="$TMP_DIR/import_missing_col_bundle"
write_valid_bundle "$IMP_MISSING_COL"
awk 'NR==1{sub(/\tevidence_status/,"")} {print}' \
  "$IMP_MISSING_COL/nodes.tsv" > "$IMP_MISSING_COL/tmp" && mv "$IMP_MISSING_COL/tmp" "$IMP_MISSING_COL/nodes.tsv"
IMP_MISSING_COL_OUT="$TMP_DIR/import_missing_col_out"
mkdir -p "$IMP_MISSING_COL_OUT"
if python3 "$IMPORTER" --bundle "$IMP_MISSING_COL" --outdir "$IMP_MISSING_COL_OUT" \
   > "$IMP_MISSING_COL_OUT/stdout.txt" 2>&1; then
  cat "$IMP_MISSING_COL_OUT/stdout.txt"
  echo "FAIL: importer accepted missing required column" >&2; exit 1
fi
if ! grep -q 'missing required column' "$IMP_MISSING_COL_OUT/stdout.txt"; then
  cat "$IMP_MISSING_COL_OUT/stdout.txt"
  echo "FAIL: importer did not clearly report missing required column" >&2; exit 1
fi
assert_no_import_outputs "$IMP_MISSING_COL_OUT"

# ── 32. importer rejects duplicate source IDs; no partial outputs ─────────────

IMP_DUP_ID="$TMP_DIR/import_duplicate_id_bundle"
write_valid_bundle "$IMP_DUP_ID"
printf "RE:obs_001\tregulatory_element\tgeneric_immune\tbulk\tobserved\tnone\tmappable\tDuplicate\tMus_musculus\tdup\n" \
  >> "$IMP_DUP_ID/nodes.tsv"
IMP_DUP_ID_OUT="$TMP_DIR/import_duplicate_id_out"
mkdir -p "$IMP_DUP_ID_OUT"
if python3 "$IMPORTER" --bundle "$IMP_DUP_ID" --outdir "$IMP_DUP_ID_OUT" \
   > "$IMP_DUP_ID_OUT/stdout.txt" 2>&1; then
  cat "$IMP_DUP_ID_OUT/stdout.txt"
  echo "FAIL: importer accepted duplicate node_id" >&2; exit 1
fi
if ! grep -q 'duplicate node_id' "$IMP_DUP_ID_OUT/stdout.txt"; then
  cat "$IMP_DUP_ID_OUT/stdout.txt"
  echo "FAIL: importer did not clearly report duplicate node_id" >&2; exit 1
fi
assert_no_import_outputs "$IMP_DUP_ID_OUT"

IMP_DUP_EDGE="$TMP_DIR/import_duplicate_edge_bundle"
write_valid_bundle "$IMP_DUP_EDGE"
printf "E:proj_d_001\tRE:obs_001\tRE:proj_i_001\tregulatory_projection\tdirect_alignment\tgeneric_immune\t0.5\tdup\n" \
  >> "$IMP_DUP_EDGE/edges.tsv"
IMP_DUP_EDGE_OUT="$TMP_DIR/import_duplicate_edge_out"
mkdir -p "$IMP_DUP_EDGE_OUT"
if python3 "$IMPORTER" --bundle "$IMP_DUP_EDGE" --outdir "$IMP_DUP_EDGE_OUT" \
   > "$IMP_DUP_EDGE_OUT/stdout.txt" 2>&1; then
  cat "$IMP_DUP_EDGE_OUT/stdout.txt"
  echo "FAIL: importer accepted duplicate edge_id" >&2; exit 1
fi
if ! grep -q 'duplicate edge_id' "$IMP_DUP_EDGE_OUT/stdout.txt"; then
  cat "$IMP_DUP_EDGE_OUT/stdout.txt"
  echo "FAIL: importer did not clearly report duplicate edge_id" >&2; exit 1
fi
assert_no_import_outputs "$IMP_DUP_EDGE_OUT"

IMP_DUP_EVIDENCE="$TMP_DIR/import_duplicate_evidence_bundle"
write_valid_bundle "$IMP_DUP_EVIDENCE"
printf "EV:obs_001\tRE:obs_001\t\tdirect_observation\tbulk\tabsent\tceeg_v0.1:assay:ATAC-seq\tdup\n" \
  >> "$IMP_DUP_EVIDENCE/evidence.tsv"
IMP_DUP_EVIDENCE_OUT="$TMP_DIR/import_duplicate_evidence_out"
mkdir -p "$IMP_DUP_EVIDENCE_OUT"
if python3 "$IMPORTER" --bundle "$IMP_DUP_EVIDENCE" --outdir "$IMP_DUP_EVIDENCE_OUT" \
   > "$IMP_DUP_EVIDENCE_OUT/stdout.txt" 2>&1; then
  cat "$IMP_DUP_EVIDENCE_OUT/stdout.txt"
  echo "FAIL: importer accepted duplicate evidence_id" >&2; exit 1
fi
if ! grep -q 'duplicate evidence_id' "$IMP_DUP_EVIDENCE_OUT/stdout.txt"; then
  cat "$IMP_DUP_EVIDENCE_OUT/stdout.txt"
  echo "FAIL: importer did not clearly report duplicate evidence_id" >&2; exit 1
fi
assert_no_import_outputs "$IMP_DUP_EVIDENCE_OUT"

IMP_DUP_METRICS="$TMP_DIR/import_duplicate_metrics_bundle"
write_valid_bundle "$IMP_DUP_METRICS"
printf "RE:obs_001\tgeneric_immune\tbulk\t0.91\t1\t3\tdup\n" \
  >> "$IMP_DUP_METRICS/metrics.tsv"
IMP_DUP_METRICS_OUT="$TMP_DIR/import_duplicate_metrics_out"
mkdir -p "$IMP_DUP_METRICS_OUT"
if python3 "$IMPORTER" --bundle "$IMP_DUP_METRICS" --outdir "$IMP_DUP_METRICS_OUT" \
   > "$IMP_DUP_METRICS_OUT/stdout.txt" 2>&1; then
  cat "$IMP_DUP_METRICS_OUT/stdout.txt"
  echo "FAIL: importer accepted duplicate metrics node_id" >&2; exit 1
fi
if ! grep -q 'duplicate node_id' "$IMP_DUP_METRICS_OUT/stdout.txt"; then
  cat "$IMP_DUP_METRICS_OUT/stdout.txt"
  echo "FAIL: importer did not clearly report duplicate metrics node_id" >&2; exit 1
fi
assert_no_import_outputs "$IMP_DUP_METRICS_OUT"

# ── 33. importer rejects empty required source values; no partial outputs ─────

IMP_EMPTY_REQUIRED="$TMP_DIR/import_empty_required_bundle"
write_valid_bundle "$IMP_EMPTY_REQUIRED"
awk -F'\t' 'BEGIN{OFS="\t"} NR==3{$1=""} {print}' \
  "$IMP_EMPTY_REQUIRED/nodes.tsv" > "$IMP_EMPTY_REQUIRED/tmp" && mv "$IMP_EMPTY_REQUIRED/tmp" "$IMP_EMPTY_REQUIRED/nodes.tsv"
IMP_EMPTY_REQUIRED_OUT="$TMP_DIR/import_empty_required_out"
mkdir -p "$IMP_EMPTY_REQUIRED_OUT"
if python3 "$IMPORTER" --bundle "$IMP_EMPTY_REQUIRED" --outdir "$IMP_EMPTY_REQUIRED_OUT" \
   > "$IMP_EMPTY_REQUIRED_OUT/stdout.txt" 2>&1; then
  cat "$IMP_EMPTY_REQUIRED_OUT/stdout.txt"
  echo "FAIL: importer accepted empty required node_id" >&2; exit 1
fi
if ! grep -q 'empty required value' "$IMP_EMPTY_REQUIRED_OUT/stdout.txt"; then
  cat "$IMP_EMPTY_REQUIRED_OUT/stdout.txt"
  echo "FAIL: importer did not clearly report empty required value" >&2; exit 1
fi
assert_no_import_outputs "$IMP_EMPTY_REQUIRED_OUT"

IMP_EMPTY_MODE="$TMP_DIR/import_empty_projection_mode_bundle"
write_valid_bundle "$IMP_EMPTY_MODE"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$5=""} {print}' \
  "$IMP_EMPTY_MODE/edges.tsv" > "$IMP_EMPTY_MODE/tmp" && mv "$IMP_EMPTY_MODE/tmp" "$IMP_EMPTY_MODE/edges.tsv"
IMP_EMPTY_MODE_OUT="$TMP_DIR/import_empty_projection_mode_out"
mkdir -p "$IMP_EMPTY_MODE_OUT"
if python3 "$IMPORTER" --bundle "$IMP_EMPTY_MODE" --outdir "$IMP_EMPTY_MODE_OUT" \
   > "$IMP_EMPTY_MODE_OUT/stdout.txt" 2>&1; then
  cat "$IMP_EMPTY_MODE_OUT/stdout.txt"
  echo "FAIL: importer accepted regulatory_projection with empty projection_mode" >&2; exit 1
fi
if ! grep -q 'missing projection_mode' "$IMP_EMPTY_MODE_OUT/stdout.txt"; then
  cat "$IMP_EMPTY_MODE_OUT/stdout.txt"
  echo "FAIL: importer did not clearly report empty projection_mode" >&2; exit 1
fi
assert_no_import_outputs "$IMP_EMPTY_MODE_OUT"

# ── 34. importer rejects reserved ceeg_bundle_source input column ─────────────

IMP_RESERVED_COL="$TMP_DIR/import_reserved_col_bundle"
write_valid_bundle "$IMP_RESERVED_COL"
awk -F'\t' 'BEGIN{OFS="\t"} NR==1{$0=$0 "\tceeg_bundle_source"} NR>1{$0=$0 "\tstale"} {print}' \
  "$IMP_RESERVED_COL/nodes.tsv" > "$IMP_RESERVED_COL/tmp" && mv "$IMP_RESERVED_COL/tmp" "$IMP_RESERVED_COL/nodes.tsv"
IMP_RESERVED_COL_OUT="$TMP_DIR/import_reserved_col_out"
mkdir -p "$IMP_RESERVED_COL_OUT"
if python3 "$IMPORTER" --bundle "$IMP_RESERVED_COL" --outdir "$IMP_RESERVED_COL_OUT" \
   > "$IMP_RESERVED_COL_OUT/stdout.txt" 2>&1; then
  cat "$IMP_RESERVED_COL_OUT/stdout.txt"
  echo "FAIL: importer accepted reserved ceeg_bundle_source input column" >&2; exit 1
fi
if ! grep -q 'reserved column' "$IMP_RESERVED_COL_OUT/stdout.txt"; then
  cat "$IMP_RESERVED_COL_OUT/stdout.txt"
  echo "FAIL: importer did not clearly report reserved input column" >&2; exit 1
fi
assert_no_import_outputs "$IMP_RESERVED_COL_OUT"

# ── 35. importer rejects whitespace-variant reserved/duplicate headers ───────

IMP_SPACED_RESERVED="$TMP_DIR/import_spaced_reserved_bundle"
write_valid_bundle "$IMP_SPACED_RESERVED"
awk -F'\t' 'BEGIN{OFS="\t"} NR==1{$0=$0 "\t ceeg_bundle_source "} NR>1{$0=$0 "\tstale"} {print}' \
  "$IMP_SPACED_RESERVED/nodes.tsv" > "$IMP_SPACED_RESERVED/tmp" && mv "$IMP_SPACED_RESERVED/tmp" "$IMP_SPACED_RESERVED/nodes.tsv"
IMP_SPACED_RESERVED_OUT="$TMP_DIR/import_spaced_reserved_out"
mkdir -p "$IMP_SPACED_RESERVED_OUT"
if python3 "$IMPORTER" --bundle "$IMP_SPACED_RESERVED" --outdir "$IMP_SPACED_RESERVED_OUT" \
   > "$IMP_SPACED_RESERVED_OUT/stdout.txt" 2>&1; then
  cat "$IMP_SPACED_RESERVED_OUT/stdout.txt"
  echo "FAIL: importer accepted whitespace-variant reserved ceeg_bundle_source column" >&2; exit 1
fi
if ! grep -q 'reserved column' "$IMP_SPACED_RESERVED_OUT/stdout.txt"; then
  cat "$IMP_SPACED_RESERVED_OUT/stdout.txt"
  echo "FAIL: importer did not clearly report whitespace-variant reserved column" >&2; exit 1
fi
assert_no_import_outputs "$IMP_SPACED_RESERVED_OUT"

IMP_SPACED_DUP="$TMP_DIR/import_spaced_duplicate_bundle"
write_valid_bundle "$IMP_SPACED_DUP"
awk 'NR==1{sub(/^node_id/,"node_id\t node_id ")} {print}' \
  "$IMP_SPACED_DUP/nodes.tsv" > "$IMP_SPACED_DUP/tmp" && mv "$IMP_SPACED_DUP/tmp" "$IMP_SPACED_DUP/nodes.tsv"
IMP_SPACED_DUP_OUT="$TMP_DIR/import_spaced_duplicate_out"
mkdir -p "$IMP_SPACED_DUP_OUT"
if python3 "$IMPORTER" --bundle "$IMP_SPACED_DUP" --outdir "$IMP_SPACED_DUP_OUT" \
   > "$IMP_SPACED_DUP_OUT/stdout.txt" 2>&1; then
  cat "$IMP_SPACED_DUP_OUT/stdout.txt"
  echo "FAIL: importer accepted whitespace-variant duplicate header" >&2; exit 1
fi
if ! grep -q 'after trimming whitespace' "$IMP_SPACED_DUP_OUT/stdout.txt"; then
  cat "$IMP_SPACED_DUP_OUT/stdout.txt"
  echo "FAIL: importer did not clearly report whitespace-variant duplicate header" >&2; exit 1
fi
assert_no_import_outputs "$IMP_SPACED_DUP_OUT"

# ── 36. backslash in provenance preserved verbatim (Bug 1 regression) ─────────
# Bug: csv.QUOTE_NONE + escapechar="\\" doubled backslashes on write.
# path\to\file was written as path\\to\\file and re-read as path\\to\\file (corrupted).

# ── 36a. importer rejects header-only required tables; no partial outputs ─────

IMP_EMPTY_EV="$TMP_DIR/import_empty_ev_bundle"
write_valid_bundle "$IMP_EMPTY_EV"
head -n 1 "$IMP_EMPTY_EV/evidence.tsv" > "$IMP_EMPTY_EV/tmp" && mv "$IMP_EMPTY_EV/tmp" "$IMP_EMPTY_EV/evidence.tsv"
IMP_EMPTY_EV_OUT="$TMP_DIR/import_empty_ev_out"
mkdir -p "$IMP_EMPTY_EV_OUT"
if python3 "$IMPORTER" --bundle "$IMP_EMPTY_EV" --outdir "$IMP_EMPTY_EV_OUT" \
   > "$IMP_EMPTY_EV_OUT/stdout.txt" 2>&1; then
  cat "$IMP_EMPTY_EV_OUT/stdout.txt"
  echo "FAIL: importer accepted header-only evidence.tsv" >&2; exit 1
fi
if ! grep -q 'no data rows' "$IMP_EMPTY_EV_OUT/stdout.txt"; then
  cat "$IMP_EMPTY_EV_OUT/stdout.txt"
  echo "FAIL: importer did not clearly report header-only evidence.tsv" >&2; exit 1
fi
assert_no_import_outputs "$IMP_EMPTY_EV_OUT"

IMP_EMPTY_EDGES="$TMP_DIR/import_empty_edges_bundle"
write_valid_bundle "$IMP_EMPTY_EDGES"
head -n 1 "$IMP_EMPTY_EDGES/edges.tsv" > "$IMP_EMPTY_EDGES/tmp" && mv "$IMP_EMPTY_EDGES/tmp" "$IMP_EMPTY_EDGES/edges.tsv"
IMP_EMPTY_EDGES_OUT="$TMP_DIR/import_empty_edges_out"
mkdir -p "$IMP_EMPTY_EDGES_OUT"
if python3 "$IMPORTER" --bundle "$IMP_EMPTY_EDGES" --outdir "$IMP_EMPTY_EDGES_OUT" \
   > "$IMP_EMPTY_EDGES_OUT/stdout.txt" 2>&1; then
  cat "$IMP_EMPTY_EDGES_OUT/stdout.txt"
  echo "FAIL: importer accepted empty edges.tsv with projected nodes" >&2; exit 1
fi
if ! grep -q 'projected nodes are present' "$IMP_EMPTY_EDGES_OUT/stdout.txt"; then
  cat "$IMP_EMPTY_EDGES_OUT/stdout.txt"
  echo "FAIL: importer did not clearly report empty edges.tsv with projected nodes" >&2; exit 1
fi
assert_no_import_outputs "$IMP_EMPTY_EDGES_OUT"

BSL_DIR="$TMP_DIR/bsl_bundle"
write_valid_bundle "$BSL_DIR"
awk -F'\t' 'BEGIN{OFS="\t"} NR==6{$7="path\\to\\file"} {print}' \
  "$BSL_DIR/evidence.tsv" > "$BSL_DIR/tmp" && mv "$BSL_DIR/tmp" "$BSL_DIR/evidence.tsv"
BSL_OUT="$TMP_DIR/bsl_out"
mkdir -p "$BSL_OUT"
if ! python3 "$IMPORTER" --bundle "$BSL_DIR" --outdir "$BSL_OUT" > "$BSL_OUT/stdout.txt" 2>&1; then
  cat "$BSL_OUT/stdout.txt"
  echo "FAIL: importer failed on bundle with backslash in provenance" >&2; exit 1
fi
if ! awk -F'\t' '
  NR==1{ for(i=1;i<=NF;i++) { if($i=="evidence_id") ei=i; if($i=="provenance") pr=i } }
  NR>1 && $ei=="EV:unk_001" && pr && $pr=="path\\to\\file" { found=1 }
  END { exit !found }
' "$BSL_OUT/ceeg_imported_evidence.tsv"; then
  grep 'EV:unk_001' "$BSL_OUT/ceeg_imported_evidence.tsv" || true
  echo "FAIL: backslash in provenance not preserved verbatim (Bug 1 regression)" >&2; exit 1
fi

# ── 36b. importer preserves optional identifier/provenance columns ────────────

OPT_DIR="$TMP_DIR/import_optional_columns_bundle"
write_valid_bundle "$OPT_DIR"
awk -F'\t' 'BEGIN{OFS="\t"} NR==1{$0=$0 "\tspecies_id\tsystem_id"} NR>1{$0=$0 "\tsp_" NR "\tsys_" NR} {print}' \
  "$OPT_DIR/nodes.tsv" > "$OPT_DIR/tmp" && mv "$OPT_DIR/tmp" "$OPT_DIR/nodes.tsv"
awk -F'\t' 'BEGIN{OFS="\t"} NR==1{$0=$0 "\toperation_type\tsource_id"} NR>1{$0=$0 "\top_" NR "\tsrc_" NR} {print}' \
  "$OPT_DIR/evidence.tsv" > "$OPT_DIR/tmp" && mv "$OPT_DIR/tmp" "$OPT_DIR/evidence.tsv"
OPT_OUT="$TMP_DIR/import_optional_columns_out"
mkdir -p "$OPT_OUT"
if ! python3 "$IMPORTER" --bundle "$OPT_DIR" --outdir "$OPT_OUT" > "$OPT_OUT/stdout.txt" 2>&1; then
  cat "$OPT_OUT/stdout.txt"
  echo "FAIL: importer failed on valid optional columns" >&2; exit 1
fi
for col in species_id system_id; do
  if ! head -n 1 "$OPT_OUT/ceeg_imported_nodes.tsv" | grep -qw "$col"; then
    head -n 1 "$OPT_OUT/ceeg_imported_nodes.tsv"
    echo "FAIL: optional nodes column '$col' not preserved by importer" >&2; exit 1
  fi
done
for col in operation_type source_id; do
  if ! head -n 1 "$OPT_OUT/ceeg_imported_evidence.tsv" | grep -qw "$col"; then
    head -n 1 "$OPT_OUT/ceeg_imported_evidence.tsv"
    echo "FAIL: optional evidence column '$col' not preserved by importer" >&2; exit 1
  fi
done
if ! awk -F'\t' '
  NR==1{for(i=1;i<=NF;i++){if($i=="operation_type")op=i;if($i=="source_id")src=i}}
  NR==2&&op&&src&&$op=="op_2"&&$src=="src_2"{found=1}
  END{exit !found}' "$OPT_OUT/ceeg_imported_evidence.tsv"; then
  cat "$OPT_OUT/ceeg_imported_evidence.tsv"
  echo "FAIL: optional operation_type/source_id values not preserved" >&2; exit 1
fi

# ── 31–36. summarizer: outputs, metrics, semantic disclaimers ────────────────

SUMMARY_OUT="$TMP_DIR/summary_out"
if ! run_summarizer "$IMPORT_OUT" "$SUMMARY_OUT"; then
  cat "$SUMMARY_OUT/stdout.txt"
  echo "FAIL: summarizer failed on import output" >&2; exit 1
fi

for f in ceeg_compatibility_summary.tsv ceeg_compatibility_report.md; do
  if [ ! -f "$SUMMARY_OUT/$f" ]; then
    echo "FAIL: summarizer did not produce $f" >&2; exit 1
  fi
done

SUMMARY="$SUMMARY_OUT/ceeg_compatibility_summary.tsv"
REPORT="$SUMMARY_OUT/ceeg_compatibility_report.md"

if ! awk -F'\t' '$1=="ceeg_unknown_count"&&$2=="1"{found=1} END{exit !found}' "$SUMMARY"; then
  cat "$SUMMARY"
  echo "FAIL: ceeg_unknown_count != 1" >&2; exit 1
fi

if ! awk -F'\t' '$1=="ceeg_absent_count"&&$2=="4"{found=1} END{exit !found}' "$SUMMARY"; then
  cat "$SUMMARY"
  echo "FAIL: ceeg_absent_count != 4" >&2; exit 1
fi

if ! grep -q 'projected_direct' "$REPORT"; then
  cat "$REPORT"
  echo "FAIL: projected_direct not mentioned in compatibility report" >&2; exit 1
fi

if ! grep -q 'Functional conservation is not implied' "$REPORT"; then
  cat "$REPORT"
  echo "FAIL: functional conservation disclaimer missing from report" >&2; exit 1
fi

if ! grep -q 'distinct' "$REPORT"; then
  cat "$REPORT"
  echo "FAIL: unknown/absent distinction not stated in report" >&2; exit 1
fi

# ── 37. summarizer norm() must preserve "none" (valid CEEG projection_type) ───
# Bug fix: summarizer previously used an aggressive norm() that collapsed "none" → "".
# "none" is the projection_type value for observed/unmappable nodes and must be preserved.

if ! python3 -c "
import importlib.util
spec = importlib.util.spec_from_file_location('s', '${SUMMARIZER}')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
assert mod.norm('none') == 'none', repr(mod.norm('none'))
assert mod.norm('unknown') == 'unknown', repr(mod.norm('unknown'))
assert mod.norm('absent') == 'absent', repr(mod.norm('absent'))
" 2>&1; then
  echo "FAIL: summarizer norm() collapses CEEG controlled vocabulary token 'none'" >&2; exit 1
fi

# ── 43. ceeg_status=UNKNOWN when --validation-report is omitted ──────────────
# Fix: ceeg_status was incorrectly OK when no validation was run.

if ! awk -F'\t' '$1=="ceeg_status"&&$2=="UNKNOWN"{found=1} END{exit !found}' "$SUMMARY"; then
  cat "$SUMMARY"
  echo "FAIL: ceeg_status should be UNKNOWN when --validation-report is omitted" >&2; exit 1
fi

# ── 44. ceeg_status=OK with a zero-error validation report ───────────────────

CLEAN_RPT="$TMP_DIR/clean_rpt.tsv"
printf 'severity\trule_id\tsource\tfield\trow\tmessage\tsuggestion\n' > "$CLEAN_RPT"
CLEAN_SUM="$TMP_DIR/clean_sum"
mkdir -p "$CLEAN_SUM"
if ! python3 "$SUMMARIZER" \
     --import-dir "$IMPORT_OUT" --outdir "$CLEAN_SUM" \
     --validation-report "$CLEAN_RPT" > "$CLEAN_SUM/stdout.txt" 2>&1; then
  cat "$CLEAN_SUM/stdout.txt"
  echo "FAIL: summarizer failed with zero-error validation report" >&2; exit 1
fi
if ! awk -F'\t' '$1=="ceeg_status"&&$2=="OK"{found=1} END{exit !found}' \
     "$CLEAN_SUM/ceeg_compatibility_summary.tsv"; then
  cat "$CLEAN_SUM/ceeg_compatibility_summary.tsv"
  echo "FAIL: ceeg_status should be OK with zero-error validation report" >&2; exit 1
fi

# ── 45. ceeg_status=ERROR with a report containing errors ────────────────────

ERR_RPT="$TMP_DIR/err_rpt.tsv"
printf 'severity\trule_id\tsource\tfield\trow\tmessage\tsuggestion\nERROR\tCEEG_BUNDLE_MISSING_FILE\tnodes.tsv\t\t\tMissing\t\n' > "$ERR_RPT"
ERR_SUM="$TMP_DIR/err_sum"
mkdir -p "$ERR_SUM"
if ! python3 "$SUMMARIZER" \
     --import-dir "$IMPORT_OUT" --outdir "$ERR_SUM" \
     --validation-report "$ERR_RPT" > "$ERR_SUM/stdout.txt" 2>&1; then
  cat "$ERR_SUM/stdout.txt"
  echo "FAIL: summarizer should exit 0 even when reporting ERROR status" >&2; exit 1
fi
if ! awk -F'\t' '$1=="ceeg_status"&&$2=="ERROR"{found=1} END{exit !found}' \
     "$ERR_SUM/ceeg_compatibility_summary.tsv"; then
  cat "$ERR_SUM/ceeg_compatibility_summary.tsv"
  echo "FAIL: ceeg_status should be ERROR when validation report contains errors" >&2; exit 1
fi

# ── 46. score statistics present in TSV with correct values ──────────────────
# Fixture scored nodes: RE:obs_001=0.91, RE:proj_d_001=0.74, RE:proj_d_sc_001=0.65,
# RE:proj_i_001=0.48 (RE:unk_001 empty — excluded)
# mean=(0.91+0.74+0.65+0.48)/4=0.6950  max=0.9100  min=0.4800  max_n_species=3

for pair in \
  "ceeg_mean_score:0.6950" \
  "ceeg_max_score:0.9100" \
  "ceeg_min_score:0.4800" \
  "ceeg_max_n_supporting_species:3"; do
  metric="${pair%%:*}"; expected="${pair##*:}"
  actual=$(awk -F'\t' -v m="$metric" '$1==m{print $2}' "$SUMMARY")
  if [ "$actual" != "$expected" ]; then
    cat "$SUMMARY"
    echo "FAIL: $metric expected '$expected', got '$actual'" >&2; exit 1
  fi
done

# ── 47. evidence_status and mapping_state breakdown in TSV ───────────────────

for pair in \
  "ceeg_observed_count:2" \
  "ceeg_projected_direct_count:2" \
  "ceeg_projected_indirect_count:1" \
  "ceeg_unknown_unmappable_count:1"; do
  metric="${pair%%:*}"; expected="${pair##*:}"
  actual=$(awk -F'\t' -v m="$metric" '$1==m{print $2}' "$SUMMARY")
  if [ "$actual" != "$expected" ]; then
    cat "$SUMMARY"
    echo "FAIL: $metric expected '$expected', got '$actual'" >&2; exit 1
  fi
done

# ── 48. absent row does not claim direct evidence for projected entries ───────
# Fix: "feature is evidenced in the reference panel" was misleading for projected entries.

if grep -q 'feature is evidenced' "$REPORT"; then
  cat "$REPORT"
  echo "FAIL: markdown 'absent' row says 'feature is evidenced' — misleading for projected entries" >&2; exit 1
fi

# ── 49–53. module structure ───────────────────────────────────────────────────

for pair in \
    "validate_ceeg_model_bundle.nf:VALIDATE_CEEG_MODEL_BUNDLE" \
    "import_ceeg_model_bundle.nf:IMPORT_CEEG_MODEL_BUNDLE" \
    "summarize_ceeg_compatibility.nf:SUMMARIZE_CEEG_COMPATIBILITY"; do
  file="${pair%%:*}"; process="${pair##*:}"
  nf="$ROOT_DIR/modules/local/$file"
  if [ ! -f "$nf" ]; then
    echo "FAIL: module not found: $nf" >&2; exit 1
  fi
  if ! grep -q "$process" "$nf"; then
    echo "FAIL: $file missing process $process" >&2; exit 1
  fi
  if ! grep -q 'ceeg_stub' "$nf"; then
    echo "FAIL: $file missing ceeg_stub variable" >&2; exit 1
  fi
  if ! grep -q '\${projectDir}/bin/' "$nf"; then
    echo "FAIL: $file does not reference \${projectDir}/bin/" >&2; exit 1
  fi
done

# ── 54. CEEG routing: explicit stage or enable flag on default validation ────
# --enable_ceeg_compatibility now routes to CEEG only from the default validation
# stage, preserving ordinary non-CEEG stage behavior.

MAIN_NF="$ROOT_DIR/main.nf"
if ! grep -q "def ceegEnabled = params.enable_ceeg_compatibility.toString().toBoolean()" "$MAIN_NF"; then
  grep 'ceegEnabled\|enable_ceeg_compatibility' "$MAIN_NF" || true
  echo "FAIL: main.nf does not normalize --enable_ceeg_compatibility for CEEG routing" >&2; exit 1
fi
if ! grep -q "isCeegCompatibilityStage = params.run_stage == 'ceeg_compatibility' || (ceegEnabled && params.run_stage == 'validation')" "$MAIN_NF"; then
  grep 'isCeegCompatibilityStage' "$MAIN_NF" || true
  echo "FAIL: isCeegCompatibilityStage must route explicit CEEG stage or enable flag on default validation stage" >&2; exit 1
fi

# Runtime routing checks: static grep above is not enough to prove behavior.
NF_DEFAULT_LOG="$TMP_DIR/nextflow_default_no_ceeg.log"
if ! nextflow run "$ROOT_DIR/main.nf" \
     -work-dir "$TMP_DIR/nf_work_default" \
     --outdir "$TMP_DIR/nf_default_no_ceeg" \
     -profile stub > "$NF_DEFAULT_LOG" 2>&1; then
  cat "$NF_DEFAULT_LOG"
  echo "FAIL: default Nextflow stub run failed" >&2; exit 1
fi
if grep -q 'CEEG_' "$NF_DEFAULT_LOG"; then
  cat "$NF_DEFAULT_LOG"
  echo "FAIL: default Nextflow stub run launched CEEG processes despite CEEG being absent" >&2; exit 1
fi

NF_CEEG_NO_BUNDLE_LOG="$TMP_DIR/nextflow_ceeg_no_bundle.log"
if nextflow run "$ROOT_DIR/main.nf" \
     -work-dir "$TMP_DIR/nf_work_ceeg_no_bundle" \
     --outdir "$TMP_DIR/nf_ceeg_no_bundle" \
     -profile stub \
     --enable_ceeg_compatibility true > "$NF_CEEG_NO_BUNDLE_LOG" 2>&1; then
  cat "$NF_CEEG_NO_BUNDLE_LOG"
  echo "FAIL: CEEG-enabled Nextflow run succeeded without --ceeg_model_bundle" >&2; exit 1
fi
if ! grep -q 'requires --ceeg_model_bundle' "$NF_CEEG_NO_BUNDLE_LOG"; then
  cat "$NF_CEEG_NO_BUNDLE_LOG"
  echo "FAIL: CEEG-enabled Nextflow run without bundle did not fail clearly" >&2; exit 1
fi

# ── 55. BUG-2: subworkflow must include and call BUILD_CAME_CEEG_FEATURE_MATRICES ─
# Feature matrices are only produced if the builder is wired into the workflow.

SW_FILE="$ROOT_DIR/subworkflows/ceeg_model_import.nf"
if ! grep -q 'BUILD_CAME_CEEG_FEATURE_MATRICES' "$SW_FILE"; then
  echo "FAIL: ceeg_model_import.nf does not include BUILD_CAME_CEEG_FEATURE_MATRICES (BUG-2: builder unwired)" >&2; exit 1
fi
if ! grep -q 're_features' "$SW_FILE"; then
  echo "FAIL: ceeg_model_import.nf does not emit re_features (BUG-2: builder output not propagated)" >&2; exit 1
fi

# ── 56. BUG-3: import module must declare path validation_report input ────────
# Without this input, Nextflow has no data dependency and IMPORT can run before
# VALIDATE completes.

IMPORT_NF="$ROOT_DIR/modules/local/import_ceeg_model_bundle.nf"
if ! grep -q 'path validation_report' "$IMPORT_NF"; then
  echo "FAIL: import module missing 'path validation_report' input (BUG-3: no ordering guarantee)" >&2; exit 1
fi

# ── 57. BUG-Q1: norm("0") must not collapse to "" (falsy zero fix) ───────────
# Old: str(value or "").strip() → norm("0")=="" and norm(0)=="". Fixed: is not None guard.
# A mappable node with ceeg_score=0 must not trigger CEEG_BUNDLE_MISSING_SCORE.

ZERO_SCORE_DIR="$TMP_DIR/zero_score_bundle"
write_valid_bundle "$ZERO_SCORE_DIR"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$4="0"} {print}' \
  "$ZERO_SCORE_DIR/metrics.tsv" > "$ZERO_SCORE_DIR/tmp" && mv "$ZERO_SCORE_DIR/tmp" "$ZERO_SCORE_DIR/metrics.tsv"
if ! run_validator "$ZERO_SCORE_DIR"; then
  cat "$ZERO_SCORE_DIR/stdout.txt"
  echo "FAIL: validator rejected ceeg_score=0 on mappable node (BUG-Q1: falsy zero in norm())" >&2; exit 1
fi
if grep -q 'CEEG_BUNDLE_MISSING_SCORE' "$ZERO_SCORE_DIR/report.tsv"; then
  cat "$ZERO_SCORE_DIR/report.tsv"
  echo "FAIL: CEEG_BUNDLE_MISSING_SCORE fired on ceeg_score=0 (BUG-Q1: falsy zero must not be treated as missing)" >&2; exit 1
fi

# ── 58. BUG-Q2: validator write_report must preserve backslash in suggestion/message ──
# Old: csv.QUOTE_NONE + escapechar="\\" doubled backslashes in report fields.

if ! python3 -c "
import importlib.util, os, tempfile
spec = importlib.util.spec_from_file_location('v', '${VALIDATOR}')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
tmp = tempfile.mktemp(suffix='.tsv')
records = [{'severity':'ERROR','rule_id':'TEST','source':'nodes','field':'','row':'2',
            'message':'path\\\\to\\\\file','suggestion':'use path\\\\to\\\\other'}]
mod.write_report(tmp, records)
with open(tmp) as f: content = f.read()
os.unlink(tmp)
assert 'path\\\\to\\\\file' in content, repr(content)
assert 'path\\\\to\\\\other' in content, repr(content)
assert 'path\\\\\\\\to\\\\\\\\file' not in content, 'backslash doubled: ' + repr(content)
" 2>&1; then
  echo "FAIL: validator write_report doubled backslashes (BUG-Q2: QUOTE_NONE+escapechar not fixed)" >&2; exit 1
fi

# ── 59. Invariant 4: evidence_status/projection_type mismatch fires CEEG_BUNDLE_INCONSISTENT_PROJECTION_TYPE ──
# e.g. projected_direct + projection_type=indirect must be an ERROR.

INV4_DIR="$TMP_DIR/inv4_bundle"
write_valid_bundle "$INV4_DIR"
awk -F'\t' 'BEGIN{OFS="\t"} NR==4{$6="indirect"} {print}' \
  "$INV4_DIR/nodes.tsv" > "$INV4_DIR/tmp" && mv "$INV4_DIR/tmp" "$INV4_DIR/nodes.tsv"
if run_validator "$INV4_DIR"; then
  cat "$INV4_DIR/stdout.txt"
  echo "FAIL: validator accepted projected_direct+projection_type=indirect (Invariant 4 missing)" >&2; exit 1
fi
if ! grep -q 'CEEG_BUNDLE_INCONSISTENT_PROJECTION_TYPE' "$INV4_DIR/report.tsv"; then
  cat "$INV4_DIR/report.tsv"
  echo "FAIL: CEEG_BUNDLE_INCONSISTENT_PROJECTION_TYPE not in report for evidence_status/projection_type mismatch" >&2; exit 1
fi

# ── 60. Invariant 5: projected_indirect + functional_conservation must be rejected ──
# The guard previously only covered projected_direct. projected_indirect also carries no
# functional conservation claim.

INV5_DIR="$TMP_DIR/inv5_bundle"
write_valid_bundle "$INV5_DIR"
awk -F'\t' 'BEGIN{OFS="\t"} NR==5{$4="functional_conservation"} {print}' \
  "$INV5_DIR/evidence.tsv" > "$INV5_DIR/tmp" && mv "$INV5_DIR/tmp" "$INV5_DIR/evidence.tsv"
if run_validator "$INV5_DIR"; then
  cat "$INV5_DIR/stdout.txt"
  echo "FAIL: validator accepted projected_indirect+functional_conservation (Invariant 5 gap)" >&2; exit 1
fi
if ! grep -q 'CEEG_BUNDLE_PROJECTED_FUNCTIONAL_CONSERVATION' "$INV5_DIR/report.tsv"; then
  cat "$INV5_DIR/report.tsv"
  echo "FAIL: CEEG_BUNDLE_PROJECTED_FUNCTIONAL_CONSERVATION not in report for projected_indirect+functional_conservation" >&2; exit 1
fi

# Also verify the importer rejects it (mirrors the same contract).
INV5I_DIR="$TMP_DIR/inv5_import_out"
mkdir -p "$INV5I_DIR"
if python3 "$IMPORTER" --bundle "$INV5_DIR" --outdir "$INV5I_DIR" > "$INV5I_DIR/stdout.txt" 2>&1; then
  cat "$INV5I_DIR/stdout.txt"
  echo "FAIL: importer accepted projected_indirect+functional_conservation (Invariant 5 gap in importer)" >&2; exit 1
fi

# ── 61. CEEG_BUNDLE_MISSING_DIRECTORY: non-existent bundle path fails clearly ──

NODIR_OUT="$TMP_DIR/nodir_report.tsv"
if python3 "$VALIDATOR" "$TMP_DIR/does_not_exist" --report "$NODIR_OUT" > "$TMP_DIR/nodir_stdout.txt" 2>&1; then
  cat "$TMP_DIR/nodir_stdout.txt"
  echo "FAIL: validator accepted non-existent bundle_dir (CEEG_BUNDLE_MISSING_DIRECTORY)" >&2; exit 1
fi
if ! grep -q 'CEEG_BUNDLE_MISSING_DIRECTORY' "$NODIR_OUT"; then
  cat "$NODIR_OUT"
  echo "FAIL: CEEG_BUNDLE_MISSING_DIRECTORY not in report for non-existent bundle dir" >&2; exit 1
fi

# ── 62. CEEG_BUNDLE_EMPTY_NODES_TABLE: header-only nodes.tsv gives clear error ──
# A header row but no data rows used to produce a storm of UNRESOLVED_NODE_REF with
# no clear root-cause message. Now it emits CEEG_BUNDLE_EMPTY_NODES_TABLE and
# suppresses the cascade.

EMPTY_NODES="$TMP_DIR/empty_nodes_bundle"
write_valid_bundle "$EMPTY_NODES"
head -n 1 "$EMPTY_NODES/nodes.tsv" > "$EMPTY_NODES/tmp" && mv "$EMPTY_NODES/tmp" "$EMPTY_NODES/nodes.tsv"
if run_validator "$EMPTY_NODES"; then
  cat "$EMPTY_NODES/stdout.txt"
  echo "FAIL: validator accepted nodes.tsv with header only" >&2; exit 1
fi
if ! grep -q 'CEEG_BUNDLE_EMPTY_NODES_TABLE' "$EMPTY_NODES/report.tsv"; then
  cat "$EMPTY_NODES/report.tsv"
  echo "FAIL: CEEG_BUNDLE_EMPTY_NODES_TABLE not in report for header-only nodes.tsv" >&2; exit 1
fi
if grep -q 'CEEG_BUNDLE_UNRESOLVED_NODE_REF' "$EMPTY_NODES/report.tsv"; then
  cat "$EMPTY_NODES/report.tsv"
  echo "FAIL: empty nodes.tsv must not cascade into UNRESOLVED_NODE_REF errors" >&2; exit 1
fi

# ── 63. CEEG_BUNDLE_INVALID_PROJECTION_TYPE: unknown projection_type in nodes ──

expect_fail invalid_projection_type \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==4{\$6=\"lateral\"} {print}" "$1/nodes.tsv" > "$1/tmp" && mv "$1/tmp" "$1/nodes.tsv"'
expect_rule  invalid_projection_type CEEG_BUNDLE_INVALID_PROJECTION_TYPE

# ── 64. CEEG_BUNDLE_MISSING_PROJECTION_MODE: regulatory_projection missing mode ──

expect_fail missing_projection_mode \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$5=\"\"} {print}" "$1/edges.tsv" > "$1/tmp" && mv "$1/tmp" "$1/edges.tsv"'
expect_rule  missing_projection_mode CEEG_BUNDLE_MISSING_PROJECTION_MODE

# ── 65. CEEG_BUNDLE_PROJECTED_FUNCTIONAL_CONSERVATION for projected_direct ────
# Test 60 covers projected_indirect; this confirms projected_direct is also guarded.
# NR==3 in evidence.tsv is EV:proj_d_001, referencing the projected_direct node RE:proj_d_001.

expect_fail proj_direct_functional_conservation \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==3{\$4=\"functional_conservation\"} {print}" "$1/evidence.tsv" > "$1/tmp" && mv "$1/tmp" "$1/evidence.tsv"'
expect_rule  proj_direct_functional_conservation CEEG_BUNDLE_PROJECTED_FUNCTIONAL_CONSERVATION

# ── 66. CEEG_BUNDLE_INVALID_DATA_MODE in evidence.tsv ────────────────────────

expect_fail invalid_data_mode_evidence \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$5=\"proteomics\"} {print}" "$1/evidence.tsv" > "$1/tmp" && mv "$1/tmp" "$1/evidence.tsv"'
expect_rule  invalid_data_mode_evidence CEEG_BUNDLE_INVALID_DATA_MODE

# ── 67. CEEG_BUNDLE_INVALID_DATA_MODE in metrics.tsv ─────────────────────────

expect_fail invalid_data_mode_metrics \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$3=\"proteomics\"} {print}" "$1/metrics.tsv" > "$1/tmp" && mv "$1/tmp" "$1/metrics.tsv"'
expect_rule  invalid_data_mode_metrics CEEG_BUNDLE_INVALID_DATA_MODE

# ── 68. CEEG_BUNDLE_UNRESOLVED_NODE_REF: edge source_node_id nonexistent ─────

expect_fail unresolved_edge_source \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$2=\"NE:ghost\"} {print}" "$1/edges.tsv" > "$1/tmp" && mv "$1/tmp" "$1/edges.tsv"'
expect_rule  unresolved_edge_source CEEG_BUNDLE_UNRESOLVED_NODE_REF

# ── 69. CEEG_BUNDLE_UNRESOLVED_NODE_REF: evidence node_id nonexistent ────────
# Independent of missing-nodes cascade (which is suppressed): tests the per-row check
# when nodes.tsv is present but the specific node_id doesn't exist.

expect_fail unresolved_evidence_node \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$2=\"NE:ghost\"} {print}" "$1/evidence.tsv" > "$1/tmp" && mv "$1/tmp" "$1/evidence.tsv"'
expect_rule  unresolved_evidence_node CEEG_BUNDLE_UNRESOLVED_NODE_REF

# ── 70. CEEG_BUNDLE_UNRESOLVED_NODE_REF: metrics node_id nonexistent ─────────

expect_fail unresolved_metrics_node \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$1=\"NE:ghost\"} {print}" "$1/metrics.tsv" > "$1/tmp" && mv "$1/tmp" "$1/metrics.tsv"'
expect_rule  unresolved_metrics_node CEEG_BUNDLE_UNRESOLVED_NODE_REF

# ── 71. n_supporting_species column is now required ───────────────────────────
# Removing the column must fail with CEEG_BUNDLE_MISSING_REQUIRED_COLUMN.

expect_fail missing_n_supporting_species_col \
  'awk "NR==1{sub(/\tn_supporting_species/,\"\")} {print}" "$1/metrics.tsv" > "$1/tmp" && mv "$1/tmp" "$1/metrics.tsv"'
expect_rule  missing_n_supporting_species_col CEEG_BUNDLE_MISSING_REQUIRED_COLUMN

# ── 72. Over-strict: non-regulatory edge with empty projection_mode must pass ─
# Before fix: projection_mode in REQUIRED_COLUMNS meant any edge with empty
# projection_mode triggered CEEG_BUNDLE_EMPTY_REQUIRED_VALUE, rejecting valid bundles.
# After fix: EDGES_OPTIONAL_VALUES exempts projection_mode from the value check.

CO_DIR="$TMP_DIR/co_reg_bundle"
write_valid_bundle "$CO_DIR"
printf 'E:co_001\tRE:obs_001\tRE:proj_d_001\tco_regulation\t\tgeneric_immune\t0.5\tcustom edge type\n' \
  >> "$CO_DIR/edges.tsv"
if ! run_validator "$CO_DIR"; then
  cat "$CO_DIR/stdout.txt"
  echo "FAIL: validator rejected valid non-regulatory edge with empty projection_mode (over-strict fix)" >&2; exit 1
fi
if grep -q 'CEEG_BUNDLE_EMPTY_REQUIRED_VALUE.*projection_mode' "$CO_DIR/report.tsv"; then
  cat "$CO_DIR/report.tsv"
  echo "FAIL: projection_mode must not be required-value for non-regulatory edges" >&2; exit 1
fi

# ── 73. malformed TSV row with extra field must fail ─────────────────────────

expect_fail malformed_extra_field \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==3{\$0=\$0 \"\textra_field\"} {print}" "$1/nodes.tsv" > "$1/tmp" && mv "$1/tmp" "$1/nodes.tsv"'
expect_rule  malformed_extra_field CEEG_BUNDLE_MALFORMED_TSV_ROW

# ── 74. malformed TSV row with missing trailing field must fail ──────────────

expect_fail malformed_missing_field \
  'awk "NR==3{sub(/\t[^\t]*$/ , \"\")} {print}" "$1/evidence.tsv" > "$1/tmp" && mv "$1/tmp" "$1/evidence.tsv"'
expect_rule  malformed_missing_field CEEG_BUNDLE_MALFORMED_TSV_ROW

# ── 75. duplicate column header must fail ────────────────────────────────────

expect_fail duplicate_column_header \
  'awk "NR==1{sub(/^node_id/,\"node_id\tnode_id\")} {print}" "$1/nodes.tsv" > "$1/tmp" && mv "$1/tmp" "$1/nodes.tsv"'
expect_rule  duplicate_column_header CEEG_BUNDLE_DUPLICATE_COLUMN

# ── 76. empty column header must fail ────────────────────────────────────────

expect_fail empty_column_header \
  'awk "NR==1{\$0=\$0 \"\t\"} NR>1{\$0=\$0 \"\t\"} {print}" "$1/nodes.tsv" > "$1/tmp" && mv "$1/tmp" "$1/nodes.tsv"'
expect_rule  empty_column_header CEEG_BUNDLE_EMPTY_COLUMN_HEADER

# ── 77. invalid node_type must fail ──────────────────────────────────────────

expect_fail invalid_node_type \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==3{\$2=\"regulatory_region\"} {print}" "$1/nodes.tsv" > "$1/tmp" && mv "$1/tmp" "$1/nodes.tsv"'
expect_rule  invalid_node_type CEEG_BUNDLE_INVALID_NODE_TYPE

# ── 78. header-only evidence.tsv must fail clearly ───────────────────────────

expect_fail empty_evidence_table \
  'head -n 1 "$1/evidence.tsv" > "$1/tmp" && mv "$1/tmp" "$1/evidence.tsv"'
expect_rule  empty_evidence_table CEEG_BUNDLE_EMPTY_EVIDENCE_TABLE

# ── 79. header-only metrics.tsv must fail clearly ────────────────────────────

expect_fail empty_metrics_table \
  'head -n 1 "$1/metrics.tsv" > "$1/tmp" && mv "$1/tmp" "$1/metrics.tsv"'
expect_rule  empty_metrics_table CEEG_BUNDLE_EMPTY_METRICS_TABLE

# ── 80. header-only edges.tsv must fail when projected nodes exist ────────────

expect_fail empty_edges_with_projected_nodes \
  'head -n 1 "$1/edges.tsv" > "$1/tmp" && mv "$1/tmp" "$1/edges.tsv"'
expect_rule  empty_edges_with_projected_nodes CEEG_BUNDLE_EMPTY_EDGES_TABLE

# ── 73–82. importer data-preservation assertions ──────────────────────────────
# These use the existing IMPORT_OUT (fixture bundle imported at test 22).

# ── 73. All required column headers present in each output ────────────────────

for pair in \
  "ceeg_imported_nodes.tsv:node_id node_type biological_system data_mode evidence_status projection_type mapping_state" \
  "ceeg_imported_edges.tsv:edge_id source_node_id target_node_id edge_type projection_mode" \
  "ceeg_imported_evidence.tsv:evidence_id node_id evidence_type data_mode unknown_absent provenance" \
  "ceeg_imported_metrics.tsv:node_id biological_system data_mode ceeg_score ceeg_rank n_supporting_species"; do
  file="${pair%%:*}"; cols="${pair##*:}"
  header=$(head -n 1 "$IMPORT_OUT/$file")
  for col in $cols; do
    case "$header" in
      *"$col"*) ;;
      *) echo "FAIL: $file missing column '$col' in output header" >&2; exit 1 ;;
    esac
  done
done

# ── 74. Original node IDs preserved verbatim ─────────────────────────────────

for nid in 'BS:generic_immune' 'RE:obs_001' 'RE:proj_d_001' 'RE:proj_d_sc_001' 'RE:proj_i_001' 'RE:unk_001'; do
  if ! awk -F'\t' -v id="$nid" \
       'NR==1{for(i=1;i<=NF;i++)if($i=="node_id"){col=i}} NR>1&&col&&$col==id{found=1} END{exit !found}' \
       "$IMPORT_OUT/ceeg_imported_nodes.tsv"; then
    echo "FAIL: node_id '$nid' not found in ceeg_imported_nodes.tsv" >&2; exit 1
  fi
done

# ── 75. Original edge IDs preserved verbatim ─────────────────────────────────

for eid in 'E:proj_d_001' 'E:proj_i_001'; do
  if ! awk -F'\t' -v id="$eid" \
       'NR==1{for(i=1;i<=NF;i++)if($i=="edge_id"){col=i}} NR>1&&col&&$col==id{found=1} END{exit !found}' \
       "$IMPORT_OUT/ceeg_imported_edges.tsv"; then
    echo "FAIL: edge_id '$eid' not found in ceeg_imported_edges.tsv" >&2; exit 1
  fi
done

# ── 76. Original evidence IDs preserved verbatim ─────────────────────────────

for evid in 'EV:obs_001' 'EV:proj_d_001' 'EV:proj_d_sc_001' 'EV:proj_i_001' 'EV:unk_001'; do
  if ! awk -F'\t' -v id="$evid" \
       'NR==1{for(i=1;i<=NF;i++)if($i=="evidence_id"){col=i}} NR>1&&col&&$col==id{found=1} END{exit !found}' \
       "$IMPORT_OUT/ceeg_imported_evidence.tsv"; then
    echo "FAIL: evidence_id '$evid' not found in ceeg_imported_evidence.tsv" >&2; exit 1
  fi
done

# ── 77. data_mode values preserved in metrics output ─────────────────────────

for mode in bulk single_cell hybrid; do
  if ! awk -F'\t' -v m="$mode" \
       'NR==1{for(i=1;i<=NF;i++)if($i=="data_mode"){col=i}} NR>1&&col&&$col==m{found=1} END{exit !found}' \
       "$IMPORT_OUT/ceeg_imported_metrics.tsv"; then
    echo "FAIL: data_mode=$mode not preserved in ceeg_imported_metrics.tsv" >&2; exit 1
  fi
done

# ── 78. projection_mode values preserved in edges output ─────────────────────

for mode in direct_alignment synteny_block; do
  if ! awk -F'\t' -v m="$mode" \
       'NR==1{for(i=1;i<=NF;i++)if($i=="projection_mode"){col=i}} NR>1&&col&&$col==m{found=1} END{exit !found}' \
       "$IMPORT_OUT/ceeg_imported_edges.tsv"; then
    echo "FAIL: projection_mode=$mode not preserved in ceeg_imported_edges.tsv" >&2; exit 1
  fi
done

# ── 79. Provenance field values preserved verbatim ────────────────────────────

for prov in 'ceeg_v0.1:assay:ATAC-seq' 'ceeg_v0.1:align:lastz' 'ceeg_v0.1:synteny:ensembl_v110'; do
  if ! awk -F'\t' -v p="$prov" \
       'NR==1{for(i=1;i<=NF;i++)if($i=="provenance"){col=i}} NR>1&&col&&$col==p{found=1} END{exit !found}' \
       "$IMPORT_OUT/ceeg_imported_evidence.tsv"; then
    echo "FAIL: provenance '$prov' not preserved verbatim in ceeg_imported_evidence.tsv" >&2; exit 1
  fi
done

# ── 80. unknown and absent preserved as distinct values in same file ──────────
# Both values must appear in the unknown_absent column; neither is collapsed to the other.

for val in unknown absent; do
  if ! awk -F'\t' -v v="$val" \
       'NR==1{for(i=1;i<=NF;i++)if($i=="unknown_absent"){col=i}} NR>1&&col&&$col==v{found=1} END{exit !found}' \
       "$IMPORT_OUT/ceeg_imported_evidence.tsv"; then
    echo "FAIL: unknown_absent=$val not found in ceeg_imported_evidence.tsv (separation broken)" >&2; exit 1
  fi
done
# Confirm only the two valid tokens appear (no unexpected normalisation).
if awk -F'\t' \
     'NR==1{for(i=1;i<=NF;i++)if($i=="unknown_absent"){col=i}}
      NR>1&&col&&$col!="unknown"&&$col!="absent"{print; found=1}
      END{exit found+0}' \
     "$IMPORT_OUT/ceeg_imported_evidence.tsv"; then
  : # no unexpected values — good
else
  grep -v '^$' "$IMPORT_OUT/ceeg_imported_evidence.tsv" | head -n 10
  echo "FAIL: unexpected unknown_absent value found (possible token normalisation)" >&2; exit 1
fi

# ── 81. ceeg_bundle_source must be an absolute path ──────────────────────────
# Risk-1 fix: bundle_dir is now os.path.abspath(). Relative paths are non-reproducible
# provenance records that become meaningless after the working directory changes.

if ! awk -F'\t' \
     'NR==1{for(i=1;i<=NF;i++)if($i=="ceeg_bundle_source"){col=i}}
      NR==2&&col{val=$col; if(substr(val,1,1)!="/"){fail=1}}
      END{exit fail+0}' \
     "$IMPORT_OUT/ceeg_imported_nodes.tsv"; then
  awk -F'\t' 'NR==1{for(i=1;i<=NF;i++)if($i=="ceeg_bundle_source"){col=i}} NR==2&&col{print $col}' \
    "$IMPORT_OUT/ceeg_imported_nodes.tsv"
  echo "FAIL: ceeg_bundle_source is a relative path (Risk-1: provenance not reproducible)" >&2; exit 1
fi

# ── 82. Risk-2: importer must reject evidence with non-existent node_id ───────
# check_invariants() previously silently passed unresolved node refs (ms="" → no check fired).

CORRUPT_DIR="$TMP_DIR/corrupt_bundle"
write_valid_bundle "$CORRUPT_DIR"
printf 'EV:ghost_001\tNE:ghost\t\tdirect_observation\tbulk\tabsent\ttest\t\n' \
  >> "$CORRUPT_DIR/evidence.tsv"
CORRUPT_OUT="$TMP_DIR/corrupt_out"
mkdir -p "$CORRUPT_OUT"
if python3 "$IMPORTER" --bundle "$CORRUPT_DIR" --outdir "$CORRUPT_OUT" \
   > "$CORRUPT_OUT/stdout.txt" 2>&1; then
  cat "$CORRUPT_OUT/stdout.txt"
  echo "FAIL: importer accepted evidence with non-existent node_id (Risk-2 fix)" >&2; exit 1
fi
if ! grep -q 'not found in nodes' "$CORRUPT_OUT/stdout.txt"; then
  cat "$CORRUPT_OUT/stdout.txt"
  echo "FAIL: importer did not report the unresolved node_id in error output" >&2; exit 1
fi
assert_no_import_outputs "$CORRUPT_OUT"

# ── 83. Risk-3: importer must reject evidence with non-existent edge_id ───────

CORRUPT_EDGE_DIR="$TMP_DIR/corrupt_edge_bundle"
write_valid_bundle "$CORRUPT_EDGE_DIR"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$3="E:ghost"} {print}' \
  "$CORRUPT_EDGE_DIR/evidence.tsv" > "$CORRUPT_EDGE_DIR/tmp" && mv "$CORRUPT_EDGE_DIR/tmp" "$CORRUPT_EDGE_DIR/evidence.tsv"
CORRUPT_EDGE_OUT="$TMP_DIR/corrupt_edge_out"
mkdir -p "$CORRUPT_EDGE_OUT"
if python3 "$IMPORTER" --bundle "$CORRUPT_EDGE_DIR" --outdir "$CORRUPT_EDGE_OUT" \
   > "$CORRUPT_EDGE_OUT/stdout.txt" 2>&1; then
  cat "$CORRUPT_EDGE_OUT/stdout.txt"
  echo "FAIL: importer accepted evidence with non-existent edge_id" >&2; exit 1
fi
if ! grep -q 'not found in edges' "$CORRUPT_EDGE_OUT/stdout.txt"; then
  cat "$CORRUPT_EDGE_OUT/stdout.txt"
  echo "FAIL: importer did not report the unresolved edge_id in error output" >&2; exit 1
fi
assert_no_import_outputs "$CORRUPT_EDGE_OUT"

# ── 84. Risk-4: importer must reject edges with non-existent node refs ────────

CORRUPT_EDGE_NODE_DIR="$TMP_DIR/corrupt_edge_node_bundle"
write_valid_bundle "$CORRUPT_EDGE_NODE_DIR"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$2="NE:ghost"} {print}' \
  "$CORRUPT_EDGE_NODE_DIR/edges.tsv" > "$CORRUPT_EDGE_NODE_DIR/tmp" && mv "$CORRUPT_EDGE_NODE_DIR/tmp" "$CORRUPT_EDGE_NODE_DIR/edges.tsv"
CORRUPT_EDGE_NODE_OUT="$TMP_DIR/corrupt_edge_node_out"
mkdir -p "$CORRUPT_EDGE_NODE_OUT"
if python3 "$IMPORTER" --bundle "$CORRUPT_EDGE_NODE_DIR" --outdir "$CORRUPT_EDGE_NODE_OUT" \
   > "$CORRUPT_EDGE_NODE_OUT/stdout.txt" 2>&1; then
  cat "$CORRUPT_EDGE_NODE_OUT/stdout.txt"
  echo "FAIL: importer accepted edge with non-existent source_node_id" >&2; exit 1
fi
if ! grep -q 'source_node_id.*not found in nodes' "$CORRUPT_EDGE_NODE_OUT/stdout.txt"; then
  cat "$CORRUPT_EDGE_NODE_OUT/stdout.txt"
  echo "FAIL: importer did not report unresolved edge source_node_id" >&2; exit 1
fi
assert_no_import_outputs "$CORRUPT_EDGE_NODE_OUT"

# ── 85. Risk-5: importer must reject edge target refs and self-edges ──────────

CORRUPT_EDGE_TARGET_DIR="$TMP_DIR/corrupt_edge_target_bundle"
write_valid_bundle "$CORRUPT_EDGE_TARGET_DIR"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$3="NE:ghost"} {print}' \
  "$CORRUPT_EDGE_TARGET_DIR/edges.tsv" > "$CORRUPT_EDGE_TARGET_DIR/tmp" && mv "$CORRUPT_EDGE_TARGET_DIR/tmp" "$CORRUPT_EDGE_TARGET_DIR/edges.tsv"
CORRUPT_EDGE_TARGET_OUT="$TMP_DIR/corrupt_edge_target_out"
mkdir -p "$CORRUPT_EDGE_TARGET_OUT"
if python3 "$IMPORTER" --bundle "$CORRUPT_EDGE_TARGET_DIR" --outdir "$CORRUPT_EDGE_TARGET_OUT" \
   > "$CORRUPT_EDGE_TARGET_OUT/stdout.txt" 2>&1; then
  cat "$CORRUPT_EDGE_TARGET_OUT/stdout.txt"
  echo "FAIL: importer accepted edge with non-existent target_node_id" >&2; exit 1
fi
if ! grep -q 'target_node_id.*not found in nodes' "$CORRUPT_EDGE_TARGET_OUT/stdout.txt"; then
  cat "$CORRUPT_EDGE_TARGET_OUT/stdout.txt"
  echo "FAIL: importer did not report unresolved edge target_node_id" >&2; exit 1
fi
assert_no_import_outputs "$CORRUPT_EDGE_TARGET_OUT"

CORRUPT_SELF_EDGE_DIR="$TMP_DIR/corrupt_self_edge_bundle"
write_valid_bundle "$CORRUPT_SELF_EDGE_DIR"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$3=$2} {print}' \
  "$CORRUPT_SELF_EDGE_DIR/edges.tsv" > "$CORRUPT_SELF_EDGE_DIR/tmp" && mv "$CORRUPT_SELF_EDGE_DIR/tmp" "$CORRUPT_SELF_EDGE_DIR/edges.tsv"
CORRUPT_SELF_EDGE_OUT="$TMP_DIR/corrupt_self_edge_out"
mkdir -p "$CORRUPT_SELF_EDGE_OUT"
if python3 "$IMPORTER" --bundle "$CORRUPT_SELF_EDGE_DIR" --outdir "$CORRUPT_SELF_EDGE_OUT" \
   > "$CORRUPT_SELF_EDGE_OUT/stdout.txt" 2>&1; then
  cat "$CORRUPT_SELF_EDGE_OUT/stdout.txt"
  echo "FAIL: importer accepted self-referencing edge" >&2; exit 1
fi
if ! grep -q 'same source and target node' "$CORRUPT_SELF_EDGE_OUT/stdout.txt"; then
  cat "$CORRUPT_SELF_EDGE_OUT/stdout.txt"
  echo "FAIL: importer did not report self-referencing edge" >&2; exit 1
fi
assert_no_import_outputs "$CORRUPT_SELF_EDGE_OUT"

# ── 86. Risk-6: importer must reject metrics with non-existent node_id ─────────

CORRUPT_MET_DIR="$TMP_DIR/corrupt_metrics_bundle"
write_valid_bundle "$CORRUPT_MET_DIR"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$1="NE:ghost"} {print}' \
  "$CORRUPT_MET_DIR/metrics.tsv" > "$CORRUPT_MET_DIR/tmp" && mv "$CORRUPT_MET_DIR/tmp" "$CORRUPT_MET_DIR/metrics.tsv"
CORRUPT_MET_OUT="$TMP_DIR/corrupt_metrics_out"
mkdir -p "$CORRUPT_MET_OUT"
if python3 "$IMPORTER" --bundle "$CORRUPT_MET_DIR" --outdir "$CORRUPT_MET_OUT" \
   > "$CORRUPT_MET_OUT/stdout.txt" 2>&1; then
  cat "$CORRUPT_MET_OUT/stdout.txt"
  echo "FAIL: importer accepted metrics with non-existent node_id" >&2; exit 1
fi
if ! grep -q 'metrics row.*not found in nodes' "$CORRUPT_MET_OUT/stdout.txt"; then
  cat "$CORRUPT_MET_OUT/stdout.txt"
  echo "FAIL: importer did not report unresolved metrics node_id" >&2; exit 1
fi
assert_no_import_outputs "$CORRUPT_MET_OUT"

# ── 87. Risk-7: importer must reject duplicate projection targets ─────────────

CORRUPT_DUP_TARGET_DIR="$TMP_DIR/corrupt_dup_target_bundle"
write_valid_bundle "$CORRUPT_DUP_TARGET_DIR"
printf "E:dup_target\tRE:obs_001\tRE:proj_d_001\tregulatory_projection\tdirect_alignment\tgeneric_immune\t0.5\tdup\n" \
  >> "$CORRUPT_DUP_TARGET_DIR/edges.tsv"
CORRUPT_DUP_TARGET_OUT="$TMP_DIR/corrupt_dup_target_out"
mkdir -p "$CORRUPT_DUP_TARGET_OUT"
if python3 "$IMPORTER" --bundle "$CORRUPT_DUP_TARGET_DIR" --outdir "$CORRUPT_DUP_TARGET_OUT" \
   > "$CORRUPT_DUP_TARGET_OUT/stdout.txt" 2>&1; then
  cat "$CORRUPT_DUP_TARGET_OUT/stdout.txt"
  echo "FAIL: importer accepted duplicate regulatory_projection target" >&2; exit 1
fi
if ! grep -q 'multiple regulatory_projection edges target' "$CORRUPT_DUP_TARGET_OUT/stdout.txt"; then
  cat "$CORRUPT_DUP_TARGET_OUT/stdout.txt"
  echo "FAIL: importer did not report duplicate regulatory_projection target" >&2; exit 1
fi
assert_no_import_outputs "$CORRUPT_DUP_TARGET_OUT"

# ── 88. Issue-1: main.nf stub guard must exempt exists() check from firing in stub mode ──
# Without the stub guard, --ceeg_stub true still required the bundle dir to exist on disk,
# defeating stub mode's purpose of running without real input data.

MAIN_NF="$ROOT_DIR/main.nf"
if ! grep -q '!(ceegStub in \["true", "1", "yes"\]).*!file(ceegBundlePath).exists' "$MAIN_NF"; then
  grep 'ceegBundlePath.*exists\|ceegStub.*exists' "$MAIN_NF" || true
  echo "FAIL: main.nf exists() check not guarded by ceeg_stub (Issue-1 fix missing)" >&2; exit 1
fi
if ! grep -q 'def ceegStub = params.ceeg_stub.toString().trim().toLowerCase()' "$MAIN_NF"; then
  grep 'ceegStub\|ceeg_stub.*toString' "$MAIN_NF" || true
  echo "FAIL: main.nf does not normalize ceeg_stub before module routing" >&2; exit 1
fi

# ── 84. Issue-2: summarize module stub must emit ceeg_status=SKIPPED, not ceeg_status=stub ──
# The token 'stub' is outside the real-mode vocabulary {OK, ERROR, UNKNOWN}.
# Downstream readers (apply_ceeg_scoring.py) must not need to handle an extra undocumented token.

SUMMARIZE_NF="$ROOT_DIR/modules/local/summarize_ceeg_compatibility.nf"
if grep -q 'ceeg_status.*stub' "$SUMMARIZE_NF"; then
  grep 'ceeg_status' "$SUMMARIZE_NF" || true
  echo "FAIL: summarize module emits ceeg_status=stub (Issue-2: outside real-mode vocabulary)" >&2; exit 1
fi
if ! grep -q 'ceeg_status.*SKIPPED' "$SUMMARIZE_NF"; then
  grep 'ceeg_status' "$SUMMARIZE_NF" || true
  echo "FAIL: summarize module stub does not emit ceeg_status=SKIPPED (Issue-2 fix missing)" >&2; exit 1
fi

# ── 85. ISSUE-1: absent row in report must clarify "Not a biological absence" ──
# The old wording said "Evidence record exists; mapping state is determined (observed or projected)."
# That is ambiguous — a reader could infer biological absence. The fix requires the phrase
# "Not a biological absence" to appear in the absent row of the Evidence State table.

if ! grep -q 'Not a biological absence' "$CLEAN_SUM/ceeg_compatibility_report.md"; then
  grep 'absent' "$CLEAN_SUM/ceeg_compatibility_report.md" || true
  echo "FAIL: report does not contain 'Not a biological absence' in absent row (ISSUE-1)" >&2; exit 1
fi

# ── 86. ISSUE-1: extended disclaimer must say "does NOT indicate biological absence" ──
# The disambiguation paragraph must use the exact phrase so automated downstream readers
# can grep for it without relying on wording variations.

if ! grep -q 'does NOT indicate biological absence' "$CLEAN_SUM/ceeg_compatibility_report.md"; then
  grep -A3 'unknown.*absent\|distinct' \
    "$CLEAN_SUM/ceeg_compatibility_report.md" || true
  echo "FAIL: report disclaimer does not contain 'does NOT indicate biological absence' (ISSUE-1)" >&2; exit 1
fi

# ── 87. ISSUE-2: with vc=0 the validation section must say "Validation passed" ──
# The old code emitted "No validation errors found" regardless of count. The fix splits
# the zero-error path to produce "Validation passed: 0 errors." for clarity.

if ! grep -q 'Validation passed' "$CLEAN_SUM/ceeg_compatibility_report.md"; then
  grep 'Validation\|validation' "$CLEAN_SUM/ceeg_compatibility_report.md" || true
  echo "FAIL: zero-error report does not contain 'Validation passed' (ISSUE-2)" >&2; exit 1
fi

# ── 88. ISSUE-2: with vc>0 the report must include remediation guidance ──
# Previously there was no actionable instruction for the user to re-run the validator.
# The fix adds "Re-run" to the error path.

if ! grep -q 'Re-run' "$ERR_SUM/ceeg_compatibility_report.md"; then
  grep 'Validation\|validation\|error\|ERROR' "$ERR_SUM/ceeg_compatibility_report.md" || true
  echo "FAIL: error-case report does not contain 'Re-run' remediation guidance (ISSUE-2)" >&2; exit 1
fi

# ── 89. ISSUE-3: ceeg_max_n_supporting_species must be "" for empty metrics ──
# The old code returned 0, which is ambiguous (zero supporting species vs. no data).
# Create a no-metrics scenario by summarizing over an import with an empty metrics file.

EMPTY_MET_DIR="$TMP_DIR/empty_met_import"
mkdir -p "$EMPTY_MET_DIR"
cp "$IMPORT_OUT/ceeg_imported_nodes.tsv" "$EMPTY_MET_DIR/"
cp "$IMPORT_OUT/ceeg_imported_edges.tsv" "$EMPTY_MET_DIR/"
cp "$IMPORT_OUT/ceeg_imported_evidence.tsv" "$EMPTY_MET_DIR/"
head -n 1 "$IMPORT_OUT/ceeg_imported_metrics.tsv" > "$EMPTY_MET_DIR/ceeg_imported_metrics.tsv"

EMPTY_MET_SUM="$TMP_DIR/empty_met_sum"
mkdir -p "$EMPTY_MET_SUM"
if ! python3 "$SUMMARIZER" \
     --import-dir "$EMPTY_MET_DIR" --outdir "$EMPTY_MET_SUM" \
     > "$EMPTY_MET_SUM/stdout.txt" 2>&1; then
  cat "$EMPTY_MET_SUM/stdout.txt"
  echo "FAIL: summarizer failed on header-only metrics file (ISSUE-3)" >&2; exit 1
fi

ACTUAL_MAX_N=$(awk -F'\t' '$1=="ceeg_max_n_supporting_species"{print $2}' \
  "$EMPTY_MET_SUM/ceeg_compatibility_summary.tsv")
if [ "$ACTUAL_MAX_N" != "" ]; then
  echo "FAIL: ceeg_max_n_supporting_species='$ACTUAL_MAX_N' for empty metrics; expected '' (ISSUE-3)" >&2; exit 1
fi

# ── 90. ISSUE-4: Nextflow stub summarize module must emit all expected metric rows ──
# The old stub printf block was missing rows for observed_count, projected_direct_count,
# projected_indirect_count, unknown_unmappable_count, ceeg_data_mode_bulk, mean/max/min_score,
# and ceeg_max_n_supporting_species — causing downstream matrix mismatch.

SUMMARIZE_NF="$ROOT_DIR/modules/local/summarize_ceeg_compatibility.nf"
for metric in \
  ceeg_observed_count \
  ceeg_projected_direct_count \
  ceeg_projected_indirect_count \
  ceeg_unknown_unmappable_count \
  ceeg_data_mode_bulk \
  ceeg_mean_score \
  ceeg_max_score \
  ceeg_min_score \
  ceeg_max_n_supporting_species; do
  if ! grep -q "$metric" "$SUMMARIZE_NF"; then
    echo "FAIL: summarize_ceeg_compatibility.nf stub block missing metric '$metric' (ISSUE-4)" >&2; exit 1
  fi
done

# ── 91. Summarizer must emit per-data_mode rows for each observed mode ─────────
# The fixture evidence has 3 bulk, 1 hybrid, 1 single_cell evidence records.

for pair in \
  "ceeg_data_mode_bulk	3" \
  "ceeg_data_mode_hybrid	1" \
  "ceeg_data_mode_single_cell	1"; do
  metric=$(printf '%s' "$pair" | cut -f1)
  value=$(printf '%s' "$pair" | cut -f2)
  actual=$(awk -F'\t' -v m="$metric" '$1==m{print $2}' \
    "$CLEAN_SUM/ceeg_compatibility_summary.tsv")
  if [ "$actual" != "$value" ]; then
    cat "$CLEAN_SUM/ceeg_compatibility_summary.tsv"
    echo "FAIL: $metric='$actual' expected '$value' in summary TSV (test 91)" >&2; exit 1
  fi
done

# ── 92. CLEAN_SUM path: ceeg_unknown_count and ceeg_absent_count still correct ──
# Tests 31–32 verify these counts on the no-validation-report path ($SUMMARY_OUT).
# The $CLEAN_SUM path (with a zero-error validation report) uses a different code
# path and could silently reclassify unknown→absent without triggering any prior test.

if ! awk -F'\t' '$1=="ceeg_unknown_count"&&$2=="1"{found=1} END{exit !found}' \
     "$CLEAN_SUM/ceeg_compatibility_summary.tsv"; then
  cat "$CLEAN_SUM/ceeg_compatibility_summary.tsv"
  echo "FAIL: ceeg_unknown_count != 1 on clean-sum path (reclassification check)" >&2; exit 1
fi
if ! awk -F'\t' '$1=="ceeg_absent_count"&&$2=="4"{found=1} END{exit !found}' \
     "$CLEAN_SUM/ceeg_compatibility_summary.tsv"; then
  cat "$CLEAN_SUM/ceeg_compatibility_summary.tsv"
  echo "FAIL: ceeg_absent_count != 4 on clean-sum path (reclassification check)" >&2; exit 1
fi

# ── 93. Stub report.md contains the conservation disclaimer ──────────────────
# Tests 34, 36, 85, 86 verify the disclaimer on the real-mode ($CLEAN_SUM) report.
# The stub-mode report is generated by printf statements in summarize_ceeg_compatibility.nf.
# A regression that dropped the disclaimer from the stub printf would be undetected.
# This test reads the .nf file content since the stub runs inside Nextflow; we
# verify the printf block contains the disclaimer string.

if ! grep -q 'Functional conservation is not implied' \
     "$ROOT_DIR/modules/local/summarize_ceeg_compatibility.nf"; then
  echo "FAIL: stub report.md printf block missing 'Functional conservation is not implied'" >&2; exit 1
fi

echo "OK: all ceeg_compatibility_stub tests passed"
