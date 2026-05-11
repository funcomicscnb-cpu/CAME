#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
IMPORTER="$ROOT_DIR/bin/import_ceeg_model_bundle.py"
BUILDER="$ROOT_DIR/bin/build_came_ceeg_feature_matrices.py"
FIXTURE_DIR="$ROOT_DIR/assets/example_samplesheets/ceeg_model_bundle"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

# ── setup: run importer on the canonical fixture bundle ───────────────────────

IMPORT_OUT="$TMP_DIR/import_out"
mkdir -p "$IMPORT_OUT"
if ! python3 "$IMPORTER" --bundle "$FIXTURE_DIR" --outdir "$IMPORT_OUT" > "$IMPORT_OUT/stdout.txt" 2>&1; then
  cat "$IMPORT_OUT/stdout.txt"
  echo "FAIL: importer failed; cannot proceed with feature matrix tests" >&2
  exit 1
fi

# ── run feature builder ───────────────────────────────────────────────────────

FEAT_OUT="$TMP_DIR/feat_out"
mkdir -p "$FEAT_OUT"
if ! python3 "$BUILDER" \
     --import-dir "$IMPORT_OUT" \
     --outdir "$FEAT_OUT" > "$FEAT_OUT/stdout.txt" 2>&1; then
  cat "$FEAT_OUT/stdout.txt"
  echo "FAIL: feature builder exited non-zero on valid imports" >&2
  exit 1
fi

RE_FILE="$FEAT_OUT/ceeg_regulatory_projection_features.tsv"
SY_FILE="$FEAT_OUT/ceeg_system_features.tsv"
EV_FILE="$FEAT_OUT/ceeg_evidence_features.tsv"

# ── 1. all three output files present ─────────────────────────────────────────

for f in "$RE_FILE" "$SY_FILE" "$EV_FILE"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: output file not produced: $f" >&2; exit 1
  fi
done

# ── 2. no functional_conservation column in any output ────────────────────────
# projected_direct carries only positional projection; functional conservation must not be implied

for f in "$RE_FILE" "$SY_FILE" "$EV_FILE"; do
  if head -n 1 "$f" | grep -qi 'functional_conservation'; then
    head -n 1 "$f"
    echo "FAIL: 'functional_conservation' column found in $(basename $f); must not be written" >&2; exit 1
  fi
done

# ── 3. RE features: correct column set ────────────────────────────────────────

for col in node_id biological_system species_id data_mode evidence_status \
           system_id projection_type mapping_state projection_edge_id projection_mode \
           projection_source_node_id projection_weight ceeg_score ceeg_rank n_supporting_species; do
  if ! head -n 1 "$RE_FILE" | grep -qw "$col"; then
    head -n 1 "$RE_FILE"
    echo "FAIL: RE features missing column '$col'" >&2; exit 1
  fi
done

# ── 4. RE features: 5 rows (5 regulatory_element nodes) ──────────────────────

re_row_count=$(awk 'NR>1{c++} END{print c+0}' "$RE_FILE")
if [ "$re_row_count" != "5" ]; then
  cat "$RE_FILE"
  echo "FAIL: RE features expected 5 rows, got $re_row_count" >&2; exit 1
fi

# ── 5. RE:unk_001 has empty ceeg_score (unmappable node) ─────────────────────
# Score must be "" not "0" — preserving the unmappable semantic

if ! awk -F'\t' '
  NR==1{ for(i=1;i<=NF;i++) { if($i=="node_id") nid=i; if($i=="ceeg_score") sc=i } }
  NR>1 && $nid=="RE:unk_001" && sc && $sc=="" { found=1 }
  END { exit !found }
' "$RE_FILE"; then
  grep 'RE:unk_001' "$RE_FILE" || true
  echo "FAIL: RE:unk_001 ceeg_score should be empty (not 0) — unmappable node" >&2; exit 1
fi

# ── 6. RE:proj_d_001 has projection_edge_id populated ────────────────────────

if ! awk -F'\t' '
  NR==1{ for(i=1;i<=NF;i++) { if($i=="node_id") nid=i; if($i=="projection_edge_id") eid=i } }
  NR>1 && $nid=="RE:proj_d_001" && eid && $eid=="E:proj_d_001" { found=1 }
  END { exit !found }
' "$RE_FILE"; then
  grep 'RE:proj_d_001' "$RE_FILE" || true
  echo "FAIL: RE:proj_d_001 should have projection_edge_id=E:proj_d_001" >&2; exit 1
fi

# ── 7. RE:obs_001 has no projection edge (source RE, not a projection target) ─

if ! awk -F'\t' '
  NR==1{ for(i=1;i<=NF;i++) { if($i=="node_id") nid=i; if($i=="projection_edge_id") eid=i } }
  NR>1 && $nid=="RE:obs_001" && eid && $eid=="" { found=1 }
  END { exit !found }
' "$RE_FILE"; then
  grep 'RE:obs_001' "$RE_FILE" || true
  echo "FAIL: RE:obs_001 should have empty projection_edge_id (it is a source, not a projection target)" >&2; exit 1
fi

# ── 8. System features: 1 row ─────────────────────────────────────────────────

sy_row_count=$(awk 'NR>1{c++} END{print c+0}' "$SY_FILE")
if [ "$sy_row_count" != "1" ]; then
  cat "$SY_FILE"
  echo "FAIL: system features expected 1 row, got $sy_row_count" >&2; exit 1
fi

# ── 9. System aggregate counts ────────────────────────────────────────────────

check_sys_field() {
  col="$1"; expected="$2"
  actual=$(awk -F'\t' -v c="$col" 'NR==1{for(i=1;i<=NF;i++)if($i==c)ci=i} NR==2&&ci{print $ci}' "$SY_FILE")
  if [ "$actual" != "$expected" ]; then
    cat "$SY_FILE"
    echo "FAIL: system_features $col expected '$expected', got '$actual'" >&2; exit 1
  fi
}

check_sys_field re_count                 5
check_sys_field observed_count           2
check_sys_field projected_direct_count   2
check_sys_field projected_indirect_count 1
check_sys_field unknown_unmappable_count 1
check_sys_field evidence_count           5
check_sys_field unknown_evidence_count   1
check_sys_field absent_evidence_count    4
check_sys_field n_supporting_species_max 3
check_sys_field data_modes               "bulk,hybrid,single_cell"
check_sys_field mean_ceeg_score          "0.6950"
check_sys_field max_ceeg_score           "0.9100"
check_sys_field min_ceeg_score           "0.4800"
check_sys_field component_node_ids        "RE:obs_001,RE:proj_d_001,RE:proj_d_sc_001,RE:proj_i_001,RE:unk_001"
check_sys_field evidence_ids              "EV:obs_001,EV:proj_d_001,EV:proj_d_sc_001,EV:proj_i_001,EV:unk_001"
check_sys_field component_ceeg_scores     "0.91,0.74,0.65,0.48,"

# ── 10. Evidence features: 5 rows ────────────────────────────────────────────

ev_row_count=$(awk 'NR>1{c++} END{print c+0}' "$EV_FILE")
if [ "$ev_row_count" != "5" ]; then
  cat "$EV_FILE"
  echo "FAIL: evidence features expected 5 rows, got $ev_row_count" >&2; exit 1
fi

# ── 11. EV:unk_001 has unknown_absent=unknown (must not be mapped to absent) ──

if ! awk -F'\t' '
  NR==1{ for(i=1;i<=NF;i++) { if($i=="evidence_id") ei=i; if($i=="unknown_absent") ua=i } }
  NR>1 && $ei=="EV:unk_001" && ua && $ua=="unknown" { found=1 }
  END { exit !found }
' "$EV_FILE"; then
  grep 'EV:unk_001' "$EV_FILE" || true
  echo "FAIL: EV:unk_001 unknown_absent must be 'unknown', not 'absent' or empty" >&2; exit 1
fi

# ── 12. EV:proj_d_001 has biological_system from joined node ─────────────────

if ! awk -F'\t' '
  NR==1{ for(i=1;i<=NF;i++) { if($i=="evidence_id") ei=i; if($i=="biological_system") bs=i } }
  NR>1 && $ei=="EV:proj_d_001" && bs && $bs=="generic_immune" { found=1 }
  END { exit !found }
' "$EV_FILE"; then
  grep 'EV:proj_d_001' "$EV_FILE" || true
  echo "FAIL: EV:proj_d_001 biological_system should be 'generic_immune' (joined from node)" >&2; exit 1
fi

# ── 13. EV:unk_001 ceeg_score is empty in evidence features ──────────────────

if ! awk -F'\t' '
  NR==1{ for(i=1;i<=NF;i++) { if($i=="evidence_id") ei=i; if($i=="ceeg_score") sc=i } }
  NR>1 && $ei=="EV:unk_001" && sc && $sc=="" { found=1 }
  END { exit !found }
' "$EV_FILE"; then
  grep 'EV:unk_001' "$EV_FILE" || true
  echo "FAIL: EV:unk_001 ceeg_score should be empty in evidence features" >&2; exit 1
fi

# ── 14. provenance is preserved verbatim ─────────────────────────────────────

if ! awk -F'\t' '
  NR==1{ for(i=1;i<=NF;i++) { if($i=="evidence_id") ei=i; if($i=="provenance") pr=i } }
  NR>1 && $ei=="EV:unk_001" && pr && $pr=="ceeg_v0.1:gap:assembly_v1" { found=1 }
  END { exit !found }
' "$EV_FILE"; then
  grep 'EV:unk_001' "$EV_FILE" || true
  echo "FAIL: EV:unk_001 provenance not preserved verbatim" >&2; exit 1
fi

# ── 16. RE features: evidence_id column present ──────────────────────────────
# Traceability requirement: each RE row must carry its source evidence_id.

if ! head -n 1 "$RE_FILE" | grep -qw 'evidence_id'; then
  head -n 1 "$RE_FILE"
  echo "FAIL: RE features missing evidence_id column (traceability requirement)" >&2; exit 1
fi

# ── 17. RE features: evidence_id values trace back to source evidence ─────────

for pair in \
  "RE:obs_001|EV:obs_001" \
  "RE:proj_d_001|EV:proj_d_001" \
  "RE:proj_d_sc_001|EV:proj_d_sc_001" \
  "RE:proj_i_001|EV:proj_i_001" \
  "RE:unk_001|EV:unk_001"; do
  nid="${pair%%|*}"; eid="${pair##*|}"
  if ! awk -F'\t' -v n="$nid" -v e="$eid" '
    NR==1{for(i=1;i<=NF;i++){if($i=="node_id")ni=i; if($i=="evidence_id")ei=i}}
    NR>1&&$ni==n&&ei&&$ei==e{found=1}
    END{exit !found}' "$RE_FILE"; then
    grep "$nid" "$RE_FILE" || true
    echo "FAIL: RE feature $nid should have evidence_id=$eid" >&2; exit 1
  fi
done

# ── 18. RE features: species_id values correct ────────────────────────────────

for pair in \
  "RE:obs_001|Mus_musculus" \
  "RE:proj_d_001|Danio_rerio" \
  "RE:proj_d_sc_001|Danio_rerio" \
  "RE:proj_i_001|Xenopus_tropicalis" \
  "RE:unk_001|Mus_musculus"; do
  nid="${pair%%|*}"; expected="${pair##*|}"
  actual=$(awk -F'\t' -v n="$nid" \
    'NR==1{for(i=1;i<=NF;i++){if($i=="node_id")ni=i;if($i=="species_id")si=i}}
     NR>1&&$ni==n&&si{print $si}' "$RE_FILE")
  if [ "$actual" != "$expected" ]; then
    grep "$nid" "$RE_FILE" || true
    echo "FAIL: $nid expected species_id=$expected, got '$actual'" >&2; exit 1
  fi
done

# ── 18a. system_id fallback is preserved in RE and evidence features ──────────

for pair in "$RE_FILE|node_id|RE:proj_d_001|system_id|generic_immune" \
            "$EV_FILE|evidence_id|EV:proj_d_001|system_id|generic_immune"; do
  file=$(printf '%s' "$pair" | cut -d'|' -f1)
  key_col=$(printf '%s' "$pair" | cut -d'|' -f2)
  key_val=$(printf '%s' "$pair" | cut -d'|' -f3)
  target_col=$(printf '%s' "$pair" | cut -d'|' -f4)
  expected=$(printf '%s' "$pair" | cut -d'|' -f5)
  actual=$(awk -F'\t' -v kc="$key_col" -v kv="$key_val" -v tc="$target_col" '
    NR==1{for(i=1;i<=NF;i++){if($i==kc)ki=i;if($i==tc)ti=i}}
    NR>1&&$ki==kv&&ti{print $ti}' "$file")
  if [ "$actual" != "$expected" ]; then
    grep "$key_val" "$file" || true
    echo "FAIL: $key_val expected $target_col=$expected, got '$actual'" >&2; exit 1
  fi
done

# ── 19. RE features: data_mode preserved verbatim for single_cell and hybrid ──

for pair in "RE:proj_d_sc_001|single_cell" "RE:proj_i_001|hybrid"; do
  nid="${pair%%|*}"; expected="${pair##*|}"
  actual=$(awk -F'\t' -v n="$nid" \
    'NR==1{for(i=1;i<=NF;i++){if($i=="node_id")ni=i;if($i=="data_mode")di=i}}
     NR>1&&$ni==n&&di{print $di}' "$RE_FILE")
  if [ "$actual" != "$expected" ]; then
    grep "$nid" "$RE_FILE" || true
    echo "FAIL: $nid expected data_mode=$expected, got '$actual'" >&2; exit 1
  fi
done

# ── 20. EV features: data_mode preserved verbatim for single_cell and hybrid ──

for pair in "EV:proj_d_sc_001|single_cell" "EV:proj_i_001|hybrid"; do
  eid="${pair%%|*}"; expected="${pair##*|}"
  actual=$(awk -F'\t' -v e="$eid" \
    'NR==1{for(i=1;i<=NF;i++){if($i=="evidence_id")ei=i;if($i=="data_mode")di=i}}
     NR>1&&$ei==e&&di{print $di}' "$EV_FILE")
  if [ "$actual" != "$expected" ]; then
    grep "$eid" "$EV_FILE" || true
    echo "FAIL: $eid expected data_mode=$expected, got '$actual'" >&2; exit 1
  fi
done

# ── 21. EV features: absent preserved verbatim (distinct from unknown) ────────

if ! awk -F'\t' '
  NR==1{for(i=1;i<=NF;i++){if($i=="evidence_id")ei=i;if($i=="unknown_absent")ua=i}}
  NR>1&&$ei=="EV:proj_d_001"&&ua&&$ua=="absent"{found=1}
  END{exit !found}' "$EV_FILE"; then
  grep 'EV:proj_d_001' "$EV_FILE" || true
  echo "FAIL: EV:proj_d_001 unknown_absent must be 'absent'" >&2; exit 1
fi

# ── 22. RE features: n_supporting_species=0 for unmappable (not empty) ───────
# Zero is a valid, distinct value — must not be collapsed to "" like ceeg_score.

actual=$(awk -F'\t' '
  NR==1{for(i=1;i<=NF;i++){if($i=="node_id")ni=i;if($i=="n_supporting_species")ns=i}}
  NR>1&&$ni=="RE:unk_001"&&ns{print $ns}' "$RE_FILE")
if [ "$actual" != "0" ]; then
  grep 'RE:unk_001' "$RE_FILE" || true
  echo "FAIL: RE:unk_001 n_supporting_species should be '0' (not empty), got '$actual'" >&2; exit 1
fi

# ── 23. duplicate metrics node_id aborts builder; no output files written ─────
# BUG-1: without duplicate guard, last row silently wins (wrong score/rank used).

MISSING_COL_IMPORT="$TMP_DIR/missing_col_import"
mkdir -p "$MISSING_COL_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$MISSING_COL_IMPORT/"
awk -F'\t' 'BEGIN{OFS="\t"} {for(i=1;i<=NF;i++) if(i!=3) printf "%s%s", (i==1 ? "" : OFS), $i; print ""}' \
  "$MISSING_COL_IMPORT/ceeg_imported_nodes.tsv" > "$MISSING_COL_IMPORT/tmp" \
  && mv "$MISSING_COL_IMPORT/tmp" "$MISSING_COL_IMPORT/ceeg_imported_nodes.tsv"
MISSING_COL_OUT="$TMP_DIR/missing_col_out"
mkdir -p "$MISSING_COL_OUT"
if python3 "$BUILDER" \
     --import-dir "$MISSING_COL_IMPORT" --outdir "$MISSING_COL_OUT" \
     > "$MISSING_COL_OUT/stdout.txt" 2>&1; then
  cat "$MISSING_COL_OUT/stdout.txt"
  echo "FAIL: builder should exit non-zero on missing required imported column" >&2; exit 1
fi
if ! grep -q 'missing required column' "$MISSING_COL_OUT/stdout.txt"; then
  cat "$MISSING_COL_OUT/stdout.txt"
  echo "FAIL: builder did not clearly report missing required imported column" >&2; exit 1
fi
for f in ceeg_regulatory_projection_features.tsv ceeg_system_features.tsv ceeg_evidence_features.tsv; do
  if [ -f "$MISSING_COL_OUT/$f" ]; then
    echo "FAIL: builder wrote $f despite missing required imported column" >&2; exit 1
  fi
done

MALFORMED_IMPORT="$TMP_DIR/malformed_import"
mkdir -p "$MALFORMED_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$MALFORMED_IMPORT/"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$0=$0 "\textra"} {print}' \
  "$MALFORMED_IMPORT/ceeg_imported_nodes.tsv" > "$MALFORMED_IMPORT/tmp" \
  && mv "$MALFORMED_IMPORT/tmp" "$MALFORMED_IMPORT/ceeg_imported_nodes.tsv"
MALFORMED_OUT="$TMP_DIR/malformed_out"
mkdir -p "$MALFORMED_OUT"
if python3 "$BUILDER" \
     --import-dir "$MALFORMED_IMPORT" --outdir "$MALFORMED_OUT" \
     > "$MALFORMED_OUT/stdout.txt" 2>&1; then
  cat "$MALFORMED_OUT/stdout.txt"
  echo "FAIL: builder should exit non-zero on malformed imported TSV row" >&2; exit 1
fi
if ! grep -q 'malformed TSV row' "$MALFORMED_OUT/stdout.txt"; then
  cat "$MALFORMED_OUT/stdout.txt"
  echo "FAIL: builder did not clearly report malformed imported TSV row" >&2; exit 1
fi
for f in ceeg_regulatory_projection_features.tsv ceeg_system_features.tsv ceeg_evidence_features.tsv; do
  if [ -f "$MALFORMED_OUT/$f" ]; then
    echo "FAIL: builder wrote $f despite malformed imported TSV row" >&2; exit 1
  fi
done

DUP_HEADER_IMPORT="$TMP_DIR/dup_header_import"
mkdir -p "$DUP_HEADER_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$DUP_HEADER_IMPORT/"
awk -F'\t' 'BEGIN{OFS="\t"} NR==1{$2=$1} {print}' \
  "$DUP_HEADER_IMPORT/ceeg_imported_nodes.tsv" > "$DUP_HEADER_IMPORT/tmp" \
  && mv "$DUP_HEADER_IMPORT/tmp" "$DUP_HEADER_IMPORT/ceeg_imported_nodes.tsv"
DUP_HEADER_OUT="$TMP_DIR/dup_header_out"
mkdir -p "$DUP_HEADER_OUT"
if python3 "$BUILDER" \
     --import-dir "$DUP_HEADER_IMPORT" --outdir "$DUP_HEADER_OUT" \
     > "$DUP_HEADER_OUT/stdout.txt" 2>&1; then
  cat "$DUP_HEADER_OUT/stdout.txt"
  echo "FAIL: builder should exit non-zero on duplicate imported TSV header" >&2; exit 1
fi
if ! grep -q 'duplicate column header' "$DUP_HEADER_OUT/stdout.txt"; then
  cat "$DUP_HEADER_OUT/stdout.txt"
  echo "FAIL: builder did not clearly report duplicate imported TSV header" >&2; exit 1
fi
for f in ceeg_regulatory_projection_features.tsv ceeg_system_features.tsv ceeg_evidence_features.tsv; do
  if [ -f "$DUP_HEADER_OUT/$f" ]; then
    echo "FAIL: builder wrote $f despite duplicate imported TSV header" >&2; exit 1
  fi
done

EMPTY_HEADER_IMPORT="$TMP_DIR/empty_header_import"
mkdir -p "$EMPTY_HEADER_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$EMPTY_HEADER_IMPORT/"
awk -F'\t' 'BEGIN{OFS="\t"} NR==1{$2=""} {print}' \
  "$EMPTY_HEADER_IMPORT/ceeg_imported_nodes.tsv" > "$EMPTY_HEADER_IMPORT/tmp" \
  && mv "$EMPTY_HEADER_IMPORT/tmp" "$EMPTY_HEADER_IMPORT/ceeg_imported_nodes.tsv"
EMPTY_HEADER_OUT="$TMP_DIR/empty_header_out"
mkdir -p "$EMPTY_HEADER_OUT"
if python3 "$BUILDER" \
     --import-dir "$EMPTY_HEADER_IMPORT" --outdir "$EMPTY_HEADER_OUT" \
     > "$EMPTY_HEADER_OUT/stdout.txt" 2>&1; then
  cat "$EMPTY_HEADER_OUT/stdout.txt"
  echo "FAIL: builder should exit non-zero on empty imported TSV header" >&2; exit 1
fi
if ! grep -q 'empty column header' "$EMPTY_HEADER_OUT/stdout.txt"; then
  cat "$EMPTY_HEADER_OUT/stdout.txt"
  echo "FAIL: builder did not clearly report empty imported TSV header" >&2; exit 1
fi
for f in ceeg_regulatory_projection_features.tsv ceeg_system_features.tsv ceeg_evidence_features.tsv; do
  if [ -f "$EMPTY_HEADER_OUT/$f" ]; then
    echo "FAIL: builder wrote $f despite empty imported TSV header" >&2; exit 1
  fi
done

DUP_NODE_IMPORT="$TMP_DIR/dup_node_import"
mkdir -p "$DUP_NODE_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$DUP_NODE_IMPORT/"
awk 'NR==2{print}' "$DUP_NODE_IMPORT/ceeg_imported_nodes.tsv" \
  >> "$DUP_NODE_IMPORT/ceeg_imported_nodes.tsv"
DUP_NODE_OUT="$TMP_DIR/dup_node_out"
mkdir -p "$DUP_NODE_OUT"
if python3 "$BUILDER" \
     --import-dir "$DUP_NODE_IMPORT" --outdir "$DUP_NODE_OUT" \
     > "$DUP_NODE_OUT/stdout.txt" 2>&1; then
  cat "$DUP_NODE_OUT/stdout.txt"
  echo "FAIL: builder should exit non-zero on duplicate imported node_id" >&2; exit 1
fi
if ! grep -q 'duplicate node_id' "$DUP_NODE_OUT/stdout.txt"; then
  cat "$DUP_NODE_OUT/stdout.txt"
  echo "FAIL: builder did not clearly report duplicate imported node_id" >&2; exit 1
fi
for f in ceeg_regulatory_projection_features.tsv ceeg_system_features.tsv ceeg_evidence_features.tsv; do
  if [ -f "$DUP_NODE_OUT/$f" ]; then
    echo "FAIL: builder wrote $f despite duplicate imported node_id" >&2; exit 1
  fi
done

DUP_EVIDENCE_IMPORT="$TMP_DIR/dup_evidence_import"
mkdir -p "$DUP_EVIDENCE_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$DUP_EVIDENCE_IMPORT/"
awk 'NR==2{print}' "$DUP_EVIDENCE_IMPORT/ceeg_imported_evidence.tsv" \
  >> "$DUP_EVIDENCE_IMPORT/ceeg_imported_evidence.tsv"
DUP_EVIDENCE_OUT="$TMP_DIR/dup_evidence_out"
mkdir -p "$DUP_EVIDENCE_OUT"
if python3 "$BUILDER" \
     --import-dir "$DUP_EVIDENCE_IMPORT" --outdir "$DUP_EVIDENCE_OUT" \
     > "$DUP_EVIDENCE_OUT/stdout.txt" 2>&1; then
  cat "$DUP_EVIDENCE_OUT/stdout.txt"
  echo "FAIL: builder should exit non-zero on duplicate imported evidence_id" >&2; exit 1
fi
if ! grep -q 'duplicate evidence_id' "$DUP_EVIDENCE_OUT/stdout.txt"; then
  cat "$DUP_EVIDENCE_OUT/stdout.txt"
  echo "FAIL: builder did not clearly report duplicate imported evidence_id" >&2; exit 1
fi
for f in ceeg_regulatory_projection_features.tsv ceeg_system_features.tsv ceeg_evidence_features.tsv; do
  if [ -f "$DUP_EVIDENCE_OUT/$f" ]; then
    echo "FAIL: builder wrote $f despite duplicate imported evidence_id" >&2; exit 1
  fi
done

EMPTY_NODE_ID_IMPORT="$TMP_DIR/empty_node_id_import"
mkdir -p "$EMPTY_NODE_ID_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$EMPTY_NODE_ID_IMPORT/"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$1=""} {print}' \
  "$EMPTY_NODE_ID_IMPORT/ceeg_imported_nodes.tsv" > "$EMPTY_NODE_ID_IMPORT/tmp" \
  && mv "$EMPTY_NODE_ID_IMPORT/tmp" "$EMPTY_NODE_ID_IMPORT/ceeg_imported_nodes.tsv"
EMPTY_NODE_ID_OUT="$TMP_DIR/empty_node_id_out"
mkdir -p "$EMPTY_NODE_ID_OUT"
if python3 "$BUILDER" \
     --import-dir "$EMPTY_NODE_ID_IMPORT" --outdir "$EMPTY_NODE_ID_OUT" \
     > "$EMPTY_NODE_ID_OUT/stdout.txt" 2>&1; then
  cat "$EMPTY_NODE_ID_OUT/stdout.txt"
  echo "FAIL: builder should exit non-zero on empty imported node_id" >&2; exit 1
fi
if ! grep -q 'empty required value for node_id' "$EMPTY_NODE_ID_OUT/stdout.txt"; then
  cat "$EMPTY_NODE_ID_OUT/stdout.txt"
  echo "FAIL: builder did not clearly report empty imported node_id" >&2; exit 1
fi
for f in ceeg_regulatory_projection_features.tsv ceeg_system_features.tsv ceeg_evidence_features.tsv; do
  if [ -f "$EMPTY_NODE_ID_OUT/$f" ]; then
    echo "FAIL: builder wrote $f despite empty imported node_id" >&2; exit 1
  fi
done

DUP_EDGE_ID_IMPORT="$TMP_DIR/dup_edge_id_import"
mkdir -p "$DUP_EDGE_ID_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$DUP_EDGE_ID_IMPORT/"
awk 'NR==2{print}' "$DUP_EDGE_ID_IMPORT/ceeg_imported_edges.tsv" \
  >> "$DUP_EDGE_ID_IMPORT/ceeg_imported_edges.tsv"
DUP_EDGE_ID_OUT="$TMP_DIR/dup_edge_id_out"
mkdir -p "$DUP_EDGE_ID_OUT"
if python3 "$BUILDER" \
     --import-dir "$DUP_EDGE_ID_IMPORT" --outdir "$DUP_EDGE_ID_OUT" \
     > "$DUP_EDGE_ID_OUT/stdout.txt" 2>&1; then
  cat "$DUP_EDGE_ID_OUT/stdout.txt"
  echo "FAIL: builder should exit non-zero on duplicate imported edge_id" >&2; exit 1
fi
if ! grep -q 'duplicate edge_id' "$DUP_EDGE_ID_OUT/stdout.txt"; then
  cat "$DUP_EDGE_ID_OUT/stdout.txt"
  echo "FAIL: builder did not clearly report duplicate imported edge_id" >&2; exit 1
fi
for f in ceeg_regulatory_projection_features.tsv ceeg_system_features.tsv ceeg_evidence_features.tsv; do
  if [ -f "$DUP_EDGE_ID_OUT/$f" ]; then
    echo "FAIL: builder wrote $f despite duplicate imported edge_id" >&2; exit 1
  fi
done

DUP_MET_IMPORT="$TMP_DIR/dup_met_import"
mkdir -p "$DUP_MET_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$DUP_MET_IMPORT/"
awk 'NR==2{print}' "$DUP_MET_IMPORT/ceeg_imported_metrics.tsv" \
  >> "$DUP_MET_IMPORT/ceeg_imported_metrics.tsv"
DUP_MET_OUT="$TMP_DIR/dup_met_out"
mkdir -p "$DUP_MET_OUT"
if python3 "$BUILDER" \
     --import-dir "$DUP_MET_IMPORT" --outdir "$DUP_MET_OUT" \
     > "$DUP_MET_OUT/stdout.txt" 2>&1; then
  cat "$DUP_MET_OUT/stdout.txt"
  echo "FAIL: builder should exit non-zero on duplicate metrics node_id" >&2; exit 1
fi
for f in ceeg_regulatory_projection_features.tsv ceeg_system_features.tsv ceeg_evidence_features.tsv; do
  if [ -f "$DUP_MET_OUT/$f" ]; then
    echo "FAIL: builder wrote $f despite duplicate metrics node — no outputs must be written" >&2; exit 1
  fi
done

# ── 24. duplicate edge target_node_id aborts builder; no output files written ─

DUP_EDGE_IMPORT="$TMP_DIR/dup_edge_import"
mkdir -p "$DUP_EDGE_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$DUP_EDGE_IMPORT/"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$1=$1 "_dup"; print}' "$DUP_EDGE_IMPORT/ceeg_imported_edges.tsv" \
  >> "$DUP_EDGE_IMPORT/ceeg_imported_edges.tsv"
DUP_EDGE_OUT="$TMP_DIR/dup_edge_out"
mkdir -p "$DUP_EDGE_OUT"
if python3 "$BUILDER" \
     --import-dir "$DUP_EDGE_IMPORT" --outdir "$DUP_EDGE_OUT" \
     > "$DUP_EDGE_OUT/stdout.txt" 2>&1; then
  cat "$DUP_EDGE_OUT/stdout.txt"
  echo "FAIL: builder should exit non-zero on duplicate edge target_node_id" >&2; exit 1
fi
if ! grep -q 'duplicate target_node_id' "$DUP_EDGE_OUT/stdout.txt"; then
  cat "$DUP_EDGE_OUT/stdout.txt"
  echo "FAIL: builder did not clearly report duplicate edge target_node_id" >&2; exit 1
fi
for f in ceeg_regulatory_projection_features.tsv ceeg_system_features.tsv ceeg_evidence_features.tsv; do
  if [ -f "$DUP_EDGE_OUT/$f" ]; then
    echo "FAIL: builder wrote $f despite duplicate edge target — no outputs must be written" >&2; exit 1
  fi
done

# ── 25. module file exists and has correct process name ──────────────────────

NF_FILE="$ROOT_DIR/modules/local/build_came_ceeg_feature_matrices.nf"
if [ ! -f "$NF_FILE" ]; then
  echo "FAIL: module not found: $NF_FILE" >&2; exit 1
fi
if ! grep -q 'BUILD_CAME_CEEG_FEATURE_MATRICES' "$NF_FILE"; then
  echo "FAIL: module missing process BUILD_CAME_CEEG_FEATURE_MATRICES" >&2; exit 1
fi
if ! grep -q 'ceeg_stub' "$NF_FILE"; then
  echo "FAIL: module missing ceeg_stub variable" >&2; exit 1
fi

# ── 30. Nextflow stub: RE features header includes evidence_id ────────────────
# BUG-A: stub printf was missing evidence_id (13 cols vs 14), causing schema
# mismatch between stub mode and real mode.

if ! grep -q 'node_id.*evidence_id' "$NF_FILE"; then
  grep 'ceeg_regulatory_projection_features' "$NF_FILE" || true
  echo "FAIL: stub RE features printf missing evidence_id (BUG-A: stub/real schema mismatch)" >&2; exit 1
fi

# ── 26. RE features: projection_weight comes from edge table (not metrics) ────
# Review: no projection confidence must be treated as activity or functional claim.

actual=$(awk -F'\t' -v n="RE:proj_d_001" \
  'NR==1{for(i=1;i<=NF;i++){if($i=="node_id")ni=i;if($i=="projection_weight")pw=i}}
   NR>1&&$ni==n&&pw{print $pw}' "$RE_FILE")
if [ "$actual" != "0.87" ]; then
  grep 'RE:proj_d_001' "$RE_FILE" || true
  echo "FAIL: RE:proj_d_001 expected projection_weight=0.87 (from edge E:proj_d_001), got '$actual'" >&2; exit 1
fi

# ── 27. RE features: ceeg_score for projected_direct equals metrics value ─────
# Must be the CEEG-derived score (0.74), not a conservation-inferred value.

actual=$(awk -F'\t' -v n="RE:proj_d_001" \
  'NR==1{for(i=1;i<=NF;i++){if($i=="node_id")ni=i;if($i=="ceeg_score")sc=i}}
   NR>1&&$ni==n&&sc{print $sc}' "$RE_FILE")
if [ "$actual" != "0.74" ]; then
  grep 'RE:proj_d_001' "$RE_FILE" || true
  echo "FAIL: RE:proj_d_001 expected ceeg_score=0.74 (from metrics), got '$actual'" >&2; exit 1
fi

# ── 28. EV features: evidence_status comes from node (not reclassified) ───────
# EV:proj_d_001 evidence_type=direct_RE_projection; node evidence_status=projected_direct.
# The output must use the node's evidence_status, not infer status from evidence_type.

actual=$(awk -F'\t' -v e="EV:proj_d_001" \
  'NR==1{for(i=1;i<=NF;i++){if($i=="evidence_id")ei=i;if($i=="evidence_status")es=i}}
   NR>1&&$ei==e&&es{print $es}' "$EV_FILE")
if [ "$actual" != "projected_direct" ]; then
  grep 'EV:proj_d_001' "$EV_FILE" || true
  echo "FAIL: EV:proj_d_001 expected evidence_status=projected_direct (from node), got '$actual'" >&2; exit 1
fi

# ── 29. evidence for non-RE node emits a WARNING; excluded from system counts ─
# BUG-6: previously the drop was silent — callers had no indication evidence was lost.

BS_EV_IMPORT="$TMP_DIR/bs_ev_import"
mkdir -p "$BS_EV_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$BS_EV_IMPORT/"
printf 'EV:bs_001\tBS:generic_immune\t\tdirect_observation\tbulk\tabsent\ttest\tnotes\ttest_src\n' \
  >> "$BS_EV_IMPORT/ceeg_imported_evidence.tsv"
BS_EV_OUT="$TMP_DIR/bs_ev_out"
mkdir -p "$BS_EV_OUT"
if ! python3 "$BUILDER" \
     --import-dir "$BS_EV_IMPORT" --outdir "$BS_EV_OUT" \
     > "$BS_EV_OUT/stdout.txt" 2>"$BS_EV_OUT/stderr.txt"; then
  cat "$BS_EV_OUT/stdout.txt"; cat "$BS_EV_OUT/stderr.txt"
  echo "FAIL: builder should exit 0 when evidence references a non-RE node" >&2; exit 1
fi
if ! grep -q 'WARNING' "$BS_EV_OUT/stderr.txt"; then
  cat "$BS_EV_OUT/stderr.txt"
  echo "FAIL: builder must emit WARNING when evidence references a non-RE node (BUG-6: silent drop)" >&2; exit 1
fi
sys_ev_count=$(awk -F'\t' \
  'NR==1{for(i=1;i<=NF;i++)if($i=="evidence_count")ci=i} NR==2&&ci{print $ci}' \
  "$BS_EV_OUT/ceeg_system_features.tsv")
if [ "$sys_ev_count" != "5" ]; then
  cat "$BS_EV_OUT/ceeg_system_features.tsv"
  echo "FAIL: non-RE evidence must not inflate system evidence_count; expected 5, got '$sys_ev_count'" >&2; exit 1
fi

# ── 31. BS-node evidence: WARNING from EV features loop + row counted ─────────
# BUG-B: EV features loop had no warning for BS-node evidence (only the system
# aggregates loop warned). After fix, both loops emit WARNING, and the EV
# features row count includes the BS-node evidence row (6 total).

ev_row_count_bs=$(awk 'NR>1{c++} END{print c+0}' "$BS_EV_OUT/ceeg_evidence_features.tsv")
if [ "$ev_row_count_bs" != "6" ]; then
  cat "$BS_EV_OUT/ceeg_evidence_features.tsv"
  echo "FAIL: BS-node evidence must appear in evidence features (expected 6 rows), got $ev_row_count_bs" >&2; exit 1
fi
if ! grep -q 'included in evidence features' "$BS_EV_OUT/stderr.txt"; then
  cat "$BS_EV_OUT/stderr.txt"
  echo "FAIL: EV features loop must emit WARNING for BS-node evidence (BUG-B: silent gap)" >&2; exit 1
fi

# ── 32. RISK-2: projected node with no edge must emit WARNING ─────────────────
# RE:proj_d_sc_001 has evidence_status=projected_direct but no edge row.
# After fix, builder emits WARNING to stderr (captured in stdout.txt via 2>&1 at top).

if ! grep -q 'no projection edge' "$FEAT_OUT/stdout.txt"; then
  cat "$FEAT_OUT/stdout.txt"
  echo "FAIL: builder must emit WARNING for projected node with no projection edge (RISK-2)" >&2; exit 1
fi
if ! grep -q "RE:proj_d_sc_001" "$FEAT_OUT/stdout.txt"; then
  cat "$FEAT_OUT/stdout.txt"
  echo "FAIL: RISK-2 WARNING must identify RE:proj_d_sc_001 by node_id" >&2; exit 1
fi
# Observed nodes must NOT trigger the warning (RE:obs_001 has no edge but is not projected)
if grep -q 'RE:obs_001.*no projection edge\|no projection edge.*RE:obs_001' "$FEAT_OUT/stdout.txt"; then
  cat "$FEAT_OUT/stdout.txt"
  echo "FAIL: RISK-2 WARNING must not fire for observed node RE:obs_001" >&2; exit 1
fi

# ── 33. RISK-3: non-numeric ceeg_score must abort builder with clear message ──

NONNUM_MET_IMPORT="$TMP_DIR/nonnum_met_import"
mkdir -p "$NONNUM_MET_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$NONNUM_MET_IMPORT/"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$4="N/A"} {print}' \
  "$NONNUM_MET_IMPORT/ceeg_imported_metrics.tsv" > "$NONNUM_MET_IMPORT/tmp" \
  && mv "$NONNUM_MET_IMPORT/tmp" "$NONNUM_MET_IMPORT/ceeg_imported_metrics.tsv"
NONNUM_MET_OUT="$TMP_DIR/nonnum_met_out"
mkdir -p "$NONNUM_MET_OUT"
if python3 "$BUILDER" \
     --import-dir "$NONNUM_MET_IMPORT" --outdir "$NONNUM_MET_OUT" \
     > "$NONNUM_MET_OUT/stdout.txt" 2>&1; then
  cat "$NONNUM_MET_OUT/stdout.txt"
  echo "FAIL: builder should exit non-zero on non-numeric ceeg_score (RISK-3)" >&2; exit 1
fi
if ! grep -q 'non-numeric ceeg_score' "$NONNUM_MET_OUT/stdout.txt"; then
  cat "$NONNUM_MET_OUT/stdout.txt"
  echo "FAIL: builder must emit clear error message for non-numeric ceeg_score (RISK-3)" >&2; exit 1
fi
for f in ceeg_regulatory_projection_features.tsv ceeg_system_features.tsv ceeg_evidence_features.tsv; do
  if [ -f "$NONNUM_MET_OUT/$f" ]; then
    echo "FAIL: builder wrote $f despite non-numeric ceeg_score — no outputs must be written" >&2; exit 1
  fi
done

# ── 34. RISK-3: non-numeric n_supporting_species must abort builder with clear message ──

NONNUM_NS_IMPORT="$TMP_DIR/nonnum_ns_import"
mkdir -p "$NONNUM_NS_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$NONNUM_NS_IMPORT/"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$6="bad"} {print}' \
  "$NONNUM_NS_IMPORT/ceeg_imported_metrics.tsv" > "$NONNUM_NS_IMPORT/tmp" \
  && mv "$NONNUM_NS_IMPORT/tmp" "$NONNUM_NS_IMPORT/ceeg_imported_metrics.tsv"
NONNUM_NS_OUT="$TMP_DIR/nonnum_ns_out"
mkdir -p "$NONNUM_NS_OUT"
if python3 "$BUILDER" \
     --import-dir "$NONNUM_NS_IMPORT" --outdir "$NONNUM_NS_OUT" \
     > "$NONNUM_NS_OUT/stdout.txt" 2>&1; then
  cat "$NONNUM_NS_OUT/stdout.txt"
  echo "FAIL: builder should exit non-zero on non-numeric n_supporting_species (RISK-3)" >&2; exit 1
fi
if ! grep -q 'non-numeric n_supporting_species' "$NONNUM_NS_OUT/stdout.txt"; then
  cat "$NONNUM_NS_OUT/stdout.txt"
  echo "FAIL: builder must emit clear error for non-numeric n_supporting_species (RISK-3)" >&2; exit 1
fi
for f in ceeg_regulatory_projection_features.tsv ceeg_system_features.tsv ceeg_evidence_features.tsv; do
  if [ -f "$NONNUM_NS_OUT/$f" ]; then
    echo "FAIL: builder wrote $f despite non-numeric n_supporting_species — no outputs must be written" >&2; exit 1
  fi
done

# ── 35. RISK-4: orphaned evidence (unknown node_id) must emit WARNING ──────────
# Importer blocks this in validated bundles; builder must still warn on manually edited imports.

ORPHAN_EV_IMPORT="$TMP_DIR/orphan_ev_import"
mkdir -p "$ORPHAN_EV_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$ORPHAN_EV_IMPORT/"
printf 'EV:orphan_001\tNE:orphan_test\t\tdirect_observation\tbulk\tabsent\ttest\tnotes\ttest_src\n' \
  >> "$ORPHAN_EV_IMPORT/ceeg_imported_evidence.tsv"
ORPHAN_EV_OUT="$TMP_DIR/orphan_ev_out"
mkdir -p "$ORPHAN_EV_OUT"
if ! python3 "$BUILDER" \
     --import-dir "$ORPHAN_EV_IMPORT" --outdir "$ORPHAN_EV_OUT" \
     > "$ORPHAN_EV_OUT/stdout.txt" 2>"$ORPHAN_EV_OUT/stderr.txt"; then
  cat "$ORPHAN_EV_OUT/stdout.txt"; cat "$ORPHAN_EV_OUT/stderr.txt"
  echo "FAIL: builder should exit 0 when evidence references unknown node (RISK-4)" >&2; exit 1
fi
if ! grep -q 'not found in imported nodes' "$ORPHAN_EV_OUT/stderr.txt"; then
  cat "$ORPHAN_EV_OUT/stderr.txt"
  echo "FAIL: builder must emit WARNING for orphaned evidence node_id (RISK-4)" >&2; exit 1
fi

# ── 36. RISK-1: multi-evidence node produces comma-joined evidence_id ──────────
# A node with two evidence rows must carry both IDs in evidence_id (comma-separated).

MULTI_EV_IMPORT="$TMP_DIR/multi_ev_import"
mkdir -p "$MULTI_EV_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$MULTI_EV_IMPORT/"
printf 'EV:obs_002\tRE:obs_001\t\tdirect_observation\tbulk\tabsent\tceeg_v0.1:assay:ATAC-seq_rep2\trep2\ttest_src\n' \
  >> "$MULTI_EV_IMPORT/ceeg_imported_evidence.tsv"
MULTI_EV_OUT="$TMP_DIR/multi_ev_out"
mkdir -p "$MULTI_EV_OUT"
if ! python3 "$BUILDER" \
     --import-dir "$MULTI_EV_IMPORT" --outdir "$MULTI_EV_OUT" \
     > "$MULTI_EV_OUT/stdout.txt" 2>&1; then
  cat "$MULTI_EV_OUT/stdout.txt"
  echo "FAIL: builder should exit 0 with multi-evidence node (RISK-1)" >&2; exit 1
fi
# Both IDs must appear in the comma-separated evidence_id for RE:obs_001
if ! awk -F'\t' -v n="RE:obs_001" '
  NR==1{for(i=1;i<=NF;i++){if($i=="node_id")ni=i; if($i=="evidence_id")ei=i}}
  NR>1&&$ni==n&&ei{val=$ei; found=1}
  END{if(!found||val!~/EV:obs_001/||val!~/EV:obs_002/) exit 1}
' "$MULTI_EV_OUT/ceeg_regulatory_projection_features.tsv"; then
  grep 'RE:obs_001' "$MULTI_EV_OUT/ceeg_regulatory_projection_features.tsv" || true
  echo "FAIL: RE:obs_001 evidence_id must contain both EV:obs_001 and EV:obs_002 (RISK-1: comma-join)" >&2; exit 1
fi
# System evidence_count must include the additional row (6 total: 5 original + 1 new)
sys_ev_count_multi=$(awk -F'\t' \
  'NR==1{for(i=1;i<=NF;i++)if($i=="evidence_count")ci=i} NR==2&&ci{print $ci}' \
  "$MULTI_EV_OUT/ceeg_system_features.tsv")
if [ "$sys_ev_count_multi" != "6" ]; then
  cat "$MULTI_EV_OUT/ceeg_system_features.tsv"
  echo "FAIL: system evidence_count must be 6 with multi-evidence node, got '$sys_ev_count_multi'" >&2; exit 1
fi

# ── 37. Projection/activity separation: ceeg_score ≠ projection_weight for RE:proj_d_001 ──
# projection_weight (alignment identity from edge) must not equal ceeg_score (CEEG metric).
# 0.87 (edge weight) vs 0.74 (ceeg_score) — different values, different sources.

proj_weight=$(awk -F'\t' -v n="RE:proj_d_001" \
  'NR==1{for(i=1;i<=NF;i++){if($i=="node_id")ni=i;if($i=="projection_weight")pw=i}}
   NR>1&&$ni==n&&pw{print $pw}' "$RE_FILE")
proj_score=$(awk -F'\t' -v n="RE:proj_d_001" \
  'NR==1{for(i=1;i<=NF;i++){if($i=="node_id")ni=i;if($i=="ceeg_score")sc=i}}
   NR>1&&$ni==n&&sc{print $sc}' "$RE_FILE")
if [ "$proj_weight" = "$proj_score" ]; then
  grep 'RE:proj_d_001' "$RE_FILE" || true
  echo "FAIL: projection_weight and ceeg_score must be distinct values (projection ≠ activity); both='$proj_weight'" >&2; exit 1
fi
if [ "$proj_weight" != "0.87" ] || [ "$proj_score" != "0.74" ]; then
  echo "FAIL: RE:proj_d_001 expected projection_weight=0.87 ceeg_score=0.74, got weight='$proj_weight' score='$proj_score'" >&2; exit 1
fi

# Edge projection confidence must not affect system score aggregates.
WEIGHT_IMPORT="$TMP_DIR/weight_import"
mkdir -p "$WEIGHT_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$WEIGHT_IMPORT/"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$7="99.0"} {print}' \
  "$WEIGHT_IMPORT/ceeg_imported_edges.tsv" > "$WEIGHT_IMPORT/tmp" \
  && mv "$WEIGHT_IMPORT/tmp" "$WEIGHT_IMPORT/ceeg_imported_edges.tsv"
WEIGHT_OUT="$TMP_DIR/weight_out"
mkdir -p "$WEIGHT_OUT"
if ! python3 "$BUILDER" \
     --import-dir "$WEIGHT_IMPORT" --outdir "$WEIGHT_OUT" \
     > "$WEIGHT_OUT/stdout.txt" 2>&1; then
  cat "$WEIGHT_OUT/stdout.txt"
  echo "FAIL: builder should exit 0 when projection_weight changes" >&2; exit 1
fi
weight_mean=$(awk -F'\t' \
  'NR==1{for(i=1;i<=NF;i++)if($i=="mean_ceeg_score")ci=i} NR==2&&ci{print $ci}' \
  "$WEIGHT_OUT/ceeg_system_features.tsv")
if [ "$weight_mean" != "0.6950" ]; then
  cat "$WEIGHT_OUT/ceeg_system_features.tsv"
  echo "FAIL: projection_weight changed mean_ceeg_score to '$weight_mean' (projection treated as activity)" >&2; exit 1
fi

# ── 38. unknown/absent/zero separation: all three values coexist and are distinct ──
# RE:unk_001: ceeg_score="" (not applicable), n_supporting_species="0" (zero species), unknown_absent="unknown"
# RE:proj_d_001: ceeg_score="0.74", unknown_absent="absent"
# These three states must produce different outputs — none collapsed into another.

unk_score=$(awk -F'\t' -v n="RE:unk_001" \
  'NR==1{for(i=1;i<=NF;i++){if($i=="node_id")ni=i;if($i=="ceeg_score")sc=i}}
   NR>1&&$ni==n{print $sc}' "$RE_FILE")
unk_ns=$(awk -F'\t' -v n="RE:unk_001" \
  'NR==1{for(i=1;i<=NF;i++){if($i=="node_id")ni=i;if($i=="n_supporting_species")ns=i}}
   NR>1&&$ni==n{print $ns}' "$RE_FILE")
if [ "$unk_score" != "" ]; then
  echo "FAIL: RE:unk_001 ceeg_score must be empty (unknown_unmappable → no score), got '$unk_score'" >&2; exit 1
fi
if [ "$unk_ns" != "0" ]; then
  echo "FAIL: RE:unk_001 n_supporting_species must be '0' (zero is distinct from empty), got '$unk_ns'" >&2; exit 1
fi
unk_ua=$(awk -F'\t' -v e="EV:unk_001" \
  'NR==1{for(i=1;i<=NF;i++){if($i=="evidence_id")ei=i;if($i=="unknown_absent")ua=i}}
   NR>1&&$ei==e{print $ua}' "$EV_FILE")
abs_ua=$(awk -F'\t' -v e="EV:proj_d_001" \
  'NR==1{for(i=1;i<=NF;i++){if($i=="evidence_id")ei=i;if($i=="unknown_absent")ua=i}}
   NR>1&&$ei==e{print $ua}' "$EV_FILE")
if [ "$unk_ua" != "unknown" ]; then
  echo "FAIL: EV:unk_001 unknown_absent must be 'unknown', got '$unk_ua'" >&2; exit 1
fi
if [ "$abs_ua" != "absent" ]; then
  echo "FAIL: EV:proj_d_001 unknown_absent must be 'absent', got '$abs_ua'" >&2; exit 1
fi
if [ "$unk_ua" = "$abs_ua" ]; then
  echo "FAIL: 'unknown' and 'absent' must not collapse to the same value" >&2; exit 1
fi

# ── 39. Evidence features: edge_id values correct ─────────────────────────────
# EV:proj_d_001 must carry E:proj_d_001 (projection traceability).
# EV:obs_001 and EV:unk_001 have no edge and must carry empty edge_id.

for pair in \
  "EV:proj_d_001|E:proj_d_001" \
  "EV:proj_i_001|E:proj_i_001" \
  "EV:obs_001|" \
  "EV:unk_001|"; do
  eid="${pair%%|*}"; expected="${pair##*|}"
  actual=$(awk -F'\t' -v e="$eid" \
    'NR==1{for(i=1;i<=NF;i++){if($i=="evidence_id")ei=i;if($i=="edge_id")ji=i}}
     NR>1&&$ei==e&&ji{print $ji}' "$EV_FILE")
  if [ "$actual" != "$expected" ]; then
    grep "$eid" "$EV_FILE" || true
    echo "FAIL: $eid expected edge_id='$expected', got '$actual' (evidence traceability broken)" >&2; exit 1
  fi
done

# ── 40. Evidence features: evidence_type values correct; never functional_conservation ──
# evidence_type is copied verbatim from the evidence table. A builder regression that
# wrote "functional_conservation" as a value would not be caught by the column-name check (test 2).

for pair in \
  "EV:obs_001|direct_observation" \
  "EV:proj_d_001|direct_RE_projection" \
  "EV:proj_d_sc_001|direct_RE_projection" \
  "EV:proj_i_001|indirect_RE_projection" \
  "EV:unk_001|unmappable"; do
  eid="${pair%%|*}"; expected="${pair##*|}"
  actual=$(awk -F'\t' -v e="$eid" \
    'NR==1{for(i=1;i<=NF;i++){if($i=="evidence_id")ei=i;if($i=="evidence_type")ti=i}}
     NR>1&&$ei==e&&ti{print $ti}' "$EV_FILE")
  if [ "$actual" != "$expected" ]; then
    grep "$eid" "$EV_FILE" || true
    echo "FAIL: $eid expected evidence_type='$expected', got '$actual'" >&2; exit 1
  fi
done
if awk -F'\t' 'NR==1{for(i=1;i<=NF;i++)if($i=="evidence_type")ti=i} NR>1&&ti&&$ti=="functional_conservation"{found=1} END{exit !found}' \
     "$EV_FILE"; then
  cat "$EV_FILE"
  echo "FAIL: evidence_type='functional_conservation' found in evidence features (conservation conflation)" >&2; exit 1
fi

# ── 41. RE features: projection_mode values correct ──────────────────────────
# Column presence is checked in test 3; values are not. A builder sourcing the wrong
# column (e.g., projection_type instead of projection_mode) would be invisible otherwise.

for pair in \
  "RE:proj_d_001|direct_alignment" \
  "RE:proj_i_001|synteny_block" \
  "RE:obs_001|" \
  "RE:unk_001|"; do
  nid="${pair%%|*}"; expected="${pair##*|}"
  actual=$(awk -F'\t' -v n="$nid" \
    'NR==1{for(i=1;i<=NF;i++){if($i=="node_id")ni=i;if($i=="projection_mode")mi=i}}
     NR>1&&$ni==n&&mi{print $mi}' "$RE_FILE")
  if [ "$actual" != "$expected" ]; then
    grep "$nid" "$RE_FILE" || true
    echo "FAIL: $nid expected projection_mode='$expected', got '$actual'" >&2; exit 1
  fi
done

# ── 42. Evidence features: provenance preserved for assay and alignment records ──
# Test 14 covers only EV:unk_001 (gap record). Other records must also be preserved.

for pair in \
  "EV:obs_001|ceeg_v0.1:assay:ATAC-seq" \
  "EV:proj_d_001|ceeg_v0.1:align:lastz" \
  "EV:proj_i_001|ceeg_v0.1:synteny:ensembl_v110"; do
  eid="${pair%%|*}"; expected="${pair##*|}"
  actual=$(awk -F'\t' -v e="$eid" \
    'NR==1{for(i=1;i<=NF;i++){if($i=="evidence_id")ei=i;if($i=="provenance")pr=i}}
     NR>1&&$ei==e&&pr{print $pr}' "$EV_FILE")
  if [ "$actual" != "$expected" ]; then
    grep "$eid" "$EV_FILE" || true
    echo "FAIL: $eid expected provenance='$expected', got '$actual'" >&2; exit 1
  fi
done

# ── 42a. RE features: projection source node is preserved ─────────────────────
# Source traceability must be available without joining back to imported edges.

actual=$(awk -F'\t' -v n="RE:proj_d_001" \
  'NR==1{for(i=1;i<=NF;i++){if($i=="node_id")ni=i;if($i=="projection_source_node_id")si=i}}
   NR>1&&$ni==n&&si{print $si}' "$RE_FILE")
if [ "$actual" != "RE:obs_001" ]; then
  grep 'RE:proj_d_001' "$RE_FILE" || true
  echo "FAIL: RE:proj_d_001 expected projection_source_node_id=RE:obs_001, got '$actual'" >&2; exit 1
fi

# ── 42b. Non-regulatory edges must not populate projection fields ─────────────
# A custom edge with target_node_id must not be treated as regulatory projection.

NONREG_EDGE_IMPORT="$TMP_DIR/nonreg_edge_import"
mkdir -p "$NONREG_EDGE_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$NONREG_EDGE_IMPORT/"
printf 'E:co_001\tRE:obs_001\tRE:proj_d_sc_001\tco_regulation\t\tgeneric_immune\t0.99\tcustom non-projection edge\ttest_src\n' \
  >> "$NONREG_EDGE_IMPORT/ceeg_imported_edges.tsv"
NONREG_EDGE_OUT="$TMP_DIR/nonreg_edge_out"
mkdir -p "$NONREG_EDGE_OUT"
if ! python3 "$BUILDER" \
     --import-dir "$NONREG_EDGE_IMPORT" --outdir "$NONREG_EDGE_OUT" \
     > "$NONREG_EDGE_OUT/stdout.txt" 2>&1; then
  cat "$NONREG_EDGE_OUT/stdout.txt"
  echo "FAIL: builder should exit 0 with non-regulatory edge" >&2; exit 1
fi
if ! awk -F'\t' -v n="RE:proj_d_sc_001" '
  NR==1{for(i=1;i<=NF;i++){if($i=="node_id")ni=i;if($i=="projection_edge_id")ei=i;if($i=="projection_source_node_id")si=i;if($i=="projection_weight")wi=i}}
  NR>1&&$ni==n&&ei&&si&&wi&&$ei==""&&$si==""&&$wi==""{found=1}
  END{exit !found}' "$NONREG_EDGE_OUT/ceeg_regulatory_projection_features.tsv"; then
  grep 'RE:proj_d_sc_001' "$NONREG_EDGE_OUT/ceeg_regulatory_projection_features.tsv" || true
  echo "FAIL: non-regulatory edge populated projection fields for RE:proj_d_sc_001" >&2; exit 1
fi

# ── 42c. Builder classification accepts validator-normalized vocabulary case ──
# The validator treats controlled vocabulary case-insensitively; the builder must
# classify the same valid imported values without changing emitted values.

CASE_IMPORT="$TMP_DIR/case_import"
mkdir -p "$CASE_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$CASE_IMPORT/"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$4="Regulatory_Projection"} {print}' \
  "$CASE_IMPORT/ceeg_imported_edges.tsv" > "$CASE_IMPORT/tmp" \
  && mv "$CASE_IMPORT/tmp" "$CASE_IMPORT/ceeg_imported_edges.tsv"
CASE_OUT="$TMP_DIR/case_out"
mkdir -p "$CASE_OUT"
if ! python3 "$BUILDER" \
     --import-dir "$CASE_IMPORT" --outdir "$CASE_OUT" \
     > "$CASE_OUT/stdout.txt" 2>&1; then
  cat "$CASE_OUT/stdout.txt"
  echo "FAIL: builder should accept validator-normalized edge_type case" >&2; exit 1
fi
if ! awk -F'\t' -v n="RE:proj_d_001" '
  NR==1{for(i=1;i<=NF;i++){if($i=="node_id")ni=i;if($i=="projection_edge_id")ei=i;if($i=="projection_source_node_id")si=i}}
  NR>1&&$ni==n&&ei&&si&&$ei=="E:proj_d_001"&&$si=="RE:obs_001"{found=1}
  END{exit !found}' "$CASE_OUT/ceeg_regulatory_projection_features.tsv"; then
  grep 'RE:proj_d_001' "$CASE_OUT/ceeg_regulatory_projection_features.tsv" || true
  echo "FAIL: mixed-case regulatory projection was not treated as projection" >&2; exit 1
fi

# ── 43. RE features: data_mode=bulk verified at row level for RE:obs_001 ──────
# Tests 19–20 verify single_cell and hybrid rows; bulk is only indirectly covered
# via the system aggregate (test 9). A bulk→"" collapse would be invisible otherwise.

actual=$(awk -F'\t' -v n="RE:obs_001" \
  'NR==1{for(i=1;i<=NF;i++){if($i=="node_id")ni=i;if($i=="data_mode")di=i}}
   NR>1&&$ni==n&&di{print $di}' "$RE_FILE")
if [ "$actual" != "bulk" ]; then
  grep 'RE:obs_001' "$RE_FILE" || true
  echo "FAIL: RE:obs_001 expected data_mode=bulk, got '$actual'" >&2; exit 1
fi

# ── 44. RE:unk_001 has empty ceeg_score AND non-empty ceeg_rank simultaneously ─
# ceeg_score="" means no score (unmappable); ceeg_rank="5" is a positional placeholder.
# These are semantically distinct — rank must not be treated as a proxy for activity.
# If both were empty, the distinction would be lost. If rank were derived from score,
# it would also be empty. The test verifies they coexist with different values.

unk_rank=$(awk -F'\t' -v n="RE:unk_001" \
  'NR==1{for(i=1;i<=NF;i++){if($i=="node_id")ni=i;if($i=="ceeg_rank")ri=i}}
   NR>1&&$ni==n&&ri{print $ri}' "$RE_FILE")
if [ "$unk_rank" != "5" ]; then
  grep 'RE:unk_001' "$RE_FILE" || true
  echo "FAIL: RE:unk_001 expected ceeg_rank=5 (positional placeholder), got '$unk_rank'" >&2; exit 1
fi
# ceeg_score must still be empty (already verified in test 5, confirmed here in tandem)
unk_score_chk=$(awk -F'\t' -v n="RE:unk_001" \
  'NR==1{for(i=1;i<=NF;i++){if($i=="node_id")ni=i;if($i=="ceeg_score")sc=i}}
   NR>1&&$ni==n&&sc{print $sc}' "$RE_FILE")
if [ "$unk_score_chk" != "" ]; then
  echo "FAIL: RE:unk_001 ceeg_score should be '' but ceeg_rank='$unk_rank' — score/rank separation broken" >&2; exit 1
fi

# ── 45. Explicit system_id is preserved when distinct from biological_system ──

SYSID_IMPORT="$TMP_DIR/sysid_import"
mkdir -p "$SYSID_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$SYSID_IMPORT/"
awk -F'\t' 'BEGIN{OFS="\t"} NR==1{$0=$0 "\tsystem_id"} NR>1{$0=$0 "\tSYS:immune_001"} {print}' \
  "$SYSID_IMPORT/ceeg_imported_nodes.tsv" > "$SYSID_IMPORT/tmp" \
  && mv "$SYSID_IMPORT/tmp" "$SYSID_IMPORT/ceeg_imported_nodes.tsv"
SYSID_OUT="$TMP_DIR/sysid_out"
mkdir -p "$SYSID_OUT"
if ! python3 "$BUILDER" \
     --import-dir "$SYSID_IMPORT" --outdir "$SYSID_OUT" \
     > "$SYSID_OUT/stdout.txt" 2>&1; then
  cat "$SYSID_OUT/stdout.txt"
  echo "FAIL: builder should exit 0 with explicit system_id column" >&2; exit 1
fi
for pair in \
  "ceeg_regulatory_projection_features.tsv|node_id|RE:proj_d_001|system_id|SYS:immune_001" \
  "ceeg_evidence_features.tsv|evidence_id|EV:proj_d_001|system_id|SYS:immune_001"; do
  file="${pair%%|*}"
  rest="${pair#*|}"
  key_col="${rest%%|*}"
  rest="${rest#*|}"
  key_val="${rest%%|*}"
  rest="${rest#*|}"
  target_col="${rest%%|*}"
  expected="${rest##*|}"
  actual=$(awk -F'\t' -v kc="$key_col" -v kv="$key_val" -v tc="$target_col" '
    NR==1{for(i=1;i<=NF;i++){if($i==kc)ki=i;if($i==tc)ti=i}}
    NR>1&&$ki==kv&&ti{print $ti}' "$SYSID_OUT/$file")
  if [ "$actual" != "$expected" ]; then
    grep "$key_val" "$SYSID_OUT/$file" || true
    echo "FAIL: explicit system_id not preserved in $file for $key_val; got '$actual'" >&2; exit 1
  fi
done
sysid_row=$(awk -F'\t' 'NR==2{print $1}' "$SYSID_OUT/ceeg_system_features.tsv")
if [ "$sysid_row" != "SYS:immune_001" ]; then
  cat "$SYSID_OUT/ceeg_system_features.tsv"
  echo "FAIL: system features expected system_id=SYS:immune_001, got '$sysid_row'" >&2; exit 1
fi

# ── 46. system_id propagates from biological_system node to RE rows ───────────

SYSNODE_IMPORT="$TMP_DIR/sysnode_import"
mkdir -p "$SYSNODE_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$SYSNODE_IMPORT/"
awk -F'\t' 'BEGIN{OFS="\t"} NR==1{$0=$0 "\tsystem_id"} NR==2{$0=$0 "\tSYS:immune_001"} NR>2{$0=$0 "\t"} {print}' \
  "$SYSNODE_IMPORT/ceeg_imported_nodes.tsv" > "$SYSNODE_IMPORT/tmp" \
  && mv "$SYSNODE_IMPORT/tmp" "$SYSNODE_IMPORT/ceeg_imported_nodes.tsv"
SYSNODE_OUT="$TMP_DIR/sysnode_out"
mkdir -p "$SYSNODE_OUT"
if ! python3 "$BUILDER" \
     --import-dir "$SYSNODE_IMPORT" --outdir "$SYSNODE_OUT" \
     > "$SYSNODE_OUT/stdout.txt" 2>&1; then
  cat "$SYSNODE_OUT/stdout.txt"
  echo "FAIL: builder should exit 0 when only biological_system node has system_id" >&2; exit 1
fi
re_sysid=$(awk -F'\t' -v n="RE:proj_d_001" '
  NR==1{for(i=1;i<=NF;i++){if($i=="node_id")ni=i;if($i=="system_id")si=i}}
  NR>1&&$ni==n&&si{print $si}' "$SYSNODE_OUT/ceeg_regulatory_projection_features.tsv")
ev_sysid=$(awk -F'\t' -v e="EV:proj_d_001" '
  NR==1{for(i=1;i<=NF;i++){if($i=="evidence_id")ei=i;if($i=="system_id")si=i}}
  NR>1&&$ei==e&&si{print $si}' "$SYSNODE_OUT/ceeg_evidence_features.tsv")
sysnode_row=$(awk -F'\t' 'NR==2{print $1}' "$SYSNODE_OUT/ceeg_system_features.tsv")
if [ "$re_sysid" != "SYS:immune_001" ] || [ "$ev_sysid" != "SYS:immune_001" ] || [ "$sysnode_row" != "SYS:immune_001" ]; then
  cat "$SYSNODE_OUT/ceeg_regulatory_projection_features.tsv"
  cat "$SYSNODE_OUT/ceeg_evidence_features.tsv"
  cat "$SYSNODE_OUT/ceeg_system_features.tsv"
  echo "FAIL: system_id from biological_system node did not propagate to RE/evidence/system outputs" >&2; exit 1
fi

# ── 47. Conflicting system_id mappings for one biological_system abort ────────

CONFLICT_SYS_IMPORT="$TMP_DIR/conflict_sys_import"
mkdir -p "$CONFLICT_SYS_IMPORT"
cp "$IMPORT_OUT"/*.tsv "$CONFLICT_SYS_IMPORT/"
awk -F'\t' 'BEGIN{OFS="\t"} NR==1{$0=$0 "\tsystem_id"} NR==2{$0=$0 "\tSYS:immune_001"} NR>2{$0=$0 "\t"} {print}' \
  "$CONFLICT_SYS_IMPORT/ceeg_imported_nodes.tsv" > "$CONFLICT_SYS_IMPORT/tmp" \
  && mv "$CONFLICT_SYS_IMPORT/tmp" "$CONFLICT_SYS_IMPORT/ceeg_imported_nodes.tsv"
printf 'BS:generic_immune_alt\tbiological_system\tgeneric_immune\tbulk\tobserved\tnone\tmappable\tAlt system\tmulti-species\tconflict\ttest_src\tSYS:immune_002\n' \
  >> "$CONFLICT_SYS_IMPORT/ceeg_imported_nodes.tsv"
CONFLICT_SYS_OUT="$TMP_DIR/conflict_sys_out"
mkdir -p "$CONFLICT_SYS_OUT"
if python3 "$BUILDER" \
     --import-dir "$CONFLICT_SYS_IMPORT" --outdir "$CONFLICT_SYS_OUT" \
     > "$CONFLICT_SYS_OUT/stdout.txt" 2>&1; then
  cat "$CONFLICT_SYS_OUT/stdout.txt"
  echo "FAIL: builder accepted conflicting system_id mappings for one biological_system" >&2; exit 1
fi
if ! grep -q 'maps to multiple system_id values' "$CONFLICT_SYS_OUT/stdout.txt"; then
  cat "$CONFLICT_SYS_OUT/stdout.txt"
  echo "FAIL: builder did not clearly report conflicting system_id mappings" >&2; exit 1
fi
for f in ceeg_regulatory_projection_features.tsv ceeg_system_features.tsv ceeg_evidence_features.tsv; do
  if [ -f "$CONFLICT_SYS_OUT/$f" ]; then
    echo "FAIL: builder wrote $f despite conflicting system_id mappings" >&2; exit 1
  fi
done

echo "OK: all ceeg_feature_matrices_stub tests passed"
