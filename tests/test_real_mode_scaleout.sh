#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PYTHON=${PYTHON:-python3}
PYTHON_BIN=$(command -v "$PYTHON")

fail() {
  echo "FAIL: $1" >&2
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
    cat "$file" >&2
    fail "$message"
  fi
}

make_fake_rna_tools() {
  local bindir="$1"
  mkdir -p "$bindir"
  cat > "$bindir/fastqc" <<'SH'
#!/usr/bin/env sh
out=.
while [ "$#" -gt 0 ]; do
  case "$1" in --outdir) shift; out="$1" ;; esac
  shift || true
done
mkdir -p "$out"
echo fastqc > "$out/fake_fastqc.html"
SH
  cat > "$bindir/STAR" <<'SH'
#!/usr/bin/env sh
mode=align
genome_dir=
prefix=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --runMode) shift; mode="$1" ;;
    --genomeDir) shift; genome_dir="$1" ;;
    --outFileNamePrefix) shift; prefix="$1" ;;
  esac
  shift || true
done
if [ "$mode" = genomeGenerate ]; then
  mkdir -p "$genome_dir"
  echo SA > "$genome_dir/SA"
  exit 0
fi
mkdir -p "$(dirname "$prefix")"
echo bam > "${prefix}Aligned.out.bam"
printf 'Number of input reads | 10\nUniquely mapped reads number | 8\nUniquely mapped reads %% | 80.00%%\nNumber of reads mapped to multiple loci | 1\n%% of reads mapped to multiple loci | 10.00%%\n' > "${prefix}Log.final.out"
echo log > "${prefix}Log.out"
echo progress > "${prefix}Log.progress.out"
echo sj > "${prefix}SJ.out.tab"
SH
  cat > "$bindir/samtools" <<'SH'
#!/usr/bin/env sh
cmd="$1"; shift || true
case "$cmd" in
  sort)
    out=
    while [ "$#" -gt 0 ]; do [ "$1" = -o ] && { shift; out="$1"; }; shift || true; done
    cat >/dev/null
    echo bam > "$out"
    ;;
  quickcheck) exit 0 ;;
  index) echo bai > "$1.bai" ;;
  flagstat) printf '10 + 0 in total (QC-passed reads + QC-failed reads)\n8 + 0 mapped (80.00%% : N/A)\n1 + 0 duplicates\n' ;;
  idxstats) printf 'chrSmoke\t1200\t8\t0\n' ;;
  stats) printf 'SN\tinsert size average:\t150\nSN\tinsert size standard deviation:\t20\n' ;;
  view) echo bam ;;
esac
SH
  cat > "$bindir/featureCounts" <<'SH'
#!/usr/bin/env sh
out=
while [ "$#" -gt 0 ]; do [ "$1" = -o ] && { shift; out="$1"; }; shift || true; done
printf '# Program: featureCounts\nGeneid\tChr\tStart\tEnd\tStrand\tLength\t%s\nsmoke_gene_1\tchrSmoke\t101\t260\t+\t160\t7\n' sample.bam > "$out"
printf 'Status\t%s\nAssigned\t7\nUnassigned_NoFeatures\t3\n' sample.bam > "$out.summary"
SH
  cat > "$bindir/multiqc" <<'SH'
#!/usr/bin/env sh
out=multiqc
while [ "$#" -gt 0 ]; do [ "$1" = --outdir ] && { shift; out="$1"; }; shift || true; done
mkdir -p "$out"
echo html > "$out/multiqc_report.html"
SH
  chmod +x "$bindir"/*
}

DATA_DIR="$TMP_DIR/data"
"$PYTHON" "$ROOT_DIR/bin/make_real_mode_smoke_data.py" --outdir "$DATA_DIR" > "$TMP_DIR/make_data.out" 2>&1

for label in process_low process_medium process_high process_star_index process_star_align process_bowtie2_align process_peak_calling process_counting; do
  assert_grep "withLabel:[[:space:]]*${label}" "$ROOT_DIR/nextflow.config" "missing resource label $label"
done
assert_grep 'process RNA_STAR_ALIGN_SAMPLE' "$ROOT_DIR/subworkflows/rna_real.nf" "RNA STAR align process was not decomposed"
assert_grep 'process RNA_SAMTOOLS_QC_SAMPLE' "$ROOT_DIR/subworkflows/rna_real.nf" "RNA samtools process was not decomposed"
assert_grep 'process ATAC_MACS3_PEAKS_SAMPLE' "$ROOT_DIR/subworkflows/atac_real.nf" "ATAC MACS3 process was not decomposed"
assert_grep 'process ATAC_PEAK_COUNTS' "$ROOT_DIR/subworkflows/atac_real.nf" "ATAC peak counting process missing"

if PATH="$TMP_DIR/empty_path" "$PYTHON_BIN" "$ROOT_DIR/bin/check_real_mode_tools.py" \
  --outdir "$TMP_DIR/missing_tools" \
  --mode strict \
  --omics-types rnaseq \
  --project-dir "$ROOT_DIR" > "$TMP_DIR/missing_tools.out" 2>&1; then
  cat "$TMP_DIR/missing_tools/tool_check.tsv" >&2
  fail "strict real-mode tool check should fail with an empty PATH"
fi
assert_grep '^STAR	rnaseq	missing	ERROR' "$TMP_DIR/missing_tools/tool_check.tsv" "missing STAR diagnostic absent"

if nextflow -log "$TMP_DIR/salmon.log" run "$ROOT_DIR" \
  -work-dir "$TMP_DIR/salmon_work" \
  --run_stage bulk_omics \
  --omics_mode real \
  --omics_types rnaseq \
  --rna_backend salmon \
  --real_mode_metadata "$DATA_DIR/real_mode_metadata.tsv" \
  --reference_manifest "$DATA_DIR/reference_manifest.tsv" \
  --reference_cache_dir "$TMP_DIR/salmon_refcache" \
  --outdir "$TMP_DIR/salmon_out" > "$TMP_DIR/salmon.out" 2>&1; then
  cat "$TMP_DIR/salmon.out" >&2
  fail "Salmon backend should fail clearly when not implemented"
fi
assert_grep 'ERROR: Salmon backend is declared but not implemented in this release\.' "$TMP_DIR/salmon.out" "Salmon guard message absent"

COLLIDE="$TMP_DIR/colliding_metadata.tsv"
"$PYTHON" - "$DATA_DIR/real_mode_metadata.tsv" "$COLLIDE" <<'PY'
import csv
import sys

src, out = sys.argv[1:3]
rows = list(csv.DictReader(open(src), delimiter="\t"))
rna = next(row for row in rows if row["assay"] == "rna")
first = dict(rna, sample_id="sample/a")
second = dict(rna, sample_id="sample_a", individual_id="other_individual")
with open(out, "w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=list(rna), delimiter="\t", lineterminator="\n")
    writer.writeheader()
    writer.writerows([first, second])
PY
if "$PYTHON" "$ROOT_DIR/bin/prepare_real_omics_inputs.py" \
  --real_mode_metadata "$COLLIDE" \
  --reference_manifest "$DATA_DIR/reference_manifest.tsv" \
  --omics_types rnaseq \
  --reference_cache_dir "$TMP_DIR/collision_refcache" \
  --output_dir "$TMP_DIR/collision_out" > "$TMP_DIR/collision.out" 2>&1; then
  cat "$TMP_DIR/collision_out/omics_input_warnings.tsv" >&2
  fail "sample_key collision should fail input preparation"
fi
assert_grep 'collide after filesystem-safe normalization' "$TMP_DIR/collision_out/omics_input_warnings.tsv" "sample_key collision diagnostic absent"

FAKE_BIN="$TMP_DIR/fake_bin"
make_fake_rna_tools "$FAKE_BIN"
NF_OUT="$TMP_DIR/nf_fake_rna"
PATH="$FAKE_BIN:$PATH" nextflow -log "$TMP_DIR/fake_rna.log" run "$ROOT_DIR" \
  -work-dir "$TMP_DIR/fake_rna_work" \
  --run_stage bulk_omics \
  --omics_mode real \
  --omics_types rnaseq \
  --real_mode_metadata "$DATA_DIR/real_mode_metadata.tsv" \
  --reference_manifest "$DATA_DIR/reference_manifest.tsv" \
  --reference_cache_dir "$TMP_DIR/fake_rna_refcache" \
  --outdir "$NF_OUT" > "$TMP_DIR/fake_rna.out" 2>&1
assert_file "$NF_OUT/rnaseq/counts/gene_counts.tsv" "RNA fake real-mode gene counts missing"
assert_file "$NF_OUT/atacseq/counts/re_counts.tsv" "empty ATAC contract missing from RNA-only real-mode run"
assert_file "$NF_OUT/omics/summary/omics_run_summary.tsv" "omics summary missing from RNA-only real-mode run"
assert_grep 'smoke_rna_1' "$NF_OUT/rnaseq/counts/gene_counts.tsv" "final gene count header did not preserve sample_id"
assert_grep 'RNA_STAR_ALIGN_SAMPLE' "$TMP_DIR/fake_rna.log" "RNA STAR per-sample process absent from run log"
assert_grep 'RNA_SAMTOOLS_QC_SAMPLE' "$TMP_DIR/fake_rna.log" "RNA samtools per-sample process absent from run log"

echo "real-mode scale-out tests passed"
