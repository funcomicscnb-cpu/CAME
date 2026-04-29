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

make_fixture() {
  local dir="$1"
  mkdir -p "$dir/ref" "$dir/reads"
  cat > "$dir/ref/tiny.fa" <<'EOF'
>chr1
ACGTACGTACGTACGTACGTACGTACGTACGT
EOF
  cat > "$dir/ref/tiny.fa.fai" <<'EOF'
chr1	32	6	32	33
EOF
  cat > "$dir/ref/tiny.dict" <<'EOF'
@HD	VN:1.6
@SQ	SN:chr1	LN:32
EOF
  cat > "$dir/reads/sample_R1.fastq" <<'EOF'
@r1
ACGTACGT
+
FFFFFFFF
EOF
  cat > "$dir/reads/sample_R2.fastq" <<'EOF'
@r1
ACGTACGT
+
FFFFFFFF
EOF
  cat > "$dir/reference_manifest.tsv" <<'EOF'
reference_id	species	fasta	fai	dict	bwa_index	known_sites_vcf	repeatmasker_bed	mappability_bed
tiny_ref	Tiny_mammal	ref/tiny.fa	ref/tiny.fa.fai	ref/tiny.dict	ref/tiny		
EOF
  cat > "$dir/wgs_samplesheet.csv" <<'EOF'
sample_id,species,individual_id,reference_id,fastq_1,fastq_2,read_layout,batch,platform,library_id,coverage_estimate,notes,study_id,biological_replicate,assay,library_protocol,tissue,condition,timepoint
wgs_tiny_1,Tiny_mammal,tiny_001,tiny_ref,reads/sample_R1.fastq,reads/sample_R2.fastq,paired,batch1,illumina,lib_tiny_1,1,fixture,stage27_fixture,rep1,wgs,short_read_wgs,tissue,control,0h
EOF
}

FIXTURE="$TMP_DIR/fixture"
make_fixture "$FIXTURE"

PREP="$TMP_DIR/prepared"
"$PYTHON" "$ROOT_DIR/bin/prepare_wgs_inputs.py" \
  --wgs_samplesheet "$FIXTURE/wgs_samplesheet.csv" \
  --reference_manifest "$FIXTURE/reference_manifest.tsv" \
  --wgs_mode real \
  --reference_cache_dir "$TMP_DIR/reference_cache" \
  --output_dir "$PREP" > "$TMP_DIR/prepare.out" 2>&1
assert_file "$PREP/wgs_manifest.tsv" "prepared WGS manifest missing"
assert_file "$PREP/wgs_input_warnings.tsv" "WGS input warnings missing"
assert_grep 'wgs_tiny_1' "$PREP/wgs_manifest.tsv" "valid WGS sample missing from prepared manifest"
assert_grep 'WARNING: known_sites_vcf absent; BQSR skipped and hard-filtering/no-BQSR fallback used\.' "$PREP/wgs_input_warnings.tsv" "known-sites warning absent"

BAD_MISSING="$TMP_DIR/missing_required.csv"
"$PYTHON" - "$FIXTURE/wgs_samplesheet.csv" "$BAD_MISSING" <<'PY'
import csv
import sys
src, dst = sys.argv[1:3]
rows = list(csv.DictReader(open(src)))
fields = [field for field in rows[0] if field != "study_id"]
with open(dst, "w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows({field: row.get(field, "") for field in fields} for row in rows)
PY
if "$PYTHON" "$ROOT_DIR/bin/prepare_wgs_inputs.py" \
  --wgs_samplesheet "$BAD_MISSING" \
  --reference_manifest "$FIXTURE/reference_manifest.tsv" \
  --wgs_mode stub \
  --output_dir "$TMP_DIR/bad_missing" > "$TMP_DIR/bad_missing.out" 2>&1; then
  cat "$TMP_DIR/bad_missing.out" >&2
  fail "missing required WGS column should fail"
fi
assert_grep 'Missing required column' "$TMP_DIR/bad_missing/wgs_input_warnings.tsv" "missing required WGS column diagnostic absent"

BAD_REF="$TMP_DIR/bad_reference.csv"
awk -F, 'BEGIN{OFS=","} NR==2{$4="missing_ref"} {print}' "$FIXTURE/wgs_samplesheet.csv" > "$BAD_REF"
if "$PYTHON" "$ROOT_DIR/bin/prepare_wgs_inputs.py" \
  --wgs_samplesheet "$BAD_REF" \
  --reference_manifest "$FIXTURE/reference_manifest.tsv" \
  --wgs_mode stub \
  --output_dir "$TMP_DIR/bad_ref" > "$TMP_DIR/bad_ref.out" 2>&1; then
  cat "$TMP_DIR/bad_ref.out" >&2
  fail "unresolved reference_id should fail"
fi
assert_grep 'Unknown reference_id' "$TMP_DIR/bad_ref/wgs_input_warnings.tsv" "unresolved reference diagnostic absent"

BAD_SPECIES="$TMP_DIR/bad_species.csv"
awk -F, 'BEGIN{OFS=","} NR==2{$2="Different_species"} {print}' "$FIXTURE/wgs_samplesheet.csv" > "$BAD_SPECIES"
if "$PYTHON" "$ROOT_DIR/bin/prepare_wgs_inputs.py" \
  --wgs_samplesheet "$BAD_SPECIES" \
  --reference_manifest "$FIXTURE/reference_manifest.tsv" \
  --wgs_mode stub \
  --output_dir "$TMP_DIR/bad_species" > "$TMP_DIR/bad_species.out" 2>&1; then
  cat "$TMP_DIR/bad_species.out" >&2
  fail "sample/reference species mismatch should fail"
fi
assert_grep 'reference_id species does not match WGS sample species' "$TMP_DIR/bad_species/wgs_input_warnings.tsv" "sample/reference species mismatch diagnostic absent"

MISSING_DICT="$TMP_DIR/missing_dict.tsv"
awk -F '\t' 'BEGIN{OFS="\t"} NR==1{for(i=1;i<=NF;i++) if($i=="dict") d=i} {for(i=1;i<=NF;i++) if(i!=d) printf "%s%s",$i,(i==NF||i+1==d&&i+1==NF?"\n":OFS)}' "$FIXTURE/reference_manifest.tsv" > "$MISSING_DICT"
if "$PYTHON" "$ROOT_DIR/bin/prepare_wgs_inputs.py" \
  --wgs_samplesheet "$FIXTURE/wgs_samplesheet.csv" \
  --reference_manifest "$MISSING_DICT" \
  --wgs_mode real \
  --reference_cache_dir "$TMP_DIR/reference_cache_missing_dict" \
  --output_dir "$TMP_DIR/missing_dict_out" > "$TMP_DIR/missing_dict.out" 2>&1; then
  cat "$TMP_DIR/missing_dict.out" >&2
  fail "missing dict should fail in real WGS validation"
fi
assert_grep 'WGS real mode requires reference field: dict' "$TMP_DIR/missing_dict_out/wgs_input_warnings.tsv" "missing dict diagnostic absent"

if "$PYTHON" "$ROOT_DIR/bin/prepare_wgs_inputs.py" \
  --wgs_samplesheet "$FIXTURE/wgs_samplesheet.csv" \
  --reference_manifest "$FIXTURE/reference_manifest.tsv" \
  --wgs_mode real \
  --require_known_sites true \
  --reference_cache_dir "$TMP_DIR/reference_cache_known_sites" \
  --output_dir "$TMP_DIR/require_known_sites" > "$TMP_DIR/require_known_sites.out" 2>&1; then
  cat "$TMP_DIR/require_known_sites.out" >&2
  fail "missing known sites should fail when require_known_sites=true"
fi
assert_grep 'known_sites_vcf is required by --require_known_sites true' "$TMP_DIR/require_known_sites/wgs_input_warnings.tsv" "require_known_sites diagnostic absent"

WES="$TMP_DIR/wes.csv"
awk -F, 'BEGIN{OFS=","} NR==2{$15="wes"} {print}' "$FIXTURE/wgs_samplesheet.csv" > "$WES"
if "$PYTHON" "$ROOT_DIR/bin/prepare_wgs_inputs.py" \
  --wgs_samplesheet "$WES" \
  --reference_manifest "$FIXTURE/reference_manifest.tsv" \
  --wgs_mode stub \
  --output_dir "$TMP_DIR/wes_out" > "$TMP_DIR/wes.out" 2>&1; then
  cat "$TMP_DIR/wes.out" >&2
  fail "WES should fail because production support is not implemented"
fi
assert_grep 'WES production support is not implemented' "$TMP_DIR/wes_out/wgs_input_warnings.tsv" "WES unsupported diagnostic absent"

NF_OUT="$TMP_DIR/nf_wgs_stub"
nextflow -log "$TMP_DIR/wgs_stub.log" run "$ROOT_DIR" \
  -work-dir "$TMP_DIR/work_stub" \
  --run_stage wgs_variants \
  --wgs_samplesheet "$ROOT_DIR/assets/example_samplesheets/wgs_samplesheet.csv" \
  --reference_manifest "$ROOT_DIR/assets/example_samplesheets/reference_manifest.tsv" \
  --wgs_mode stub \
  --outdir "$NF_OUT" > "$TMP_DIR/nextflow_stub.out" 2>&1
assert_file "$NF_OUT/wgs/bam/wgs_mouse_1.bam" "stub WGS BAM missing"
assert_file "$NF_OUT/wgs/variants/wgs_mouse_1.vcf.gz" "stub WGS VCF missing"
assert_file "$NF_OUT/wgs/qc/variant_qc.tsv" "stub WGS variant QC missing"
assert_grep '	mode	' "$NF_OUT/wgs/qc/variant_qc.tsv" "stub WGS QC missing mode column"
assert_grep '	bqsr_applied	' "$NF_OUT/wgs/qc/variant_qc.tsv" "stub WGS QC missing bqsr_applied column"
assert_grep '	calling_mode	' "$NF_OUT/wgs/qc/variant_qc.tsv" "stub WGS QC missing calling_mode column"
assert_grep '	joint_genotyping	' "$NF_OUT/wgs/qc/variant_qc.tsv" "stub WGS QC missing joint_genotyping column"
assert_grep '	stub	' "$NF_OUT/wgs/qc/variant_qc.tsv" "stub WGS QC did not record mode=stub"
assert_grep '	false	per_sample	false	' "$NF_OUT/wgs/qc/variant_qc.tsv" "stub WGS limitation fields missing"
assert_grep '	false	per_sample	false	' "$NF_OUT/wgs/summary/wgs_variant_summary.tsv" "stub WGS summary limitation fields missing"

EMPTY_PATH="$TMP_DIR/empty_path"
mkdir -p "$EMPTY_PATH"
if PATH="$EMPTY_PATH" "$PYTHON_BIN" "$ROOT_DIR/bin/check_real_mode_tools.py" \
  --outdir "$TMP_DIR/missing_tools" \
  --mode strict \
  --omics-types wgs \
  --project-dir "$ROOT_DIR" > "$TMP_DIR/missing_tools.out" 2>&1; then
  cat "$TMP_DIR/missing_tools/tool_check.tsv" >&2
  fail "WGS real-mode tool detection should fail clearly when tools are absent"
fi
assert_grep '^fastqc	wgs	missing	ERROR' "$TMP_DIR/missing_tools/tool_check.tsv" "missing FastQC diagnostic absent"
assert_grep '^bwa-mem2	wgs	missing	ERROR' "$TMP_DIR/missing_tools/tool_check.tsv" "missing BWA-MEM2 diagnostic absent"
assert_grep '^samtools	wgs	missing	ERROR' "$TMP_DIR/missing_tools/tool_check.tsv" "missing samtools diagnostic absent"
assert_grep '^gatk	wgs	missing	ERROR' "$TMP_DIR/missing_tools/tool_check.tsv" "missing GATK diagnostic absent"
assert_grep 'ERROR: BWA-MEM2 executable not found for WGS real mode' "$ROOT_DIR/subworkflows/wgs_real.nf" "WGS BWA-MEM2 process diagnostic absent"
assert_grep 'ERROR: samtools executable not found for WGS real mode' "$ROOT_DIR/subworkflows/wgs_real.nf" "WGS samtools process diagnostic absent"
assert_grep 'ERROR: FastQC executable not found for WGS real mode' "$ROOT_DIR/subworkflows/wgs_qc.nf" "WGS FastQC process diagnostic absent"
assert_grep 'ERROR: gatk executable not found for WGS real mode' "$ROOT_DIR/subworkflows/wgs_variant_calling.nf" "WGS GATK process diagnostic absent"

if rg 'wgs_variants' "$ROOT_DIR/workflows/all.nf" >/dev/null 2>&1; then
  fail "wgs_variants should not be included in workflows/all.nf"
fi

echo "WGS variant tests passed"
