#!/usr/bin/env sh
# Mock-driven unit tests for the reciprocal-best orthology projection scripts.
# These exercise the deterministic interval/QC core on fixture BED/chain files
# and require no external genomics binaries (liftOver, halLiftover, UCSC Kent).
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FIX="$ROOT_DIR/tests/fixtures/orthology"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

assert_grep() {
  if ! grep -q "$1" "$2"; then
    cat "$2"
    echo "FAIL: $3" >&2
    exit 1
  fi
}

assert_field() {
  # assert_field FILE KEYCOL KEYVAL TARGETCOL EXPECTED MESSAGE
  file="$1"; keycol="$2"; keyval="$3"; targetcol="$4"; expected="$5"; message="$6"
  actual=$(awk -F'\t' -v kc="$keycol" -v kv="$keyval" -v tc="$targetcol" 'NR>1 && $kc==kv {print $tc; exit}' "$file")
  if [ "$actual" != "$expected" ]; then
    cat "$file"
    echo "FAIL: $message (expected '$expected' got '$actual')" >&2
    exit 1
  fi
}

# --- reciprocal-best chain identifier intersection -------------------------
printf 'chain 9 c 100 + 0 1 q 100 + 0 1 1\n1\n\nchain 9 c 100 + 1 2 q 100 + 1 2 2\n1\n\nchain 9 c 100 + 2 3 q 100 + 2 3 3\n1\n\n' > "$TMP_DIR/target.chain"
printf 'chain 9 c 100 + 0 1 q 100 + 0 1 2\n1\n\nchain 9 c 100 + 1 2 q 100 + 1 2 3\n1\n\nchain 9 c 100 + 2 3 q 100 + 2 3 4\n1\n\n' > "$TMP_DIR/query.chain"
printf 'chain 9 c 100 + 0 1 q 100 + 0 1 1\n1\n\nchain 9 c 100 + 1 2 q 100 + 1 2 2\n1\n\nchain 9 c 100 + 2 3 q 100 + 2 3 3\n1\n\nchain 9 c 100 + 3 4 q 100 + 3 4 4\n1\n\n' > "$TMP_DIR/raw.chain"
python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$TMP_DIR/target.chain" \
  --query-net-chains "$TMP_DIR/query.chain" \
  --raw-chains "$TMP_DIR/raw.chain" \
  --out-chains "$TMP_DIR/recip.chain" \
  --out-ids "$TMP_DIR/recip.ids" > "$TMP_DIR/recip.out" 2>&1
ids=$(tr '\n' ',' < "$TMP_DIR/recip.ids")
[ "$ids" = "2,3," ] || { echo "FAIL: reciprocal-best ids expected 2,3 got $ids" >&2; exit 1; }

# Gzipped chain inputs must be read transparently (.chain.gz is common).
gzip -c "$TMP_DIR/target.chain" > "$TMP_DIR/target.chain.gz"
gzip -c "$TMP_DIR/raw.chain" > "$TMP_DIR/raw.chain.gz"
python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$TMP_DIR/target.chain.gz" \
  --query-net-chains "$TMP_DIR/query.chain" \
  --raw-chains "$TMP_DIR/raw.chain.gz" \
  --out-chains "$TMP_DIR/recip_gz.chain" \
  --out-ids "$TMP_DIR/recip_gz.ids" > "$TMP_DIR/recip_gz.out" 2>&1
gzids=$(tr '\n' ',' < "$TMP_DIR/recip_gz.ids")
[ "$gzids" = "2,3," ] || { echo "FAIL: gzipped chain reciprocal-best ids expected 2,3 got $gzids" >&2; exit 1; }
if grep -q 'q 100 + 3 4 4' "$TMP_DIR/recip.chain"; then
  echo "FAIL: non-reciprocal chain id 4 leaked into reciprocal-best output" >&2; exit 1
fi

# Reciprocal-best ids that are absent from the raw chain are an input mismatch.
printf 'chain 9 c 100 + 0 1 q 100 + 0 1 shared\n1\n\n' > "$TMP_DIR/rb_target.chain"
printf 'chain 9 c 100 + 0 1 q 100 + 0 1 shared\n1\n\n' > "$TMP_DIR/rb_query.chain"
printf 'chain 9 c 100 + 0 1 q 100 + 0 1 other\n1\n\n' > "$TMP_DIR/rb_raw.chain"
if python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$TMP_DIR/rb_target.chain" \
  --query-net-chains "$TMP_DIR/rb_query.chain" \
  --raw-chains "$TMP_DIR/rb_raw.chain" \
  --out-chains "$TMP_DIR/rb_out.chain" > "$TMP_DIR/rb.out" 2>&1; then
  echo "FAIL: reciprocal-best ids absent from raw chain should be an error" >&2; exit 1
fi
assert_grep 'absent from the raw chain' "$TMP_DIR/rb.out" "raw-chain mismatch error absent"

# Duplicate chain ids within an input are an ambiguity (ids are the join key)
# and must be rejected outright, not silently collapsed.
printf 'chain 9 c 100 + 0 1 q 100 + 0 1 id1\n1\n\nchain 9 c 100 + 1 2 q 100 + 1 2 id2\n1\n\n' > "$TMP_DIR/dup_target.chain"
cp "$TMP_DIR/dup_target.chain" "$TMP_DIR/dup_query.chain"
printf 'chain 9 c 100 + 0 1 q 100 + 0 1 id1\n1\n\nchain 9 c 100 + 5 6 q 100 + 5 6 id1\n1\n\n' > "$TMP_DIR/dup_raw.chain"
if python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$TMP_DIR/dup_target.chain" \
  --query-net-chains "$TMP_DIR/dup_query.chain" \
  --raw-chains "$TMP_DIR/dup_raw.chain" \
  --out-chains "$TMP_DIR/dup_out.chain" > "$TMP_DIR/dup.out" 2>&1; then
  echo "FAIL: duplicate chain ids were not rejected" >&2; exit 1
fi
assert_grep 'duplicate chain id' "$TMP_DIR/dup.out" "duplicate-id rejection missing"

# A non-empty file with no chain headers is malformed, not an empty subset.
printf 'not a chain\nstill not\n' > "$TMP_DIR/notchain_target.chain"
if python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$TMP_DIR/notchain_target.chain" \
  --query-net-chains "$TMP_DIR/rb_query.chain" \
  --raw-chains "$TMP_DIR/rb_raw.chain" \
  --out-chains "$TMP_DIR/notchain_out.chain" > "$TMP_DIR/notchain.out" 2>&1; then
  echo "FAIL: malformed (non-chain) subset accepted as empty" >&2; exit 1
fi
assert_grep 'no UCSC chain headers' "$TMP_DIR/notchain.out" "malformed chain-subset error absent"

# A header-looking line that is not parseable (too few fields) is malformed, not
# an empty subset. "chain\n10\n" previously slipped through.
printf 'chain\n10\n' > "$TMP_DIR/badhdr_target.chain"
if python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$TMP_DIR/badhdr_target.chain" \
  --query-net-chains "$TMP_DIR/rb_query.chain" \
  --raw-chains "$TMP_DIR/rb_raw.chain" \
  --out-chains "$TMP_DIR/badhdr_out.chain" > "$TMP_DIR/badhdr.out" 2>&1; then
  echo "FAIL: malformed chain header (too few fields) accepted" >&2; exit 1
fi
assert_grep 'malformed chain header' "$TMP_DIR/badhdr.out" "malformed-header error absent"

# Partial: one valid header + one malformed header must fail, not drop silently.
printf 'chain 9 c 100 + 0 1 q 100 + 0 1 good\n1\n\nchain bad header\n1\n\n' > "$TMP_DIR/partialhdr.chain"
if python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$TMP_DIR/partialhdr.chain" \
  --query-net-chains "$TMP_DIR/rb_query.chain" \
  --raw-chains "$TMP_DIR/rb_raw.chain" \
  --out-chains "$TMP_DIR/partialhdr_out.chain" > "$TMP_DIR/partialhdr.out" 2>&1; then
  echo "FAIL: partially malformed chain header accepted" >&2; exit 1
fi
assert_grep 'malformed chain header' "$TMP_DIR/partialhdr.out" "partial malformed-header error absent"

# A 13-field header with invalid required fields (non-numeric coords, bad strand)
# must be rejected, not pass with field 13 as a bogus id.
printf 'chain notanumber c X Y 0 1 q 100 + 0 1 badid\n1\n\n' > "$TMP_DIR/garbagehdr.chain"
if python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$TMP_DIR/garbagehdr.chain" \
  --query-net-chains "$TMP_DIR/rb_query.chain" \
  --raw-chains "$TMP_DIR/rb_raw.chain" \
  --out-chains "$TMP_DIR/garbagehdr_out.chain" \
  --out-ids "$TMP_DIR/garbagehdr_out.ids" > "$TMP_DIR/garbagehdr.out" 2>&1; then
  echo "FAIL: structurally invalid 13-field chain header accepted" >&2; exit 1
fi
assert_grep 'malformed chain header' "$TMP_DIR/garbagehdr.out" "garbage-header structural error absent"
[ -e "$TMP_DIR/garbagehdr_out.ids" ] && { echo "FAIL: bogus id written despite malformed header" >&2; exit 1; } || true

# Coordinate ranges must be consistent (start <= end <= size). A header with
# tStart > tEnd (or end > size) is structurally invalid even with 13 numeric
# fields, and must not yield a bogus reciprocal-best id.
printf 'chain 9 c 100 + 10 5 q 100 + 0 1 badrange\n1\n\n' > "$TMP_DIR/badrange.chain"
if python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$TMP_DIR/badrange.chain" \
  --query-net-chains "$TMP_DIR/rb_query.chain" \
  --raw-chains "$TMP_DIR/rb_raw.chain" \
  --out-chains "$TMP_DIR/badrange_out.chain" \
  --out-ids "$TMP_DIR/badrange_out.ids" > "$TMP_DIR/badrange.out" 2>&1; then
  echo "FAIL: chain header with start>end accepted" >&2; exit 1
fi
assert_grep 'malformed chain header' "$TMP_DIR/badrange.out" "coordinate-range structural error absent"
[ -e "$TMP_DIR/badrange_out.ids" ] && { echo "FAIL: bogus id written despite invalid coordinate range" >&2; exit 1; } || true

# A valid header followed by a malformed body record (not 1 or 3 integers) must
# be rejected, not copied verbatim into the filtered chain.
printf 'chain 9 c 100 + 0 1 q 100 + 0 1 bodybad\nnot_a_chain_body\n\n' > "$TMP_DIR/badbody.chain"
if python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$TMP_DIR/badbody.chain" \
  --query-net-chains "$TMP_DIR/rb_query.chain" \
  --raw-chains "$TMP_DIR/rb_raw.chain" \
  --out-chains "$TMP_DIR/badbody_out.chain" > "$TMP_DIR/badbody.out" 2>&1; then
  echo "FAIL: malformed chain body record accepted" >&2; exit 1
fi
assert_grep 'chain body record' "$TMP_DIR/badbody.out" "malformed-body error absent"

# Block structure: a block of only continuation (3-field) rows with no final
# 1-field size row is invalid.
printf 'chain 9 c 100 + 0 1 q 100 + 0 1 nofinal\n5 0 0\n\n' > "$TMP_DIR/nofinal.chain"
if python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$TMP_DIR/nofinal.chain" \
  --query-net-chains "$TMP_DIR/rb_query.chain" \
  --raw-chains "$TMP_DIR/rb_raw.chain" \
  --out-chains "$TMP_DIR/nofinal_out.chain" > "$TMP_DIR/nofinal.out" 2>&1; then
  echo "FAIL: chain block without a final size row accepted" >&2; exit 1
fi
assert_grep 'no final size row' "$TMP_DIR/nofinal.out" "missing-final-row error absent"

# Block structure: a row after the final 1-field size row is invalid.
printf 'chain 9 c 100 + 0 1 q 100 + 0 1 afterfinal\n1\n1\n\n' > "$TMP_DIR/afterfinal.chain"
if python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$TMP_DIR/afterfinal.chain" \
  --query-net-chains "$TMP_DIR/rb_query.chain" \
  --raw-chains "$TMP_DIR/rb_raw.chain" \
  --out-chains "$TMP_DIR/afterfinal_out.chain" > "$TMP_DIR/afterfinal.out" 2>&1; then
  echo "FAIL: row after final size row accepted" >&2; exit 1
fi
assert_grep 'row after its final size' "$TMP_DIR/afterfinal.out" "row-after-final error absent"

# Block structure: a header with no body rows is invalid.
printf 'chain 9 c 100 + 0 1 q 100 + 0 1 nobody\n\n' > "$TMP_DIR/nobody.chain"
if python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$TMP_DIR/nobody.chain" \
  --query-net-chains "$TMP_DIR/rb_query.chain" \
  --raw-chains "$TMP_DIR/rb_raw.chain" \
  --out-chains "$TMP_DIR/nobody_out.chain" > "$TMP_DIR/nobody.out" 2>&1; then
  echo "FAIL: header with no body rows accepted" >&2; exit 1
fi
assert_grep 'no body rows' "$TMP_DIR/nobody.out" "body-less-header error absent"

# A multi-block chain with valid 3-field continuations + final row is accepted.
printf 'chain 9 c 100 + 0 30 q 100 + 0 30 multi\n10 5 5\n10\n\n' > "$TMP_DIR/multi.chain"
python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$TMP_DIR/multi.chain" \
  --query-net-chains "$TMP_DIR/multi.chain" \
  --raw-chains "$TMP_DIR/multi.chain" \
  --out-chains "$TMP_DIR/multi_out.chain" \
  --out-ids "$TMP_DIR/multi_out.ids" > "$TMP_DIR/multi.out" 2>&1 || { cat "$TMP_DIR/multi.out"; echo "FAIL: valid multi-row chain block rejected" >&2; exit 1; }
assert_grep 'multi' "$TMP_DIR/multi_out.ids" "valid multi-row chain id missing"

# A track/browser/comment line INSIDE a block is rejected (and never copied into
# the filtered output) — validation and filtering use the same delimiter set.
printf 'chain 9 c 100 + 0 1 q 100 + 0 1 meta\n1\ntrack name=x\n\n' > "$TMP_DIR/meta.chain"
if python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$TMP_DIR/meta.chain" \
  --query-net-chains "$TMP_DIR/meta.chain" \
  --raw-chains "$TMP_DIR/meta.chain" \
  --out-chains "$TMP_DIR/meta_out.chain" \
  --out-ids "$TMP_DIR/meta_out.ids" > "$TMP_DIR/meta.out" 2>&1; then
  echo "FAIL: track line inside a chain block was accepted" >&2; exit 1
fi
assert_grep 'metadata line inside a chain block' "$TMP_DIR/meta.out" "in-block metadata error absent"
if [ -e "$TMP_DIR/meta_out.chain" ] && grep -q 'track name=x' "$TMP_DIR/meta_out.chain"; then
  echo "FAIL: track line was written into the filtered chain" >&2; exit 1
fi

# Metadata BEFORE the first header (and between blank-separated blocks) is allowed.
printf 'track name=ok\nchain 9 c 100 + 0 1 q 100 + 0 1 withmeta\n1\n\n' > "$TMP_DIR/okmeta.chain"
python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$TMP_DIR/okmeta.chain" \
  --query-net-chains "$TMP_DIR/okmeta.chain" \
  --raw-chains "$TMP_DIR/okmeta.chain" \
  --out-chains "$TMP_DIR/okmeta_out.chain" \
  --out-ids "$TMP_DIR/okmeta_out.ids" > "$TMP_DIR/okmeta.out" 2>&1 || { cat "$TMP_DIR/okmeta.out"; echo "FAIL: metadata before first header rejected" >&2; exit 1; }
assert_grep 'withmeta' "$TMP_DIR/okmeta_out.ids" "valid chain with leading metadata missing"
if grep -q 'track name=ok' "$TMP_DIR/okmeta_out.chain"; then
  echo "FAIL: leading metadata leaked into the filtered chain" >&2; exit 1
fi

# A line starting with "track"/"browser" but not a whole-token directive (e.g.
# "tracking garbage") is NOT metadata — it must be treated as content and the
# file rejected, not silently accepted as an empty subset.
for bad in 'tracking garbage' 'browserX foo'; do
  printf '%s\n' "$bad" > "$TMP_DIR/pseudometa.chain"
  if python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
    --target-net-chains "$TMP_DIR/pseudometa.chain" \
    --query-net-chains "$TMP_DIR/rb_query.chain" \
    --raw-chains "$TMP_DIR/rb_raw.chain" \
    --out-chains "$TMP_DIR/pseudometa_out.chain" > "$TMP_DIR/pseudometa.out" 2>&1; then
    echo "FAIL: pseudo-metadata line '$bad' accepted as an empty subset" >&2; exit 1
  fi
  assert_grep 'no UCSC chain headers' "$TMP_DIR/pseudometa.out" "pseudo-metadata '$bad' not treated as content"
done

# Fatal validation must run BEFORE writing outputs: a mismatch leaves no artifacts.
rm -f "$TMP_DIR/preflight_out.chain" "$TMP_DIR/preflight_out.ids"
if python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$TMP_DIR/rb_target.chain" \
  --query-net-chains "$TMP_DIR/rb_query.chain" \
  --raw-chains "$TMP_DIR/rb_raw.chain" \
  --out-chains "$TMP_DIR/preflight_out.chain" \
  --out-ids "$TMP_DIR/preflight_out.ids" > "$TMP_DIR/preflight.out" 2>&1; then
  echo "FAIL: id mismatch should be a fatal error" >&2; exit 1
fi
if [ -e "$TMP_DIR/preflight_out.chain" ] || [ -e "$TMP_DIR/preflight_out.ids" ]; then
  echo "FAIL: outputs were written despite a fatal validation error" >&2; exit 1
fi

# A bogus "chainX ... id2" line (first token != "chain") is neither a valid
# header nor a valid body record, so the file is rejected as stray content and
# its field-13 token (id2) can never leak into any output.
printf 'chain 9 c 100 + 0 1 q 100 + 0 1 realid\n1\n\nchainX foo bar baz a b c d e f g h id2\n1\n\n' > "$TMP_DIR/bogus.chain"
if python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$TMP_DIR/bogus.chain" \
  --query-net-chains "$TMP_DIR/bogus.chain" \
  --raw-chains "$TMP_DIR/bogus.chain" \
  --out-chains "$TMP_DIR/bogus_out.chain" \
  --out-ids "$TMP_DIR/bogus_out.ids" > "$TMP_DIR/bogus.out" 2>&1; then
  echo "FAIL: stray 'chainX' content was accepted" >&2; exit 1
fi
if [ -e "$TMP_DIR/bogus_out.ids" ] && grep -q 'id2' "$TMP_DIR/bogus_out.ids"; then
  echo "FAIL: bogus 'chainX' line leaked id2 into the output" >&2; exit 1
fi

# --out-chains in a non-existent directory must be created, not crash.
python3 "$ROOT_DIR/bin/define_reciprocal_best_chains.py" \
  --target-net-chains "$TMP_DIR/recip.chain" \
  --query-net-chains "$TMP_DIR/recip.chain" \
  --raw-chains "$TMP_DIR/recip.chain" \
  --out-chains "$TMP_DIR/newdir/out.chain" > "$TMP_DIR/newdir.out" 2>&1 || { cat "$TMP_DIR/newdir.out"; echo "FAIL: --out-chains in a new directory crashed" >&2; exit 1; }
[ -e "$TMP_DIR/newdir/out.chain" ] || { echo "FAIL: --out-chains parent dir was not created" >&2; exit 1; }

# --- callable mask intersection with min-fragment drop ---------------------
printf 'chr1\t100\t500\nchr1\t600\t640\nchr1\t1000\t1200\n' > "$TMP_DIR/ref.bed"
printf 'chr1\t300\t700\nchr1\t1100\t1300\n' > "$TMP_DIR/qry.bed"
python3 "$ROOT_DIR/bin/build_callable_mask.py" \
  --reference-fills "$TMP_DIR/ref.bed" \
  --query-fills-projected "$TMP_DIR/qry.bed" \
  --min-fragment 50 \
  --out "$TMP_DIR/mask.bed" > "$TMP_DIR/mask.out" 2>&1
assert_grep '^chr1	300	500$' "$TMP_DIR/mask.bed" "callable mask intersection 300-500 missing"
assert_grep '^chr1	1100	1200$' "$TMP_DIR/mask.bed" "callable mask intersection 1100-1200 missing"
if grep -q '600' "$TMP_DIR/mask.bed"; then
  echo "FAIL: sub-threshold (40bp) reference fill survived into callable mask" >&2; exit 1
fi

# A malformed fills file must not become an empty callable mask.
printf 'not a bed\nstill not\n' > "$TMP_DIR/malformed_fills.bed"
if python3 "$ROOT_DIR/bin/build_callable_mask.py" \
  --reference-fills "$TMP_DIR/malformed_fills.bed" \
  --query-fills-projected "$TMP_DIR/qry.bed" \
  --out "$TMP_DIR/mask_bad.bed" > "$TMP_DIR/mask_bad.out" 2>&1; then
  echo "FAIL: malformed callable-mask fills accepted as empty" >&2; exit 1
fi
assert_grep 'malformed' "$TMP_DIR/mask_bad.out" "malformed fills error absent"

# --- region projection + round-trip QC engine ------------------------------
ENG="$TMP_DIR/engine"
python3 "$ROOT_DIR/bin/project_orthologous_regions.py" \
  --prepared-manifest "$FIX/manifest.tsv" \
  --forward-fragments "$FIX/forward_fragments.bed" \
  --backlift-fragments "$FIX/backlift_fragments.bed" \
  --element-fragments "$FIX/element_fragments.bed" \
  --source-element-union "$FIX/source_element_union.bed" \
  --species-callable-mask "$FIX/species_callable_mask.bed" \
  --source-callable-mask "$FIX/source_callable_mask.bed" \
  --output-dir "$ENG" > "$TMP_DIR/engine.out" 2>&1

SUM="$ENG/region_orthology_summary.tsv"
# column positions: forward_status=30 roundtrip_qc=31 structural_class=32 high_confidence_primary=33
assert_field "$SUM" 4 mmus_re_0001 32 compact "compact single-contig locus misclassified"
assert_field "$SUM" 4 mmus_re_0001 33 true "compact locus should be high-confidence primary"
assert_field "$SUM" 4 mmus_re_0002 30 MULTICONTIG_RESOLVED "multi-contig competition not resolved"
assert_field "$SUM" 4 mmus_re_0002 32 fragmented "multi-contig locus should be fragmented"
# Round-trip recovery must use only the selected contig's back-lift fragments.
# The losing contig (ctgC) spans the full window; if its fragments leaked in,
# window_recovered_fraction (col 26) would be 1.0000 instead of 0.5556.
assert_field "$SUM" 4 mmus_re_0002 26 0.5556 "round-trip recovery leaked back-lift from a losing contig"
assert_field "$SUM" 4 mmus_re_0003 30 NO_FORWARD_MAPPING "unmapped region not labelled NO_FORWARD_MAPPING"
assert_field "$SUM" 4 mmus_re_0003 33 false "unmapped region must not be high-confidence"
assert_grep 'NO_FORWARD_MAPPING' "$ENG/projected_regions.tsv" "failed projection missing from projected_regions"
assert_grep 'FAILED' "$ENG/projected_regions.tsv" "failed projection status missing"

# Failure must not be reinterpreted as biological absence: it stays a status label.
if grep -qi 'absent' "$SUM"; then
  echo "FAIL: engine emitted an absence claim" >&2; exit 1
fi

# Without a constituent-element union, high confidence is not claimed (core
# recovery cannot be evaluated); the locus is WINDOW_ONLY_NO_CORE, not primary.
NOCORE="$TMP_DIR/nocore"
python3 "$ROOT_DIR/bin/project_orthologous_regions.py" \
  --prepared-manifest "$FIX/manifest.tsv" \
  --forward-fragments "$FIX/forward_fragments.bed" \
  --backlift-fragments "$FIX/backlift_fragments.bed" \
  --species-callable-mask "$FIX/species_callable_mask.bed" \
  --output-dir "$NOCORE" > "$TMP_DIR/nocore.out" 2>&1
assert_field "$NOCORE/region_orthology_summary.tsv" 4 mmus_re_0001 31 WINDOW_ONLY_NO_CORE "no-element run should not claim HIGH_CONFIDENCE"
assert_field "$NOCORE/region_orthology_summary.tsv" 4 mmus_re_0001 33 false "no-element locus must not be high-confidence primary"

# A supplied-but-missing callable mask is an input error, never an empty mask.
if python3 "$ROOT_DIR/bin/project_orthologous_regions.py" \
  --prepared-manifest "$FIX/manifest.tsv" \
  --forward-fragments "$FIX/forward_fragments.bed" \
  --backlift-fragments "$FIX/backlift_fragments.bed" \
  --species-callable-mask "$TMP_DIR/does_not_exist.bed" \
  --output-dir "$TMP_DIR/badmask" > "$TMP_DIR/badmask.out" 2>&1; then
  echo "FAIL: missing callable mask was silently accepted as empty" >&2; exit 1
fi
assert_grep 'does not exist' "$TMP_DIR/badmask.out" "missing-mask error message absent"

# A malformed mask (data lines that do not parse as BED) is an input error too.
printf 'this is not a bed file\nneither is this\n' > "$TMP_DIR/malformed_mask.bed"
if python3 "$ROOT_DIR/bin/project_orthologous_regions.py" \
  --prepared-manifest "$FIX/manifest.tsv" \
  --forward-fragments "$FIX/forward_fragments.bed" \
  --backlift-fragments "$FIX/backlift_fragments.bed" \
  --source-callable-mask "$TMP_DIR/malformed_mask.bed" \
  --output-dir "$TMP_DIR/malformed" > "$TMP_DIR/malformed.out" 2>&1; then
  echo "FAIL: malformed mask was silently accepted as empty" >&2; exit 1
fi
assert_grep 'malformed' "$TMP_DIR/malformed.out" "malformed-mask error message absent"

# A malformed source element union is an input error, not a "no core" result.
printf 'garbage line one\ngarbage line two\n' > "$TMP_DIR/malformed_union.bed"
if python3 "$ROOT_DIR/bin/project_orthologous_regions.py" \
  --prepared-manifest "$FIX/manifest.tsv" \
  --forward-fragments "$FIX/forward_fragments.bed" \
  --backlift-fragments "$FIX/backlift_fragments.bed" \
  --source-element-union "$TMP_DIR/malformed_union.bed" \
  --output-dir "$TMP_DIR/malformed_union_out" > "$TMP_DIR/malformed_union.out" 2>&1; then
  echo "FAIL: malformed element union was silently treated as no element union" >&2; exit 1
fi
assert_grep 'source-element-union' "$TMP_DIR/malformed_union.out" "malformed element-union error absent"

# A PARTIALLY malformed union (one good row, one bad) must also fail — a dropped
# row would silently change core recovery.
printf 'chr1\t110\t150\tproj1::mmus_re_0001\ngarbage row here\n' > "$TMP_DIR/partial_union.bed"
if python3 "$ROOT_DIR/bin/project_orthologous_regions.py" \
  --prepared-manifest "$FIX/manifest.tsv" \
  --forward-fragments "$FIX/forward_fragments.bed" \
  --backlift-fragments "$FIX/backlift_fragments.bed" \
  --source-element-union "$TMP_DIR/partial_union.bed" \
  --output-dir "$TMP_DIR/partial_union_out" > "$TMP_DIR/partial_union.out" 2>&1; then
  echo "FAIL: partially malformed element union was silently accepted" >&2; exit 1
fi
assert_grep 'malformed/unparseable' "$TMP_DIR/partial_union.out" "partial-malformed union error absent"

# --- regulatory orthology inference / classification -----------------------
python3 "$ROOT_DIR/bin/classify_orthologous_regions.py" \
  --region-summary "$SUM" \
  --projected-regions "$ENG/projected_regions.tsv" \
  --output-dir "$ENG" > "$TMP_DIR/classify.out" 2>&1
ORTH="$ENG/inferred_orthologous_res.tsv"
assert_grep 'reciprocal_best_orthology' "$ORTH" "inferred orthology source label missing"
assert_grep 'OG_RE_RB_proj1_mmus_re_0001' "$ORTH" "compact locus orthogroup missing"
# mmus_re_0003 failed (structural_class=missing) and must be excluded.
if grep -q 'mmus_re_0003' "$ORTH"; then
  echo "FAIL: failed/missing region leaked into inferred orthology table" >&2; exit 1
fi

# primary-only filtering keeps only high-confidence non-hyperfragmented loci.
python3 "$ROOT_DIR/bin/classify_orthologous_regions.py" \
  --region-summary "$SUM" \
  --projected-regions "$ENG/projected_regions.tsv" \
  --output-dir "$TMP_DIR/primary" --primary-only > "$TMP_DIR/primary.out" 2>&1
assert_grep 'mmus_re_0001' "$TMP_DIR/primary/inferred_orthologous_res.tsv" "primary-only dropped a high-confidence locus"

# --- manifest reshaping ----------------------------------------------------
python3 "$ROOT_DIR/bin/manifest_to_region_bed.py" \
  --prepared-manifest "$FIX/manifest.tsv" \
  --output-dir "$TMP_DIR/reshape" > "$TMP_DIR/reshape.out" 2>&1
assert_grep 'proj1::mmus_re_0001' "$TMP_DIR/reshape/regions.bed" "reshaped regions.bed missing keyed name"
assert_grep 'source_species' "$TMP_DIR/reshape/chains.tsv" "chains.tsv header missing source_species"

# --- HAL real-mode input preparation (no chain/MAF required) ---------------
HALPREP="$TMP_DIR/halprep"
mkdir -p "$HALPREP"
printf 'species\tfeature_id\tchrom\tstart\tend\n' > "$HALPREP/regions.tsv"
printf 'Mus_musculus\tmmus_re_0001\tchr1\t100\t180\n' >> "$HALPREP/regions.tsv"
printf 'source_species\ttarget_species\talignment_id\n' > "$HALPREP/align.tsv"
printf 'Mus_musculus\tPan_troglodytes\tmmus_to_ptro\n' >> "$HALPREP/align.tsv"
printf 'projection_id\tsource_species\ttarget_species\tmethod\n' > "$HALPREP/config.tsv"
printf 'proj1\tMus_musculus\tPan_troglodytes\tliftover_chain\n' >> "$HALPREP/config.tsv"
: > "$HALPREP/genome.hal"

# halliftover real mode must not require chain/MAF assets.
python3 "$ROOT_DIR/bin/prepare_coordinate_projection_inputs.py" \
  --regulatory_regions "$HALPREP/regions.tsv" \
  --genome_alignment_manifest "$HALPREP/align.tsv" \
  --coordinate_projection_config "$HALPREP/config.tsv" \
  --coordinate_projection_stub false \
  --orthology_lift_tool halliftover \
  --orthology_hal_file "$HALPREP/genome.hal" \
  --output_dir "$HALPREP/out" > "$HALPREP/prep.out" 2>&1 || { cat "$HALPREP/prep.out"; cat "$HALPREP/out/coordinate_projection_warnings.tsv"; echo "FAIL: HAL real-mode prep rejected a pure-HAL config" >&2; exit 1; }
assert_grep '^proj1' "$HALPREP/out/coordinate_projection_manifest.tsv" "HAL prep produced no manifest record"

# halliftover without a HAL file must fail clearly.
if python3 "$ROOT_DIR/bin/prepare_coordinate_projection_inputs.py" \
  --regulatory_regions "$HALPREP/regions.tsv" \
  --genome_alignment_manifest "$HALPREP/align.tsv" \
  --coordinate_projection_config "$HALPREP/config.tsv" \
  --coordinate_projection_stub false \
  --orthology_lift_tool halliftover \
  --output_dir "$HALPREP/out2" > "$HALPREP/prep2.out" 2>&1; then
  echo "FAIL: halliftover prep without a HAL file should fail" >&2; exit 1
fi
assert_grep 'requires --orthology_hal_file' "$HALPREP/out2/coordinate_projection_warnings.tsv" "missing-HAL diagnostic absent"

# Prep validation must agree with the liftOver executor: precomputed_map needs a
# chain (not a MAF), and maf_projection is rejected under the liftOver executor.
printf 'source_species\ttarget_species\talignment_id\tmaf_file\n' > "$HALPREP/maf_align.tsv"
printf 'Mus_musculus\tPan_troglodytes\tmmus_to_ptro\t%s/aln.maf\n' "$HALPREP" >> "$HALPREP/maf_align.tsv"
: > "$HALPREP/aln.maf"
printf 'projection_id\tsource_species\ttarget_species\tmethod\n' > "$HALPREP/maf_config.tsv"
printf 'proj1\tMus_musculus\tPan_troglodytes\tmaf_projection\n' >> "$HALPREP/maf_config.tsv"
if python3 "$ROOT_DIR/bin/prepare_coordinate_projection_inputs.py" \
  --regulatory_regions "$HALPREP/regions.tsv" \
  --genome_alignment_manifest "$HALPREP/maf_align.tsv" \
  --coordinate_projection_config "$HALPREP/maf_config.tsv" \
  --coordinate_projection_stub false \
  --orthology_lift_tool liftover \
  --output_dir "$HALPREP/maf_out" > "$HALPREP/maf.out" 2>&1; then
  echo "FAIL: maf_projection under liftover executor should be rejected at prep" >&2; exit 1
fi
assert_grep 'requires orthology_lift_tool=halliftover' "$HALPREP/maf_out/coordinate_projection_warnings.tsv" "maf_projection/liftover disagreement not caught at prep"

printf 'projection_id\tsource_species\ttarget_species\tmethod\n' > "$HALPREP/pm_config.tsv"
printf 'proj1\tMus_musculus\tPan_troglodytes\tprecomputed_map\n' >> "$HALPREP/pm_config.tsv"
if python3 "$ROOT_DIR/bin/prepare_coordinate_projection_inputs.py" \
  --regulatory_regions "$HALPREP/regions.tsv" \
  --genome_alignment_manifest "$HALPREP/maf_align.tsv" \
  --coordinate_projection_config "$HALPREP/pm_config.tsv" \
  --coordinate_projection_stub false \
  --orthology_lift_tool liftover \
  --output_dir "$HALPREP/pm_out" > "$HALPREP/pm.out" 2>&1; then
  echo "FAIL: precomputed_map without a chain should fail prep under liftover" >&2; exit 1
fi
assert_grep 'chain_file' "$HALPREP/pm_out/coordinate_projection_warnings.tsv" "precomputed_map chain requirement not enforced at prep"

# Reserved BED-name delimiters in feature_id must be rejected at prep, since they
# would corrupt the internal projection_id::feature_id@@contig fragment naming.
printf 'species\tfeature_id\tchrom\tstart\tend\n' > "$HALPREP/bad_regions.tsv"
printf 'Mus_musculus\tfeat@@x\tchr1\t100\t180\n' >> "$HALPREP/bad_regions.tsv"
if python3 "$ROOT_DIR/bin/prepare_coordinate_projection_inputs.py" \
  --regulatory_regions "$HALPREP/bad_regions.tsv" \
  --genome_alignment_manifest "$HALPREP/align.tsv" \
  --coordinate_projection_config "$HALPREP/config.tsv" \
  --coordinate_projection_stub true \
  --output_dir "$HALPREP/bad_out" > "$HALPREP/bad.out" 2>&1; then
  echo "FAIL: feature_id with reserved delimiter '@@' should be rejected at prep" >&2; exit 1
fi
assert_grep 'reserved delimiter' "$HALPREP/bad_out/coordinate_projection_warnings.tsv" "reserved-delimiter diagnostic absent"

echo "reciprocal-best orthology tests passed"
