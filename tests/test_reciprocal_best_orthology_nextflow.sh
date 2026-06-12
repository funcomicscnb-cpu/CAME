#!/usr/bin/env sh
# Real-mode coordinate_projection integration test for reciprocal-best orthology.
# Uses lightweight mock liftOver/chainSwap shims (identity mappers) so the
# Nextflow orchestration path is exercised end-to-end without UCSC Kent tools.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

# --- mock UCSC tools -------------------------------------------------------
MOCKBIN="$TMP_DIR/bin"
mkdir -p "$MOCKBIN"
# liftOver [flags] oldFile map.chain newFile unMapped -> identity copy of the BED
# (preserving all columns, so BED6 strand survives). Skips leading -flags.
cat > "$MOCKBIN/liftOver" <<'EOF'
#!/usr/bin/env sh
pos=""
for a in "$@"; do case "$a" in -*) ;; *) pos="$pos $a" ;; esac; done
set -- $pos
cp "$1" "$3"
: > "$4"
EOF
# chainSwap in.chain out.chain -> identity copy.
cat > "$MOCKBIN/chainSwap" <<'EOF'
#!/usr/bin/env sh
cp "$1" "$2"
EOF
chmod +x "$MOCKBIN/liftOver" "$MOCKBIN/chainSwap"

# --- fixtures with an existing chain asset ---------------------------------
echo "chain 1000 chr1 1000000 + 0 1000000 ctgA 1000000 + 0 1000000 1" > "$TMP_DIR/mmus_to_ptro.chain"
echo "chain 1000 chr1 1000000 + 0 1000000 ctgA 1000000 + 0 1000000 2" > "$TMP_DIR/mmus_to_drer.chain"

REGIONS="$TMP_DIR/regulatory_regions.tsv"
printf 'species\tfeature_id\tchrom\tstart\tend\tregion_type\n' > "$REGIONS"
printf 'Mus_musculus\tmmus_re_0001\tchr1\t100\t180\tenhancer\n' >> "$REGIONS"
printf 'Mus_musculus\tmmus_re_0002\tchr1\t220\t310\tpromoter\n' >> "$REGIONS"

ALIGN="$TMP_DIR/genome_alignment_manifest.tsv"
printf 'source_species\ttarget_species\talignment_id\tchain_file\talignment_type\n' > "$ALIGN"
printf 'Mus_musculus\tPan_troglodytes\tmmus_to_ptro\t%s\tliftover_chain\n' "$TMP_DIR/mmus_to_ptro.chain" >> "$ALIGN"

CONFIG="$TMP_DIR/coordinate_projection_config.tsv"
printf 'projection_id\tsource_species\ttarget_species\tmethod\n' > "$CONFIG"
printf 'proj1\tMus_musculus\tPan_troglodytes\tliftover_chain\n' >> "$CONFIG"

# Constituent-element union (source coords), named projection_id::feature_id.
# Filename contains a space to exercise shell quoting of staged optional paths.
ELEMENTS="$TMP_DIR/element union.bed"
printf 'chr1\t110\t150\tproj1::mmus_re_0001\n' > "$ELEMENTS"
printf 'chr1\t240\t290\tproj1::mmus_re_0002\n' >> "$ELEMENTS"
DRER_ELEMENTS="$TMP_DIR/drer element union.bed"
printf 'chr1\t110\t150\tproj2::mmus_re_0001\n' > "$DRER_ELEMENTS"
printf 'chr1\t240\t290\tproj2::mmus_re_0002\n' >> "$DRER_ELEMENTS"

# Two real masks that share a basename ("NO_FILE.mask.bed") from different
# directories: exercises both the input-name-collision fix (slot-specific
# stageAs) and that NO_FILE-prefixed real files are not mistaken for the unset
# placeholder (presence is from explicit has_* flags). Both cover the regions.
mkdir -p "$TMP_DIR/dir_a" "$TMP_DIR/dir_b"
SPECIES_MASK="$TMP_DIR/dir_a/NO_FILE.mask.bed"
printf 'chr1\t0\t100000\n' > "$SPECIES_MASK"
SOURCE_MASK="$TMP_DIR/dir_b/NO_FILE.mask.bed"
printf 'chr1\t0\t100000\n' > "$SOURCE_MASK"
DRER_MASK="$TMP_DIR/drer target mask.bed"
printf 'chr1\t100\t150\nchr1\t220\t270\n' > "$DRER_MASK"

OUT="$TMP_DIR/results"
PATH="$MOCKBIN:$PATH" nextflow run "$ROOT_DIR" \
  --run_stage coordinate_projection \
  --regulatory_regions "$REGIONS" \
  --genome_alignment_manifest "$ALIGN" \
  --coordinate_projection_config "$CONFIG" \
  --coordinate_projection_stub false \
  --orthology_source_element_union "$ELEMENTS" \
  --orthology_species_callable_mask "$SPECIES_MASK" \
  --orthology_source_callable_mask "$SOURCE_MASK" \
  --outdir "$OUT" > "$TMP_DIR/nf.out" 2>&1 || { cat "$TMP_DIR/nf.out"; echo "FAIL: real-mode reciprocal-best run errored (spaced path / same-basename masks / NO_FILE-prefixed mask?)" >&2; exit 1; }

PROJ="$OUT/coordinate_projection/projected_regions.tsv"
SUMM="$OUT/coordinate_projection/region_orthology_summary.tsv"
ORTH="$OUT/coordinate_projection/inferred_orthologous_res.tsv"
for f in "$PROJ" "$SUMM" "$ORTH"; do
  [ -s "$f" ] || { cat "$TMP_DIR/nf.out"; echo "FAIL: missing real-mode output $f" >&2; exit 1; }
done

# Identity mock lift recovers the full window: high-confidence compact loci.
grep -q 'mmus_re_0001' "$PROJ" || { cat "$PROJ"; echo "FAIL: region not projected" >&2; exit 1; }
grep -q 'HIGH_CONFIDENCE' "$SUMM" || { cat "$SUMM"; echo "FAIL: expected HIGH_CONFIDENCE round-trip" >&2; exit 1; }
grep -q 'reciprocal_best_orthology' "$ORTH" || { cat "$ORTH"; echo "FAIL: inferred orthology not emitted" >&2; exit 1; }

# The NO_FILE-prefixed real mask must have been applied: species_mask_support_fraction
# (column 22) is populated. If the mask were mistaken for the unset placeholder
# it would be empty.
support=$(awk -F'\t' 'NR>1 && $4=="mmus_re_0001"{print $22; exit}' "$SUMM")
[ -n "$support" ] || { cat "$SUMM"; echo "FAIL: NO_FILE-prefixed species mask was ignored (no mask support recorded)" >&2; exit 1; }
# Both same-basename masks must be applied: source_callable_fraction (col 11) set too.
srcfrac=$(awk -F'\t' 'NR>1 && $4=="mmus_re_0001"{print $11; exit}' "$SUMM")
[ -n "$srcfrac" ] || { cat "$SUMM"; echo "FAIL: same-basename source mask was not applied (no source callable fraction)" >&2; exit 1; }

# The new real-mode artifacts must appear in the outputs manifest.
MANIFEST="$OUT/coordinate_projection/summary/coordinate_projection_outputs_manifest.tsv"
grep -q 'region_orthology_summary' "$MANIFEST" || { cat "$MANIFEST"; echo "FAIL: region_orthology_summary missing from outputs manifest" >&2; exit 1; }
grep -q 'orthologous_region_blocks' "$MANIFEST" || { cat "$MANIFEST"; echo "FAIL: orthologous_region_blocks missing from outputs manifest" >&2; exit 1; }

BUNDLE="$TMP_DIR/orthology_reference_bundle.tsv"
printf 'schema_version\tbundle_id\tbundle_source\tsource_species\ttarget_species\tsource_assembly\ttarget_assembly\tasset_role\tasset_path\tasset_format\torthology_lift_tool\tvalidation_status\ttool_versions\tparams_hash\tinput_hashes\tcreated_at\tcreated_by\tnotes\tprojection_id\n' > "$BUNDLE"
printf 'orthology_reference_bundle.v1\tbundle_proj1\texternal\tMus_musculus\tPan_troglodytes\tGRCm39\tpanTro6\treciprocal_best_chain\tmmus_to_ptro.chain\tchain\tliftover\tvalid\t\t\t\t\t\tbundle fixture\tproj1\n' >> "$BUNDLE"
printf 'orthology_reference_bundle.v1\tbundle_proj1\texternal\tMus_musculus\tPan_troglodytes\tGRCm39\tpanTro6\tsource_callable_mask\tdir_b/NO_FILE.mask.bed\tbed\tliftover\tvalid\t\t\t\t\t\tbundle fixture\tproj1\n' >> "$BUNDLE"
printf 'orthology_reference_bundle.v1\tbundle_proj1\texternal\tMus_musculus\tPan_troglodytes\tGRCm39\tpanTro6\ttarget_callable_mask\tdir_a/NO_FILE.mask.bed\tbed\tliftover\tvalid\t\t\t\t\t\tbundle fixture\tproj1\n' >> "$BUNDLE"
printf 'orthology_reference_bundle.v1\tbundle_proj1\texternal\tMus_musculus\tPan_troglodytes\tGRCm39\tpanTro6\tsource_element_union\telement union.bed\tbed\tliftover\tvalid\t\t\t\t\t\tbundle fixture\tproj1\n' >> "$BUNDLE"

BUNDLE_OUT="$TMP_DIR/results_bundle"
PATH="$MOCKBIN:$PATH" nextflow run "$ROOT_DIR" \
  --run_stage coordinate_projection \
  --regulatory_regions "$REGIONS" \
  --orthology_reference_bundle_manifest "$BUNDLE" \
  --coordinate_projection_stub false \
  --outdir "$BUNDLE_OUT" > "$TMP_DIR/nf_bundle.out" 2>&1 || { cat "$TMP_DIR/nf_bundle.out"; echo "FAIL: bundle-backed coordinate projection errored" >&2; exit 1; }

BUNDLE_SUMM="$BUNDLE_OUT/coordinate_projection/region_orthology_summary.tsv"
BUNDLE_ORTH="$BUNDLE_OUT/coordinate_projection/inferred_orthologous_res.tsv"
BUNDLE_VALIDATION="$BUNDLE_OUT/coordinate_projection/input/orthology_reference_bundle_validation.tsv"
for f in "$BUNDLE_SUMM" "$BUNDLE_ORTH" "$BUNDLE_VALIDATION"; do
  [ -s "$f" ] || { cat "$TMP_DIR/nf_bundle.out"; echo "FAIL: missing bundle-backed output $f" >&2; exit 1; }
done
grep -q 'HIGH_CONFIDENCE' "$BUNDLE_SUMM" || { cat "$BUNDLE_SUMM"; echo "FAIL: bundle-backed run did not project high-confidence loci" >&2; exit 1; }
grep -q 'reciprocal_best_orthology' "$BUNDLE_ORTH" || { cat "$BUNDLE_ORTH"; echo "FAIL: bundle-backed inferred orthology not emitted" >&2; exit 1; }
grep -q 'orthology_reference_bundle:bundle_proj1' "$BUNDLE_OUT/coordinate_projection/input/genome_alignment_manifest.from_bundle.tsv" || { cat "$BUNDLE_OUT/coordinate_projection/input/genome_alignment_manifest.from_bundle.tsv"; echo "FAIL: generated alignment manifest missing bundle provenance" >&2; exit 1; }

MULTI_BUNDLE="$TMP_DIR/orthology_reference_bundle_multi.tsv"
printf 'schema_version\tbundle_id\tbundle_source\tsource_species\ttarget_species\tsource_assembly\ttarget_assembly\tasset_role\tasset_path\tasset_format\torthology_lift_tool\tvalidation_status\ttool_versions\tparams_hash\tinput_hashes\tcreated_at\tcreated_by\tnotes\tprojection_id\n' > "$MULTI_BUNDLE"
printf 'orthology_reference_bundle.v1\tbundle_proj1\texternal\tMus_musculus\tPan_troglodytes\tGRCm39\tpanTro6\treciprocal_best_chain\tmmus_to_ptro.chain\tchain\tliftover\tvalid\t\t\t\t\t\tbundle fixture\tproj1\n' >> "$MULTI_BUNDLE"
printf 'orthology_reference_bundle.v1\tbundle_proj1\texternal\tMus_musculus\tPan_troglodytes\tGRCm39\tpanTro6\tsource_callable_mask\tdir_b/NO_FILE.mask.bed\tbed\tliftover\tvalid\t\t\t\t\t\tbundle fixture\tproj1\n' >> "$MULTI_BUNDLE"
printf 'orthology_reference_bundle.v1\tbundle_proj1\texternal\tMus_musculus\tPan_troglodytes\tGRCm39\tpanTro6\ttarget_callable_mask\tdir_a/NO_FILE.mask.bed\tbed\tliftover\tvalid\t\t\t\t\t\tbundle fixture\tproj1\n' >> "$MULTI_BUNDLE"
printf 'orthology_reference_bundle.v1\tbundle_proj1\texternal\tMus_musculus\tPan_troglodytes\tGRCm39\tpanTro6\tsource_element_union\telement union.bed\tbed\tliftover\tvalid\t\t\t\t\t\tbundle fixture\tproj1\n' >> "$MULTI_BUNDLE"
printf 'orthology_reference_bundle.v1\tbundle_proj2\texternal\tMus_musculus\tDanio_rerio\tGRCm39\tGRCz11\treciprocal_best_chain\tmmus_to_drer.chain\tchain\tliftover\tvalid\t\t\t\t\t\tbundle fixture\tproj2\n' >> "$MULTI_BUNDLE"
printf 'orthology_reference_bundle.v1\tbundle_proj2\texternal\tMus_musculus\tDanio_rerio\tGRCm39\tGRCz11\tsource_callable_mask\tdir_b/NO_FILE.mask.bed\tbed\tliftover\tvalid\t\t\t\t\t\tbundle fixture\tproj2\n' >> "$MULTI_BUNDLE"
printf 'orthology_reference_bundle.v1\tbundle_proj2\texternal\tMus_musculus\tDanio_rerio\tGRCm39\tGRCz11\ttarget_callable_mask\tdrer target mask.bed\tbed\tliftover\tvalid\t\t\t\t\t\tbundle fixture\tproj2\n' >> "$MULTI_BUNDLE"
printf 'orthology_reference_bundle.v1\tbundle_proj2\texternal\tMus_musculus\tDanio_rerio\tGRCm39\tGRCz11\tsource_element_union\tdrer element union.bed\tbed\tliftover\tvalid\t\t\t\t\t\tbundle fixture\tproj2\n' >> "$MULTI_BUNDLE"

run_multi_bundle() {
  outdir="$1"
  workdir="$2"
  shift 2
  PATH="$MOCKBIN:$PATH" nextflow run "$ROOT_DIR" "$@" \
    -work-dir "$workdir" \
    --run_stage coordinate_projection \
    --regulatory_regions "$REGIONS" \
    --orthology_reference_bundle_manifest "$MULTI_BUNDLE" \
    --coordinate_projection_stub false \
    --outdir "$outdir"
}

MULTI_WORK="$TMP_DIR/work_multi"
MULTI_OUT="$TMP_DIR/results_bundle_multi"
run_multi_bundle "$MULTI_OUT" "$MULTI_WORK" > "$TMP_DIR/nf_bundle_multi.out" 2>&1 || { cat "$TMP_DIR/nf_bundle_multi.out"; echo "FAIL: multi-target bundle-backed coordinate projection errored" >&2; exit 1; }
MULTI_SUMM="$MULTI_OUT/coordinate_projection/region_orthology_summary.tsv"
MULTI_PROJ="$MULTI_OUT/coordinate_projection/projected_regions.tsv"
MULTI_ORTH="$MULTI_OUT/coordinate_projection/inferred_orthologous_res.tsv"
MULTI_BLOCKS="$MULTI_OUT/coordinate_projection/orthologous_region_blocks.tsv"
for target in Pan_troglodytes Danio_rerio; do
  grep -q "$target" "$MULTI_SUMM" || { cat "$MULTI_SUMM"; echo "FAIL: multi-target summary missing $target" >&2; exit 1; }
done
pan_support=$(awk -F'\t' 'NR>1 && $3=="Pan_troglodytes" && $4=="mmus_re_0001"{print $22; exit}' "$MULTI_SUMM")
drer_support=$(awk -F'\t' 'NR>1 && $3=="Danio_rerio" && $4=="mmus_re_0001"{print $22; exit}' "$MULTI_SUMM")
[ "$pan_support" = "1.0000" ] || { cat "$MULTI_SUMM"; echo "FAIL: Pan_troglodytes per-pair mask was not applied (support=$pan_support)" >&2; exit 1; }
[ "$drer_support" = "0.6250" ] || { cat "$MULTI_SUMM"; echo "FAIL: Danio_rerio per-pair mask was not applied (support=$drer_support)" >&2; exit 1; }
grep -q 'proj2' "$MULTI_ORTH" || { cat "$MULTI_ORTH"; echo "FAIL: multi-target inferred orthology missing second projection" >&2; exit 1; }

MULTI_OUT_FRESH="$TMP_DIR/results_bundle_multi_fresh"
run_multi_bundle "$MULTI_OUT_FRESH" "$TMP_DIR/work_multi_fresh" > "$TMP_DIR/nf_bundle_multi_fresh.out" 2>&1 || { cat "$TMP_DIR/nf_bundle_multi_fresh.out"; echo "FAIL: fresh deterministic multi-target bundle run errored" >&2; exit 1; }
for rel in coordinate_projection/projected_regions.tsv coordinate_projection/region_orthology_summary.tsv coordinate_projection/orthologous_region_blocks.tsv coordinate_projection/inferred_orthologous_res.tsv; do
  cmp "$MULTI_OUT/$rel" "$MULTI_OUT_FRESH/$rel" || { echo "FAIL: fresh multi-target bundle output is not deterministic for $rel" >&2; exit 1; }
done

MULTI_OUT_RESUME="$TMP_DIR/results_bundle_multi_resume"
run_multi_bundle "$MULTI_OUT_RESUME" "$MULTI_WORK" -resume > "$TMP_DIR/nf_bundle_multi_resume.out" 2>&1 || { cat "$TMP_DIR/nf_bundle_multi_resume.out"; echo "FAIL: resumed multi-target bundle run errored" >&2; exit 1; }
for rel in coordinate_projection/projected_regions.tsv coordinate_projection/region_orthology_summary.tsv coordinate_projection/orthologous_region_blocks.tsv coordinate_projection/inferred_orthologous_res.tsv; do
  cmp "$MULTI_OUT/$rel" "$MULTI_OUT_RESUME/$rel" || { echo "FAIL: resumed multi-target bundle output differs for $rel" >&2; exit 1; }
done

if nextflow run "$ROOT_DIR" \
  --run_stage coordinate_projection \
  --regulatory_regions "$REGIONS" \
  --orthology_reference_bundle_manifest "$BUNDLE" \
  --orthology_source_callable_mask "$SOURCE_MASK" \
  --coordinate_projection_stub false \
  --outdir "$TMP_DIR/conflict_results" > "$TMP_DIR/nf_bundle_conflict.out" 2>&1; then
  cat "$TMP_DIR/nf_bundle_conflict.out"
  echo "FAIL: bundle plus loose orthology asset should fail" >&2
  exit 1
fi
grep -q 'Cannot combine --orthology_reference_bundle_manifest' "$TMP_DIR/nf_bundle_conflict.out" || { cat "$TMP_DIR/nf_bundle_conflict.out"; echo "FAIL: bundle/loose conflict diagnostic absent" >&2; exit 1; }

echo "reciprocal-best orthology Nextflow real-mode test passed"
