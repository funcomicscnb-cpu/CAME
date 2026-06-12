#!/usr/bin/env sh
# Real-mode coordinate_projection integration test for the halLiftover branch.
# Uses a mock halLiftover (identity mapper preserving columns) and a
# launch-dir-relative HAL path, exercising HAL input prep (no chain/MAF needed),
# the HAL execution branch, and projected-strand preservation.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

MOCKBIN="$TMP_DIR/bin"
mkdir -p "$MOCKBIN"
# halLiftover [--flags] HAL srcGenome src.bed tgtGenome out.bed -> identity copy
# of the source BED (preserving all columns, so BED6 strand survives).
cat > "$MOCKBIN/halLiftover" <<'EOF'
#!/usr/bin/env sh
pos=""
for a in "$@"; do case "$a" in --*) ;; *) pos="$pos $a" ;; esac; done
set -- $pos
cp "$3" "$5"
EOF
chmod +x "$MOCKBIN/halLiftover"

# Fixtures live in the launch directory; HAL is referenced by a relative path.
WORK="$TMP_DIR/run"
mkdir -p "$WORK"
: > "$WORK/genome.hal"

REGIONS="$WORK/regulatory_regions.tsv"
printf 'species\tfeature_id\tchrom\tstart\tend\tstrand\tregion_type\n' > "$REGIONS"
printf 'Mus_musculus\tmmus_re_0001\tchr1\t100\t180\t-\tenhancer\n' >> "$REGIONS"

ALIGN="$WORK/genome_alignment_manifest.tsv"
printf 'source_species\ttarget_species\talignment_id\n' > "$ALIGN"
printf 'Mus_musculus\tPan_troglodytes\tmmus_to_ptro\n' >> "$ALIGN"

CONFIG="$WORK/coordinate_projection_config.tsv"
printf 'projection_id\tsource_species\ttarget_species\tmethod\n' > "$CONFIG"
printf 'proj1\tMus_musculus\tPan_troglodytes\tliftover_chain\n' >> "$CONFIG"

OUT="$WORK/results"
# Launch from $WORK so the relative HAL path resolves against launchDir.
( cd "$WORK" && PATH="$MOCKBIN:$PATH" nextflow run "$ROOT_DIR" \
    --run_stage coordinate_projection \
    --regulatory_regions "regulatory_regions.tsv" \
    --genome_alignment_manifest "genome_alignment_manifest.tsv" \
    --coordinate_projection_config "coordinate_projection_config.tsv" \
    --coordinate_projection_stub false \
    --orthology_lift_tool halliftover \
    --orthology_hal_file "genome.hal" \
    --outdir "results" ) > "$TMP_DIR/nf.out" 2>&1 || { cat "$TMP_DIR/nf.out"; echo "FAIL: HAL real-mode run errored (relative HAL path?)" >&2; exit 1; }

PROJ="$OUT/coordinate_projection/projected_regions.tsv"
[ -s "$PROJ" ] || { cat "$TMP_DIR/nf.out"; echo "FAIL: HAL run produced no projected_regions" >&2; exit 1; }
grep -q 'mmus_re_0001' "$PROJ" || { cat "$PROJ"; echo "FAIL: region not projected in HAL mode" >&2; exit 1; }
# Projected strand must be preserved from the lifted BED6 (column 12 = strand).
strand=$(awk -F'\t' 'NR>1 && $4=="mmus_re_0001"{print $12; exit}' "$PROJ")
[ "$strand" = "-" ] || { cat "$PROJ"; echo "FAIL: HAL projected strand not preserved (got '$strand')" >&2; exit 1; }

echo "reciprocal-best orthology HAL real-mode test passed"
