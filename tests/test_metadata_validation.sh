#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT_DIR/bin/validate_metadata.py"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

write_valid_data() {
  dir="$1"
  mkdir -p "$dir"
  cat > "$dir/species_traits.tsv" <<'EOF'
species	phylogeny_label	common_name	clade	external_trait	covariate	trait_value	trait_unit	trait_source	trait_confidence
Mus_musculus	Mus_musculus	house mouse	Mammalia	generic	body_size	1	kg	example	medium
Danio_rerio	Danio_rerio	zebrafish	Actinopterygii	generic	body_size	1	kg	example	medium
EOF
  cat > "$dir/phenotype_samplesheet.csv" <<'EOF'
sample_id,species,individual_id,replicate_id,condition,timepoint,assay,measurement,value,unit,batch
p1,Mus_musculus,i1,r1,control,0h,generic,response,1.0,ratio,b1
p2,Danio_rerio,i2,r1,control,0h,generic,response,2.0,ratio,b1
EOF
  cat > "$dir/omics_samplesheet.csv" <<'EOF'
sample_id,species,individual_id,replicate_id,omics_type,condition,timepoint,reference_id,batch,fastq_1,fastq_2,read_layout
o1,Mus_musculus,i1,r1,rnaseq,control,0h,mmus_ref,b1,mouse_R1.fq.gz,mouse_R2.fq.gz,paired-end
o2,Danio_rerio,i2,r1,atacseq,control,0h,drer_ref,b1,fish_R1.fq.gz,fish_R2.fq.gz,paired-end
EOF
  cat > "$dir/reference_manifest.tsv" <<'EOF'
reference_id	species	genome_fasta	annotation_version	source
mmus_ref	Mus_musculus	mouse.fa	v1	example
drer_ref	Danio_rerio	fish.fa	v1	example
EOF
  cat > "$dir/phylogeny_manifest.tsv" <<'EOF'
phylogeny_id	phylogeny_file	species	phylogeny_label	source	branch_length_type
tree	tree.nwk	Mus_musculus	Mus_musculus	example	substitutions
tree	tree.nwk	Danio_rerio	Danio_rerio	example	substitutions
EOF
  cat > "$dir/study_design.yaml" <<'EOF'
study:
  study_id: test
metadata:
  phenotype_samplesheet: phenotype_samplesheet.csv
contrasts:
  - contrast_id: c1
EOF
}

run_validator() {
  dir="$1"
  python3 "$VALIDATOR" \
    --phenotype_samplesheet "$dir/phenotype_samplesheet.csv" \
    --omics_samplesheet "$dir/omics_samplesheet.csv" \
    --species_traits "$dir/species_traits.tsv" \
    --reference_manifest "$dir/reference_manifest.tsv" \
    --phylogeny_manifest "$dir/phylogeny_manifest.tsv" \
    --study_design "$dir/study_design.yaml" \
    --report "$dir/report.tsv" > "$dir/stdout.txt" 2>&1
}

expect_pass() {
  name="$1"
  dir="$TMP_DIR/$name"
  write_valid_data "$dir"
  if ! run_validator "$dir"; then
    cat "$dir/stdout.txt"
    echo "FAIL: $name expected pass" >&2
    exit 1
  fi
}

expect_fail() {
  name="$1"
  mutate="$2"
  dir="$TMP_DIR/$name"
  write_valid_data "$dir"
  sh -c "$mutate" sh "$dir"
  if run_validator "$dir"; then
    cat "$dir/stdout.txt"
    echo "FAIL: $name expected failure" >&2
    exit 1
  fi
}

expect_warning_pass() {
  name="$1"
  mutate="$2"
  expected="$3"
  dir="$TMP_DIR/$name"
  write_valid_data "$dir"
  sh -c "$mutate" sh "$dir"
  if ! run_validator "$dir"; then
    cat "$dir/stdout.txt"
    echo "FAIL: $name expected warning pass" >&2
    exit 1
  fi
  if ! grep -q "$expected" "$dir/report.tsv"; then
    cat "$dir/report.tsv"
    echo "FAIL: $name missing expected warning" >&2
    exit 1
  fi
}

expect_pass valid_metadata

expect_fail missing_required_phenotype_column \
  'awk -F, "BEGIN{OFS=\",\"} NR==1{sub(/,measurement/,\"\")} NR>1{sub(/,response/,\"\")} {print}" "$1/phenotype_samplesheet.csv" > "$1/tmp" && mv "$1/tmp" "$1/phenotype_samplesheet.csv"'

expect_fail duplicate_phenotype_sample_id \
  'awk -F, "BEGIN{OFS=\",\"} NR==3{\$1=\"p1\"} {print}" "$1/phenotype_samplesheet.csv" > "$1/tmp" && mv "$1/tmp" "$1/phenotype_samplesheet.csv"'

expect_fail unknown_omics_reference_id \
  'awk -F, "BEGIN{OFS=\",\"} NR==2{\$8=\"missing_ref\"} {print}" "$1/omics_samplesheet.csv" > "$1/tmp" && mv "$1/tmp" "$1/omics_samplesheet.csv"'

expect_fail reference_species_not_in_traits \
  'awk -F"\t" "BEGIN{OFS=\"\t\"} NR==2{\$2=\"Unknown_species\"} {print}" "$1/reference_manifest.tsv" > "$1/tmp" && mv "$1/tmp" "$1/reference_manifest.tsv"'

expect_fail non_numeric_phenotype_value \
  'awk -F, "BEGIN{OFS=\",\"} NR==2{\$9=\"not_numeric\"} {print}" "$1/phenotype_samplesheet.csv" > "$1/tmp" && mv "$1/tmp" "$1/phenotype_samplesheet.csv"'

expect_warning_pass unknown_omics_type \
  'awk -F, "BEGIN{OFS=\",\"} NR==2{\$5=\"proteomics\"} {print}" "$1/omics_samplesheet.csv" > "$1/tmp" && mv "$1/tmp" "$1/omics_samplesheet.csv"' \
  'Unknown omics_type'

expect_fail missing_paired_fastq2 \
  'awk -F, "BEGIN{OFS=\",\"} NR==2{\$11=\"\"} {print}" "$1/omics_samplesheet.csv" > "$1/tmp" && mv "$1/tmp" "$1/omics_samplesheet.csv"'

expect_fail missing_single_fastq1 \
  'awk -F, "BEGIN{OFS=\",\"} NR==2{\$10=\"\"; \$12=\"single-end\"} {print}" "$1/omics_samplesheet.csv" > "$1/tmp" && mv "$1/tmp" "$1/omics_samplesheet.csv"'

expect_fail missing_condition \
  'awk -F, "BEGIN{OFS=\",\"} NR==2{\$5=\"\"} {print}" "$1/phenotype_samplesheet.csv" > "$1/tmp" && mv "$1/tmp" "$1/phenotype_samplesheet.csv"'

echo "metadata validation tests passed"
